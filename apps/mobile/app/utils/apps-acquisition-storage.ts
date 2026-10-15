import type { AcquisitionContext, AcquisitionTouch } from './acquisition'
import { sanitizeAcquisitionContext } from './acquisition'

export type AppsAcquisitionAuthMethod = 'phone_otp' | 'email_otp' | 'github' | 'wx_open' | 'unknown'

export interface AppsAcquisitionAttempt {
  id: string
  createdAt: number
  context: AcquisitionContext | null
  authMethod: AppsAcquisitionAuthMethod
  oauthState?: string
  delegatedSso?: true
}

export interface AppsAcquisitionPending extends AppsAcquisitionAttempt {
  userId: string
  attempts: number
  nextRetryAt: number
}

export interface AcquisitionStorage {
  getItem: (key: string) => string | null
  setItem: (key: string, value: string) => void
  removeItem: (key: string) => void
}

export const APPS_ACQUISITION_WINDOW_MS = 30 * 60 * 1000
export const APPS_ACQUISITION_FIRST_WINDOW_MS = 30 * 24 * 60 * 60 * 1000
export const APPS_ACQUISITION_MAX_ATTEMPTS = 3
export const APPS_ACQUISITION_ORIGIN = 'https://apps.yunle.fun'
export const APPS_ACQUISITION_KEYS = {
  first: 'ylf:apps-acquisition:first:v1',
  entry: 'ylf:apps-acquisition:entry:v1',
  attempt: 'ylf:apps-acquisition:attempt:v1',
  pending: 'ylf:apps-acquisition:pending:v1',
  callback: 'ylf:apps-acquisition:callback:v1',
} as const

const METHODS = new Set<AppsAcquisitionAuthMethod>(['phone_otp', 'email_otp', 'github', 'wx_open', 'unknown'])
// eslint-disable-next-line no-control-regex -- Never retain control characters in attribution.
const CONTROL_RE = /[\u0000-\u001F\u007F-\u009F]/
const UTM_RE = /^[\p{L}\p{N}\p{M} ._/-]*$/u

