import { setResponseHeader } from 'h3'
import { resolvePublicFeatures } from '../utils/feature-flags'

export default defineEventHandler((event) => {
  // 公开、与身份无关；短缓存让改动在几分钟内生效。
  setResponseHeader(event, 'Cache-Control', 'public, max-age=300')
  return resolvePublicFeatures(useRuntimeConfig(event) as Record<string, unknown>)
})
