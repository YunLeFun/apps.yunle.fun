import { isAllowedOrigin, readOriginRules } from './origin-rules'

/**
 * /api 跨域白名单
 *
 * Capacitor 原生壳内 WebView 的页面 origin 不是部署域名：
 * - iOS: capacitor://localhost（旧版 ionic scheme: ionic://localhost）
 * - Android: https://localhost
 *
 * App 内带 Authorization 头的请求必触发 preflight，需要在服务端放行；
 * localhost 放行用于本地 Web 开发时把 NUXT_PUBLIC_API_BASE_URL 指向线上调试。
 * 鉴权走 Bearer token（不下发 Allow-Credentials），cookie 不会随跨域请求发送。
 */
const NATIVE_APP_ORIGINS = new Set([
  'capacitor://localhost',
  'ionic://localhost',
  'https://localhost',
])

const LOCAL_DEV_ORIGIN_RE = /^https?:\/\/(?:localhost|127\.0\.0\.1)(?::\d+)?$/

interface ResolveCorsOriginOptions {
  jsapiAllowedOrigins?: string
}

/** 返回应写入 Access-Control-Allow-Origin 的值；不放行则返回 null */
export function resolveCorsOrigin(origin: string | undefined, options: ResolveCorsOriginOptions = {}): string | null {
  if (!origin)
    return null
  if (NATIVE_APP_ORIGINS.has(origin) || LOCAL_DEV_ORIGIN_RE.test(origin))
    return origin
  if (options.jsapiAllowedOrigins && isAllowedOrigin(origin, readOriginRules(options.jsapiAllowedOrigins)))
    return origin
  return null
}