/** Separate Apps storage never reads a third-party SSO acquisition query or broker request. */
export function createAppsAcquisitionStorage(options: {
  local?: AcquisitionStorage
  session?: AcquisitionStorage
  now?: () => number
  createId?: () => string
} = {}) {
  const now = options.now || Date.now
  const createId = options.createId || (() => globalThis.crypto?.randomUUID?.() || `${now()}-${Math.random().toString(36).slice(2)}`)
  const memory = new Map<string, unknown>()
  const unavailableKeys = new Set<string>()

  function read(key: string, storage?: AcquisitionStorage): unknown {
    if (!storage)
      return memory.get(key)
    try {
      const raw = storage.getItem(key)
      if (unavailableKeys.has(key))
        return memory.get(key)
      if (!raw || new TextEncoder().encode(raw).byteLength > 6144) {
        memory.delete(key)
        return undefined
      }
      let parsed: unknown
      try {
        parsed = JSON.parse(raw) as unknown
      }
      catch {
        memory.delete(key)
        return undefined
      }
      memory.set(key, parsed)
      return parsed
    }
    catch {
      // Restricted WebViews keep the same attempt in memory for this process.
    }
    return memory.get(key)
  }

  function write(key: string, value: unknown, storage?: AcquisitionStorage) {
    memory.set(key, value)
    try {
      storage?.setItem(key, JSON.stringify(value))
      unavailableKeys.delete(key)
    }
    catch {
      unavailableKeys.add(key)
      // Storage is optional; recording must never interrupt authentication.
    }
  }

  function remove(key: string, storage?: AcquisitionStorage) {
    memory.delete(key)
    try {
      storage?.removeItem(key)
      unavailableKeys.delete(key)
    }
    catch {
      unavailableKeys.add(key)
      // Memory has already discarded this attempt.
    }
  }

  function context(input: unknown, capturedAt = now()): AcquisitionContext | null {
    const value = sanitizeAcquisitionContext(input)
    if (!value || !recent(value.firstTouch.capturedAt, APPS_ACQUISITION_FIRST_WINDOW_MS, capturedAt)
      || !recent(value.registerTouch.capturedAt, APPS_ACQUISITION_FIRST_WINDOW_MS, capturedAt)) {
      return null
    }
    return value
  }

  function recent(timestamp: number, window: number, at = now()) {
    return Number.isSafeInteger(timestamp) && timestamp > 0
      && timestamp <= at + 60_000 && at - timestamp <= window
  }

  function readAttempt(): AppsAcquisitionAttempt | null {
    const value = read(APPS_ACQUISITION_KEYS.attempt, options.session)
    if (!isRecord(value) || typeof value.id !== 'string' || !value.id || value.id.length > 128
      || typeof value.createdAt !== 'number' || !recent(value.createdAt, APPS_ACQUISITION_WINDOW_MS)
      || typeof value.authMethod !== 'string' || !METHODS.has(value.authMethod as AppsAcquisitionAuthMethod)
      || (value.oauthState !== undefined && (typeof value.oauthState !== 'string' || !value.oauthState || value.oauthState.length > 200))) {
      remove(APPS_ACQUISITION_KEYS.attempt, options.session)
      return null
    }
    const captured = value.context === null ? null : context(value.context, value.createdAt)
    if (value.context !== null && !captured)
      return null
    return {
      id: value.id,
      createdAt: value.createdAt,
      context: captured,
      authMethod: value.authMethod as AppsAcquisitionAuthMethod,
      ...(typeof value.oauthState === 'string' ? { oauthState: value.oauthState } : {}),
      ...(value.delegatedSso === true ? { delegatedSso: true } : {}),
    }
  }

  function readPending(): AppsAcquisitionPending | null {
    const value = read(APPS_ACQUISITION_KEYS.pending, options.session)
    if (!isRecord(value) || typeof value.id !== 'string' || !value.id || value.id.length > 128
      || typeof value.createdAt !== 'number' || !recent(value.createdAt, APPS_ACQUISITION_WINDOW_MS)
      || typeof value.userId !== 'string' || !value.userId || value.userId.length > 128
      || !Number.isInteger(value.attempts) || Number(value.attempts) < 0 || Number(value.attempts) > APPS_ACQUISITION_MAX_ATTEMPTS
      || typeof value.nextRetryAt !== 'number' || !Number.isFinite(value.nextRetryAt)
      || typeof value.authMethod !== 'string' || !METHODS.has(value.authMethod as AppsAcquisitionAuthMethod)) {
      remove(APPS_ACQUISITION_KEYS.pending, options.session)
      return null
    }
    const captured = value.context === null ? null : context(value.context, value.createdAt)
    if (value.context !== null && !captured)
      return null
    return {
      id: value.id,
      createdAt: value.createdAt,
      context: captured,
      authMethod: value.authMethod as AppsAcquisitionAuthMethod,
      userId: value.userId,
      attempts: Number(value.attempts),
      nextRetryAt: value.nextRetryAt,
    }
  }

  function clearPending(id: string) {
    const value = read(APPS_ACQUISITION_KEYS.pending, options.session)
    if (isRecord(value) && value.id === id)
      remove(APPS_ACQUISITION_KEYS.pending, options.session)
  }

  /** A document entry may use referrer. SPA transitions may only contribute explicit UTM. */
  function captureEntry(url: URL, referrer = '', entryKind: 'document' | 'navigation' = 'document') {
    if (isAcquisitionCallback(url.pathname)) {
      rememberOAuthCallback(url)
      return
    }
    const touch = captureAppsAcquisitionTouch(url, entryKind === 'document' ? referrer : '', now())
    if (!touch || (entryKind === 'navigation' && !hasAppsAcquisitionUtm(touch)))
      return
    // A fresh document has its own entry evidence, even on /login or /signup.
    // Internal navigation without UTM returned above, preserving this document's landing.
    const storedFirst = read(APPS_ACQUISITION_KEYS.first, options.local)
    const firstContext = sanitizeAcquisitionContext({ version: 1, firstTouch: storedFirst, registerTouch: touch })
    const first = firstContext && recent(firstContext.firstTouch.capturedAt, APPS_ACQUISITION_FIRST_WINDOW_MS)
      ? firstContext.firstTouch
      : touch
    write(APPS_ACQUISITION_KEYS.first, first, options.local)
    write(APPS_ACQUISITION_KEYS.entry, { version: 1, firstTouch: first, registerTouch: touch }, options.session)
  }

  function beginAuthentication(authMethod: AppsAcquisitionAuthMethod, oauthState?: string, delegatedSso = false) {
    remove(APPS_ACQUISITION_KEYS.callback, options.session)
    const attempt: AppsAcquisitionAttempt = {
      id: createId(),
      createdAt: now(),
      context: delegatedSso ? null : context(read(APPS_ACQUISITION_KEYS.entry, options.session)),
      authMethod,
      ...(oauthState ? { oauthState } : {}),
      ...(delegatedSso ? { delegatedSso: true } : {}),
    }
    write(APPS_ACQUISITION_KEYS.attempt, attempt, options.session)
    return attempt
  }

  function bindOAuthState(id: string, state: string) {
    const attempt = readAttempt()
    if (attempt?.id === id && state && state.length <= 200 && !CONTROL_RE.test(state))
      write(APPS_ACQUISITION_KEYS.attempt, { ...attempt, oauthState: state }, options.session)
  }

  /** Freeze the original identity and context once; subsequent landings never mutate a retry. */
  function completeAuthentication(userId: string, oauthState?: string): AppsAcquisitionPending | null {
    const attempt = readAttempt()
    if (attempt?.delegatedSso) {
      remove(APPS_ACQUISITION_KEYS.attempt, options.session)
      remove(APPS_ACQUISITION_KEYS.callback, options.session)
      return null
    }
    const callback = read(APPS_ACQUISITION_KEYS.callback, options.session)
    const rememberedState = attempt?.oauthState && isRecord(callback) && callback.id === attempt.id
      && callback.state === attempt.oauthState && typeof callback.createdAt === 'number' && recent(callback.createdAt, APPS_ACQUISITION_WINDOW_MS)
      ? attempt.oauthState
      : undefined
    const returnedState = oauthState ?? rememberedState
    if (!attempt || !userId || userId.length > 128 || attempt.oauthState !== returnedState)
      return null
    const existing = readPending()
    if (existing?.id === attempt.id && existing.userId === userId)
      return existing
    const pending: AppsAcquisitionPending = {
      ...attempt,
      userId,
      attempts: 0,
      nextRetryAt: now(),
    }
    write(APPS_ACQUISITION_KEYS.pending, pending, options.session)
    remove(APPS_ACQUISITION_KEYS.attempt, options.session)
    remove(APPS_ACQUISITION_KEYS.callback, options.session)
    return pending
  }

  /** The pre plugin reads only our exact state before the SDK removes OAuth query parameters. */
  function rememberOAuthCallback(url: URL) {
    if (!/^\/auth\/callback\/?$/.test(url.pathname))
      return
    const attempt = readAttempt()
    if (attempt?.oauthState && url.searchParams.get('state') === attempt.oauthState)
      write(APPS_ACQUISITION_KEYS.callback, { id: attempt.id, state: attempt.oauthState, createdAt: now() }, options.session)
    else if (url.searchParams.has('state') || url.searchParams.has('code'))
      remove(APPS_ACQUISITION_KEYS.callback, options.session)
  }

  function savePending(pending: AppsAcquisitionPending) {
    if (pending.attempts > APPS_ACQUISITION_MAX_ATTEMPTS) {
      clearPending(pending.id)
      return
    }
    const existing = read(APPS_ACQUISITION_KEYS.pending, options.session)
    if (isRecord(existing) && existing.id === pending.id)
      write(APPS_ACQUISITION_KEYS.pending, pending, options.session)
  }

  return { captureEntry, beginAuthentication, bindOAuthState, completeAuthentication, readAttempt, readPending, savePending, clearPending }
}

