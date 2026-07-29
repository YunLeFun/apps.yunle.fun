import type { HostAuthorizationEvent } from '~/composables/useBrowser'

import { describe, expect, it } from 'vitest'
import {
  readIssuedAuthorizationCode,
  validateHostAuthorization,
} from '~/utils/host-identity-broker'

const request = {
  appId: 'play',
  requestId: 'native-request-1234',
  sourceOrigin: 'https://play.yunle.fun',
  request: {
    clientId: 'play-web',
    codeChallenge: 'challenge_'.padEnd(43, 'c'),
    codeChallengeMethod: 'S256' as const,
    nonce: 'nonce_'.padEnd(43, 'n'),
    redirectUri: 'https://play.yunle.fun/',
    scope: ['identity:bootstrap'],
  },
} satisfies HostAuthorizationEvent

describe('host identity broker', () => {
  it('accepts only the exact registered Play SSO binding', () => {
    expect(validateHostAuthorization(request)).toEqual({
      appId: 'play',
      clientId: 'play-web',
      codeChallenge: request.request.codeChallenge,
      nonce: request.request.nonce,
      redirectUri: 'https://play.yunle.fun/',
      scope: 'identity:bootstrap',
      targetOrigin: 'https://play.yunle.fun',
    })
  })

  it('accepts the separately registered CMS binding', () => {
    expect(validateHostAuthorization({
      ...request,
      appId: 'cms',
      sourceOrigin: 'https://cms.yunle.fun',
      request: {
        ...request.request,
        clientId: 'cms-web',
        redirectUri: 'https://cms.yunle.fun/',
      },
    })).toEqual({
      appId: 'cms',
      clientId: 'cms-web',
      codeChallenge: request.request.codeChallenge,
      nonce: request.request.nonce,
      redirectUri: 'https://cms.yunle.fun/',
      scope: 'identity:bootstrap',
      targetOrigin: 'https://cms.yunle.fun',
    })
  })

  it.each([
    { sourceOrigin: 'https://evil.example' },
    { appId: 'cms' },
    { request: { ...request.request, clientId: 'other-web' } },
    { request: { ...request.request, redirectUri: 'https://play.yunle.fun/callback' } },
    { request: { ...request.request, scope: ['identity:bootstrap', 'profile'] } },
  ])('rejects altered origin/client/redirect/scope bindings', (patch) => {
    expect(() => validateHostAuthorization({
      ...request,
      ...patch,
    } as HostAuthorizationEvent)).toThrow('内嵌应用请求的统一登录参数无效')
  })

  it('reads the CloudBase callFunction envelope without exposing a token', () => {
    expect(readIssuedAuthorizationCode({
      result: {
        ok: true,
        code: 'code_'.padEnd(43, 'c'),
        expiresAt: 1_234,
      },
    })).toEqual({
      code: 'code_'.padEnd(43, 'c'),
      expiresAt: 1_234,
    })
  })
})
