import type { H3Event } from 'h3'
import { Buffer } from 'node:buffer'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCloudbaseAuthCache } from '../../server/utils/cloudbase-auth'
import { handleAppsUserAcquisition } from '../../server/utils/user-acquisition'
import { acquisition } from './acquisition-fixture'

const mocks = vi.hoisted(() => ({
  body: vi.fn(),
  callFunction: vi.fn(),
}))

vi.mock('h3', async (importOriginal) => {
  const original = await importOriginal<typeof import('h3')>()
  return { ...original, readRawBody: mocks.body }
})

vi.mock('../../server/utils/cloudbase-admin', () => ({
  useCloudbaseAdmin: () => ({ app: { callFunction: mocks.callFunction } }),
}))

const PRIVATE_TOKEN = 'private-test-service-token'
let serviceToken = PRIVATE_TOKEN

function event(authorization?: string): H3Event {
  return {
    node: {
      req: { headers: authorization ? { authorization } : {} },
      res: { setHeader: vi.fn(), statusCode: 200 },
    },
  } as unknown as H3Event
}

function bearer() {
  const payload = Buffer.from(JSON.stringify({ exp: Math.floor(Date.now() / 1000) + 3600 })).toString('base64url')
  return `Bearer header.${payload}.signature`
}

function profile(overrides: Record<string, unknown> = {}) {
  vi.mocked(fetch).mockResolvedValue({
    ok: true,
    json: async () => ({ sub: 'verified-uid', ...overrides }),
  } as unknown as Response)
}

