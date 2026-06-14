import { resolveCorsOrigin } from '../utils/cors'

/**
 * /api 跨域支持（Capacitor 原生壳 + 本地调试指向线上）
 *
 * 仅当请求携带白名单内的 Origin 时追加 CORS 头，Web 同源访问不受影响。
 */
export default defineEventHandler((event) => {
  if (!event.path.startsWith('/api/'))
    return

  const config = useRuntimeConfig()
  const jsapiAllowedOrigins = event.path.startsWith('/api/jsapi/auth/')
    ? String(config.jsapiAuthAllowedOrigins || '')
    : undefined
  const allowOrigin = resolveCorsOrigin(getRequestHeader(event, 'origin'), { jsapiAllowedOrigins })
  if (!allowOrigin)
    return

  setResponseHeader(event, 'Access-Control-Allow-Origin', allowOrigin)
  appendResponseHeader(event, 'Vary', 'Origin')

  // 带 Authorization 头的跨 origin 请求一定先发 OPTIONS preflight
  if (event.method === 'OPTIONS') {
    setResponseHeaders(event, {
      'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization,Content-Type',
      'Access-Control-Max-Age': '86400',
    })
    return sendNoContent(event)
  }
})
