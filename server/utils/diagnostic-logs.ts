import type { DiagnosticLogEntry } from '~/utils/diagnostic-logs'
import { createError } from 'h3'
import {
  estimateDiagnosticLogBytes,
  MAX_DIAGNOSTIC_LOGS,
  normalizeDiagnosticLogEntry,
  redactDiagnosticText,
} from '~/utils/diagnostic-logs'

export interface DiagnosticClientContext {
  appVersion: string
  buildNumber: string
  platform: string
  route: string
  timezone: string
  userAgent: string
}

export interface ValidDiagnosticLogUpload {
  client: DiagnosticClientContext
  endTime: number
  issueDescription: string
  logs: DiagnosticLogEntry[]
  sizeBytes: number
  startTime: number
}

export interface DiagnosticLogAdminQuery {
  limit: number
  supportCode: string
  uid: string
}

export interface DiagnosticLogUploadSummary {
  _id: string
  client: DiagnosticClientContext
  createdAt: number
  endTime: number
  expiresAt: number
  issueDescription: string
  logCount: number
  ownerUid: string
  schemaVersion: number
  sizeBytes: number
  startTime: number
  status: string
  supportCode: string
  updatedAt: number
}

export interface DiagnosticLogUploadDetail extends DiagnosticLogUploadSummary {
  logs: DiagnosticLogEntry[]
}

export const DIAGNOSTIC_UPLOAD_RETENTION_MS = 7 * 24 * 60 * 60 * 1000
// 客户端的 datetime-local 结束值按所选秒末尾计算，因此包含 999ms。
export const MAX_DIAGNOSTIC_UPLOAD_RANGE_MS = 24 * 60 * 60 * 1000 + 999
export const MAX_DIAGNOSTIC_UPLOAD_BYTES = 256 * 1024
export const MAX_DIAGNOSTIC_ADMIN_RESULTS = 50

const MAX_RAW_MESSAGE_LENGTH = 4000
const MAX_ISSUE_DESCRIPTION_LENGTH = 500
const MAX_CLOCK_SKEW_MS = 5 * 60 * 1000
const MAX_UID_LENGTH = 128
const SUPPORT_CODE_REGEX = /^[A-Z0-9]{12}$/
const CLIENT_FIELD_LIMITS: Record<keyof DiagnosticClientContext, number> = {
  appVersion: 50,
  buildNumber: 50,
  platform: 20,
  route: 200,
  timezone: 100,
  userAgent: 500,
}

export function validateDiagnosticLogUpload(
  body: unknown,
  now = Date.now(),
): ValidDiagnosticLogUpload {
  if (!isRecord(body))
    throw createError({ statusCode: 400, message: '请求数据格式错误' })

  const startTime = finiteTimestamp(body.startTime)
  const endTime = finiteTimestamp(body.endTime)
  if (startTime === null || endTime === null || startTime > endTime)
    throw createError({ statusCode: 400, message: '日志时间范围无效' })
  if (endTime - startTime > MAX_DIAGNOSTIC_UPLOAD_RANGE_MS)
    throw createError({ statusCode: 400, message: '单次最多上传 24 小时内的日志' })
  if (startTime < now - DIAGNOSTIC_UPLOAD_RETENTION_MS || endTime > now + MAX_CLOCK_SKEW_MS)
    throw createError({ statusCode: 400, message: '只能上传最近 7 天内的日志' })

  if (!Array.isArray(body.logs) || body.logs.length === 0)
    throw createError({ statusCode: 400, message: '所选时间内没有可上传的日志' })
  if (body.logs.length > MAX_DIAGNOSTIC_LOGS)
    throw createError({ statusCode: 413, message: `单次最多上传 ${MAX_DIAGNOSTIC_LOGS} 条日志` })

  const logs = body.logs.map((value) => {
    if (!isRecord(value) || typeof value.message !== 'string')
      throw createError({ statusCode: 400, message: '日志条目格式错误' })
    if (value.message.length > MAX_RAW_MESSAGE_LENGTH)
      throw createError({ statusCode: 413, message: '单条日志内容过长' })

    const entry = normalizeDiagnosticLogEntry(value)
    if (!entry)
      throw createError({ statusCode: 400, message: '日志条目格式错误' })
    if (entry.timestamp < startTime || entry.timestamp > endTime)
      throw createError({ statusCode: 400, message: '日志条目超出所选时间范围' })
    return entry
  })

  const issueDescription = optionalString(body.issueDescription)
  if (issueDescription.length > MAX_ISSUE_DESCRIPTION_LENGTH)
    throw createError({ statusCode: 400, message: '问题描述不能超过 500 个字符' })

  const client = normalizeClientContext(body.client)
  const sizeBytes = estimateDiagnosticLogBytes(logs)
    + new TextEncoder().encode(JSON.stringify(client)).byteLength
    + new TextEncoder().encode(issueDescription).byteLength
  if (sizeBytes > MAX_DIAGNOSTIC_UPLOAD_BYTES)
    throw createError({ statusCode: 413, message: '诊断日志超过 256 KB，请缩短时间范围' })

  return {
    client,
    endTime,
    issueDescription: redactDiagnosticText(issueDescription).slice(0, MAX_ISSUE_DESCRIPTION_LENGTH),
    logs,
    sizeBytes,
    startTime,
  }
}

