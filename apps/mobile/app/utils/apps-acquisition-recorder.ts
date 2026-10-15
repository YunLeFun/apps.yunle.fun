import type { AppsAcquisitionPending, AppsAcquisitionStorage } from './apps-acquisition-storage'
import { APPS_ACQUISITION_MAX_ATTEMPTS } from './apps-acquisition-storage'

export const APPS_ACQUISITION_TIMEOUT_MS = 1500
const RETRY_DELAY_CAPS_MS = [2000, 10_000]

/** Full jitter is sampled only when arranging a new retry, then its due time is persisted. */
export function appsAcquisitionRetryDelay(attempts: number, random: () => number = Math.random): number {
  const cap = RETRY_DELAY_CAPS_MS[attempts - 1]
  if (cap === undefined)
    return 0
  try {
    const sample = random()
    return Number.isFinite(sample) ? Math.max(0, Math.min(cap, Math.floor(sample * (cap + 1)))) : cap
  }
  catch {
    return cap
  }
}

export interface AppsAcquisitionSession {
  userId: string
  accessToken: string
}

export type AppsAcquisitionResult
  = { ok: true, status: 'recorded' | 'existing' | 'skipped', reason?: 'existing_account' | 'synthetic' }
    | { ok: false, code: string, statusCode: number, retryable: boolean }

/** One in-flight operation, a frozen attempt, and a finite total budget; no background durability claim. */
export function createAppsAcquisitionRecorder(options: {
  storage: AppsAcquisitionStorage
  currentUserId: () => string | null
  getSession: () => Promise<AppsAcquisitionSession | null>
  request: (pending: AppsAcquisitionPending, session: AppsAcquisitionSession, signal: AbortSignal) => Promise<unknown>
  now?: () => number
  random?: () => number
  log?: (outcome: string, attempts: number, statusCode?: number) => void
}) {
  const now = options.now || Date.now
  let active: Promise<void> | null = null
  let retryTimer: ReturnType<typeof setTimeout> | undefined
  let disposed = false

  function schedule(pending: AppsAcquisitionPending) {
    clearTimeout(retryTimer)
    if (!disposed) {
      retryTimer = setTimeout(() => {
        retryTimer = undefined
        void resume()
      }, Math.max(0, pending.nextRetryAt - now()))
    }
  }

  function retry(pending: AppsAcquisitionPending, statusCode?: number) {
    if (options.storage.readPending()?.id !== pending.id)
      return
    if (pending.attempts >= APPS_ACQUISITION_MAX_ATTEMPTS) {
      options.storage.clearPending(pending.id)
      options.log?.('exhausted', pending.attempts, statusCode)
      return
    }
    const updated = { ...pending, nextRetryAt: now() + appsAcquisitionRetryDelay(pending.attempts, options.random) }
    options.storage.savePending(updated)
    options.log?.('retry', pending.attempts, statusCode)
    schedule(updated)
  }

  function resume(): Promise<void> {
    if (disposed)
      return Promise.resolve()
    if (active)
      return active
    const original = options.storage.readPending()
    if (!original)
      return Promise.resolve()
    if (original.attempts >= APPS_ACQUISITION_MAX_ATTEMPTS) {
      options.storage.clearPending(original.id)
      return Promise.resolve()
    }
    const currentUserId = options.currentUserId()
    // No session after cold start: wait for auth recovery. Another account must never reuse this task.
    if (!currentUserId)
      return Promise.resolve()
    if (currentUserId !== original.userId) {
      options.storage.clearPending(original.id)
      options.log?.('identity_changed', original.attempts)
      return Promise.resolve()
    }
    if (original.nextRetryAt > now()) {
      schedule(original)
      return Promise.resolve()
    }
    const attempts = original.attempts + 1
    // If the document closes mid-flight, recovery waits conservatively. No jitter is sampled yet.
    const pending = { ...original, attempts, nextRetryAt: now() + APPS_ACQUISITION_TIMEOUT_MS + (RETRY_DELAY_CAPS_MS[attempts - 1] || 0) }
    options.storage.savePending(pending)
    const controller = new AbortController()
    let deadline: ReturnType<typeof setTimeout> | undefined
    let timedOut = false
    let retryScheduled = false
    function retryAttempt(statusCode?: number) {
      const live = options.storage.readPending()
      if (!live || live.id !== pending.id)
        return
      if (retryScheduled) {
        // The caller deadline already sampled and stored this retry. A late failure reuses it.
        schedule(live)
        return
      }
      retry(pending, statusCode)
      retryScheduled = true
    }
    let release!: () => void
    // Return by the deadline while retaining the underlying lock until the SDK operation settles.
    const completion = new Promise<void>((resolve) => {
      release = resolve
      deadline = setTimeout(() => {
        timedOut = true
        controller.abort()
        options.log?.('timeout', pending.attempts)
        retryAttempt()
        release()
      }, APPS_ACQUISITION_TIMEOUT_MS)
    })
    const operation = Promise.resolve().then(async () => {
      try {
        const session = await options.getSession()
        const live = options.storage.readPending()
        if (!live || live.id !== pending.id || options.currentUserId() !== pending.userId || session?.userId !== pending.userId) {
          options.storage.clearPending(pending.id)
          options.log?.('identity_changed', pending.attempts)
          return
        }
        if (timedOut) {
          retryAttempt()
          return
        }
        const response = readAppsAcquisitionResult(await options.request(pending, session, controller.signal))
        const current = options.storage.readPending()
        if (!current || current.id !== pending.id)
          return
        if (response?.ok) {
          options.storage.clearPending(pending.id)
          options.log?.(response.status, pending.attempts)
        }
        else if (response?.statusCode === 503 && response.retryable) {
          retryAttempt(response.statusCode)
        }
        else {
          options.storage.clearPending(pending.id)
          options.log?.('terminal', pending.attempts, response?.statusCode)
        }
      }
      catch (error) {
        if (timedOut || isTransientAppsAcquisitionError(error))
          retryAttempt()
        else
          options.storage.clearPending(pending.id)
      }
      finally {
        clearTimeout(deadline)
        active = null
        release()
        const latest = options.storage.readPending()
        if (latest && latest.id !== pending.id)
          void Promise.resolve().then(() => resume())
      }
    })
    // The operation catches errors, including late completions after the caller's deadline.
    active = completion
    void operation
    return completion
  }

  function dispose() {
    disposed = true
    clearTimeout(retryTimer)
  }

  return { resume, dispose }
}

