import type { AppsAcquisitionPending } from '../../app/utils/apps-acquisition-storage'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { appsAcquisitionRetryDelay, createAppsAcquisitionRecorder, isTransientAppsAcquisitionError, readAppsAcquisitionResult } from '../../app/utils/apps-acquisition-recorder'
import { createAppsAcquisitionStorage } from '../../app/utils/apps-acquisition-storage'

const NOW = 1_791_547_200_000

function setup(random: () => number = () => 1) {
  let id = 0
  const storage = createAppsAcquisitionStorage({ now: Date.now, createId: () => `attempt-${++id}` })
  storage.captureEntry(new URL('https://apps.yunle.fun/?utm_source=zhihu'))
  storage.beginAuthentication('phone_otp')
  storage.completeAuthentication('uid-1')
  let currentUser = 'uid-1'
  const getSession = vi.fn(async () => ({ userId: currentUser, accessToken: 'never-persist-token' }))
  const request = vi.fn(async (_pending: AppsAcquisitionPending) => ({ ok: true, status: 'recorded' }))
  const log = vi.fn()
  const recorder = createAppsAcquisitionRecorder({ storage, getSession, request, currentUserId: () => currentUser, log, random })
  return {
    storage,
    getSession,
    request,
    log,
    recorder,
    switchUser: (userId: string) => {
      currentUser = userId
    },
  }
}

