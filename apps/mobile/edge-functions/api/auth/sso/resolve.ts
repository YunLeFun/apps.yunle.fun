import {
  resolveCentralSsoAuthorization,
  SsoAuthorizationResolverInputError,
  SsoAuthorizationResolverUpstreamError,
  ssoResolverEndpoints,
  upstreamSsoTiming,
} from '../../../../server/utils/sso-authorization-resolver'

const responseHeaders = {
  'Cache-Control': 'no-store, max-age=0',
  'Content-Type': 'application/json; charset=utf-8',
  'Pragma': 'no-cache',
  'Referrer-Policy': 'no-referrer',
}

/** Keep the native resolver URL on a lightweight runtime. The central broker still validates each request. */
export async function onRequest({ request, env }: {
  request: Request
  env: { NUXT_SSO_RESOLVER_URL?: string, NUXT_SSO_TICKET_URL?: string }
}): Promise<Response> {
  if (request.method !== 'POST') {
    return errorResponse(405, 'Method Not Allowed', { Allow: 'POST' })
  }

  let body: unknown
  try {
    body = await request.json()
  }
  catch {
    return errorResponse(400, 'SSO authorization request is invalid')
  }

  const started = performance.now()
  try {
    const { endpoint, fallbackEndpoint } = ssoResolverEndpoints(env.NUXT_SSO_RESOLVER_URL, env.NUXT_SSO_TICKET_URL)
    let backend = endpoint === fallbackEndpoint ? 'scf' : 'cloudrun'
    let timing: string[] = []
    const result = await resolveCentralSsoAuthorization(body, {
      endpoint,
      fallbackEndpoint,
      onResponse(response, fallback) {
        if (fallback)
          backend = 'scf'
        timing = upstreamSsoTiming(response)
      },
    })
    return new Response(JSON.stringify(result), {
      headers: {
        ...responseHeaders,
        'Server-Timing': [`sso-edge;dur=${Math.round(performance.now() - started)}`, ...timing].join(', '),
        'X-Yunle-Sso-Resolver': backend,
      },
    })
  }
  catch (error) {
    const status = error instanceof SsoAuthorizationResolverInputError
      ? 400
      : error instanceof SsoAuthorizationResolverUpstreamError ? error.statusCode : 500
    return errorResponse(status, status === 400 ? 'SSO authorization request is invalid' : 'SSO authorization could not be resolved')
  }
}

function errorResponse(statusCode: number, statusMessage: string, headers?: Record<string, string>): Response {
  return new Response(JSON.stringify({ error: true, statusCode, statusMessage }), {
    status: statusCode,
    headers: { ...responseHeaders, ...headers },
  })
}
