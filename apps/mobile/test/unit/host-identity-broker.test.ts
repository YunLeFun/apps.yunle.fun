import type { HostAuthorizationEvent } from '~/host-runtime'

import { describe, expect, it } from 'vitest'
import {
  createHostAuthorizationResolutionRequest,
  readIssuedAuthorizationCode,
  readResolvedHostAuthorization,
} from '~/utils/host-identity-broker'
import { acquisition } from './acquisition-fixture'

const event = {
  appId: 'dayun-kicker',
  requestId: 'native-request-1234',
  sourceOrigin: 'https://dayun-kicker.yunle.fun',
  request: {
    clientId: 'dayun-kicker-web',
    codeChallenge: 'challenge_'.padEnd(43, 'c'),
    codeChallengeMethod: 'S256' as const,
    nonce: 'nonce_'.padEnd(43, 'n'),
    redirectUri: 'https://dayun-kicker.yunle.fun/',
    scope: ['identity:bootstrap'],
  },
} satisfies HostAuthorizationEvent

function resolvedResponse(
  pending = createHostAuthorizationResolutionRequest(event),
  overrides: Record<string, unknown> = {},
) {
  return {
    result: {
      ok: true,
      issuer: 'https://www.yunle.fun',
      policyVersion: '2026-08-03.2',
      registrationFingerprint: 'f'.repeat(64),
      request: {
        mode: pending.mode,
        clientId: pending.clientId,
        targetOrigin: pending.targetOrigin,
        returnUrl: pending.returnUrl,
        scope: pending.scope,
        nonce: pending.nonce,
        codeChallenge: pending.codeChallenge,
        codeChallengeMethod: pending.codeChallengeMethod,
      },
      presentation: {
        appId: 'dayun-kicker',
        applicationIconUrl: 'https://dayun-kicker.yunle.fun/favicon.svg',
        applicationName: '暴力电驴',
        applicationOrigin: pending.targetOrigin,
        permissionDescription: '账号标识、昵称和头像',
        consent: 'trusted',
      },
      ...overrides,
    },
  }
}

