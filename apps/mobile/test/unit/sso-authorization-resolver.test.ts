import { afterEach, describe, expect, it, vi } from 'vitest'
import { onRequest } from '../../edge-functions/api/auth/sso/resolve'
import {
  CLOUDRUN_SSO_RESOLVER,
  resolveCentralSsoAuthorization,
  SsoAuthorizationResolverInputError,
  ssoResolverEndpoints,
} from '../../server/utils/sso-authorization-resolver'
import { acquisition } from './acquisition-fixture'

const endpoint = 'https://api.yunle.fun/sso-ticket'
const nativeInput = {
  mode: 'redirect',
  clientId: 'cms-ios',
  targetOrigin: 'https://cms.yunle.fun',
  returnUrl: 'https://cms.yunle.fun/ios-auth/callback',
  scope: 'identity:bootstrap',
  nonce: 'n'.repeat(32),
  codeChallenge: 'c'.repeat(43),
  codeChallengeMethod: 'S256',
}

function edgeRequest(body: string): Request {
  return new Request('https://apps.yunle.fun/api/auth/sso/resolve', {
    method: 'POST',
    body,
    headers: { Cookie: 'test=private', Authorization: 'Bearer test' },
  })
}

afterEach(() => vi.unstubAllGlobals())

describe('central SSO authorization resolver transport', () => {
  it('keeps a configured non-production Broker as the resolver unless explicitly overridden', () => {
    const legacy = 'https://dev.example/sso-ticket'
    expect(ssoResolverEndpoints(undefined, legacy)).toEqual({ endpoint: legacy, fallbackEndpoint: legacy })
    expect(ssoResolverEndpoints(endpoint, endpoint)).toEqual({ endpoint, fallbackEndpoint: endpoint })
  })

  it('forwards bounded acquisition without adding caller-selected identity fields', async () => {
    const request = vi.fn<typeof fetch>().mockResolvedValue(Response.json({ ok: true }))
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
    const body = JSON.parse(request.mock.calls[0]![1]?.body as string)
    expect(body).toMatchObject({ acquisition })
    expect(body).not.toHaveProperty('userId')
  })

  it('forwards only known protocol fields to the fixed central endpoint', async () => {
    const request = vi.fn<typeof fetch>().mockResolvedValue(Response.json({ ok: true }))
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

    const [url, options] = request.mock.calls[0]!
    expect(url).toBe(endpoint)
    expect(options).toMatchObject({ method: 'POST', redirect: 'error' })
    expect(JSON.parse(options?.body as string)).toEqual({
      action: 'resolveSsoAuthorization',
      mode: 'redirect',
      clientId: 'dayun-kicker-web',
      targetOrigin: 'https://dayun-kicker.yunle.fun',
      returnUrl: 'https://dayun-kicker.yunle.fun/',
      scope: 'identity:bootstrap',
      nonce: 'n'.repeat(32),
      codeChallenge: 'c'.repeat(43),
      codeChallengeMethod: 'S256',
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

describe('native authorization edge route', () => {
  it('validates every authorization and forwards no credentials or caller-selected action', async () => {
    const broker = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(Response.json({ ok: true, request: { nonce: nativeInput.nonce } }, { headers: { 'Server-Timing': 'sso-rate-limit;dur=72, sso-policy;dur=1, unexpected;dur=8' } }))
      .mockResolvedValueOnce(Response.json({ ok: true, request: { nonce: 'b'.repeat(32) } }))
    vi.stubGlobal('fetch', broker)
    const first = await onRequest({ request: edgeRequest(JSON.stringify({ ...nativeInput, action: 'issueSsoCode' })), env: {} })
    const second = await onRequest({ request: edgeRequest(JSON.stringify({ ...nativeInput, nonce: 'b'.repeat(32) })), env: {} })
    expect(broker).toHaveBeenCalledTimes(2)
    const [url, options] = broker.mock.calls[0]!
    expect(url).toBe(CLOUDRUN_SSO_RESOLVER)
    expect(new Headers(options?.headers).has('Authorization')).toBe(false)
    expect(new Headers(options?.headers).has('Cookie')).toBe(false)
    expect(JSON.parse(options?.body as string)).toEqual({ action: 'resolveSsoAuthorization', ...nativeInput })
    expect(first.headers.get('Cache-Control')).toContain('no-store')
    expect(first.headers.get('Server-Timing')).toMatch(/^sso-edge;dur=\d+, sso-rate-limit;dur=72, sso-policy;dur=1$/)
    expect(first.headers.get('X-Yunle-Sso-Resolver')).toBe('cloudrun')
    expect(await first.json()).toMatchObject({ request: { nonce: nativeInput.nonce } })
    expect(await second.json()).toMatchObject({ request: { nonce: 'b'.repeat(32) } })
  })

  it('falls back to read-only SCF when the CloudRun route is unavailable', async () => {
    const upstream = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(new Response(null, { status: 503 }))
      .mockResolvedValueOnce(Response.json({ ok: true, request: { nonce: nativeInput.nonce } }))
    vi.stubGlobal('fetch', upstream)
    const response = await onRequest({ request: edgeRequest(JSON.stringify(nativeInput)), env: {} })
    expect(response.status).toBe(200)
    expect(response.headers.get('X-Yunle-Sso-Resolver')).toBe('scf')
    expect(upstream.mock.calls.map(call => call[0])).toEqual([CLOUDRUN_SSO_RESOLVER, endpoint])
    expect(upstream.mock.calls[1]![1]?.body).toBe(upstream.mock.calls[0]![1]?.body)
  })

  it('rejects invalid requests and reports broker failure without an authorization result', async () => {
    const broker = vi.fn<typeof fetch>().mockResolvedValueOnce(new Response(null, { status: 429 }))
    vi.stubGlobal('fetch', broker)
    const badBody = await onRequest({ request: edgeRequest('!'), env: {} })
    const invalidProof = await onRequest({ request: edgeRequest(JSON.stringify({ ...nativeInput, nonce: 'short' })), env: {} })
    expect(badBody.status).toBe(400)
    expect(invalidProof.status).toBe(400)
    expect(broker).not.toHaveBeenCalled()
    const limited = await onRequest({ request: edgeRequest(JSON.stringify(nativeInput)), env: {} })
    expect(limited.status).toBe(429)
    expect(broker).toHaveBeenCalledTimes(1)
    expect(limited.headers.get('Cache-Control')).toContain('no-store')
  })
})
