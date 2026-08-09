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
const SENSITIVE_KEY_REGEX = /(?:^|_)(?:authorization|code|code_challenge|code_verifier|cookie|nonce|password|pkce|refresh_token|secret|token)(?:$|_)/i

function normalizedTelemetryKey(key: string): string {
  return key
    .replace(/([a-z\d])([A-Z])/g, '$1_$2')
    .replace(/[^a-z\d]+/gi, '_')
    .toLowerCase()
}

function normalizeValue(key: string, value: TelemetryValue): boolean | null | number | string {
  if (SENSITIVE_KEY_REGEX.test(normalizedTelemetryKey(key)))
    return '[redacted]'
  if (value === undefined)
    return ''
  if (typeof value !== 'string')
    return value
  return value
    .replace(BEARER_TOKEN_REGEX, 'Bearer [redacted]')
    .replace(HTTP_URL_REGEX, '[redacted-url]')
    .slice(0, MAX_VALUE_LENGTH)
}

/**
 * 生成可跨客户端与服务端关联、但不可反推出 nonce 的短 flow ID。
 * 监控能力不可用时返回空串，绝不阻断授权主链路。
 */
export async function anonymizeTelemetryIdentifier(value: string): Promise<string> {
  try {
    const subtle = globalThis.crypto?.subtle
    if (!subtle || !value)
      return ''
    const digest = await subtle.digest('SHA-256', new TextEncoder().encode(value))
    return Array.from(new Uint8Array(digest).slice(0, 8))
      .map(byte => byte.toString(16).padStart(2, '0'))
      .join('')
  }
  catch {
    return ''
  }
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
    Object.entries(context).map(([key, value]) => [key, normalizeValue(key, value)]),
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
