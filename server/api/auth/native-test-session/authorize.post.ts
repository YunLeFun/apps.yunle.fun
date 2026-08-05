import type { NativeTestSsoRequest } from '../../../utils/native-test-session-proxy'
import {
  authorizeNativeTestSession,
  NativeTestSessionInputError,
} from '../../../utils/native-test-session-proxy'

export default defineEventHandler(async (event) => {
  setResponseHeaders(event, {
    'Cache-Control': 'no-store, max-age=0',
    'Pragma': 'no-cache',
    'Referrer-Policy': 'no-referrer',
  })
  const body = await readBody<{
    hostSession?: string
    request?: NativeTestSsoRequest
  }>(event)
  const runtime = useRuntimeConfig(event)
  try {
    return await authorizeNativeTestSession({
      hostSession: body?.hostSession ?? '',
      request: body?.request as NativeTestSsoRequest,
    }, {
      brokerBaseUrl: runtime.nativeSessionBrokerBaseUrl,
      serviceToken: runtime.nativeSessionBrokerToken,
    })
  }
  catch (error) {
    if (error instanceof NativeTestSessionInputError) {
      throw createError({
        statusCode: 400,
        statusMessage: error.message,
      })
    }
    throw error
  }
})
