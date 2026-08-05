import { exchangeNativeTestSession } from '../../../utils/native-test-session-proxy'

export default defineEventHandler(async (event) => {
  setResponseHeaders(event, {
    'Cache-Control': 'no-store, max-age=0',
    'Pragma': 'no-cache',
    'Referrer-Policy': 'no-referrer',
  })
  const body = await readBody<{
    publicAlias?: string
    challengeId?: string
    code?: string
  }>(event)
  const runtime = useRuntimeConfig(event)
  return await exchangeNativeTestSession({
    publicAlias: body?.publicAlias ?? '',
    challengeId: body?.challengeId ?? '',
    code: body?.code ?? '',
  }, {
    brokerBaseUrl: runtime.nativeSessionBrokerBaseUrl,
    serviceToken: runtime.nativeSessionBrokerToken,
  })
})
