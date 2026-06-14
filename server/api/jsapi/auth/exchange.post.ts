import { assertAllowedJsapiOrigin, consumeJsapiAuthCode, normalizeOrigin } from '../../../utils/jsapi-auth'

export default defineEventHandler(async (event) => {
  const body = await readBody(event)
  const origin = normalizeOrigin(getRequestHeader(event, 'origin') || body?.origin)
  assertAllowedJsapiOrigin(origin)

  const data = await consumeJsapiAuthCode({
    code: typeof body?.code === 'string' ? body.code : '',
    origin,
  })

  return { data }
})
