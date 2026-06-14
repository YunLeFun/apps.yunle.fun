import { requireCloudbaseUser } from '../../../utils/cloudbase-auth'
import { assertAllowedJsapiOrigin, createJsapiAuthCode, normalizeCloudbaseSession, normalizeOrigin, normalizeScope } from '../../../utils/jsapi-auth'

export default defineEventHandler(async (event) => {
  const user = await requireCloudbaseUser(event)
  const body = await readBody(event)

  const origin = normalizeOrigin(body?.origin)
  assertAllowedJsapiOrigin(origin)

  const payload = await createJsapiAuthCode({
    user,
    origin,
    appId: typeof body?.appId === 'string' && body.appId.trim()
      ? body.appId.trim()
      : new URL(origin).hostname,
    scope: normalizeScope(body?.scope),
    session: normalizeCloudbaseSession(body?.session),
  })

  return payload
})
