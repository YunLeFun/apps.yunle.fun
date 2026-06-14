import type { ServerAuthUser } from './cloudbase-auth'
import { createHash, randomBytes } from 'node:crypto'
import { createError } from 'h3'
import { useCloudbaseAdmin } from './cloudbase-admin'
import { isAllowedOrigin, readOriginRules } from './origin-rules'

const COLLECTION = 'jsapi_auth_codes'
const CODE_TTL_MS = 5 * 60 * 1000
const MAX_SCOPE_COUNT = 8
const MAX_SCOPE_LENGTH = 64
const CLOUDBASE_SESSION_SCOPE = 'cloudbase:session'

export interface CloudbaseSessionSnapshot {
  access_token: string
  refresh_token: string
}

export interface JsapiAuthCodeRecord {
  _id?: string
  codeHash: string
  uid: string
  user: {
    id: string
    nickname?: string
    avatar?: string
  }
  appId: string
  origin: string
  scope: string[]
  createdAt: number
  expiresAt: number
  consumedAt: number
  session?: CloudbaseSessionSnapshot
}

export interface JsapiAuthCodePayload {
  code: string
  expiresIn: number
  scope: string[]
}

export interface JsapiAuthExchangeResult {
  appId: string
  origin: string
  scope: string[]
  user: {
    id: string
    nickname?: string
    avatar?: string
  }
  session?: CloudbaseSessionSnapshot
}

interface RuntimeConfigLike {
  jsapiAuthAllowedOrigins?: unknown
}

const DEFAULT_ALLOWED_ORIGINS = 'https://*.yunle.fun,https://*.yunyoujun.cn'

export function resolveJsapiAuthAllowedOrigins(config: RuntimeConfigLike): string {
  return typeof config.jsapiAuthAllowedOrigins === 'string' && config.jsapiAuthAllowedOrigins.trim()
    ? config.jsapiAuthAllowedOrigins
    : DEFAULT_ALLOWED_ORIGINS
}

export function normalizeOrigin(value: unknown): string {
  if (typeof value !== 'string')
    return ''
  try {
    return new URL(value).origin
  }
  catch {
    return ''
  }
}

export function assertAllowedJsapiOrigin(origin: string, config = useRuntimeConfig()): void {
  const rules = readOriginRules(resolveJsapiAuthAllowedOrigins(config))
  if (!origin || !isAllowedOrigin(origin, rules)) {
    throw createError({
      statusCode: 403,
      message: '当前域名未开通云乐坊登录能力',
    })
  }
}

export function normalizeScope(value: unknown): string[] {
  const raw = Array.isArray(value)
    ? value
    : typeof value === 'string'
      ? value.split(/[,\s]+/)
      : []

  const scope = new Set<string>()
  for (const item of raw) {
    if (typeof item !== 'string')
      continue
    const trimmed = item.trim()
    if (!trimmed || trimmed.length > MAX_SCOPE_LENGTH)
      continue
    if (!/^[a-z][\w:-]*$/i.test(trimmed))
      continue
    scope.add(trimmed)
    if (scope.size >= MAX_SCOPE_COUNT)
      break
  }

  if (scope.size === 0)
    scope.add('profile')
  return [...scope]
}

export function normalizeCloudbaseSession(value: unknown): CloudbaseSessionSnapshot | undefined {
  if (!isRecord(value))
    return undefined
  const accessToken = stringProp(value, 'access_token')
  const refreshToken = stringProp(value, 'refresh_token')
  if (!accessToken || !refreshToken)
    return undefined
  return {
    access_token: accessToken,
    refresh_token: refreshToken,
  }
}

