import type { H3Event } from 'h3'
import { createError } from 'h3'
import { requireRegisteredCloudbaseUser } from './cloudbase-auth'

export function parseDiagnosticAdminUids(value: unknown): Set<string> {
  if (typeof value !== 'string')
    return new Set()
  return new Set(
    value
      .split(',')
      .map(uid => uid.trim())
      .filter(Boolean),
  )
}

export function isDiagnosticAdminUid(uid: string, configuredUids: unknown): boolean {
  return Boolean(uid) && parseDiagnosticAdminUids(configuredUids).has(uid)
}

export async function requireDiagnosticAdmin(event: H3Event) {
  const user = await requireRegisteredCloudbaseUser(event)
  const config = useRuntimeConfig()
  if (!isDiagnosticAdminUid(user.uid, config.diagnosticAdminUids)) {
    throw createError({
      statusCode: 403,
      statusMessage: '无权访问诊断日志',
    })
  }
  return user
}
