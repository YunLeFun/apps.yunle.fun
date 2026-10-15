import { describe, expect, it, vi } from 'vitest'
import {
  resolveCentralSsoAuthorization,
  SsoAuthorizationResolverInputError,
} from '../../server/utils/sso-authorization-resolver'
import { acquisition } from './acquisition-fixture'

describe('central SSO authorization resolver transport', () => {
  it('forwards bounded acquisition without adding caller-selected identity fields', async () => {
    const request = vi.fn(async (_url: string, _options: Record<string, unknown>) => ({ ok: true }))
    await resolveCentralSsoAuthorization({
      mode: 'redirect',
      clientId: 'cook-web',
      targetOrigin: 'https://cook.yunle.fun',
      returnUrl: 'https://cook.yunle.fun/',
      scope: 'identity:bootstrap',
      nonce: 'n'.repeat(32),
      codeChallenge: 'c'.repeat(43),
      codeChallengeMethod: 'S256',
      acquisition,
      userId: 'untrusted',
    }, { endpoint: 'https://api.yunle.fun/sso-ticket', request })
    const options = request.mock.calls[0]![1]
    expect(options.body).toMatchObject({ acquisition })
    expect(options.body).not.toHaveProperty('userId')
  })

  it('forwards only known protocol fields to the fixed central endpoint', async () => {
    const request = vi.fn(async () => ({ ok: true }))
    await resolveCentralSsoAuthorization({
      action: 'caller-selected-action',
      mode: 'redirect',
      clientId: 'dayun-kicker-web',
      targetOrigin: 'https://dayun-kicker.yunle.fun',
      returnUrl: 'https://dayun-kicker.yunle.fun/',
      scope: 'identity:bootstrap',
      nonce: 'n'.repeat(32),
      codeChallenge: 'c'.repeat(43),
      codeChallengeMethod: 'S256',
      uid: 'attacker-selected-subject',
    }, {
      endpoint: 'https://api.yunle.fun/sso-ticket',
      request,
    })

    expect(request).toHaveBeenCalledWith('https://api.yunle.fun/sso-ticket', {
      method: 'POST',
      body: {
        action: 'resolveSsoAuthorization',
        mode: 'redirect',
        clientId: 'dayun-kicker-web',
        targetOrigin: 'https://dayun-kicker.yunle.fun',
        returnUrl: 'https://dayun-kicker.yunle.fun/',
        scope: 'identity:bootstrap',
        nonce: 'n'.repeat(32),
        codeChallenge: 'c'.repeat(43),
        codeChallengeMethod: 'S256',
      },
      retry: 0,
      timeout: 10_000,
    })
  })

  it('rejects malformed input and non-HTTPS resolver configuration', async () => {
    await expect(resolveCentralSsoAuthorization(null, {
      endpoint: 'https://api.yunle.fun/sso-ticket',
    })).rejects.toBeInstanceOf(SsoAuthorizationResolverInputError)
    await expect(resolveCentralSsoAuthorization({}, {
      endpoint: 'http://api.yunle.fun/sso-ticket',
    })).rejects.toThrow('Central SSO resolver URL is invalid')
    await expect(resolveCentralSsoAuthorization({
      mode: 'redirect',
      clientId: 'dayun-kicker-web',
      targetOrigin: 'https://evil.example',
      returnUrl: 'https://dayun-kicker.yunle.fun/',
      scope: 'identity:bootstrap',
      nonce: 'n'.repeat(32),
      codeChallenge: 'c'.repeat(43),
      codeChallengeMethod: 'S256',
    }, {
      endpoint: 'https://api.yunle.fun/sso-ticket',
    })).rejects.toBeInstanceOf(SsoAuthorizationResolverInputError)
    await expect(resolveCentralSsoAuthorization({
      mode: 'redirect',
      clientId: 'dayun-kicker-web',
      targetOrigin: 'https://dayun-kicker.yunle.fun',
      returnUrl: 'https://dayun-kicker.yunle.fun/',
      scope: 'identity:bootstrap',
      nonce: 'n'.repeat(32),
      codeChallenge: 'c'.repeat(43),
      codeChallengeMethod: 'S256',
    }, {
      endpoint: 'https://api.yunle.fun/sso-ticket?target=evil',
    })).rejects.toThrow('Central SSO resolver URL is invalid')
  })
})