export async function createJsapiAuthCode(input: {
  user: ServerAuthUser
  appId: string
  origin: string
  scope: string[]
  session?: CloudbaseSessionSnapshot
}): Promise<JsapiAuthCodePayload> {
  const now = Date.now()
  const code = randomBytes(32).toString('base64url')
  const userSnapshot: JsapiAuthCodeRecord['user'] = { id: input.user.uid }
  if (input.user.name)
    userSnapshot.nickname = input.user.name
  if (input.user.picture)
    userSnapshot.avatar = input.user.picture

  const record: JsapiAuthCodeRecord = {
    codeHash: hashCode(code),
    uid: input.user.uid,
    user: userSnapshot,
    appId: input.appId,
    origin: input.origin,
    scope: input.scope,
    createdAt: now,
    expiresAt: now + CODE_TTL_MS,
    consumedAt: 0,
  }
  if (input.scope.includes(CLOUDBASE_SESSION_SCOPE) && input.session)
    record.session = input.session

  const { db } = useCloudbaseAdmin()
  await db.collection(COLLECTION).add(record)

  return {
    code,
    expiresIn: Math.floor(CODE_TTL_MS / 1000),
    scope: input.scope,
  }
}

export async function consumeJsapiAuthCode(input: {
  code: string
  origin: string
}): Promise<JsapiAuthExchangeResult> {
  const code = typeof input.code === 'string' ? input.code.trim() : ''
  if (!code) {
    throw createError({
      statusCode: 400,
      message: '缺少授权码',
    })
  }

  const { db } = useCloudbaseAdmin()
  const collection = db.collection(COLLECTION)
  const result = await collection
    .where({ codeHash: hashCode(code) })
    .limit(1)
    .get()

  const record = normalizeRecord(result.data?.[0])
  if (!record) {
    throw createError({
      statusCode: 400,
      message: '授权码无效',
    })
  }
  if (record.origin !== input.origin) {
    throw createError({
      statusCode: 403,
      message: '授权码来源不匹配',
    })
  }
  if (record.consumedAt) {
    throw createError({
      statusCode: 400,
      message: '授权码已使用',
    })
  }
  if (record.expiresAt <= Date.now()) {
    throw createError({
      statusCode: 400,
      message: '授权码已过期',
    })
  }

  if (record._id)
    await collection.doc(record._id).update({ consumedAt: Date.now() })

  const exchange: JsapiAuthExchangeResult = {
    appId: record.appId,
    origin: record.origin,
    scope: record.scope,
    user: record.user,
  }
  if (record.scope.includes(CLOUDBASE_SESSION_SCOPE) && record.session)
    exchange.session = record.session
  return exchange
}

function hashCode(code: string): string {
  return createHash('sha256').update(code).digest('hex')
}

function normalizeRecord(value: unknown): JsapiAuthCodeRecord | null {
  if (!isRecord(value))
    return null
  const codeHash = stringProp(value, 'codeHash')
  const uid = stringProp(value, 'uid')
  const appId = stringProp(value, 'appId')
  const origin = stringProp(value, 'origin')
  const createdAt = numberProp(value, 'createdAt')
  const expiresAt = numberProp(value, 'expiresAt')
  const consumedAt = numberProp(value, 'consumedAt') ?? 0
  const session = normalizeCloudbaseSession(value.session)
  const user = isRecord(value.user) ? value.user : {}
  const id = stringProp(user, 'id') || uid
  if (!codeHash || !uid || !id || !appId || !origin || !createdAt || !expiresAt)
    return null

  return {
    _id: stringProp(value, '_id'),
    codeHash,
    uid,
    user: {
      id,
      nickname: stringProp(user, 'nickname'),
      avatar: stringProp(user, 'avatar'),
    },
    appId,
    origin,
    scope: Array.isArray(value.scope) ? value.scope.filter((item): item is string => typeof item === 'string') : ['profile'],
    createdAt,
    expiresAt,
    consumedAt,
    session,
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}

function stringProp(value: Record<string, unknown>, key: string): string | undefined {
  const field = value[key]
  return typeof field === 'string' && field.trim() ? field : undefined
}

function numberProp(value: Record<string, unknown>, key: string): number | undefined {
  const field = value[key]
  return typeof field === 'number' ? field : undefined
}
