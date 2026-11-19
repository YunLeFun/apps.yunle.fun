import { sanitizeAcquisitionContext } from '../../app/utils/acquisition'

export const CLOUDRUN_SSO_RESOLVER = 'https://api.yunle.fun/auth/sso/resolve'
export const SCF_SSO_RESOLVER = 'https://api.yunle.fun/sso-ticket'

export interface SsoAuthorizationResolverOptions {
  endpoint: string
  fallbackEndpoint?: string
  onResponse?: (response: Response, fallback: boolean) => void
  request?: typeof fetch
}

/**
 * Server-side transport for the central read-only resolver. Known protocol
 * fields are copied into a fresh object; the central function remains the
 * authority for client, Origin, redirect URI, scope, prompt, nonce, and PKCE.
 */
export async function resolveCentralSsoAuthorization(
  input: unknown,
  options: SsoAuthorizationResolverOptions,
): Promise<unknown> {
  const endpoint = exactHttpsEndpoint(options.endpoint)
  const body = normalizeSsoAuthorizationProtocolRequest(input)
  const fallback = options.fallbackEndpoint && exactHttpsEndpoint(options.fallbackEndpoint)
  const request = options.request ?? fetch
  const encoded = JSON.stringify({ action: 'resolveSsoAuthorization', ...body })
  const mayFallback = !!fallback && fallback !== endpoint

  async function attempt(url: string, timeoutMs: number, isFallback: boolean) {
    const controller = new AbortController()
    const deadline = setTimeout(() => controller.abort(), timeoutMs)
    try {
      const response = await request(url, {
        method: 'POST',
        headers: { 'Accept': 'application/json', 'Content-Type': 'application/json' },
        body: encoded,
        redirect: 'error',
        signal: controller.signal,
      })
      if (!response.ok)
        throw new SsoAuthorizationResolverUpstreamError(response.status)
      const result: unknown = await response.json()
      options.onResponse?.(response, isFallback)
      return result
    }
    catch (error) {
      if (error instanceof SsoAuthorizationResolverUpstreamError)
        throw error
      throw new SsoAuthorizationResolverUpstreamError(controller.signal.aborted ? 504 : 502)
    }
    finally {
      clearTimeout(deadline)
    }
  }

  try {
    return await attempt(endpoint, mayFallback ? 2_000 : 10_000, false)
  }
  catch (error) {
    if (!mayFallback || !(error instanceof SsoAuthorizationResolverUpstreamError) || ![404, 502, 503, 504].includes(error.statusCode))
      throw error
    return await attempt(fallback, 8_000, true)
  }
}

export function upstreamSsoTiming(response: Response): string[] {
  return (response.headers.get('Server-Timing') ?? '').split(',').map(value => value.trim()).filter(value => /^sso-(?:rate-limit|policy);dur=\d{1,5}$/.test(value))
}

export function normalizeSsoAuthorizationProtocolRequest(input: unknown) {
  if (!isRecord(input))
    throw new SsoAuthorizationResolverInputError('SSO authorization request is invalid')
  const targetOrigin = exactHttpsOrigin(input.targetOrigin)
  const returnUrl = exactHttpsUrl(input.returnUrl)
  if (input.mode !== 'redirect'
    || typeof input.clientId !== 'string'
    || !/^[a-z0-9][a-z0-9-]{1,127}$/.test(input.clientId)
    || !targetOrigin
    || !returnUrl
    || new URL(returnUrl).origin !== targetOrigin
    || input.scope !== 'identity:bootstrap'
    || typeof input.nonce !== 'string'
    || !/^[\w-]{32,128}$/.test(input.nonce)
    || typeof input.codeChallenge !== 'string'
    || !/^[\w-]{43}$/.test(input.codeChallenge)
    || input.codeChallengeMethod !== 'S256'
    || (input.prompt !== undefined
      && input.prompt !== 'consent'
      && input.prompt !== 'select_account')) {
    throw new SsoAuthorizationResolverInputError('SSO authorization request is invalid')
  }
  const acquisition = sanitizeAcquisitionContext(input.acquisition)
  return {
    mode: 'redirect' as const,
    clientId: input.clientId,
    targetOrigin,
    returnUrl,
    scope: 'identity:bootstrap' as const,
    nonce: input.nonce,
    codeChallenge: input.codeChallenge,
    codeChallengeMethod: 'S256' as const,
    ...(input.prompt
      ? { prompt: input.prompt as 'consent' | 'select_account' }
      : {}),
    ...(acquisition ? { acquisition } : {}),
  }
}

export class SsoAuthorizationResolverInputError extends Error {
  override name = 'SsoAuthorizationResolverInputError'
}

export class SsoAuthorizationResolverUpstreamError extends Error {
  override name = 'SsoAuthorizationResolverUpstreamError'

  constructor(readonly statusCode: number) {
    super('Central SSO authorization resolver is unavailable')
  }
}

function exactHttpsEndpoint(input: string): string {
  const url = exactHttpsUrl(input)
  if (!url || new URL(url).search)
    throw new Error('Central SSO resolver URL is invalid')
  return url
}

function exactHttpsOrigin(input: unknown): string {
  if (typeof input !== 'string')
    return ''
  try {
    const url = new URL(input)
    return url.protocol === 'https:'
      && !url.username
      && !url.password
      && !url.search
      && !url.hash
      && !url.hostname.endsWith('.')
      && url.pathname === '/'
      && url.origin === input
      ? input
      : ''
  }
  catch {
    return ''
  }
}

function exactHttpsUrl(input: unknown): string {
  if (typeof input !== 'string')
    return ''
  try {
    const url = new URL(input)
    if (url.protocol !== 'https:'
      || url.username
      || url.password
      || url.hash
      || url.hostname.endsWith('.')
      || url.toString() !== input) {
      return ''
    }
    return input
  }
  catch {
    return ''
  }
}

function isRecord(input: unknown): input is Record<string, unknown> {
  return input !== null && typeof input === 'object' && !Array.isArray(input)
}