export function validateDiagnosticLogAdminQuery(value: unknown): DiagnosticLogAdminQuery {
  if (!isRecord(value))
    throw createError({ statusCode: 400, message: '查询参数格式错误' })

  const uid = queryString(value.uid)
  const supportCode = queryString(value.supportCode).toUpperCase()
  if (!uid && !supportCode)
    throw createError({ statusCode: 400, message: '请提供 uid 或 supportCode' })
  if (uid.length > MAX_UID_LENGTH || containsControlCharacter(uid))
    throw createError({ statusCode: 400, message: 'uid 格式错误' })
  if (supportCode && !SUPPORT_CODE_REGEX.test(supportCode))
    throw createError({ statusCode: 400, message: 'supportCode 格式错误' })

  const limit = optionalPositiveInteger(value.limit, 20)
  if (limit > MAX_DIAGNOSTIC_ADMIN_RESULTS)
    throw createError({ statusCode: 400, message: `单次最多查询 ${MAX_DIAGNOSTIC_ADMIN_RESULTS} 条记录` })

  return { uid, supportCode, limit }
}

export function normalizeDiagnosticLogUploadSummary(
  value: unknown,
): DiagnosticLogUploadSummary | null {
  if (!isRecord(value))
    return null

  const _id = requiredStoredString(value._id, 128)
  const supportCode = requiredStoredString(value.supportCode, 64)
  const ownerUid = requiredStoredString(value.ownerUid, MAX_UID_LENGTH)
  const startTime = nonNegativeNumber(value.startTime)
  const endTime = nonNegativeNumber(value.endTime)
  const createdAt = nonNegativeNumber(value.createdAt)
  const expiresAt = nonNegativeNumber(value.expiresAt)
  if (!_id || !supportCode || !ownerUid
    || startTime === null || endTime === null
    || createdAt === null || expiresAt === null) {
    return null
  }

  return {
    _id,
    schemaVersion: nonNegativeNumber(value.schemaVersion) ?? 1,
    supportCode,
    ownerUid,
    issueDescription: redactDiagnosticText(queryString(value.issueDescription))
      .slice(0, MAX_ISSUE_DESCRIPTION_LENGTH),
    startTime,
    endTime,
    logCount: nonNegativeNumber(value.logCount) ?? 0,
    sizeBytes: nonNegativeNumber(value.sizeBytes) ?? 0,
    client: normalizeClientContext(value.client),
    status: requiredStoredString(value.status, 50) || 'new',
    createdAt,
    updatedAt: nonNegativeNumber(value.updatedAt) ?? createdAt,
    expiresAt,
  }
}

export function normalizeDiagnosticLogUploadDetail(
  value: unknown,
): DiagnosticLogUploadDetail | null {
  const summary = normalizeDiagnosticLogUploadSummary(value)
  if (!summary || !isRecord(value) || !Array.isArray(value.logs))
    return null

  const logs = value.logs
    .map(normalizeDiagnosticLogEntry)
    .filter((entry): entry is DiagnosticLogEntry => entry !== null)
  return {
    ...summary,
    logs,
    logCount: logs.length,
  }
}

function normalizeClientContext(value: unknown): DiagnosticClientContext {
  const input = isRecord(value) ? value : {}
  return {
    appVersion: clientField(input, 'appVersion'),
    buildNumber: clientField(input, 'buildNumber'),
    platform: clientField(input, 'platform'),
    route: clientField(input, 'route'),
    timezone: clientField(input, 'timezone'),
    userAgent: clientField(input, 'userAgent'),
  }
}

function clientField(
  value: Record<string, unknown>,
  key: keyof DiagnosticClientContext,
): string {
  const field = value[key]
  if (typeof field !== 'string')
    return ''
  return redactDiagnosticText(field).slice(0, CLIENT_FIELD_LIMITS[key])
}

function finiteTimestamp(value: unknown): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value))
    return null
  return Math.trunc(value)
}

function optionalString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : ''
}

function queryString(value: unknown): string {
  if (Array.isArray(value))
    return queryString(value[0])
  return typeof value === 'string' ? value.trim() : ''
}

function optionalPositiveInteger(value: unknown, fallback: number): number {
  const raw = queryString(value)
  if (!raw)
    return fallback
  if (!/^\d+$/.test(raw))
    throw createError({ statusCode: 400, message: 'limit 格式错误' })
  const parsed = Number(raw)
  if (!Number.isSafeInteger(parsed) || parsed < 1)
    throw createError({ statusCode: 400, message: 'limit 格式错误' })
  return parsed
}

function requiredStoredString(value: unknown, maxLength: number): string {
  if (typeof value !== 'string')
    return ''
  const normalized = value.trim()
  return normalized.length <= maxLength ? normalized : ''
}

function nonNegativeNumber(value: unknown): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0)
    return null
  return Math.trunc(value)
}

function containsControlCharacter(value: string): boolean {
  for (const character of value) {
    const code = character.charCodeAt(0)
    if (code <= 31 || code === 127)
      return true
  }
  return false
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
