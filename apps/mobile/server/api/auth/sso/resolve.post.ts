import {
  resolveCentralSsoAuthorization,
  SsoAuthorizationResolverInputError,
  ssoResolverEndpoints,
} from '../../../utils/sso-authorization-resolver'

export default defineEventHandler(async (event) => {
  setResponseHeaders(event, {
    'Cache-Control': 'no-store, max-age=0',
    'Pragma': 'no-cache',
    'Referrer-Policy': 'no-referrer',
  })
  const body = await readBody(event)
  const runtime = useRuntimeConfig(event)
  try {
    return await resolveCentralSsoAuthorization(body, ssoResolverEndpoints(runtime.ssoResolverUrl, runtime.ssoTicketUrl))
  }
  catch (error) {
    if (error instanceof SsoAuthorizationResolverInputError) {
      throw createError({
        statusCode: 400,
        statusMessage: error.message,
      })
    }
    throw error
  }
})
