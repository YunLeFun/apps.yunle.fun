import type { YlfAppInfo } from '@yunlefun/types'

const CANONICAL_WEBSITE_URLS: Readonly<Record<string, string>> = Object.freeze({
  'web-resume': 'https://resume.yunle.fun',
  'ai-sfc': 'https://ai-sfc.yunle.fun',
  'give-me-money': 'https://gmm.yunle.fun/',
})

/** 在目录数据源完成迁移期间，确保所有打开入口都使用应用的唯一主域。 */
export function withCanonicalAppDomain<T extends YlfAppInfo>(app: T): T {
  const canonicalUrl = CANONICAL_WEBSITE_URLS[app.slug || app.id]
  return canonicalUrl && app.websiteUrl !== canonicalUrl
    ? { ...app, websiteUrl: canonicalUrl }
    : app
}
