import { Buffer } from 'node:buffer'
import { createError, getRequestHeader, readRawBody, setResponseHeader } from 'h3'
import { parseBearerToken } from '../../utils/cloudbase-auth'
import { requireWebBuildMember } from '../../utils/web-build-access'
import { getWebBuildTestSession, requireWebBuildEditor } from '../../utils/web-build-config'
import { submitWebBuildToMarket } from '../../utils/web-build-market'
import { generateWebBuildPage, getWebBuildRuntimeConfig } from '../../utils/web-build-model'
import {
  getOwnedWebBuild,
  publishWebBuild,
  reserveWebBuildAction,
  saveWebBuildDraft,
  withdrawWebBuild,
} from '../../utils/web-build-storage'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  requireWebBuildEditor(event)
  const user = await requireWebBuildMember(event)
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
    if (getWebBuildTestSession(event))
      throw createError({ statusCode: 403, message: '网页验收会话仅用于生成和分享' })
    return submitWebBuildToMarket(user, id, revision, shortName)
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
  const prior = id ? await getOwnedWebBuild(id, user.uid) : undefined
  if (prior && prior.revision !== revision)
    throw createError({ statusCode: 409, statusMessage: '网页已有更新，请刷新后再试' })
  await reserveWebBuildAction(user.uid, 'generate')
  const page = await generateWebBuildPage(runtime, token, prompt, prior?.page ?? null)
  return saveWebBuildDraft(user.uid, page, prompt, prior)
})