export type AppsAcquisitionStorage = ReturnType<typeof createAppsAcquisitionStorage>

export function captureAppsAcquisitionTouch(url: URL, referrer: string, now: number): AcquisitionTouch | null {
  const nativeLocal = (['capacitor:', 'ionic:'].includes(url.protocol) && url.hostname === 'localhost')
    || (url.protocol === 'https:' && url.hostname === 'localhost')
  const web = ['http:', 'https:'].includes(url.protocol)
    && (url.hostname === 'apps.yunle.fun' || ['localhost', '127.0.0.1'].includes(url.hostname))
  if ((!nativeLocal && !web) || url.username || url.password)
    return null
  const host = nativeLocal ? 'apps.yunle.fun' : url.hostname
  let referrerHost = ''
  try {
    const referrerUrl = new URL(referrer)
    if (['http:', 'https:'].includes(referrerUrl.protocol) && !referrerUrl.username && !referrerUrl.password
      && !isAppsInternalHost(referrerUrl.hostname, host)) {
      referrerHost = referrerUrl.hostname.replace(/\.$/, '')
    }
  }
  catch {
    // Empty or unsupported referrer is unknown.
  }
  const touch: AcquisitionTouch = {
    capturedAt: now,
    landingHost: host,
    landingPath: url.pathname,
    referrerHost,
    utmSource: readUtm(url.searchParams.get('utm_source')),
    utmMedium: readUtm(url.searchParams.get('utm_medium')),
    utmCampaign: readUtm(url.searchParams.get('utm_campaign')),
  }
  return sanitizeAcquisitionContext({ version: 1, firstTouch: touch, registerTouch: touch })?.registerTouch || null
}

