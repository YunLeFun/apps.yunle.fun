import type { H3Event } from 'h3'
import { Buffer } from 'node:buffer'
import { createHash } from 'node:crypto'
import { createError, getRequestHeader } from 'h3'

interface CachedAuthUser {
  user: ServerAuthUser
  expiresAt: number
}

export interface ServerAuthUser {
  uid: string
  name?: string
  picture?: string
}

interface CloudbaseUserProfile {
  sub?: string
  uid?: string
  id?: string
  name?: string
  nickname?: string
  picture?: string
  avatar_url?: string
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
  const envId = config.public.tcbEnvId
  if (!envId) {
    throw createError({
      statusCode: 500,
      message: 'CloudBase 环境未配置',
    })
  }

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

  const user: ServerAuthUser = {
    uid: profile.sub,
    name: profile.name || profile.nickname,
    picture: profile.picture || profile.avatar_url,
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
  }
}

function stringProp(value: Record<string, unknown>, key: string): string | undefined {
  const prop = value[key]
  return typeof prop === 'string' && prop ? prop : undefined
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
