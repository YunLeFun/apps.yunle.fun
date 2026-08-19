import { Buffer } from 'node:buffer'
import { randomUUID } from 'node:crypto'
import http from 'node:http'
import process from 'node:process'
import cloudbase from '@cloudbase/node-sdk'
import { normalizeLimit, searchAppsInMemory } from './search.js'

const ENV_ID = process.env.CLOUDBASE_ENV_ID
  || process.env.TCB_ENV_ID
  || process.env.NUXT_PUBLIC_TCB_ENV_ID
  || 'yunlefun-8g7ybcxc7345c490'
const REGION = process.env.CLOUDBASE_REGION || process.env.TCB_REGION || 'ap-shanghai'
const PORT = Number(process.env.PORT || 9000)
const DAILY_LIMIT = Number(process.env.AGENT_DAILY_LIMIT || 50)
const CANDIDATE_LIMIT = Number(process.env.AGENT_SEARCH_CANDIDATE_LIMIT || 100)

const app = cloudbase.init({ env: ENV_ID })
const db = app.database()
const command = db.command

class HttpError extends Error {
  constructor(statusCode, message, code) {
    super(message)
    this.name = 'HttpError'
    this.statusCode = statusCode
    this.code = code
  }
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  })
  res.end(JSON.stringify(payload))
}

function sendOptions(res, req) {
  const origin = req.headers.origin
  res.writeHead(204, {
    'access-control-allow-origin': origin || '*',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'authorization,content-type,x-sdk-version,x-client-timestamp',
    'access-control-max-age': '300',
    'vary': 'Origin,Access-Control-Request-Method,Access-Control-Request-Headers',
  })
  res.end()
}

function writeSse(res, event) {
  res.write(`data: ${JSON.stringify(event)}\n\n`)
}

function startSse(res) {
  res.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache, no-transform',
    'connection': 'keep-alive',
    'x-accel-buffering': 'no',
  })
}

async function readJsonBody(req) {
  const chunks = []
  for await (const chunk of req)
    chunks.push(chunk)
  const raw = Buffer.concat(chunks).toString('utf8')
  if (!raw)
    return {}
  try {
    return JSON.parse(raw)
  }
  catch {
    throw new HttpError(400, '请求参数无效', 'BAD_REQUEST')
  }
}

function bearerToken(req) {
  const value = req.headers.authorization
  if (!value || Array.isArray(value))
    return ''
  const trimmed = value.trim()
  return trimmed.toLowerCase().startsWith('bearer ') ? trimmed.slice(7).trim() : ''
}

function decodeJwtPayload(token) {
  const payload = token.split('.')[1]
  if (!payload)
    return null
  try {
    const normalized = payload.replace(/-/g, '+').replace(/_/g, '/')
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=')
    return JSON.parse(Buffer.from(padded, 'base64').toString('utf8'))
  }
  catch {
    return null
  }
}

async function verifyUser(req) {
  const token = bearerToken(req)
  if (!token)
    throw new HttpError(401, '请先登录', 'UNAUTHENTICATED')

  const jwtPayload = decodeJwtPayload(token)
  if (jwtPayload?.exp && jwtPayload.exp * 1000 <= Date.now())
    throw new HttpError(401, '登录已过期', 'TOKEN_EXPIRED')

  let profile = null
  try {
    const response = await fetch(`https://${ENV_ID}.api.tcloudbasegateway.com/auth/v1/user/me`, {
      headers: { Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(5000),
    })
    if (!response.ok)
      throw new Error(`CloudBase auth rejected token with ${response.status}`)
    profile = await response.json()
  }
  catch (error) {
    console.warn('[agent] user profile verification request failed:', error instanceof Error ? error.message : 'unknown error')
    throw new HttpError(401, '请先登录', 'UNAUTHENTICATED')
  }

  const uid = stringValue(profile?.sub)
    || stringValue(profile?.uid)
    || stringValue(profile?.id)

  if (!uid || uid === 'anon')
    throw new HttpError(401, '请先登录', 'UNAUTHENTICATED')

  return {
    uid,
    name: stringValue(profile?.name) || stringValue(profile?.nickname) || '',
  }
}

async function requireMembership(uid) {
  const now = Date.now()
  const { data } = await db
    .collection('user_memberships')
    .where({ userId: uid })
    .limit(1)
    .get()

  const membership = Array.isArray(data) ? data[0] : null
  const expireAt = numberValue(membership?.expireAt) || numberValue(membership?.expiresAt) || 0
  const activeByStatus = membership?.status === undefined || membership?.status === 'active' || membership?.status === 'paid'
  const isActive = membership?.isActive === true || (expireAt > now && activeByStatus)

  if (!isActive) {
    throw new HttpError(403, 'AI 助手是会员功能，请先开通会员', 'MEMBERSHIP_REQUIRED')
  }

  return {
    expireAt,
    level: stringValue(membership?.level) || 'member',
  }
}

function localDateKey(date = new Date()) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  })
  return formatter.format(date)
}

async function checkDailyUsage(uid) {
  const date = localDateKey()
  const id = `${uid}_${date}`
  const doc = db.collection('agent_usage').doc(id)
  const now = Date.now()

  let nextCount = 1
  try {
    const existing = await doc.get()
    const record = Array.isArray(existing.data) ? existing.data[0] : existing.data
    if (!record)
      throw new Error('usage record not found')
    nextCount = (numberValue(record?.count) || 0) + 1
    await doc.update({
      count: command.inc(1),
      monthCount: command.inc(1),
      updatedAt: now,
    })
  }
  catch {
    await doc.set({
      uid,
      date,
      count: 1,
      monthCount: 1,
      createdAt: now,
      updatedAt: now,
    })
  }

  if (nextCount > DAILY_LIMIT) {
    throw new HttpError(429, '今日 AI 助手使用次数已达上限', 'DAILY_LIMIT_EXCEEDED')
  }

  return {
    count: nextCount,
    limit: DAILY_LIMIT,
  }
}