describe('apps acquisition trusted BFF handler', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    clearCloudbaseAuthCache()
    serviceToken = PRIVATE_TOKEN
    vi.stubGlobal('useRuntimeConfig', () => ({
      appsAcquisitionInternalToken: serviceToken,
      accountApiInternalToken: 'legacy-general-asset-token-must-not-be-used',
      public: { tcbEnvId: 'yunlefun-test' },
    }))
    vi.stubGlobal('fetch', vi.fn())
    mocks.body.mockResolvedValue(JSON.stringify({ context: acquisition, authMethod: 'phone_otp', expectedUserId: 'verified-uid' }))
    mocks.callFunction.mockResolvedValue({ result: { ok: true, status: 'recorded' } })
    profile()
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
  })

  it('verifies bearer and sends only server UID and allowlisted context with a private token', async () => {
    mocks.body.mockResolvedValue(JSON.stringify({
      context: { ...acquisition, accessToken: 'client-secret' },
      authMethod: 'phone_otp',
      expectedUserId: 'verified-uid',
      userId: 'attacker-uid',
      appId: 'cook',
      entry: { appId: 'cook', origin: 'https://evil.example' },
      serviceToken: 'attacker-token',
    }))
    const request = event(bearer())
    await expect(handleAppsUserAcquisition(request)).resolves.toEqual({ ok: true, status: 'recorded' })
    expect(fetch).toHaveBeenCalledWith('https://yunlefun-test.api.tcloudbasegateway.com/auth/v1/user/me', expect.objectContaining({ headers: { Authorization: request.node.req.headers.authorization } }))
    expect(mocks.callFunction).toHaveBeenCalledWith({
      name: 'account-api',
      data: { action: 'recordAppsUserAcquisition', serviceToken: PRIVATE_TOKEN, userId: 'verified-uid', context: acquisition, authMethod: 'phone_otp' },
    }, { timeout: 1000, retryOptions: { retries: 0 } })
    expect(request.node.res.setHeader).toHaveBeenCalledWith('Cache-Control', 'no-store, max-age=0')
  })

  it('rejects missing bearer before accessing input or internal API', async () => {
    await expect(handleAppsUserAcquisition(event())).resolves.toMatchObject({ ok: false, statusCode: 401, retryable: false })
    expect(mocks.body).not.toHaveBeenCalled()
    expect(mocks.callFunction).not.toHaveBeenCalled()
  })

  it.each([{ is_anonymous: true }, { isAnonymous: true }, { account_status: 'suspended' }])('rejects non-registered or inactive profile %s', async (flags) => {
    profile(flags)
    await expect(handleAppsUserAcquisition(event(bearer()))).resolves.toMatchObject({ ok: false, statusCode: 403, retryable: false })
    expect(mocks.callFunction).not.toHaveBeenCalled()
  })

  it('rejects an account switch equality guard without letting it choose another write identity', async () => {
    mocks.body.mockResolvedValue(JSON.stringify({ context: acquisition, expectedUserId: 'previous-uid' }))
    await expect(handleAppsUserAcquisition(event(bearer()))).resolves.toEqual({ ok: false, code: 'acquisition_account_changed', statusCode: 409, retryable: false })
    expect(mocks.callFunction).not.toHaveBeenCalled()
  })

  it.each(['{bad json', JSON.stringify([]), JSON.stringify({ context: { version: 999 } }), 'x'.repeat(6145)])('rejects malformed or excessive input', async (body) => {
    mocks.body.mockResolvedValue(body)
    await expect(handleAppsUserAcquisition(event(bearer()))).resolves.toMatchObject({ ok: false, statusCode: 400, retryable: false })
    expect(mocks.callFunction).not.toHaveBeenCalled()
  })

  it('returns a missing dedicated token as terminal even when a general asset token exists', async () => {
    serviceToken = ''
    await expect(handleAppsUserAcquisition(event(bearer()))).resolves.toEqual({ ok: false, code: 'acquisition_service_unconfigured', statusCode: 503, retryable: false })
    expect(mocks.callFunction).not.toHaveBeenCalled()
  })

  it.each([
    { ok: false, code: 'acquisition_unavailable', statusCode: 503, retryable: true },
    { ok: false, code: 'acquisition_not_configured', statusCode: 503, retryable: false },
    { ok: false, code: 'acquisition_forbidden', statusCode: 403, retryable: false },
  ])('retains only the internal failure contract %s', async (result) => {
    mocks.callFunction.mockResolvedValue({ result: { ...result, error: 'private details', headers: { secret: PRIVATE_TOKEN }, userId: 'private' } })
    const request = event(bearer())
    await expect(handleAppsUserAcquisition(request)).resolves.toEqual(result)
    expect(request.node.res.statusCode).toBe(result.statusCode)
  })

  it('does not infer retryability from an invalid internal response or unknown error', async () => {
    mocks.callFunction.mockResolvedValueOnce({ result: { ok: false } })
    await expect(handleAppsUserAcquisition(event(bearer()))).resolves.toMatchObject({ ok: false, statusCode: 503, retryable: false })
    mocks.callFunction.mockRejectedValueOnce(new Error(PRIVATE_TOKEN))
    const result = await handleAppsUserAcquisition(event(bearer()))
    expect(result).toMatchObject({ ok: false, statusCode: 503, retryable: false })
    expect(JSON.stringify(result)).not.toContain(PRIVATE_TOKEN)
  })

  it('bounds the whole operation and prevents a late auth response from initiating a write', async () => {
    vi.useFakeTimers()
    let resolveAuth!: (value: Response) => void
    vi.mocked(fetch).mockReturnValueOnce(new Promise((resolve) => {
      resolveAuth = resolve
    }))
    const result = handleAppsUserAcquisition(event(bearer()))
    await vi.advanceTimersByTimeAsync(1500)
    await expect(result).resolves.toMatchObject({ ok: false, statusCode: 503, retryable: true })
    resolveAuth({ ok: true, json: async () => ({ sub: 'verified-uid' }) } as unknown as Response)
    await vi.advanceTimersByTimeAsync(0)
    expect(mocks.callFunction).not.toHaveBeenCalled()
  })

  it('bounds a stalled internal API call after auth and consumes its late completion', async () => {
    vi.useFakeTimers()
    let resolveWrite!: (value: unknown) => void
    mocks.callFunction.mockReturnValueOnce(new Promise((resolve) => {
      resolveWrite = resolve
    }))
    const result = handleAppsUserAcquisition(event(bearer()))
    await vi.advanceTimersByTimeAsync(1500)
    await expect(result).resolves.toMatchObject({ ok: false, statusCode: 503, retryable: true })
    resolveWrite({ result: { ok: true, status: 'recorded' } })
    await vi.advanceTimersByTimeAsync(0)
    expect(mocks.callFunction).toHaveBeenCalledOnce()
  })
})
