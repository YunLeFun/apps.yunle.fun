export interface RequestErrorInfo {
  message: string
  copyText: string
}

export function getRequestErrorInfo(error: unknown, fallback: string): RequestErrorInfo {
  const record = isRecord(error) ? error : null
  const data = record && isRecord(record.data) ? record.data : null
  const response = record && isRecord(record.response) ? record.response : null
  const message = firstString(
    data?.statusMessage,
    data?.message,
    record?.statusMessage,
    record?.message,
    error instanceof Error ? error.message : null,
  ) || fallback
  const status = firstNumber(
    data?.statusCode,
    data?.status,
    record?.statusCode,
    record?.status,
    response?.status,
  )
  const requestPath = safeRequestPath(record?.request)
    || safeRequestPath(response?.url)

  const lines = [`错误：${message}`]
  if (status)
    lines.push(`状态：${status}`)
  if (requestPath)
    lines.push(`请求：${requestPath}`)

  return {
    message,
    copyText: lines.join('\n'),
  }
}

function safeRequestPath(value: unknown): string {
  const raw = typeof value === 'string'
    ? value
    : isRecord(value) && typeof value.url === 'string'
      ? value.url
      : ''
  if (!raw)
    return ''
  try {
    return new URL(raw, 'https://local.invalid').pathname
  }
  catch {
    return raw.startsWith('/') ? (raw.split('?')[0] || '') : ''
  }
}

function firstString(...values: unknown[]): string {
  for (const value of values) {
    if (typeof value === 'string' && value.trim())
      return value.trim()
  }
  return ''
}

function firstNumber(...values: unknown[]): number | undefined {
  return values.find(value => typeof value === 'number') as number | undefined
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
