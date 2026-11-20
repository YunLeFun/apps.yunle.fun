import { Buffer } from 'node:buffer'
import { createError, getRouterParam, readRawBody, setResponseHeader } from 'h3'
import { requireRegisteredCloudbaseUser } from '../../../../utils/cloudbase-auth'
import { actOnConversationCard, cardReference, getConversationCard } from '../../../../utils/conversation-cards'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  if (event.method !== 'GET' && event.method !== 'PATCH') {
    setResponseHeader(event, 'Allow', 'GET, PATCH')
    throw createError({ statusCode: 405, message: '请求方法不可用' })
  }
  const { uid } = await requireRegisteredCloudbaseUser(event)
  const reference = cardReference(getRouterParam(event, 'type'), getRouterParam(event, 'id'))
  if (event.method === 'GET')
    return getConversationCard(reference, uid)
  const body = await readRawBody(event)
  if (!body || Buffer.byteLength(body) > 1024)
    throw createError({ statusCode: 400, message: '卡片动作格式错误' })
  let action: unknown
  try {
    action = JSON.parse(body)
  }
  catch {
    throw createError({ statusCode: 400, message: '卡片动作格式错误' })
  }
  return actOnConversationCard(reference, uid, action)
})
