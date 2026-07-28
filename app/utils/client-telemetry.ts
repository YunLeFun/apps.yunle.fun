import { Capacitor } from '@capacitor/core'
import consola from 'consola'

interface RumClient {
  report: (payload: Record<string, unknown>) => void
  reportEvent: (payload: Record<string, string>) => void
}

type TelemetryValue = boolean | null | number | string | undefined

const MAX_VALUE_LENGTH = 300
const BEARER_TOKEN_REGEX = /Bearer\s+[\w.~+/=-]+/gi
const HTTP_URL_REGEX = /https?:\/\/[^\s"'<>]+/gi

function normalizeValue(value: TelemetryValue): boolean | null | number | string {
  if (value === undefined)
    return ''
  if (typeof value !== 'string')
    return value
  return value
    .replace(BEARER_TOKEN_REGEX, 'Bearer [redacted]')
    .replace(HTTP_URL_REGEX, '[redacted-url]')
    .slice(0, MAX_VALUE_LENGTH)
}

function currentRum(): RumClient | undefined {
  if (typeof window === 'undefined')
    return undefined
  return (window as typeof window & { $rum?: RumClient }).$rum
}

/**
 * 只返回排障所需的非敏感资源特征，不上传完整路径、查询参数或签名。
 */
export function describeRemoteResource(source?: string | null) {
  if (!source) {
    return {
      extension: '',
      host: '',
      scheme: '',
      signed: false,
    }
  }

  try {
    const url = new URL(source)
    const filename = url.pathname.split('/').pop() || ''
    const extension = filename.includes('.') ? filename.split('.').pop()?.toLowerCase() || '' : ''
    return {
      extension,
      host: url.hostname,
      scheme: url.protocol.replace(':', ''),
      signed: url.searchParams.has('sign') || url.searchParams.has('q-signature'),
    }
  }
  catch {
    return {
      extension: '',
      host: '',
      scheme: 'invalid',
      signed: false,
    }
  }
}

/**
 * 同时写入本地 WebView 控制台和腾讯 RUM。
 *
 * ext1/2/3 固定为 surface/stage/host，便于在 RUM 控制台直接聚合筛选；
 * msg 保存其余脱敏上下文。Aegis 的 uin 已由 rum.client.ts 单独绑定。
 */
export function reportClientEvent(
  name: string,
  context: Record<string, TelemetryValue> = {},
) {
  const normalizedContext = Object.fromEntries(
    Object.entries(context).map(([key, value]) => [key, normalizeValue(value)]),
  )
  const payload = {
    event: name,
    platform: Capacitor.getPlatform(),
    route: typeof window === 'undefined' ? '' : window.location.pathname,
    ...normalizedContext,
  }

  consola.warn('[ClientTelemetry]', payload)

  const rum = currentRum()
  if (!rum)
    return

  const ext1 = String(normalizedContext.surface || '').slice(0, 1024)
  const ext2 = String(normalizedContext.stage || '').slice(0, 1024)
  const ext3 = String(normalizedContext.host || '').slice(0, 1024)

  try {
    rum.reportEvent({ name, ext1, ext2, ext3 })
    rum.report({
      msg: JSON.stringify(payload),
      ext1,
      ext2,
      ext3,
    })
  }
  catch (error) {
    consola.warn('[ClientTelemetry] RUM report failed', error)
  }
}
