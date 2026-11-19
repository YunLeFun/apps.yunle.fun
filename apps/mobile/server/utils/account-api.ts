import type { H3Event } from 'h3'
import { createError, getRequestHeader } from 'h3'
import { parseBearerToken } from './cloudbase-auth'
import { resolveCloudbaseEnvId } from './cloudbase-config'

export async function invokeAccountApi(event: H3Event, fields: Record<string, unknown>, unavailableMessage: string): Promise<unknown> {
  const token = parseBearerToken(getRequestHeader(event, 'authorization'))
  if (!token)
    throw createError({ statusCode: 401 })
  const unavailable = () => createError({ statusCode: 503, message: unavailableMessage })
  const env = resolveCloudbaseEnvId(useRuntimeConfig(event))
  if (!/^[\w-]+$/.test(env))
    throw unavailable()

  let response: Response
  try {
    response = await fetch(`https://${env}.api.tcloudbasegateway.com/v1/functions/account-api`, {
      method: 'POST',
      redirect: 'error',
      cache: 'no-store',
      signal: AbortSignal.timeout(20000),
      headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify(fields),
    })
  }
  catch {
    throw unavailable()
  }
  if (response.status === 401 || response.status === 403)
    throw createError({ statusCode: response.status })
  if (!response.ok)
    throw unavailable()
  try {
    return await response.json() as unknown
  }
  catch {
    throw unavailable()
  }
}