/** Only supported, already resolved host routes may contribute launch UTM; query/hash never become a path. */
export function readAppsLaunchAcquisitionUrl(rawUrl: string, routePath: string): URL | null {
  try {
    const raw = new URL(rawUrl)
    if (!routePath.startsWith('/') || routePath.startsWith('//') || routePath.includes('?') || routePath.includes('#'))
      return null
    const allowed = (raw.protocol === 'https:' && raw.hostname === 'apps.yunle.fun')
      || (raw.protocol === 'yunlefun:' && ['workshop', 'wallet'].includes(raw.hostname))
    if (!allowed || raw.username || raw.password)
      return null
    const landing = new URL(routePath, APPS_ACQUISITION_ORIGIN)
    for (const key of ['utm_source', 'utm_medium', 'utm_campaign']) {
      const value = readUtm(raw.searchParams.get(key))
      if (value)
        landing.searchParams.set(key, value)
    }
    return landing
  }
  catch {
    return null
  }
}

function hasAppsAcquisitionUtm(touch: AcquisitionTouch) {
  return !!(touch.utmSource || touch.utmMedium || touch.utmCampaign)
}

function isAppsInternalHost(host: string, landingHost: string) {
  host = host.replace(/\.$/, '')
  landingHost = landingHost.replace(/\.$/, '')
  return host === landingHost || host === 'yunle.fun' || host.endsWith('.yunle.fun') || host === 'cook.yunyoujun.cn'
}

function isAcquisitionCallback(path: string) {
  return /^\/auth\/(?:callback|sso)(?:\/|$)/.test(path)
}

function readUtm(value: string | null) {
  return value && value.length <= 120 && !CONTROL_RE.test(value) && UTM_RE.test(value) ? value.trim() : ''
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
