import type { H3Event } from 'h3'
import { createHash } from 'node:crypto'
import { createError } from 'h3'
import { invokeAccountApi } from './account-api'
import { useCloudbaseAdmin } from './cloudbase-admin'
import { requireRegisteredCloudbaseUser, requireVerifiedCloudbaseUser } from './cloudbase-auth'
import { getWebBuildTestSession } from './web-build-config'

const unavailableMessage = '暂时无法核对会员状态，请稍后重试'

export async function requireWebBuildMember(event: H3Event) {
  const testSession = getWebBuildTestSession(event)
  const user = testSession ? await requireRegisteredCloudbaseUser(event) : await requireVerifiedCloudbaseUser(event)
  const config = useRuntimeConfig(event)
  if (testSession)
    await requireSyntheticPilot(user.uid, testSession)
  else if (config.webBuildEnabled !== true && config.webBuildPilotUid !== user.uid)
    throw createError({ statusCode: 503, message: 'AI 网页服务暂未开放' })
  const snapshot = await invokeAccountApi(event, { action: 'getAccount' }, unavailableMessage) as {
    membership?: { isActive?: unknown, expireAt?: unknown } | null
  } | null
  const membership = snapshot?.membership
  if (typeof membership?.isActive !== 'boolean'
    || (membership.isActive && !Number.isFinite(membership.expireAt))) {
    throw createError({ statusCode: 503, message: unavailableMessage })
  }
  if (!membership.isActive || Number(membership.expireAt) <= Date.now()) {
    throw createError({
      statusCode: 403,
      message: 'AI 制作网页需要有效的云乐坊会员',
      data: { code: 'MEMBERSHIP_REQUIRED' },
    })
  }
  return user
}

async function requireSyntheticPilot(uid: string, session: string) {
  const { db } = useCloudbaseAdmin()
  const deny = () => createError({ statusCode: 403, message: '网页验收会话无效或已结束' })
  const sessionId = `synthetic_pilot_${createHash('sha256').update(session).digest('hex')}`
  const sessionRecord = await db.collection('web_builds').doc(sessionId).get()
  const pilot = firstRecord(sessionRecord.data)
  const now = Date.now()
  if (sessionRecord.code || pilot?.kind !== 'synthetic-pilot' || pilot.uid !== uid
    || typeof pilot.identityId !== 'string' || !/^[\w-]{1,128}$/.test(pilot.identityId)
    || typeof pilot.virtualPhone !== 'string' || !/^\+120255501\d{2}$/.test(pilot.virtualPhone)
    || typeof pilot.issuedAt !== 'number' || typeof pilot.expiresAt !== 'number'
    || !Number.isSafeInteger(pilot.issuedAt) || !Number.isSafeInteger(pilot.expiresAt)
    || pilot.issuedAt > now || pilot.expiresAt <= now || pilot.expiresAt > pilot.issuedAt + 30 * 60_000) {
    throw deny()
  }

  const identityRecord = await db.collection('test_identities').doc(pilot.identityId).get()
  const identity = firstRecord(identityRecord.data)
  if (identityRecord.code || identity?.uid !== uid || identity.synthetic !== true || identity.source !== 'managed'
    || identity.accountKind !== 'fixed' || identity.environment !== 'production' || identity.status !== 'ready') {
    throw deny()
  }
}

function firstRecord(data: unknown) {
  const record: unknown = Array.isArray(data) ? (data.length === 1 ? data[0] : null) : data
  return record && typeof record === 'object' && !Array.isArray(record) ? record as Record<string, unknown> : null
}
