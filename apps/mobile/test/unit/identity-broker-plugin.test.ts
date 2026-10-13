import type { HostAuthorizationEvent } from '../../app/host-runtime'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  authorizationHandler: undefined as ((event: HostAuthorizationEvent) => Promise<void>) | undefined,
  authorizeWithOtherAccount: vi.fn(),
  callFunction: vi.fn(),
  confirmAuthorization: vi.fn(),
  getSession: vi.fn(),
  navigateTo: vi.fn(),
  requestHostLogin: vi.fn(),
  resolveAuthorization: vi.fn(),
  fetch: vi.fn(),
  telemetryEvents: [] as Array<{
    context: Record<string, unknown>
    name: string
  }>,
  userInfo: { nickname: '云游君', avatar: '' },
}))

const sessionStorageValues = new Map<string, string>()

vi.mock('@capacitor/app', () => ({
  App: {
    getInfo: vi.fn().mockResolvedValue({ build: '42', version: '1.2.3' }),
  },
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
    requestHostLogin: h.requestHostLogin,
    resolveAuthorization: h.resolveAuthorization,
  },
}))

vi.mock('../../app/utils/client-telemetry', () => ({
  anonymizeTelemetryIdentifier: vi.fn().mockResolvedValue('flow-1234567890'),
  reportClientEvent: vi.fn((name: string, context: Record<string, unknown>) => {
    h.telemetryEvents.push({ context, name })
  }),
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
  userInfo: h.userInfo,
}))
vi.stubGlobal('navigateTo', h.navigateTo)
vi.stubGlobal('$fetch', h.fetch)
vi.stubGlobal('useNuxtApp', () => ({ $api: h.fetch }))

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

function resolvePolicy(data: Record<string, unknown>) {
  const clientId = String(data.clientId)
  const isAiSfc = clientId === 'ai-sfc-web'
  return {
    result: {
      ok: true,
      issuer: 'https://www.yunle.fun',
      policyVersion: '2026-08-03.2',
      registrationFingerprint: 'f'.repeat(64),
      request: {
        mode: data.mode,
        clientId,
        targetOrigin: data.targetOrigin,
        returnUrl: data.returnUrl,
        scope: data.scope,
        nonce: data.nonce,
        codeChallenge: data.codeChallenge,
        codeChallengeMethod: data.codeChallengeMethod,
      },
      presentation: {
        appId: isAiSfc ? 'ai-sfc' : 'cms',
        applicationIconUrl: isAiSfc
          ? 'https://ai-sfc.yunle.fun/brand/ai-sfc-logo.svg'
          : 'https://cms.yunle.fun/icon.svg',
        applicationName: isAiSfc ? 'AI 春联' : 'Yunle CMS',
        applicationOrigin: data.targetOrigin,
        permissionDescription: '账号标识、昵称和头像',
        consent: 'trusted',
        ...(data.prompt ? { prompt: data.prompt } : {}),
      },
    },
  }
}

