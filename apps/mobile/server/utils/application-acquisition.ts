import type { H3Event } from 'h3'
import type { CloudbaseAdminDb } from './cloudbase-admin'
import type { AppRecord } from '~/types/app'
import { Buffer } from 'node:buffer'
import { createError, getRequestHeader, readRawBody, setResponseHeader } from 'h3'
import { useCloudbaseAdmin } from './cloudbase-admin'
import { parseBearerToken, requireRegisteredCloudbaseUser } from './cloudbase-auth'
import { resolveCloudbaseEnvId } from './cloudbase-config'
import { getPublicAppByKey } from './public-apps'

interface AccountSnapshot {
  coin: number
  membership: { isActive: boolean, expireAt?: number | null }
}
export interface ApplicationAcquisitionInput {
  action: 'check' | 'purchase'
  appId: string
  expectedCoinCost?: number
}
export interface ApplicationAcquisitionDependencies {
  application: (key: string) => Promise<AppRecord | null>
  account: () => Promise<unknown>
  purchased: (uid: string, appId: string) => Promise<boolean>
  deduct: (appId: string, amount: number, bizId: string) => Promise<unknown>
  now: () => number
}
export type ApplicationAcquisitionState = 'allowed' | 'membership_required' | 'purchase_required' | 'invitation_required'

function unavailable(): never {
  throw createError({ statusCode: 503, message: '暂时无法核对应用权益，请稍后重试' })
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function coinAmount(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) >= 0
}
export function readApplicationAcquisitionInput(value: unknown): ApplicationAcquisitionInput {
  if (!isRecord(value) || (value.action !== 'check' && value.action !== 'purchase')
    || typeof value.appId !== 'string' || !/^[\w-]{1,128}$/.test(value.appId)
    || Object.keys(value).some(key => !['action', 'appId', 'expectedCoinCost'].includes(key))
    || (value.action === 'purchase' && (!coinAmount(value.expectedCoinCost) || value.expectedCoinCost <= 0))) {
    throw createError({ statusCode: 400, message: '请重新打开应用详情' })
  }
  return value as unknown as ApplicationAcquisitionInput
}

/** The published catalog supplies the price; a confirmation supplies only an expected-price condition. */
export async function resolveApplicationAcquisition(uid: string, input: ApplicationAcquisitionInput, deps: ApplicationAcquisitionDependencies) {
  const application = await deps.application(input.appId)
  if (!application || application._id !== input.appId)
    throw createError({ statusCode: 404, message: '应用暂未上架或已下架' })
  const price = application.coinCost ?? 0
  if (!coinAmount(price) || (application.requiresMembership != null && typeof application.requiresMembership !== 'boolean'))
    unavailable()
  const raw = await deps.account()
  if (!isRecord(raw) || !coinAmount(raw.coin) || !isRecord(raw.membership) || typeof raw.membership.isActive !== 'boolean')
    unavailable()
  const account = raw as unknown as AccountSnapshot
  const isMember = account.membership.isActive && typeof account.membership.expireAt === 'number'
    && Number.isFinite(account.membership.expireAt) && account.membership.expireAt > deps.now()
  if (account.membership.isActive && !isMember)
    unavailable()
  const result = (state: ApplicationAcquisitionState, reason: string, balance = account.coin) => ({
    userId: uid,
    application,
    state,
    reason,
    coinCost: price,
    balance,
  })
  // Membership/payment never supplies a missing invitation.
  if (application.accessMode === 'invite_only')
    return result('invitation_required', 'invitation')
  if (application.accessMode && !['public', 'login_required'].includes(application.accessMode))
    unavailable()
  if (application.requiresMembership && !isMember)
    return result('membership_required', 'membership')
  if (price === 0)
    return result('allowed', application.requiresMembership ? 'member' : 'free')
  if (isMember)
    return result('allowed', 'member')
  if (await deps.purchased(uid, application._id))
    return result('allowed', 'purchased')
  if (input.action === 'check')
    return result('purchase_required', 'purchase')
  if (input.expectedCoinCost !== price)
    throw createError({ statusCode: 409, message: '应用价格已变化，请重新确认', data: { code: 'APP_PRICE_CHANGED' } })
  if (account.coin < price)
    throw createError({ statusCode: 409, message: '云币余额不足，请先前往钱包', data: { code: 'APP_INSUFFICIENT_COIN' } })
  const receipt = await deps.deduct(application._id, price, `purchase:${application._id}`)
  if (!isRecord(receipt) || !coinAmount(receipt.balance) || typeof receipt.deduped !== 'boolean')
    unavailable()
  // An ambiguous timeout stays retryable. The canonical account-api transaction owns idempotency.
  if (!await deps.purchased(uid, application._id))
    unavailable()
  return result('allowed', 'purchased', receipt.balance)
}

/** Read the same owner/ref/type ledger key used by the legacy Web purchase, without trusting local storage. */
export async function hasApplicationPurchase(uid: string, appId: string, db: CloudbaseAdminDb = useCloudbaseAdmin().db): Promise<boolean> {
  const refId = `purchase:${appId}`
  const response: { data?: unknown, code?: unknown } = await db.collection('coin_transactions')
    .where({ userId: uid, refId, type: 'consume' })
    .limit(2)
    .get()
  if (response.code || !Array.isArray(response.data))
    unavailable()
  if (response.data.length === 0)
    return false
  for (const row of response.data) {
    if (!isRecord(row) || row.userId !== uid || row.appId !== appId || row.refId !== refId || row.type !== 'consume'
      || !Number.isSafeInteger(row.amount) || Number(row.amount) >= 0) {
      unavailable()
    }
  }
  return true
}

export async function handleApplicationAcquisition(event: H3Event) {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  const user = await requireRegisteredCloudbaseUser(event)
  const raw = await readRawBody(event)
  if (!raw || Buffer.byteLength(raw) > 4096)
    throw createError({ statusCode: 400 })
  let body: unknown
  try {
    body = JSON.parse(raw)
  }
  catch { throw createError({ statusCode: 400 }) }
  const input = readApplicationAcquisitionInput(body)
  const token = parseBearerToken(getRequestHeader(event, 'authorization'))
  if (!token)
    throw createError({ statusCode: 401 })
  const env = resolveCloudbaseEnvId(useRuntimeConfig(event))
  if (!/^[\w-]+$/.test(env))
    unavailable()
  // Delegation stays on this environment's fixed official gateway, with no redirects or internal secret.
  const invoke = async (fields: Record<string, unknown>) => {
    let response: Response
    try {
      response = await fetch(`https://${env}.api.tcloudbasegateway.com/v1/functions/account-api`, {
        method: 'POST',
        redirect: 'error',
        cache: 'no-store',
        signal: AbortSignal.timeout(20000),
        headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify(fields),
      })
    }
    catch { return unavailable() }
    if (response.status === 401 || response.status === 403)
      throw createError({ statusCode: response.status })
    if (!response.ok)
      unavailable()
    try {
      return await response.json() as unknown
    }
    catch { return unavailable() }
  }
  return resolveApplicationAcquisition(user.uid, input, {
    application: getPublicAppByKey,
    account: () => invoke({ action: 'getAccount' }),
    purchased: hasApplicationPurchase,
    deduct: (appId, amount, bizId) => invoke({ action: 'deductCoin', appId, amount, bizId, meta: { scene: 'purchase-app' } }),
    now: Date.now,
  })
}