describe('apps finite acquisition delivery', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(NOW)
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  it('records once and never persists the bearer token', async () => {
    const test = setup()
    expect(JSON.stringify(test.storage.readPending())).not.toContain('never-persist-token')
    await test.recorder.resume()
    expect(test.request).toHaveBeenCalledOnce()
    expect(test.storage.readPending()).toBeNull()
    await test.recorder.resume()
    expect(test.request).toHaveBeenCalledOnce()
  })

  it('retries only explicit transient failures, with a maximum of three total requests', async () => {
    const test = setup()
    test.request.mockResolvedValue({ ok: false, status: 'recorded', statusCode: 503, retryable: true, code: 'acquisition_unavailable' } as never)
    await test.recorder.resume()
    expect(test.storage.readPending()?.attempts).toBe(1)
    await vi.advanceTimersByTimeAsync(2000)
    expect(test.request).toHaveBeenCalledTimes(2)
    await vi.advanceTimersByTimeAsync(10_000)
    expect(test.request).toHaveBeenCalledTimes(3)
    expect(test.storage.readPending()).toBeNull()
    await vi.advanceTimersByTimeAsync(60_000)
    expect(test.request).toHaveBeenCalledTimes(3)
  })

  it.each([0, 1])('keeps the three-request budget with jitter sample %s', async (sample) => {
    const random = vi.fn(() => sample)
    const test = setup(random)
    test.request.mockRejectedValue(new TypeError('Failed to fetch'))
    await test.recorder.resume()
    await vi.advanceTimersByTimeAsync(12_000)
    expect(test.request).toHaveBeenCalledTimes(3)
    expect(random).toHaveBeenCalledTimes(2)
    expect(test.storage.readPending()).toBeNull()
  })

  it('persists the sampled retry time and does not resample during auth/online recovery', async () => {
    const random = vi.fn(() => 0.5)
    const test = setup(random)
    test.request.mockRejectedValueOnce(new TypeError('Failed to fetch'))
    await test.recorder.resume()
    const dueAt = test.storage.readPending()?.nextRetryAt
    expect(dueAt).toBe(NOW + 1000)
    test.recorder.dispose()
    const recovered = createAppsAcquisitionRecorder({
      storage: test.storage,
      getSession: test.getSession,
      request: test.request,
      currentUserId: () => 'uid-1',
      random,
    })
    await recovered.resume()
    await recovered.resume()
    expect(test.storage.readPending()?.nextRetryAt).toBe(dueAt)
    expect(random).toHaveBeenCalledOnce()
    await vi.advanceTimersByTimeAsync(999)
    expect(test.request).toHaveBeenCalledOnce()
    await vi.advanceTimersByTimeAsync(1)
    expect(test.request).toHaveBeenCalledTimes(2)
    expect(random).toHaveBeenCalledOnce()
    recovered.dispose()
  })

  it('bounds jitter and falls back to the cap for invalid or throwing random sources', () => {
    expect(appsAcquisitionRetryDelay(1, () => 0)).toBe(0)
    expect(appsAcquisitionRetryDelay(1, () => 1)).toBe(2000)
    expect(appsAcquisitionRetryDelay(2, () => 0.5)).toBe(5000)
    expect(appsAcquisitionRetryDelay(2, () => 1)).toBe(10_000)
    expect(appsAcquisitionRetryDelay(1, () => -1)).toBe(0)
    expect(appsAcquisitionRetryDelay(1, () => 2)).toBe(2000)
    expect(appsAcquisitionRetryDelay(1, () => Number.NaN)).toBe(2000)
    expect(appsAcquisitionRetryDelay(2, () => {
      throw new Error('unavailable random')
    })).toBe(10_000)
  })

  it.each([400, 401, 403, 409, 503])('does not retry terminal status %s', async (statusCode) => {
    const test = setup()
    test.request.mockResolvedValue({ ok: false, status: 'recorded', code: 'acquisition_request_rejected', statusCode, retryable: false } as never)
    await test.recorder.resume()
    await vi.advanceTimersByTimeAsync(60_000)
    expect(test.request).toHaveBeenCalledOnce()
    expect(test.storage.readPending()).toBeNull()
  })

  it('does not resend the old context after switching accounts', async () => {
    const test = setup()
    test.request.mockRejectedValueOnce(new TypeError('Failed to fetch'))
    await test.recorder.resume()
    test.switchUser('uid-2')
    await vi.advanceTimersByTimeAsync(2000)
    expect(test.request).toHaveBeenCalledOnce()
    expect(test.storage.readPending()).toBeNull()
  })

  it('rechecks identity after an asynchronous session refresh', async () => {
    const test = setup()
    let resolveSession!: (value: { userId: string, accessToken: string }) => void
    test.getSession.mockReturnValueOnce(new Promise((resolve) => {
      resolveSession = resolve
    }))
    const completed = test.recorder.resume()
    test.switchUser('uid-2')
    resolveSession({ userId: 'uid-1', accessToken: 'token' })
    await completed
    expect(test.request).not.toHaveBeenCalled()
    expect(test.storage.readPending()).toBeNull()
  })

  it('returns by 1.5 seconds while preventing overlap with an unresolved auth SDK call', async () => {
    const test = setup()
    let resolveSession!: (value: { userId: string, accessToken: string }) => void
    test.getSession.mockReturnValueOnce(new Promise((resolve) => {
      resolveSession = resolve
    }))
    const completed = test.recorder.resume()
    await vi.advanceTimersByTimeAsync(1500)
    await completed
    await test.recorder.resume()
    expect(test.getSession).toHaveBeenCalledOnce()
    expect(test.request).not.toHaveBeenCalled()
    resolveSession({ userId: 'uid-1', accessToken: 'token' })
    await vi.advanceTimersByTimeAsync(2000)
    expect(test.request).toHaveBeenCalledOnce()
  })

  it('samples one retry at timeout, retains the lock, and reuses its time after a late failure', async () => {
    const random = vi.fn(() => 0.5)
    const test = setup(random)
    let rejectWrite!: (reason: Error) => void
    test.request.mockReturnValueOnce(new Promise((_resolve, reject) => {
      rejectWrite = reject
    }))
    const completed = test.recorder.resume()
    expect(test.storage.readPending()?.nextRetryAt).toBe(NOW + 3500)
    expect(random).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(1500)
    await completed
    const dueAt = test.storage.readPending()?.nextRetryAt
    expect(dueAt).toBe(NOW + 2500)
    expect(random).toHaveBeenCalledOnce()
    await test.recorder.resume()
    expect(test.request).toHaveBeenCalledOnce()
    rejectWrite(new TypeError('Failed to fetch'))
    await vi.advanceTimersByTimeAsync(0)
    expect(random).toHaveBeenCalledOnce()
    expect(test.storage.readPending()?.nextRetryAt).toBe(dueAt)
    await vi.advanceTimersByTimeAsync(1000)
    expect(test.request).toHaveBeenCalledTimes(2)
    expect(test.storage.readPending()).toBeNull()
  })

  it('treats a late successful write as completed and does not send another record', async () => {
    const test = setup()
    let resolveWrite!: (value: { ok: boolean, status: string }) => void
    test.request.mockReturnValueOnce(new Promise((resolve) => {
      resolveWrite = resolve
    }))
    const completed = test.recorder.resume()
    await vi.advanceTimersByTimeAsync(1500)
    await completed
    resolveWrite({ ok: true, status: 'recorded' })
    await vi.advanceTimersByTimeAsync(20_000)
    expect(test.request).toHaveBeenCalledOnce()
    expect(test.storage.readPending()).toBeNull()
  })

  it('never retries an expired original attempt', async () => {
    const test = setup()
    test.request.mockRejectedValueOnce(new TypeError('Failed to fetch'))
    await test.recorder.resume()
    vi.setSystemTime(NOW + 30 * 60 * 1000 + 1)
    await test.recorder.resume()
    expect(test.request).toHaveBeenCalledOnce()
    expect(test.storage.readPending()).toBeNull()
  })

  it('preserves a new account task when an old write rejects late', async () => {
    const test = setup()
    let rejectFirst!: (reason: Error) => void
    test.request.mockReturnValueOnce(new Promise((_resolve, reject) => {
      rejectFirst = reject
    }))
    const first = test.recorder.resume()
    await vi.advanceTimersByTimeAsync(0)
    test.storage.captureEntry(new URL('https://apps.yunle.fun/?utm_source=new'), '', 'navigation')
    test.storage.beginAuthentication('email_otp')
    const second = test.storage.completeAuthentication('uid-2')!
    test.switchUser('uid-2')
    rejectFirst(new TypeError('Failed to fetch'))
    await first
    await vi.advanceTimersByTimeAsync(0)
    expect(test.request).toHaveBeenCalledTimes(2)
    expect(test.request.mock.calls[1]?.[0]).toMatchObject({ id: second.id, userId: 'uid-2', context: { registerTouch: { utmSource: 'new' } } })
    await vi.advanceTimersByTimeAsync(20_000)
    expect(test.request).toHaveBeenCalledTimes(2)
  })

  it('handles a synchronous transient SDK throw without leaving a resolved lock that suppresses retries', async () => {
    const test = setup()
    test.getSession.mockImplementationOnce(() => {
      throw new TypeError('Failed to fetch')
    })
    await test.recorder.resume()
    await vi.advanceTimersByTimeAsync(2000)
    expect(test.getSession).toHaveBeenCalledTimes(2)
    expect(test.request).toHaveBeenCalledOnce()
  })

  it('allowlists result metadata and never trusts a generic ok=false as retryable', () => {
    expect(readAppsAcquisitionResult({ ok: false, code: 'acquisition_unavailable' })).toBeNull()
    expect(readAppsAcquisitionResult({ ok: false, code: 'acquisition_account_changed', statusCode: 409, retryable: true, userId: 'private' }))
      .toEqual({ ok: false, code: 'acquisition_account_changed', statusCode: 409, retryable: false })
    expect(readAppsAcquisitionResult({ ok: true, status: 'skipped', reason: 'existing_account', serviceToken: 'secret' }))
      .toEqual({ ok: true, status: 'skipped', reason: 'existing_account' })
    expect(isTransientAppsAcquisitionError(new TypeError('Cannot read properties of undefined'))).toBe(false)
    expect(isTransientAppsAcquisitionError(new TypeError('Failed to fetch'))).toBe(true)
    expect(isTransientAppsAcquisitionError({ category: 'SERVICE_ERROR' })).toBe(true)
  })
})
