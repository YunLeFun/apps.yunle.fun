import { Buffer } from 'node:buffer'
import { createError, getRequestHeader, readRawBody, setResponseHeader } from 'h3'
import { parseBearerToken } from '../../utils/cloudbase-auth'
import { requireWebBuildInvitePeer, requireWebBuildMember } from '../../utils/web-build-access'
import { requireWebBuildEditor } from '../../utils/web-build-config'
import { submitWebBuildToMarket } from '../../utils/web-build-market'
import { generateWebBuildPage, getWebBuildRuntimeConfig } from '../../utils/web-build-model'
import {
  acceptWebBuildFriendInvite,
  changeWebBuildRoomMembers,
  createWebBuildRoomInvite,
  getEditableWebBuild,
  getOwnedWebBuild,
  joinWebBuildRoom,
  moderateWebBuildRoomMessage,
  publishWebBuild,
  reserveWebBuildAction,
  revokeWebBuildRoomInvite,
  saveWebBuildDraft,
  sendWebBuildFriendInvite,
  sendWebBuildRoomMessage,
  withdrawWebBuild,
} from '../../utils/web-build-storage'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  requireWebBuildEditor(event)
  const { user, personalTestSession, testPeerUid } = await requireWebBuildMember(event)
  const length = Number(getRequestHeader(event, 'content-length'))
  if (length > 8192)
    throw createError({ statusCode: 413, statusMessage: '请求内容过长' })
  const raw = await readRawBody(event)
  if (!raw || Buffer.byteLength(raw) > 8192)
    throw createError({ statusCode: 413, statusMessage: '请求内容为空或过长' })
  let input: Record<string, unknown>
  try {
    input = JSON.parse(raw)
    if (!input || typeof input !== 'object' || Array.isArray(input))
      throw new Error('Expected object')
  }
  catch {
    throw createError({ statusCode: 400, statusMessage: '请求格式不正确' })
  }

  const { action, revision, shortName } = input
  const id = typeof input.id === 'string' ? input.id : ''
  if (action === 'publish')
    return publishWebBuild(id, user.uid, revision)
  if (action === 'withdraw')
    return withdrawWebBuild(id, user.uid, revision)
  if (action === 'submit') {
    if (personalTestSession || testPeerUid)
      throw createError({ statusCode: 403, message: '网页验收会话仅用于生成和分享' })
    return submitWebBuildToMarket(user, id, revision, shortName)
  }
  if (typeof action === 'string' && action.startsWith('room.')) {
    if (personalTestSession)
      throw createError({ statusCode: 403, statusMessage: '网页验收会话不支持多人协作' })
    if (testPeerUid && (action === 'room.invite' || action === 'room.join'))
      throw createError({ statusCode: 403, statusMessage: '请通过受管测试好友的邀请卡加入' })
    switch (action) {
      case 'room.invite': return createWebBuildRoomInvite(id, user)
      case 'room.revoke': return revokeWebBuildRoomInvite(id, user.uid)
      case 'room.join': return joinWebBuildRoom(typeof input.inviteCode === 'string' ? input.inviteCode.trim() : '', user)
      case 'room.inviteFriend': {
        const target = input.targetId
        if (typeof target !== 'string' || !target || target !== target.trim() || target.length > 128 || target === user.uid)
          throw createError({ statusCode: 400, statusMessage: '请选择互关好友' })
        return sendWebBuildFriendInvite(id, user, target, targetId => requireWebBuildInvitePeer(event, targetId, testPeerUid))
      }
      case 'room.acceptInvite': {
        const noticeId = input.inviteId
        if (typeof noticeId !== 'string' || !/^[a-f0-9]{24}$/.test(noticeId))
          throw createError({ statusCode: 400, statusMessage: '无效的项目邀请' })
        return acceptWebBuildFriendInvite(noticeId, user, targetId => requireWebBuildInvitePeer(event, targetId, testPeerUid))
      }
      case 'room.leave': return changeWebBuildRoomMembers(id, user.uid)
      case 'room.remove': {
        const memberId = input.memberId
        if (typeof memberId !== 'string' || !/^[a-f0-9]{32}$/.test(memberId))
          throw createError({ statusCode: 400, statusMessage: '无效的项目成员' })
        return changeWebBuildRoomMembers(id, user.uid, memberId)
      }
      case 'room.chat': {
        const text = typeof input.text === 'string' ? input.text.trim() : ''
        if (!text || text.length > 600)
          throw createError({ statusCode: 400, statusMessage: '请输入 1–600 字的聊天消息' })
        return sendWebBuildRoomMessage(id, user.uid, text)
      }
    }
  }
  if (action !== 'generate')
    throw createError({ statusCode: 400, statusMessage: '未知操作' })

  const prompt = typeof input.prompt === 'string' ? input.prompt.trim() : ''
  if (!prompt || prompt.length > 1000 || (input.id !== undefined && !id))
    throw createError({ statusCode: 400, statusMessage: '请输入 1–1000 字的网页需求' })
  const runtime = getWebBuildRuntimeConfig()
  if (!runtime)
    throw createError({ statusCode: 503, statusMessage: '网页生成服务暂未配置' })
  const token = parseBearerToken(getRequestHeader(event, 'authorization'))
  if (!token)
    throw createError({ statusCode: 401 })
  const prior = id ? await (personalTestSession ? getOwnedWebBuild(id, user.uid) : getEditableWebBuild(id, user.uid)) : undefined
  if (prior && prior.revision !== revision)
    throw createError({ statusCode: 409, statusMessage: '网页已有更新，请刷新后再试' })
  await reserveWebBuildAction(user.uid, 'generate')
  if (prior?.room) {
    if (personalTestSession)
      throw createError({ statusCode: 403, statusMessage: '网页验收会话不支持多人协作' })
    await moderateWebBuildRoomMessage(id, user.uid, prompt)
  }
  const page = await generateWebBuildPage(runtime, token, prompt, prior?.page ?? null)
  return saveWebBuildDraft(user.uid, page, prompt, prior)
})
