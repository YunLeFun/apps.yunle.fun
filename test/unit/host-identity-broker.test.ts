import type { HostAuthorizationEvent } from '~/host-runtime'

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
      applicationName: 'Play',
      applicationOrigin: 'https://play.yunle.fun',
      clientId: 'play-web',
      codeChallenge: request.request.codeChallenge,
      nonce: request.request.nonce,
      permissionDescription: '账号标识、昵称和头像',
      redirectUri: 'https://play.yunle.fun/',
      scope: 'identity:bootstrap',
      targetOrigin: 'https://play.yunle.fun',
    })
  })

  it('accepts the separately registered CMS binding', () => {
    expect(validateHostAuthorization({
      ...request,
      appId: 'yunjian',
      sourceOrigin: 'https://cms.yunle.fun',
      request: {
        ...request.request,
        clientId: 'cms-web',
        redirectUri: 'https://cms.yunle.fun/',
      },
    })).toEqual({
      appId: 'yunjian',
      applicationName: '云笺',
      applicationOrigin: 'https://cms.yunle.fun',
      clientId: 'cms-web',
      codeChallenge: request.request.codeChallenge,
      nonce: request.request.nonce,
      permissionDescription: '账号标识、昵称和头像',
      redirectUri: 'https://cms.yunle.fun/',
      scope: 'identity:bootstrap',
      targetOrigin: 'https://cms.yunle.fun',
    })
  })

  it('preserves an explicit consent prompt for the trusted host UI', () => {
    expect(validateHostAuthorization({
      ...request,
      appId: 'yunjian',
      sourceOrigin: 'https://cms.yunle.fun',
      request: {
        ...request.request,
        clientId: 'cms-web',
        redirectUri: 'https://cms.yunle.fun/',
        prompt: 'consent',
      },
    })).toMatchObject({
      appId: 'yunjian',
      prompt: 'consent',
    })
  })

  it('ignores page-supplied display copy and uses only registry metadata', () => {
    const result = validateHostAuthorization({
      ...request,
      request: {
        ...request.request,
        applicationName: '伪造应用',
        applicationOrigin: 'https://evil.example',
        permissionDescription: '读取全部数据',
      },
    } as HostAuthorizationEvent)

    expect(result).toMatchObject({
      applicationName: 'Play',
      applicationOrigin: 'https://play.yunle.fun',
      permissionDescription: '账号标识、昵称和头像',
    })
  })

  it('accepts AI SFC and derives its disclosure copy from the trusted registry', () => {
    expect(validateHostAuthorization({
      ...request,
      appId: 'ai-sfc',
      sourceOrigin: 'https://ai-sfc.yunle.fun',
      request: {
        ...request.request,
        clientId: 'ai-sfc-web',
        redirectUri: 'https://ai-sfc.yunle.fun/',
        prompt: 'consent',
      },
    })).toMatchObject({
      appId: 'ai-sfc',
      applicationIconUrl: 'https://ai-sfc.yunle.fun/brand/ai-sfc-logo-256.png',
      applicationName: 'AI 春联',
      applicationOrigin: 'https://ai-sfc.yunle.fun',
      authorizationNotice: '登录本身不会消耗云币；生成春联时会另行提示消耗。',
      permissionDescription: '账号标识、昵称和头像',
      targetOrigin: 'https://ai-sfc.yunle.fun',
    })
  })

  it('preserves an explicit account-selection prompt for system authentication', () => {
    expect(validateHostAuthorization({
      ...request,
      appId: 'yunjian',
      sourceOrigin: 'https://cms.yunle.fun',
      request: {
        ...request.request,
        clientId: 'cms-web',
        redirectUri: 'https://cms.yunle.fun/',
        prompt: 'select_account',
      },
    })).toMatchObject({
      appId: 'yunjian',
      prompt: 'select_account',
    })
  })

  it('accepts the private Admin control-plane binding without marketplace discovery', () => {
    expect(validateHostAuthorization({
      ...request,
      appId: 'admin',
      sourceOrigin: 'https://admin.yunle.fun',
      request: {
        ...request.request,
        clientId: 'admin-web',
        redirectUri: 'https://admin.yunle.fun/',
      },
    })).toEqual({
      appId: 'admin',
      applicationName: '云乐坊管理后台',
      applicationOrigin: 'https://admin.yunle.fun',
      clientId: 'admin-web',
      codeChallenge: request.request.codeChallenge,
      nonce: request.request.nonce,
      permissionDescription: '账号标识、昵称和头像',
      redirectUri: 'https://admin.yunle.fun/',
      scope: 'identity:bootstrap',
      targetOrigin: 'https://admin.yunle.fun',
    })
  })

  it('accepts the separately registered Saier binding', () => {
    expect(validateHostAuthorization({
      ...request,
      appId: 'saier',
      sourceOrigin: 'https://saier.yunle.fun',
      request: {
        ...request.request,
        clientId: 'saier-web',
        redirectUri: 'https://saier.yunle.fun/',
      },
    })).toEqual({
      appId: 'saier',
      applicationName: '赛尔',
      applicationOrigin: 'https://saier.yunle.fun',
      clientId: 'saier-web',
      codeChallenge: request.request.codeChallenge,
      nonce: request.request.nonce,
      permissionDescription: '账号标识、昵称和头像',
      redirectUri: 'https://saier.yunle.fun/',
      scope: 'identity:bootstrap',
      targetOrigin: 'https://saier.yunle.fun',
    })
  })

  it('accepts the separately registered Wenta binding', () => {
    expect(validateHostAuthorization({
      ...request,
      appId: 'wenta',
      sourceOrigin: 'https://wenta.yunle.fun',
      request: {
        ...request.request,
        clientId: 'wenta-web',
        redirectUri: 'https://wenta.yunle.fun/',
      },
    })).toEqual({
      appId: 'wenta',
      applicationName: '闻塔',
      applicationOrigin: 'https://wenta.yunle.fun',
      clientId: 'wenta-web',
      codeChallenge: request.request.codeChallenge,
      nonce: request.request.nonce,
      permissionDescription: '账号标识、昵称和头像',
      redirectUri: 'https://wenta.yunle.fun/',
      scope: 'identity:bootstrap',
      targetOrigin: 'https://wenta.yunle.fun',
    })
  })

  it.each([
    { sourceOrigin: 'https://evil.example' },
    { appId: 'cms' },
    { request: { ...request.request, clientId: 'other-web' } },
    { request: { ...request.request, redirectUri: 'https://play.yunle.fun/callback' } },
    { request: { ...request.request, scope: ['identity:bootstrap', 'profile'] } },
    { request: { ...request.request, prompt: 'login' } },
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
