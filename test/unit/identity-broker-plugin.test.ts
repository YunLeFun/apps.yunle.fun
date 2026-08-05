import type { HostAuthorizationEvent } from '../../app/host-runtime'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  authorizationHandler: undefined as ((event: HostAuthorizationEvent) => Promise<void>) | undefined,
  authorizeWithOtherAccount: vi.fn(),
  callFunction: vi.fn(),
  confirmAuthorization: vi.fn(),
  getSession: vi.fn(),
  nativeTestSession: undefined as undefined | {
    hostSession: string
    expiresAt: number
    account: { publicAlias: string, virtualPhone: string, displayName: string }
  },
  resolveAuthorization: vi.fn(),
  fetch: vi.fn(),
}))

vi.mock('@capacitor/core', () => ({
  Capacitor: {
    isNativePlatform: () => true,
    isPluginAvailable: (name: string) => name === 'HostRuntime',
    getPlatform: () => 'android',
  },
}))

vi.mock('../../app/host-runtime', () => ({
  HostRuntime: {
    addListener: vi.fn((_event: string, handler: (event: HostAuthorizationEvent) => Promise<void>) => {
      h.authorizationHandler = handler
    }),
    authorizeWithOtherAccount: h.authorizeWithOtherAccount,
    confirmAuthorization: h.confirmAuthorization,
    resolveAuthorization: h.resolveAuthorization,
  },
}))

vi.stubGlobal('defineNuxtPlugin', (setup: () => void) => {
  setup()
  return setup
})
vi.stubGlobal('useCloudbase', () => ({
  app: { callFunction: h.callFunction },
  auth: {
    getSession: h.getSession,
  },
}))
vi.stubGlobal('useUserStore', () => ({
  userInfo: { nickname: '云游君' },
  nativeTestSession: h.nativeTestSession,
  clearNativeTestSession: vi.fn(),
}))
vi.stubGlobal('$fetch', h.fetch)
vi.stubGlobal('useNuxtApp', () => ({ $api: h.fetch }))

h.getSession.mockImplementation(async () => ({
  data: {
    session: {
      access_token: 'apps-access-token',
      user: { is_anonymous: false },
    },
  },
  error: null,
}))

const consentRequest: HostAuthorizationEvent = {
  appId: 'yunjian',
  requestId: 'native-request-1234',
  sourceOrigin: 'https://cms.yunle.fun',
  request: {
    clientId: 'cms-web',
    codeChallenge: 'challenge_'.padEnd(43, 'c'),
    codeChallengeMethod: 'S256',
    nonce: 'nonce_'.padEnd(43, 'n'),
    redirectUri: 'https://cms.yunle.fun/',
    scope: ['identity:bootstrap'],
    prompt: 'consent',
  },
}

describe('apps host identity broker consent', () => {
  beforeEach(async () => {
    vi.clearAllMocks()
    h.nativeTestSession = undefined
    h.confirmAuthorization.mockResolvedValue({ allowed: false })
    if (!h.authorizationHandler)
      await import('../../app/plugins/identity-broker.client')
  })

  it('does not mint a code when the user declines current-account authorization', async () => {
    expect(h.authorizationHandler).toBeTypeOf('function')
    await h.authorizationHandler?.(consentRequest)

    expect(h.confirmAuthorization).toHaveBeenCalledWith({
      applicationName: '云笺',
      accountName: '云游君',
    })
    expect(h.callFunction).not.toHaveBeenCalled()
    expect(h.resolveAuthorization).toHaveBeenCalledWith({
      requestId: consentRequest.requestId,
      error: 'HOST_AUTH_DENIED',
    })
  })

  it('mints and returns only a one-time code after consent', async () => {
    h.confirmAuthorization.mockResolvedValue({ allowed: true })
    h.callFunction.mockResolvedValue({
      result: { ok: true, code: 'c'.repeat(43) },
    })

    await h.authorizationHandler?.(consentRequest)

    expect(h.callFunction).toHaveBeenCalledTimes(1)
    expect(h.resolveAuthorization).toHaveBeenCalledWith({
      requestId: consentRequest.requestId,
      result: {
        ok: true,
        code: 'c'.repeat(43),
        issuer: 'https://www.yunle.fun',
      },
    })
  })

  it('hands other-account authorization to the platform system session', async () => {
    h.confirmAuthorization.mockResolvedValue({ allowed: false, choice: 'other' })

    await h.authorizationHandler?.(consentRequest)

    expect(h.authorizeWithOtherAccount).toHaveBeenCalledWith({
      requestId: consentRequest.requestId,
    })
    expect(h.callFunction).not.toHaveBeenCalled()
    expect(h.resolveAuthorization).not.toHaveBeenCalled()
  })

  it('uses the narrow native test host session when no CloudBase account is logged in', async () => {
    h.getSession.mockResolvedValueOnce({ data: { session: null }, error: null })
    h.nativeTestSession = {
      hostSession: 'host.jwt.value',
      expiresAt: Date.now() + 60_000,
      account: {
        publicAlias: 'native-sso-smoke@yunlefun',
        virtualPhone: '+86 000 0000 0001',
        displayName: 'Native SSO Smoke',
      },
    }
    h.confirmAuthorization.mockResolvedValue({ allowed: true })
    h.fetch.mockResolvedValue({ ok: true, code: 't'.repeat(43), expiresAt: Date.now() + 60_000 })

    await h.authorizationHandler?.(consentRequest)

    expect(h.confirmAuthorization).toHaveBeenCalledWith({
      applicationName: '云笺',
      accountName: 'native-sso-smoke@yunlefun',
    })
    expect(h.fetch).toHaveBeenCalledWith('/api/auth/native-test-session/authorize', expect.objectContaining({
      method: 'POST',
      body: expect.objectContaining({ hostSession: 'host.jwt.value' }),
    }))
    expect(h.callFunction).not.toHaveBeenCalled()
    expect(h.resolveAuthorization).toHaveBeenCalledWith(expect.objectContaining({
      requestId: consentRequest.requestId,
      result: expect.objectContaining({ code: 't'.repeat(43) }),
    }))
  })

  it('starts system account selection without reading the host account', async () => {
    await h.authorizationHandler?.({
      ...consentRequest,
      request: {
        ...consentRequest.request,
        prompt: 'select_account',
      },
    })

    expect(h.getSession).not.toHaveBeenCalled()
    expect(h.confirmAuthorization).not.toHaveBeenCalled()
    expect(h.authorizeWithOtherAccount).toHaveBeenCalledWith({
      requestId: consentRequest.requestId,
    })
    expect(h.callFunction).not.toHaveBeenCalled()
    expect(h.resolveAuthorization).not.toHaveBeenCalled()
  })
})