async function searchApps(input) {
  const limit = normalizeLimit(input.limit)
  const where = {
    isPublic: true,
    status: 'approved',
  }
  if (stringValue(input.category))
    where.category = stringValue(input.category)

  const { data } = await db
    .collection('apps')
    .where(where)
    .orderBy('updatedAt', 'desc')
    .limit(CANDIDATE_LIMIT)
    .get()

  return searchAppsInMemory(Array.isArray(data) ? data : [], {
    query: stringValue(input.query) || '',
    category: stringValue(input.category),
    limit,
  })
}

function stringValue(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined
}

function numberValue(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined
}

function latestUserContent(body) {
  const messages = Array.isArray(body.messages) ? body.messages : []
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index]
    if (message?.role === 'user' && stringValue(message.content))
      return stringValue(message.content)
  }
  return ''
}

function shouldSearchApps(prompt) {
  return /应用|工具|开发|代码|写作|游戏|推荐|找|搜索|app|tool|game|code|dev/i.test(prompt)
}

function chunkText(text, size = 14) {
  const chunks = []
  for (let index = 0; index < text.length; index += size)
    chunks.push(text.slice(index, index + size))
  return chunks
}

async function handleSendMessage(req, res) {
  const body = await readJsonBody(req)
  const user = await verifyUser(req)
  await requireMembership(user.uid)
  const usage = await checkDailyUsage(user.uid)

  const threadId = stringValue(body.threadId) || `thread_${randomUUID()}`
  const runId = stringValue(body.runId) || `run_${randomUUID()}`
  const messageId = `msg_${randomUUID()}`
  const toolCallId = `tool_${randomUUID()}`
  const toolMessageId = `toolmsg_${randomUUID()}`
  const prompt = latestUserContent(body) || '你好'

  startSse(res)
  writeSse(res, { type: 'RUN_STARTED', threadId, runId })
  writeSse(res, { type: 'TEXT_MESSAGE_START', messageId, role: 'assistant' })

  if (!shouldSearchApps(prompt)) {
    const reply = `你好，我是云乐坊 AI 助手。你可以告诉我想找哪类应用，我会返回可打开或安装的应用卡片。`
    for (const delta of chunkText(reply))
      writeSse(res, { type: 'TEXT_MESSAGE_CONTENT', messageId, delta })
    writeSse(res, { type: 'TEXT_MESSAGE_END', messageId })
    writeSse(res, { type: 'RUN_FINISHED', threadId, runId })
    res.end()
    return
  }

  const intro = '我先检索云乐坊已公开审核的应用，再把匹配结果整理成卡片。'
  for (const delta of chunkText(intro))
    writeSse(res, { type: 'TEXT_MESSAGE_CONTENT', messageId, delta })

  const args = { query: prompt, limit: 6 }
  writeSse(res, { type: 'TOOL_CALL_START', toolCallId, toolCallName: 'search_apps', parentMessageId: messageId })
  writeSse(res, { type: 'TOOL_CALL_ARGS', toolCallId, delta: JSON.stringify(args) })
  writeSse(res, { type: 'TOOL_CALL_END', toolCallId })

  const apps = await searchApps(args)
  writeSse(res, {
    type: 'TOOL_CALL_RESULT',
    toolCallId,
    messageId: toolMessageId,
    content: JSON.stringify({ apps }),
  })

  const summary = apps.length > 0
    ? `\n\n找到 ${apps.length} 个相关应用，优先看下面这些卡片。`
    : '\n\n暂时没有找到匹配的公开应用，可以换个关键词再试。'
  for (const delta of chunkText(summary))
    writeSse(res, { type: 'TEXT_MESSAGE_CONTENT', messageId, delta })

  writeSse(res, {
    type: 'STATE_SNAPSHOT',
    snapshot: {
      usage,
      user: { uid: user.uid },
    },
  })
  writeSse(res, { type: 'TEXT_MESSAGE_END', messageId })
  writeSse(res, { type: 'RUN_FINISHED', threadId, runId })
  res.end()
}

async function handleRequest(req, res) {
  if (req.method === 'OPTIONS') {
    sendOptions(res, req)
    return
  }

  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`)
  if (req.method === 'GET' && url.pathname.endsWith('/healthz')) {
    sendJson(res, 200, { ok: true, envId: ENV_ID, region: REGION })
    return
  }

  if (req.method === 'POST' && url.pathname.endsWith('/send-message')) {
    try {
      await handleSendMessage(req, res)
    }
    catch (error) {
      if (error instanceof HttpError) {
        sendJson(res, error.statusCode, {
          code: error.code,
          message: error.message,
        })
        return
      }

      console.error('[agent] send-message failed:', error)
      sendJson(res, 500, {
        code: 'INTERNAL_ERROR',
        message: 'AI 助手暂时不可用',
      })
    }
    return
  }

  sendJson(res, 404, { code: 'NOT_FOUND', message: 'Not found' })
}

const server = http.createServer((req, res) => {
  handleRequest(req, res).catch((error) => {
    console.error('[agent] unhandled request error:', error)
    if (!res.headersSent)
      sendJson(res, 500, { code: 'INTERNAL_ERROR', message: 'AI 助手暂时不可用' })
    else
      res.end()
  })
})

server.listen(PORT, () => {
  console.warn(`[agent] YunLeFun app discovery agent listening on ${PORT}`)
})
