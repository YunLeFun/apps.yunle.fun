import { describe, expect, it, vi } from 'vitest'
import {
  authorizeNativeTestSession,
  exchangeNativeTestSession,
  NativeTestSessionInputError,
} from '../../server/utils/native-test-session-proxy'

const options = {
  brokerBaseUrl: 'https://admin.yunle.fun',
  serviceToken: 'native-session-service-token-at-least-32-bytes',
}

describe('native test session server proxy', () => {
  it('exchanges only an alias, challenge id, and six-digit code', async () => {
    const request = vi.fn(async () => ({
      hostSession: 'host.jwt.value',
      expiresAt: Date.now() + 60_000,
      account: {
        publicAlias: 'native-sso-smoke@yunlefun',
        virtualPhone: '+86 000 0000 0001',
        displayName: 'Native SSO Smoke',
      },
    }))
    await exchangeNativeTestSession({
      publicAlias: 'Native-SSO-Smoke@YunLeFun',
      challengeId: 'challenge_01',
      code: '000042',
    }, { ...options, request })

    expect(request).toHaveBeenCalledWith(
      'https://admin.yunle.fun/api/internal/test-broker/native-session/exchange',
      expect.objectContaining({
        method: 'POST',
        headers: { Authorization: `Bearer ${options.serviceToken}` },
        body: {
          publicAlias: 'native-sso-smoke@yunlefun',
          challengeId: 'challenge_01',
          code: '000042',
        },
      }),
    )
  })

  it('forwards a host capability only for an exact registered native SSO request', async () => {
    const request = vi.fn(async () => ({ code: 'c'.repeat(43), expiresAt: Date.now() + 60_000 }))
    await authorizeNativeTestSession({
      hostSession: 'host.jwt.value',
      request: {
        mode: 'redirect',
        clientId: 'cms-web',
        targetOrigin: 'https://cms.yunle.fun',
        returnUrl: 'https://cms.yunle.fun/',
        scope: 'identity:bootstrap',
        nonce: 'n'.repeat(32),
        codeChallenge: 'c'.repeat(43),
        codeChallengeMethod: 'S256',
      },
    }, { ...options, request })

    expect(request).toHaveBeenCalledOnce()
    await authorizeNativeTestSession({
      hostSession: 'host.jwt.value',
      request: {
        mode: 'redirect',
        clientId: 'ai-sfc-web',
        targetOrigin: 'https://ai-sfc.yunle.fun',
        returnUrl: 'https://ai-sfc.yunle.fun/',
        scope: 'identity:bootstrap',
        nonce: 'n'.repeat(32),
        codeChallenge: 'c'.repeat(43),
        codeChallengeMethod: 'S256',
      },
    }, { ...options, request })

    expect(request).toHaveBeenCalledTimes(2)
    await expect(authorizeNativeTestSession({
      hostSession: 'host.jwt.value',
      request: {
        mode: 'redirect',
        clientId: 'cms-web',
        targetOrigin: 'https://evil.example',
        returnUrl: 'https://cms.yunle.fun/',
        scope: 'identity:bootstrap',
        nonce: 'n'.repeat(32),
        codeChallenge: 'c'.repeat(43),
        codeChallengeMethod: 'S256',
      },
    }, { ...options, request })).rejects.toThrow(/invalid/i)

    await expect(authorizeNativeTestSession({
      hostSession: 'host.jwt.value',
      request: {
        mode: 'redirect',
        clientId: 'ai-sfc-web',
        targetOrigin: 'https://ai-sfc.yunle.fun',
        returnUrl: 'https://cms.yunle.fun/',
        scope: 'identity:bootstrap',
        nonce: 'n'.repeat(32),
        codeChallenge: 'c'.repeat(43),
        codeChallengeMethod: 'S256',
      },
    }, { ...options, request })).rejects.toThrow(/invalid/i)
  })

  it('classifies malformed client payloads separately from runtime failures', async () => {
    await expect(exchangeNativeTestSession({
      publicAlias: '',
      challengeId: '',
      code: '',
    }, options)).rejects.toBeInstanceOf(NativeTestSessionInputError)

    await expect(exchangeNativeTestSession({
      publicAlias: 'native-sso-smoke@yunlefun',
      challengeId: 'challenge_01',
      code: '000042',
    }, {
      brokerBaseUrl: '',
      serviceToken: '',
    })).rejects.not.toBeInstanceOf(NativeTestSessionInputError)
  })
})
