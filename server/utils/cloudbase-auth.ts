import type { H3Event } from 'h3'
import { Buffer } from 'node:buffer'
import { createHash } from 'node:crypto'
import { createError, getRequestHeader } from 'h3'
import { resolveCloudbaseEnvId } from './cloudbase-config'

interface CachedAuthUser {
  user: ServerAuthUser
  expiresAt: number
}

export interface ServerAuthUser {
  uid: string
  name?: string
  picture?: string
  handle?: string
  phoneVerified: boolean
  accountStatus: 'active' | 'suspended'
  anonymous: boolean
}

interface CloudbaseUserProfile {
  sub?: string
  uid?: string
  id?: string
  name?: string
  nickname?: string
  picture?: string
  avatar_url?: string
  username?: string
  preferred_username?: string
}

const CACHE_LIMIT = 500
const CACHE_MAX_TTL_MS = 5 * 60 * 1000
const authCache = new Map<string, CachedAuthUser>()

export function parseBearerToken(header: string | undefined | null): string | null {
  if (!header)
    return null
  const trimmed = header.trim()
  if (!trimmed.toLowerCase().startsWith('bearer '))
    return null
  return trimmed.slice(7).trim() || null
}

export function readJwtExpiry(token: string): number | null {
  const payloadPart = token.split('.')[1]
  if (!payloadPart)
    return null
  try {
    const payload = JSON.parse(base64UrlDecode(payloadPart)) as unknown
    if (!isRecord(payload) || typeof payload.exp !== 'number')
      return null
    return payload.exp * 1000
  }
  catch {
    return null
  }
}

export function clearCloudbaseAuthCache() {
  authCache.clear()
}

export async function requireCloudbaseUser(event: H3Event): Promise<ServerAuthUser> {
  const user = await verifyCloudbaseUser(event)
  if (!user) {
    throw createError({
      statusCode: 401,
      message: '请先登录',
    })
  }
  return user
}

/** 应用提交等高信任操作要求已验证手机号、非匿名且账号状态正常。 */
export async function requireVerifiedCloudbaseUser(event: H3Event): Promise<ServerAuthUser> {
  const user = await requireCloudbaseUser(event)
  if (user.anonymous) {
    throw createError({
      statusCode: 403,
      statusMessage: '匿名账号不能提交应用',
    })
  }
  if (!user.phoneVerified) {
    throw createError({
      statusCode: 403,
      statusMessage: '提交应用前请先验证云乐坊手机号',
    })
  }
  if (user.accountStatus !== 'active') {
    throw createError({
      statusCode: 403,
      statusMessage: '当前账号状态不能提交应用',
    })
  }
  return user
}

export async function tryGetCloudbaseUser(event: H3Event): Promise<ServerAuthUser | null> {
  return verifyCloudbaseUser(event)
}

async function verifyCloudbaseUser(event: H3Event): Promise<ServerAuthUser | null> {
  const authorization = getRequestHeader(event, 'authorization')
  const token = parseBearerToken(authorization)
  if (!token)
    return null

  const expiresAt = readJwtExpiry(token)
  if (expiresAt !== null && expiresAt <= Date.now())
    return null

  const cacheKey = hashToken(token)
  const cached = authCache.get(cacheKey)
  if (cached && cached.expiresAt > Date.now())
    return cached.user

  const config = useRuntimeConfig()
  const envId = resolveCloudbaseEnvId(config)

  const endpoint = `https://${envId}.api.tcloudbasegateway.com/auth/v1/user/me`
  let response: Response
  try {
    response = await fetch(endpoint, {
      headers: { Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(5000),
    })
  }
  catch {
    return null
  }

  if (!response.ok)
    return null

  const rawProfile = await response.json() as unknown
  const profile = normalizeCloudbaseProfile(rawProfile)
  if (!profile?.sub)
    return null
  const rawRecord = isRecord(rawProfile) ? rawProfile : {}
  const claims = readJwtPayload(token)

  const user: ServerAuthUser = {
    uid: profile.sub,
    name: profile.name || profile.nickname,
    picture: profile.picture || profile.avatar_url,
    handle: profile.username || profile.preferred_username,
    phoneVerified: hasVerifiedPhone(rawRecord, claims),
    accountStatus: accountIsSuspended(rawRecord, claims) ? 'suspended' : 'active',
    anonymous: isAnonymousCloudbaseUser(rawRecord, claims),
  }

  const ttl = expiresAt === null
    ? CACHE_MAX_TTL_MS
    : Math.max(0, Math.min(expiresAt - Date.now(), CACHE_MAX_TTL_MS))
  setAuthCache(cacheKey, user, Date.now() + ttl)

  return user
}

function setAuthCache(cacheKey: string, user: ServerAuthUser, expiresAt: number) {
  if (authCache.size >= CACHE_LIMIT) {
    const oldestKey = authCache.keys().next().value as string | undefined
    if (oldestKey)
      authCache.delete(oldestKey)
  }
  authCache.set(cacheKey, { user, expiresAt })
}

function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex')
}

