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
  nativeTestSession: h.nativeTestSession,
  clearNativeTestSession: vi.fn(),
}))
vi.stubGlobal('navigateTo', h.navigateTo)
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
    sessionStorageValues.clear()
    vi.stubGlobal('window', {
      sessionStorage: {
        getItem: (key: string) => sessionStorageValues.get(key) ?? null,
        removeItem: (key: string) => sessionStorageValues.delete(key),
        setItem: (key: string, value: string) => sessionStorageValues.set(key, value),
      },
    })
    h.nativeTestSession = undefined
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
    h.confirmAuthorization.mockResolvedValue({ allowed: false })
    if (!h.authorizationHandler)
      await import('../../app/plugins/identity-broker.client')
  })

  it('does not mint a code when the user declines current-account authorization', async () => {
    expect(h.authorizationHandler).toBeTypeOf('function')
    await h.authorizationHandler?.(consentRequest)

    expect(h.confirmAuthorization).toHaveBeenCalledWith({
      requestId: consentRequest.requestId,
      applicationName: '云笺',
      applicationOrigin: 'https://cms.yunle.fun',
      accountName: '云游君',
      permissionDescription: '账号标识、昵称和头像',
    })
    expect(h.callFunction).not.toHaveBeenCalled()
    expect(h.resolveAuthorization).toHaveBeenCalledWith({
      requestId: consentRequest.requestId,
      error: 'HOST_AUTH_DENIED',
    })
    expect(h.telemetryEvents).toContainEqual(expect.objectContaining({
      context: expect.objectContaining({
        outcome: 'denied',
        requestId: consentRequest.requestId,
        stage: 'consent',
      }),
      name: 'auth.native_sso.failed',
    }))
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
    expect(h.telemetryEvents.map(event => event.name)).toEqual(expect.arrayContaining([
      'auth.native_sso.requested',
      'auth.native_sso.validated',
      'auth.native_sso.prompted',
      'auth.native_sso.consent_decided',
      'auth.native_sso.code_issued',
      'auth.native_sso.completed',
    ]))
    expect(h.telemetryEvents).toContainEqual(expect.objectContaining({
      context: expect.objectContaining({
        clientId: 'cms-web',
        flow: 'flow-1234567890',
        outcome: 'success',
        requestId: consentRequest.requestId,
        stage: 'deliver_code',
      }),
      name: 'auth.native_sso.completed',
    }))
    const telemetry = JSON.stringify(h.telemetryEvents)
    expect(telemetry).not.toContain(consentRequest.request.nonce)
    expect(telemetry).not.toContain('c'.repeat(43))
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

    expect(h.getSession).not.toHaveBeenCalled()
    expect(h.confirmAuthorization).toHaveBeenCalledWith({
      requestId: consentRequest.requestId,
      applicationName: '云笺',
      applicationOrigin: 'https://cms.yunle.fun',
      accountName: 'native-sso-smoke@yunlefun',
      permissionDescription: '账号标识、昵称和头像',
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
    expect(h.callFunction).not.toHaveBeenCalled()
    expect(h.resolveAuthorization).not.toHaveBeenCalled()
    expect(h.telemetryEvents).toContainEqual(expect.objectContaining({
      context: expect.objectContaining({
        outcome: 'host_login',
        stage: 'host_login',
      }),
      name: 'auth.native_sso.handed_off',
    }))
  })

  it('passes the AI SFC cost notice from the trusted registry to native UI', async () => {
    h.confirmAuthorization.mockResolvedValue({ allowed: false })
    h.userInfo = {
      nickname: '云游君',
      avatar: 'https://avatars.example.com/yunyoujun.png',
    }

    await h.authorizationHandler?.({
      ...consentRequest,
      appId: 'ai-sfc',
      sourceOrigin: 'https://ai-sfc.yunle.fun',
      request: {
        ...consentRequest.request,
        clientId: 'ai-sfc-web',
        redirectUri: 'https://ai-sfc.yunle.fun/',
      },
    })

    expect(h.confirmAuthorization).toHaveBeenCalledWith({
      requestId: consentRequest.requestId,
      applicationIconUrl: 'https://ai-sfc.yunle.fun/brand/ai-sfc-logo-256.png',
      applicationName: 'AI 春联',
      applicationOrigin: 'https://ai-sfc.yunle.fun',
      accountName: '云游君',
      accountAvatarUrl: 'https://avatars.example.com/yunyoujun.png',
      permissionDescription: '账号标识、昵称和头像',
      authorizationNotice: '登录本身不会消耗云币；生成春联时会另行提示消耗。',
    })
  })
})
