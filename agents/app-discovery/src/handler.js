import { Buffer } from 'node:buffer'
import { randomUUID } from 'node:crypto'
import { searchAppsInMemory } from './search.js'

const MAX_BODY = 128 * 1024
export class AgentHttpError extends Error {
  constructor(statusCode, code) {
    super(code)
    this.statusCode = statusCode
    this.code = code
  }
}
function fail(status, code) {
  throw new AgentHttpError(status, code)
}
function record(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function safeCount(value) {
  return Number.isSafeInteger(value) && value >= 0
}
function activeProfile(profile) {
  const rows = [profile, profile.app_metadata, profile.user_metadata].filter(record)
  return !rows.some(row =>
    ['blocked', 'disabled', 'banned', 'suspended', 'deleted'].includes(String(row.accountStatus || row.account_status || row.status || '').toLowerCase())
    || row.disabled === true || row.banned === true || row.suspended === true
    || row.is_anonymous === true || row.isAnonymous === true || row.scope === 'anonymous'
    || String(row.loginType || row.login_type || row.provider || '').toLowerCase() === 'anonymous')
}
export async function authorizeAgent(token, { envId, fetchImpl = fetch, now = Date.now }) {
  if (typeof envId !== 'string' || !/^[\w-]+$/.test(envId))
    fail(503, 'ACCOUNT_UNAVAILABLE')
  if (!token)
    fail(401, 'UNAUTHENTICATED')
  const gateway = `https://${envId}.api.tcloudbasegateway.com`
  const request = async (path, fields) => {
    let response
    try {
      response = await fetchImpl(gateway + path, {
        method: fields ? 'POST' : 'GET',
        redirect: 'error',
        cache: 'no-store',
        headers: { Authorization: `Bearer ${token}`, ...(fields ? { 'Content-Type': 'application/json' } : {}) },
        ...(fields ? { body: JSON.stringify(fields) } : {}),
        signal: AbortSignal.timeout(8000),
      })
    }
    catch { return fail(503, 'ACCOUNT_UNAVAILABLE') }
    if (response.status === 401)
      fail(401, 'UNAUTHENTICATED')
    if (response.status === 403)
      fail(403, 'ACCOUNT_RESTRICTED')
    if (!response.ok)
      fail(503, 'ACCOUNT_UNAVAILABLE')
    try {
      return await response.json()
    }
    catch { return fail(503, 'ACCOUNT_UNAVAILABLE') }
  }
  const profile = await request('/auth/v1/user/me')
  const uid = record(profile) && (profile.sub || profile.uid || profile.id)
  if (typeof uid !== 'string' || !uid || ['anon', 'anonymous'].includes(uid) || !activeProfile(profile))
    fail(403, 'ACCOUNT_RESTRICTED')
  // The existing account service also enforces account restrictions/deletion.
  // Do not trust a legacy membership isActive flag or duplicate its database rules here.
  const account = await request('/v1/functions/account-api', { action: 'getAccount' })
  if (!record(account) || !safeCount(account.coin) || !record(account.membership)
    || typeof account.membership.isActive !== 'boolean') {
    fail(503, 'ACCOUNT_UNAVAILABLE')
  }
  if (!account.membership.isActive || !Number.isFinite(account.membership.expireAt) || account.membership.expireAt <= now())
    fail(403, 'MEMBERSHIP_REQUIRED')
  return { uid }
}
function localDateKey(now) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(now))
}
export async function takeDailyUsage(db, uid, limit, now = Date.now()) {
  if (!Number.isSafeInteger(limit) || limit <= 0 || limit > 100000)
    fail(503, 'USAGE_UNAVAILABLE')
  const date = localDateKey(now)
  return db.runTransaction(async (transaction) => {
    const doc = transaction.collection('agent_usage').doc(`${uid}_${date}`)
    const response = await doc.get()
    if (response?.code)
      fail(503, 'USAGE_UNAVAILABLE')
    const value = Array.isArray(response?.data) ? response.data[0] : response?.data
    if (value && (!record(value) || value.uid !== uid || value.date !== date || !safeCount(value.count)))
      fail(503, 'USAGE_UNAVAILABLE')
    const count = value?.count || 0
    if (count >= limit)
      fail(429, 'DAILY_LIMIT_EXCEEDED')
    const fields = { count: count + 1, monthCount: safeCount(value?.monthCount) ? value.monthCount + 1 : count + 1, updatedAt: now }
    const result = value ? await doc.update(fields) : await doc.set({ uid, date, ...fields, createdAt: now })
    if (result?.code || (value && result?.updated === 0))
      fail(503, 'USAGE_UNAVAILABLE')
    return { count: count + 1, limit }
  })
}
export function validateAgentInput(body) {
  if (!record(body) || typeof body.threadId !== 'string' || typeof body.runId !== 'string'
    || !/^[\w-]{1,128}$/.test(body.threadId) || !/^[\w-]{1,128}$/.test(body.runId)
    || !Array.isArray(body.messages) || body.messages.length === 0 || body.messages.length > 32) {
    fail(400, 'BAD_REQUEST')
  }
  for (const message of body.messages) {
    if (!record(message) || !['user', 'assistant'].includes(message.role) || typeof message.content !== 'string'
      || message.content.length > 8000) {
      fail(400, 'BAD_REQUEST')
    }
  }
  const prompt = [...body.messages].reverse().find(message => message.role === 'user')?.content.trim()
  if (!prompt)
    fail(400, 'BAD_REQUEST')
  return { threadId: body.threadId, runId: body.runId, prompt }
}
async function readBody(req) {
  if (Number(req.headers['content-length']) > MAX_BODY)
    fail(413, 'REQUEST_TOO_LARGE')
  const chunks = []
  let size = 0
  for await (const chunk of req) {
    size += chunk.length
    if (size > MAX_BODY)
      fail(413, 'REQUEST_TOO_LARGE')
    chunks.push(chunk)
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'))
  }
  catch { return fail(400, 'BAD_REQUEST') }
}
function json(res, status, value) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'private, no-store' })
  res.end(JSON.stringify(value))
}
const publicMessages = {
  UNAUTHENTICATED: '请先登录',
  ACCOUNT_RESTRICTED: '当前账号暂不能使用 AI 助手',
  MEMBERSHIP_REQUIRED: 'AI 助手需要有效会员',
  ACCOUNT_UNAVAILABLE: '暂时无法核对账户状态',
  DAILY_LIMIT_EXCEEDED: '今日 AI 助手使用次数已达上限',
  USAGE_UNAVAILABLE: '暂时无法核对使用次数',
  BAD_REQUEST: '请重新输入问题',
  REQUEST_TOO_LARGE: '对话内容过长，请开始新对话',
  INTERNAL_ERROR: 'AI 助手暂时不可用',
}
function emit(res, event) {
  if (!res.destroyed)
    res.write(`data: ${JSON.stringify(event)}\n\n`)
}
export function createDiscoveryHandler({ db, envId, region = 'ap-shanghai', dailyLimit = 50, fetchImpl = fetch, now = Date.now }) {
  const publicCatalog = async () => {
    const response = await fetchImpl('https://apps.yunle.fun/api/apps/public', {
      redirect: 'error',
      cache: 'no-store',
      signal: AbortSignal.timeout(10000),
      headers: { Accept: 'application/json' },
    })
    if (!response.ok)
      fail(503, 'INTERNAL_ERROR')
    const value = await response.json()
    if (!record(value) || !Array.isArray(value.items) || value.items.length > 1000)
      fail(503, 'INTERNAL_ERROR')
    return value.items
  }
  return async (req, res) => {
    const path = new URL(req.url || '/', 'http://localhost').pathname
    if (req.method === 'OPTIONS') {
      res.writeHead(204, {
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'GET,POST,OPTIONS',
        'access-control-allow-headers': 'authorization,content-type,x-sdk-version,x-client-timestamp',
        'access-control-max-age': '300',
      })
      res.end()
      return
    }
    if (req.method === 'GET' && path.endsWith('/healthz')) {
      json(res, 200, { ok: true, envId, region })
      return
    }
    if (req.method !== 'POST' || !path.endsWith('/send-message')) {
      json(res, 404, { code: 'NOT_FOUND', message: 'Not found' })
      return
    }
    let input
    try {
      const header = req.headers.authorization
      const token = typeof header === 'string' && /^bearer /i.test(header.trim()) ? header.trim().slice(7).trim() : ''
      if (!token)
        fail(401, 'UNAUTHENTICATED')
      input = validateAgentInput(await readBody(req))
      const user = await authorizeAgent(token, { envId, fetchImpl, now })
      const usage = await takeDailyUsage(db, user.uid, dailyLimit, now())
      res.writeHead(200, { 'content-type': 'text/event-stream; charset=utf-8', 'cache-control': 'private, no-store, no-transform', 'x-accel-buffering': 'no' })
      const messageId = `msg_${randomUUID()}`
      const toolCallId = `tool_${randomUUID()}`
      emit(res, { type: 'RUN_STARTED', threadId: input.threadId, runId: input.runId })
      emit(res, { type: 'TEXT_MESSAGE_START', messageId, role: 'assistant' })
      const text = (content) => {
        // This deployed assistant is a deterministic discovery service; no new model or billing is introduced.
        for (let index = 0; index < content.length; index += 14)
          emit(res, { type: 'TEXT_MESSAGE_CONTENT', messageId, delta: content.slice(index, index + 14) })
      }
      if (/应用|工具|开发|代码|写作|游戏|推荐|找|搜索|app|tool|game|code|dev/i.test(input.prompt)) {
        text('我先检索云乐坊已发布的公开应用，再把匹配结果整理成卡片。')
        const args = { query: input.prompt, limit: 6 }
        emit(res, { type: 'TOOL_CALL_START', toolCallId, toolCallName: 'search_apps', parentMessageId: messageId })
        emit(res, { type: 'TOOL_CALL_ARGS', toolCallId, delta: JSON.stringify(args) })
        emit(res, { type: 'TOOL_CALL_END', toolCallId })
        const apps = searchAppsInMemory(await publicCatalog(), args)
        if (res.destroyed)
          return
        emit(res, { type: 'TOOL_CALL_RESULT', toolCallId, messageId: `toolmsg_${randomUUID()}`, content: JSON.stringify({ apps }) })
        text(apps.length ? `\n\n找到 ${apps.length} 个相关应用，请查看下面的卡片。` : '\n\n暂时没有找到匹配的公开应用，可以换个关键词再试。')
      }
      else {
        text('你好，我是云乐坊 AI 助手。告诉我想找哪类应用，我会返回可查看和获取的应用卡片。')
      }
      emit(res, { type: 'STATE_SNAPSHOT', snapshot: { usage } })
      emit(res, { type: 'TEXT_MESSAGE_END', messageId })
      emit(res, { type: 'RUN_FINISHED', threadId: input.threadId, runId: input.runId })
      res.end()
    }
    catch (error) {
      const known = error instanceof AgentHttpError
      const code = known ? error.code : 'INTERNAL_ERROR'
      const message = publicMessages[code] || publicMessages.INTERNAL_ERROR
      if (res.destroyed)
        return
      if (res.headersSent) {
        emit(res, { type: 'RUN_ERROR', code, message, ...(input ? { runId: input.runId, threadId: input.threadId } : {}) })
        res.end()
      }
      else {
        json(res, known ? error.statusCode : 503, { code, message })
      }
    }
  }
}
