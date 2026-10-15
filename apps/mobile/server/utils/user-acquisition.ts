import type { H3Event } from 'h3'
import type { AppsAcquisitionResult } from '../../app/utils/apps-acquisition-recorder'
import { Buffer } from 'node:buffer'
import { createError, readRawBody, setResponseHeaders, setResponseStatus } from 'h3'
import { sanitizeAcquisitionContext } from '../../app/utils/acquisition'
import { isTransientAppsAcquisitionError, readAppsAcquisitionResult } from '../../app/utils/apps-acquisition-recorder'
import { useCloudbaseAdmin } from './cloudbase-admin'
import { requireRegisteredCloudbaseUser } from './cloudbase-auth'

export const APPS_ACQUISITION_SERVER_TIMEOUT_MS = 1500
const METHODS = new Set(['phone_otp', 'email_otp', 'github', 'wx_open', 'unknown'])

/** Bearer verification supplies UID. No caller-selected app, origin or evidence reaches the internal action. */
export async function handleAppsUserAcquisition(event: H3Event) {
  setResponseHeaders(event, { 'Cache-Control': 'no-store, max-age=0', 'Pragma': 'no-cache' })
  let timer: ReturnType<typeof setTimeout> | undefined
  const controller = new AbortController()
  try {
    const deadline = new Promise<never>((_, reject) => {
      timer = setTimeout(() => {
        controller.abort()
        reject(createError({ statusCode: 503 }))
      }, APPS_ACQUISITION_SERVER_TIMEOUT_MS)
    })
    const result = await Promise.race([recordForAuthenticatedUser(event, controller.signal), deadline])
    if (!result.ok)
      setResponseStatus(event, result.statusCode)
    return result
  }
  catch (error) {
    const statusCode = typeof error === 'object' && error !== null && 'statusCode' in error
      && typeof error.statusCode === 'number' && [400, 401, 403, 409].includes(error.statusCode)
      ? error.statusCode
      : 503
    setResponseStatus(event, statusCode)
    return {
      ok: false,
      code: statusCode === 503 ? 'acquisition_unavailable' : statusCode === 409 ? 'acquisition_account_changed' : 'acquisition_request_rejected',
      statusCode,
      retryable: statusCode === 503 && (controller.signal.aborted || isTransientAppsAcquisitionError(error)),
    } satisfies AppsAcquisitionResult
  }
  finally {
    clearTimeout(timer)
  }
}

async function recordForAuthenticatedUser(event: H3Event, signal: AbortSignal): Promise<AppsAcquisitionResult> {
  const user = await requireRegisteredCloudbaseUser(event)
  if (signal.aborted)
    return { ok: false, code: 'acquisition_unavailable', statusCode: 503, retryable: true }
  const raw = await readRawBody(event)
  if (!raw || Buffer.byteLength(raw, 'utf8') > 6144)
    throw createError({ statusCode: 400 })
  let input: unknown
  try {
    input = JSON.parse(raw) as unknown
  }
  catch {
    throw createError({ statusCode: 400 })
  }
  if (!isRecord(input))
    throw createError({ statusCode: 400 })
  if (input.expectedUserId !== undefined && (typeof input.expectedUserId !== 'string' || input.expectedUserId !== user.uid))
    throw createError({ statusCode: 409 })
  const context = input.context === null || input.context === undefined ? null : sanitizeAcquisitionContext(input.context)
  if (input.context !== null && input.context !== undefined && !context)
    throw createError({ statusCode: 400 })
  const authMethod = typeof input.authMethod === 'string' && METHODS.has(input.authMethod) ? input.authMethod : 'unknown'
  const runtime = useRuntimeConfig(event)
  const serviceToken = runtime.appsAcquisitionInternalToken
  if (!serviceToken)
    return { ok: false, code: 'acquisition_service_unconfigured', statusCode: 503, retryable: false }
  const { app } = useCloudbaseAdmin()
  if (signal.aborted)
    return { ok: false, code: 'acquisition_unavailable', statusCode: 503, retryable: true }
  const response = await app.callFunction({
    name: 'account-api',
    data: { action: 'recordAppsUserAcquisition', serviceToken, userId: user.uid, context, authMethod },
  }, { timeout: 1000, retryOptions: { retries: 0 } })
  return readAppsAcquisitionResult(response.result) || { ok: false, code: 'acquisition_invalid_response', statusCode: 503, retryable: false }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