describe('host identity broker', () => {
  it('keeps only sanitized client-reported acquisition in the resolved issue payload', () => {
    const pending = createHostAuthorizationResolutionRequest({
      ...event,
      request: {
        ...event.request,
        acquisition: {
          ...acquisition,
          firstTouch: { ...acquisition.firstTouch, landingPath: '/random?secret=private#token' },
        },
      },
    })
    expect(pending.acquisition?.firstTouch.landingPath).toBe('/random')
    expect(readResolvedHostAuthorization(resolvedResponse(pending), pending).issueRequest.acquisition)
      .toEqual(acquisition)
    expect(JSON.stringify(pending)).not.toContain('private')
  })

  it('drops malformed optional acquisition without rejecting valid authorization', () => {
    const pending = createHostAuthorizationResolutionRequest({
      ...event,
      request: { ...event.request, acquisition: { version: 9 } as never },
    })
    expect(pending).not.toHaveProperty('acquisition')
    expect(readResolvedHostAuthorization(resolvedResponse(pending), pending).clientId).toBe(event.request.clientId)
  })

  it('builds a central policy request from protocol facts and the actual source origin', () => {
    expect(createHostAuthorizationResolutionRequest(event)).toEqual({
      action: 'resolveSsoAuthorization',
      mode: 'redirect',
      clientId: 'dayun-kicker-web',
      targetOrigin: 'https://dayun-kicker.yunle.fun',
      returnUrl: 'https://dayun-kicker.yunle.fun/',
      scope: 'identity:bootstrap',
      nonce: event.request.nonce,
      codeChallenge: event.request.codeChallenge,
      codeChallengeMethod: 'S256',
    })
  })

  it('does not use marketplace appId or page display copy as authorization input', () => {
    expect(createHostAuthorizationResolutionRequest({
      ...event,
      appId: 'unrelated-marketplace-slug',
      request: {
        ...event.request,
        applicationName: '伪造应用',
        permissionDescription: '读取全部数据',
      },
    } as HostAuthorizationEvent)).toEqual(
      createHostAuthorizationResolutionRequest(event),
    )
  })

  it('accepts only a fully bound central response and uses its presentation metadata', () => {
    const pending = createHostAuthorizationResolutionRequest(event)
    expect(readResolvedHostAuthorization(resolvedResponse(pending), pending)).toMatchObject({
      appId: 'dayun-kicker',
      applicationIconUrl: 'https://dayun-kicker.yunle.fun/favicon.svg',
      applicationName: '暴力电驴',
      applicationOrigin: 'https://dayun-kicker.yunle.fun',
      clientId: 'dayun-kicker-web',
      consent: 'trusted',
      issuer: 'https://www.yunle.fun',
      permissionDescription: '账号标识、昵称和头像',
      policyVersion: '2026-08-03.2',
      registrationFingerprint: 'f'.repeat(64),
      issueRequest: {
        mode: 'redirect',
        clientId: 'dayun-kicker-web',
        targetOrigin: 'https://dayun-kicker.yunle.fun',
        returnUrl: 'https://dayun-kicker.yunle.fun/',
        scope: 'identity:bootstrap',
      },
    })
  })

  it('allows central policy to require consent even when the page omitted a prompt', () => {
    const pending = createHostAuthorizationResolutionRequest(event)
    const response = resolvedResponse(pending)
    response.result.presentation.consent = 'explicit'
    Object.assign(response.result.presentation, { prompt: 'consent' })
    expect(readResolvedHostAuthorization(response, pending).prompt).toBe('consent')
  })

  it('rejects an explicit-consent policy response that omits the prompt', () => {
    const pending = createHostAuthorizationResolutionRequest(event)
    const response = resolvedResponse(pending)
    response.result.presentation.consent = 'explicit'
    expect(() => readResolvedHostAuthorization(response, pending))
      .toThrow('统一身份服务返回了无效的授权策略')
  })

  it('preserves an explicit account-selection prompt end to end', () => {
    const pending = createHostAuthorizationResolutionRequest({
      ...event,
      request: { ...event.request, prompt: 'select_account' },
    })
    const response = resolvedResponse(pending)
    Object.assign(response.result.presentation, { prompt: 'select_account' })
    expect(readResolvedHostAuthorization(response, pending).prompt).toBe('select_account')
  })

  it.each([
    { sourceOrigin: 'https://evil.example' },
    { sourceOrigin: 'https://dayun-kicker.yunle.fun/' },
    { request: { ...event.request, clientId: 'Other Client' } },
    { request: { ...event.request, scope: ['identity:bootstrap', 'profile'] } },
    { request: { ...event.request, prompt: 'login' } },
  ])('rejects malformed local protocol facts before contacting policy', (patch) => {
    expect(() => createHostAuthorizationResolutionRequest({
      ...event,
      ...patch,
    } as HostAuthorizationEvent)).toThrow('内嵌应用请求未获统一身份策略授权')
  })

  it.each([
    { issuer: 'https://evil.example' },
    { registrationFingerprint: 'short' },
    { request: { mode: 'redirect' } },
    { presentation: { appId: 'other-app' } },
  ])('rejects an altered or incomplete central response', (patch) => {
    const pending = createHostAuthorizationResolutionRequest(event)
    expect(() => readResolvedHostAuthorization(
      resolvedResponse(pending, patch),
      pending,
    )).toThrow('统一身份服务返回了无效的授权策略')
  })

  it('maps an authoritative policy rejection to an invalid host request', () => {
    const pending = createHostAuthorizationResolutionRequest(event)
    expect(() => readResolvedHostAuthorization({
      result: { ok: false, reason: 'client_unknown' },
    }, pending)).toThrow('内嵌应用请求未获统一身份策略授权')
  })

  it('reads the CloudBase callFunction envelope without exposing a token', () => {
    expect(readIssuedAuthorizationCode({
      result: {
        ok: true,
        code: 'c'.repeat(43),
        expiresAt: 1_234,
      },
    })).toEqual({
      code: 'c'.repeat(43),
      expiresAt: 1_234,
    })
  })
})