describe('apps host identity broker consent', () => {
  beforeEach(async () => {
    vi.clearAllMocks()
    sessionStorageValues.clear()
    vi.stubGlobal('window', {
      sessionStorage: {
        getItem: (key: string) => sessionStorageValues.get(key) ?? null,
        removeItem: (key: string) => sessionStorageValues.delete(key),
        setItem: (key: string, value: string) => sessionStorageValues.set(key, value),
      },
    })
    h.telemetryEvents.length = 0
    h.userInfo = { nickname: '云游君', avatar: '' }
    h.getSession.mockResolvedValue({
      data: {
        session: {
          access_token: 'apps-access-token',
          user: { is_anonymous: false },
        },
      },
      error: null,
    })
    h.callFunction.mockResolvedValue({ result: { ok: true, code: 'c'.repeat(43) } })
    h.fetch.mockImplementation(async (_url: string, options: { body?: Record<string, unknown> }) => (
      resolvePolicy(options.body || {})
    ))
    h.confirmAuthorization.mockResolvedValue({ allowed: false })
    if (!h.authorizationHandler)
      await import('../../app/plugins/identity-broker.client')
  })

  it('does not mint a code when the user declines current-account authorization', async () => {
    await h.authorizationHandler?.(consentRequest)

    expect(h.confirmAuthorization).toHaveBeenCalledWith({
      requestId: consentRequest.requestId,
      applicationIconUrl: 'https://cms.yunle.fun/icon.svg',
      applicationName: 'Yunle CMS',
      applicationOrigin: 'https://cms.yunle.fun',
      accountName: '云游君',
      permissionDescription: '账号标识、昵称和头像',
    })
    expect(h.fetch).toHaveBeenCalledWith('/api/auth/sso/resolve', expect.objectContaining({
      body: expect.objectContaining({ action: 'resolveSsoAuthorization' }),
    }))
    expect(h.callFunction).not.toHaveBeenCalled()
    expect(h.resolveAuthorization).toHaveBeenCalledWith({
      requestId: consentRequest.requestId,
      error: 'HOST_AUTH_DENIED',
    })
  })

  it('resolves policy, then mints and returns only a one-time code after consent', async () => {
    h.confirmAuthorization.mockResolvedValue({ allowed: true })

    await h.authorizationHandler?.(consentRequest)

    expect(h.fetch).toHaveBeenCalledWith('/api/auth/sso/resolve', expect.any(Object))
    expect(h.callFunction).toHaveBeenCalledTimes(1)
    expect(h.callFunction).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({
        action: 'issueSsoCode',
        clientId: 'cms-web',
        targetOrigin: 'https://cms.yunle.fun',
        returnUrl: 'https://cms.yunle.fun/',
      }),
    }))
    expect(h.resolveAuthorization).toHaveBeenCalledWith({
      requestId: consentRequest.requestId,
      result: {
        ok: true,
        code: 'c'.repeat(43),
        issuer: 'https://www.yunle.fun',
      },
    })
    expect(h.telemetryEvents.map(event => event.name)).toEqual(expect.arrayContaining([
      'auth.native_sso.requested',
      'auth.native_sso.resolved',
      'auth.native_sso.prompted',
      'auth.native_sso.consent_decided',
      'auth.native_sso.code_issued',
      'auth.native_sso.completed',
    ]))
    const telemetry = JSON.stringify(h.telemetryEvents)
    expect(telemetry).not.toContain(consentRequest.request.nonce)
    expect(telemetry).not.toContain('c'.repeat(43))
  })

  it('hands other-account authorization to the platform after policy resolution', async () => {
    h.confirmAuthorization.mockResolvedValue({ allowed: false, choice: 'other' })

    await h.authorizationHandler?.(consentRequest)

    expect(h.authorizeWithOtherAccount).toHaveBeenCalledWith({
      requestId: consentRequest.requestId,
    })
    expect(h.callFunction).not.toHaveBeenCalled()
    expect(h.resolveAuthorization).not.toHaveBeenCalled()
  })

  it('starts system account selection after the central policy permits it', async () => {
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
    expect(h.fetch).toHaveBeenCalledTimes(1)
    expect(h.callFunction).not.toHaveBeenCalled()
  })

  it('keeps the page request pending and opens local Apps login when signed out', async () => {
    h.getSession.mockResolvedValue({ data: { session: null }, error: null })
    h.requestHostLogin.mockResolvedValue(undefined)

    await h.authorizationHandler?.(consentRequest)

    expect(h.requestHostLogin).toHaveBeenCalledWith({
      requestId: consentRequest.requestId,
    })
    expect(h.navigateTo).toHaveBeenCalledWith({
      path: '/login',
      query: { returnTo: 'native-authorization' },
    })
    expect(h.confirmAuthorization).not.toHaveBeenCalled()
    expect(h.fetch).toHaveBeenCalledTimes(1)
    expect(h.callFunction).not.toHaveBeenCalled()
    expect(h.resolveAuthorization).not.toHaveBeenCalled()
  })

  it('uses central presentation metadata and ignores page-supplied display fields', async () => {
    h.confirmAuthorization.mockResolvedValue({ allowed: false })
    h.userInfo = {
      nickname: '云游君',
      avatar: 'https://avatars.example.com/yunyoujun.png',
    }

    await h.authorizationHandler?.({
      ...consentRequest,
      appId: 'marketplace-alias',
      sourceOrigin: 'https://ai-sfc.yunle.fun',
      request: {
        ...consentRequest.request,
        clientId: 'ai-sfc-web',
        redirectUri: 'https://ai-sfc.yunle.fun/',
        applicationName: '伪造应用名',
      },
    } as HostAuthorizationEvent)

    expect(h.confirmAuthorization).toHaveBeenCalledWith({
      requestId: consentRequest.requestId,
      applicationIconUrl: 'https://ai-sfc.yunle.fun/brand/ai-sfc-logo.svg',
      applicationName: 'AI 春联',
      applicationOrigin: 'https://ai-sfc.yunle.fun',
      accountName: '云游君',
      accountAvatarUrl: 'https://avatars.example.com/yunyoujun.png',
      permissionDescription: '账号标识、昵称和头像',
    })
  })
})
