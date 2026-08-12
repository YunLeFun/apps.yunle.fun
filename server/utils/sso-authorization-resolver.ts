export interface SsoAuthorizationResolverOptions {
  endpoint: string
  request?: (url: string, options: Record<string, unknown>) => Promise<unknown>
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
  const request = options.request ?? ((url, requestOptions) => $fetch(url, requestOptions))
  return await request(endpoint, {
    method: 'POST',
    body: {
      action: 'resolveSsoAuthorization',
      ...body,
    },
    retry: 0,
    timeout: 10_000,
  })
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
  }
}

export class SsoAuthorizationResolverInputError extends Error {
  override name = 'SsoAuthorizationResolverInputError'
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
