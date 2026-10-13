export type DiagnosticLogLevel = 'log' | 'info' | 'warn' | 'error' | 'debug'

export interface DiagnosticLogEntry {
  level: DiagnosticLogLevel
  message: string
  timestamp: number
}

interface DiagnosticLogStorage {
  getItem: (key: string) => string | null
  removeItem: (key: string) => void
  setItem: (key: string, value: string) => void
}

export const DIAGNOSTIC_LOG_STORAGE_KEY = 'ylf:diagnostic-logs:v1'
export const DIAGNOSTIC_LOG_RETENTION_MS = 7 * 24 * 60 * 60 * 1000
export const MAX_DIAGNOSTIC_LOGS = 500
export const MAX_DIAGNOSTIC_MESSAGE_LENGTH = 1500

const FUTURE_CLOCK_SKEW_MS = 5 * 60 * 1000
const LOG_LEVELS = new Set<DiagnosticLogLevel>(['log', 'info', 'warn', 'error', 'debug'])
const AUTHORIZATION_BEARER_REGEX = /(Authorization\s*[:=]\s*)Bearer\s+[\w.~+/=-]+/gi
const BEARER_TOKEN_REGEX = /Bearer\s+[\w.~+/=-]+/gi
const JWT_REGEX = /\beyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]{10,}\b/g
const HTTP_URL_REGEX = /https?:\/\/[^\s"'<>]+/gi
const EMAIL_REGEX = /\b[\w.%+-]+@[\w.-]+\.[A-Z]{2,}\b/gi
const PHONE_REGEX = /(?:\+?86[\s-]?)?1[3-9]\d{9}/g
const LONG_ID_REGEX = /\b\d{16,20}\b/g
const SENSITIVE_KEY_PATTERN = [
  'access[_-]?token',
  'refresh[_-]?token',
  'password',
  'passwd',
  'secret',
  'cookie',
  'session',
  'q-signature',
  'signature',
  'token',
].join('|')
const QUOTED_SENSITIVE_VALUE_REGEX = new RegExp(
  `(["']?(?:${SENSITIVE_KEY_PATTERN})["']?\\s*[:=]\\s*)(["'])(.*?)\\2`,
  'gi',
)
const BARE_SENSITIVE_VALUE_REGEX = new RegExp(
  `((?:${SENSITIVE_KEY_PATTERN})\\s*[:=]\\s*)([^\\s,;&}\\]"']+)`,
  'gi',
)

/**
 * 将 console 参数转为可诊断文本。原生 Error 的 message/stack 默认不可枚举，
 * 直接 JSON.stringify 会得到 `{}`；这里显式展开并容忍循环引用与 BigInt。
 */
export function serializeDiagnosticLogArgument(value: unknown): string {
  if (value === null)
    return 'null'
  if (value === undefined)
    return 'undefined'
  if (typeof value === 'string')
    return value

  const seen = new WeakSet<object>()
  try {
    const serialized = JSON.stringify(value, (_key, nestedValue: unknown) => {
      if (typeof nestedValue === 'bigint')
        return `${nestedValue}n`
      if (typeof nestedValue !== 'object' || nestedValue === null)
        return nestedValue
      if (seen.has(nestedValue))
        return '[Circular]'
      seen.add(nestedValue)
      if (nestedValue instanceof Error) {
        return {
          name: nestedValue.name,
          message: nestedValue.message,
          stack: nestedValue.stack || '',
          cause: nestedValue.cause,
        }
      }
      return nestedValue
    }, 2)
    return serialized === undefined ? String(value) : serialized
  }
  catch {
    return String(value)
  }
}

/**
 * 上传前默认脱敏。保留日志结构和 URL 主机名，但移除凭证、签名、
 * 查询参数、联系方式和长数字账号标识。
 */
export function redactDiagnosticText(value: string): string {
  return value
    .replace(AUTHORIZATION_BEARER_REGEX, '$1Bearer [redacted]')
    .replace(BEARER_TOKEN_REGEX, 'Bearer [redacted]')
    .replace(QUOTED_SENSITIVE_VALUE_REGEX, '$1$2[redacted]$2')
    .replace(BARE_SENSITIVE_VALUE_REGEX, '$1[redacted]')
    .replace(JWT_REGEX, '[redacted-token]')
    .replace(HTTP_URL_REGEX, redactUrl)
    .replace(EMAIL_REGEX, '[redacted-email]')
    .replace(LONG_ID_REGEX, '[redacted-id]')
    .replace(PHONE_REGEX, '[redacted-phone]')
    .slice(0, MAX_DIAGNOSTIC_MESSAGE_LENGTH)
}

export function normalizeDiagnosticLogEntry(value: unknown): DiagnosticLogEntry | null {
  if (!isRecord(value))
    return null

  const { level, message, timestamp } = value
  if (!isDiagnosticLogLevel(level) || typeof message !== 'string')
    return null
  if (typeof timestamp !== 'number' || !Number.isFinite(timestamp))
    return null

  const normalizedMessage = redactDiagnosticText(message)
  if (!normalizedMessage)
    return null

  return {
    level,
    message: normalizedMessage,
    timestamp: Math.trunc(timestamp),
  }
}

export function pruneDiagnosticLogs(
  entries: readonly unknown[],
  now = Date.now(),
): DiagnosticLogEntry[] {
  const earliest = now - DIAGNOSTIC_LOG_RETENTION_MS
  const latest = now + FUTURE_CLOCK_SKEW_MS
  return entries
    .map(normalizeDiagnosticLogEntry)
    .filter((entry): entry is DiagnosticLogEntry =>
      entry !== null
      && entry.timestamp >= earliest
      && entry.timestamp <= latest,
    )
    .sort((left, right) => left.timestamp - right.timestamp)
    .slice(-MAX_DIAGNOSTIC_LOGS)
}

export function selectDiagnosticLogs(
  entries: readonly unknown[],
  startTime: number,
  endTime: number,
): DiagnosticLogEntry[] {
  if (!Number.isFinite(startTime) || !Number.isFinite(endTime) || startTime > endTime)
    return []

  return entries
    .map(normalizeDiagnosticLogEntry)
    .filter((entry): entry is DiagnosticLogEntry =>
      entry !== null
      && entry.timestamp >= startTime
      && entry.timestamp <= endTime,
    )
    .sort((left, right) => left.timestamp - right.timestamp)
    .slice(-MAX_DIAGNOSTIC_LOGS)
}

export function estimateDiagnosticLogBytes(entries: readonly DiagnosticLogEntry[]): number {
  return new TextEncoder().encode(JSON.stringify(entries)).byteLength
}

export function loadDiagnosticLogs(
  storage: DiagnosticLogStorage,
  now = Date.now(),
): DiagnosticLogEntry[] {
  try {
    const raw = storage.getItem(DIAGNOSTIC_LOG_STORAGE_KEY)
    if (!raw)
      return []
    const parsed = JSON.parse(raw) as unknown
    return Array.isArray(parsed) ? pruneDiagnosticLogs(parsed, now) : []
  }
  catch {
    return []
  }
}

export function saveDiagnosticLogs(
  storage: DiagnosticLogStorage,
  entries: readonly unknown[],
  now = Date.now(),
): DiagnosticLogEntry[] {
  const normalized = pruneDiagnosticLogs(entries, now)
  try {
    storage.setItem(DIAGNOSTIC_LOG_STORAGE_KEY, JSON.stringify(normalized))
  }
  catch {
    // 存储空间不足或 WebView 禁用 localStorage 时保留当前内存缓冲。
    return normalized
  }
  return normalized
}

export function clearDiagnosticLogs(storage: DiagnosticLogStorage): boolean {
  try {
    storage.removeItem(DIAGNOSTIC_LOG_STORAGE_KEY)
    return true
  }
  catch {
    // localStorage 不可用时，本次会话的内存日志仍会被清空。
    return false
  }
}

function redactUrl(rawValue: string): string {
  const trailing = rawValue.match(/[),.;]+$/)?.[0] || ''
  const candidate = trailing ? rawValue.slice(0, -trailing.length) : rawValue
  try {
    const url = new URL(candidate)
    return `[redacted-url:${url.hostname}]${trailing}`
  }
  catch {
    return `[redacted-url]${trailing}`
  }
}

function isDiagnosticLogLevel(value: unknown): value is DiagnosticLogLevel {
  return typeof value === 'string' && LOG_LEVELS.has(value as DiagnosticLogLevel)
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
