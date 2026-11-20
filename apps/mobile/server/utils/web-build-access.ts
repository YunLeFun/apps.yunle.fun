import type { H3Event } from 'h3'
import { createHash } from 'node:crypto'
import { createError } from 'h3'
import { invokeAccountApi } from './account-api'
import { useCloudbaseAdmin } from './cloudbase-admin'
import { assertVerifiedCloudbasePhone, requireRegisteredCloudbaseUser } from './cloudbase-auth'
import { allowsWebBuildCollaborationTest, getWebBuildTestSession } from './web-build-config'

const unavailableMessage = '暂时无法核对会员状态，请稍后重试'
const collaborationTestIdentityIds = new Set(['testid_production-web-build-owner', 'testid_production-web-build-member'])

export async function requireWebBuildMember(event: H3Event) {
  const personalTestSession = getWebBuildTestSession(event)
  const user = await requireRegisteredCloudbaseUser(event)
  const config = useRuntimeConfig(event)
  let testPeerUid: string | undefined
  if (personalTestSession) {
    await requireSyntheticPilot(user.uid, personalTestSession)
  }
  else if (!user.phoneVerified && allowsWebBuildCollaborationTest(event)) {
    testPeerUid = await findCollaborationTestPeer(user.uid)
  }
  if (!personalTestSession && !testPeerUid)
    assertVerifiedCloudbasePhone(user)
  if (!personalTestSession && !testPeerUid && config.webBuildEnabled !== true && config.webBuildPilotUid !== user.uid)
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
  const canCollaborate = !personalTestSession && (Boolean(testPeerUid) || config.webBuildCollaborationEnabled === true)
  return { user, personalTestSession: Boolean(personalTestSession), testPeerUid, canCollaborate }
}

export async function requireWebBuildInvitePeer(event: H3Event, targetId: string, testPeerUid?: string) {
  if (testPeerUid && targetId !== testPeerUid)
    throw createError({ statusCode: 403, message: '测试账号只能邀请同一场景的测试好友' })
  const message = '暂时无法核对好友关系'
  const result = await invokeAccountApi(event, { action: 'checkWebBuildInvitePeer', targetId }, message) as {
    ok?: boolean
    code?: string
  } | null
  if (result?.ok === true)
    return
  if (result?.code === 'not_mutual' || result?.code === 'recipient_unavailable') {
    throw createError({
      statusCode: 403,
      message: result.code === 'not_mutual' ? '互关好友才能接受邀请' : '对方当前无法参与项目协作',
      data: { code: result.code === 'not_mutual' ? 'WEB_BUILD_INVITE_NOT_MUTUAL' : 'WEB_BUILD_INVITE_PEER_UNAVAILABLE' },
    })
  }
  throw createError({ statusCode: 503, statusMessage: message })
}

async function findCollaborationTestPeer(uid: string) {
  const { db } = useCloudbaseAdmin()
  const result = await db.collection('web_builds').doc('synthetic_collaboration').get()
  const scenario = firstRecord(result.data)
  const now = Date.now()
  if (result.code || scenario?.kind !== 'synthetic-collaboration'
    || typeof scenario.issuedAt !== 'number' || typeof scenario.expiresAt !== 'number'
    || !Number.isSafeInteger(scenario.issuedAt) || !Number.isSafeInteger(scenario.expiresAt)
    || scenario.issuedAt > now || scenario.expiresAt <= now || scenario.expiresAt > scenario.issuedAt + 30 * 60_000
    || !Array.isArray(scenario.accounts) || scenario.accounts.length !== 2) {
    return
  }

  const accounts = scenario.accounts.map(firstRecord)
  const [left, right] = accounts
  if (!left || !right || left.uid === right.uid || left.identityId === right.identityId || left.virtualPhone === right.virtualPhone)
    return
  const peer = left.uid === uid ? right.uid : right.uid === uid ? left.uid : undefined
  if (typeof peer !== 'string')
    return
  const valid = await Promise.all(accounts.map(async (account) => {
    if (typeof account?.uid !== 'string' || !/^[\w.:-]{1,128}$/.test(account.uid)
      || typeof account.identityId !== 'string' || !collaborationTestIdentityIds.has(account.identityId)
      || typeof account.virtualPhone !== 'string' || !/^\+120255501\d{2}$/.test(account.virtualPhone)) {
      return false
    }
    const identity = await db.collection('test_identities').doc(account.identityId).get()
    const record = firstRecord(identity.data)
    return !identity.code && isReadyTestIdentity(record, account.uid)
      && Array.isArray(record?.tags) && record.tags.includes('member-active')
  }))
  if (valid.every(Boolean))
    return peer
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
  if (identityRecord.code || !isReadyTestIdentity(identity, uid)) {
    throw deny()
  }
}

function isReadyTestIdentity(identity: Record<string, unknown> | null, uid: string) {
  return identity?.uid === uid && identity.synthetic === true && identity.source === 'managed'
    && identity.accountKind === 'fixed' && identity.environment === 'production' && identity.status === 'ready'
}

function firstRecord(data: unknown) {
  const record: unknown = Array.isArray(data) ? (data.length === 1 ? data[0] : null) : data
  return record && typeof record === 'object' && !Array.isArray(record) ? record as Record<string, unknown> : null
}