function base64UrlDecode(value: string): string {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/')
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=')
  return Buffer.from(padded, 'base64').toString('utf8')
}

function normalizeCloudbaseProfile(value: unknown): CloudbaseUserProfile | null {
  if (!isRecord(value))
    return null
  return {
    sub: stringProp(value, 'sub') || stringProp(value, 'uid') || stringProp(value, 'id'),
    uid: stringProp(value, 'uid'),
    id: stringProp(value, 'id'),
    name: stringProp(value, 'name'),
    nickname: stringProp(value, 'nickname'),
    picture: stringProp(value, 'picture'),
    avatar_url: stringProp(value, 'avatar_url'),
    username: stringProp(value, 'username'),
    preferred_username: stringProp(value, 'preferred_username'),
  }
}

function readJwtPayload(token: string): Record<string, unknown> | null {
  const payloadPart = token.split('.')[1]
  if (!payloadPart)
    return null
  try {
    const payload = JSON.parse(base64UrlDecode(payloadPart)) as unknown
    return isRecord(payload) ? payload : null
  }
  catch {
    return null
  }
}

function nestedRecords(...values: unknown[]): Record<string, unknown>[] {
  return values.filter(isRecord)
}

function booleanProp(value: Record<string, unknown>, key: string): boolean | undefined {
  const prop = value[key]
  return typeof prop === 'boolean' ? prop : undefined
}

function firstBoolean(records: Record<string, unknown>[], ...keys: string[]): boolean | undefined {
  for (const record of records) {
    for (const key of keys) {
      const value = booleanProp(record, key)
      if (value !== undefined)
        return value
    }
  }
}

function hasVerifiedPhone(profile: Record<string, unknown>, claims: Record<string, unknown> | null): boolean {
  const records = nestedRecords(
    profile,
    claims,
    profile.user_metadata,
    profile.app_metadata,
    claims?.user_metadata,
    claims?.app_metadata,
  )
  const verified = firstBoolean(records, 'phoneVerified', 'phone_verified', 'phone_number_verified')
  if (verified !== undefined)
    return verified
  return records.some((record) => {
    const phone = record.phone
    return isRecord(phone) && firstBoolean([phone], 'verified', 'is_verified') === true
  })
}

function accountIsSuspended(profile: Record<string, unknown>, claims: Record<string, unknown> | null): boolean {
  const records = nestedRecords(profile, claims, profile.app_metadata, claims?.app_metadata)
  return records.some((record) => {
    const status = (
      stringProp(record, 'accountStatus')
      || stringProp(record, 'account_status')
      || stringProp(record, 'status')
      || ''
    ).toLowerCase()
    return firstBoolean([record], 'disabled', 'banned', 'suspended') === true
      || ['disabled', 'banned', 'suspended', 'deleted'].includes(status)
  })
}

function isAnonymousCloudbaseUser(profile: Record<string, unknown>, claims: Record<string, unknown> | null): boolean {
  const metadata = isRecord(profile.app_metadata)
    ? profile.app_metadata
    : isRecord(claims?.app_metadata)
      ? claims.app_metadata
      : {}
  const loginType = stringProp(profile, 'loginType') || stringProp(profile, 'login_type')
  return booleanProp(profile, 'is_anonymous') === true
    || booleanProp(claims ?? {}, 'is_anonymous') === true
    || loginType?.toUpperCase() === 'ANONYMOUS'
    || stringProp(profile, 'scope') === 'anonymous'
    || stringProp(claims ?? {}, 'scope') === 'anonymous'
    || stringProp(metadata, 'provider') === 'anonymous'
}

function stringProp(value: Record<string, unknown>, key: string): string | undefined {
  const prop = value[key]
  return typeof prop === 'string' && prop ? prop : undefined
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
