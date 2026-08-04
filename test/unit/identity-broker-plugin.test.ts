import type { HostAuthorizationEvent } from '../../app/composables/useBrowser'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  authorizationHandler: undefined as ((event: HostAuthorizationEvent) => Promise<void>) | undefined,
  callFunction: vi.fn(),
  confirmAuthorization: vi.fn(),
  resolveAuthorization: vi.fn(),
}))

vi.mock('@capacitor/core', () => ({
  Capacitor: {
    isNativePlatform: () => true,
    getPlatform: () => 'ios',
  },
}))

vi.mock('../../app/composables/useBrowser', () => ({
  InAppWebView: {
    addListener: vi.fn((_event: string, handler: (event: HostAuthorizationEvent) => Promise<void>) => {
      h.authorizationHandler = handler
    }),
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
    getSession: vi.fn(async () => ({
      data: {
        session: {
          access_token: 'apps-access-token',
          user: { is_anonymous: false },
        },
      },
      error: null,
    })),
  },
}))
vi.stubGlobal('useUserStore', () => ({
  userInfo: { nickname: '云游君' },
}))

const consentRequest: HostAuthorizationEvent = {
  appId: 'cms',
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
})