export function readAppsAcquisitionResult(input: unknown): AppsAcquisitionResult | null {
  if (!isRecord(input))
    return null
  if (input.ok === true && ['recorded', 'existing', 'skipped'].includes(String(input.status))) {
    if (input.status === 'skipped' && !['existing_account', 'synthetic'].includes(String(input.reason)))
      return null
    return {
      ok: true,
      status: input.status as 'recorded' | 'existing' | 'skipped',
      ...(input.status === 'skipped' ? { reason: input.reason as 'existing_account' | 'synthetic' } : {}),
    }
  }
  if (input.ok === false && typeof input.code === 'string' && /^[a-z_]{1,80}$/.test(input.code)
    && typeof input.statusCode === 'number' && [400, 401, 403, 409, 503].includes(input.statusCode)
    && typeof input.retryable === 'boolean') {
    return { ok: false, code: input.code, statusCode: input.statusCode, retryable: input.statusCode === 503 && input.retryable }
  }
  return null
}

export function isTransientAppsAcquisitionError(error: unknown) {
  if (error instanceof TypeError && /^(?:Failed to fetch|Load failed|NetworkError when attempting to fetch resource\.?|fetch failed)$/i.test(error.message))
    return true
  if (error instanceof Error && ['AbortError', 'TimeoutError'].includes(error.name))
    return true
  if (isRecord(error)) {
    if (typeof error.code === 'string' && ['ETIMEDOUT', 'ECONNRESET', 'ECONNREFUSED', 'ENETUNREACH', 'EAI_AGAIN', 'REQUEST_TIMEOUT', 'NETWORK_ERROR'].includes(error.code))
      return true
    if (['unreachable', 'server_error', 'temporarily_unavailable'].includes(String(error.status)) || error.category === 'SERVICE_ERROR')
      return true
    const cause = error.cause
    return error.name === 'FetchError' && cause instanceof Error
      && ((cause instanceof TypeError && /^(?:Failed to fetch|Load failed|fetch failed)$/i.test(cause.message))
        || ['AbortError', 'TimeoutError'].includes(cause.name))
  }
  return false
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
