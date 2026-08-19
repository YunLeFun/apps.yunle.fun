import type { YlfAppInfo } from '@yunlefun/types'
import type { AppAccessMode, AppRecord, AppReleaseStage } from '~/types/app'
import { withCanonicalAppDomain } from '~/utils/canonical-app-domain'
import { withCanonicalAppIcon } from '~/utils/canonical-app-icon'

export type CatalogAppInfo = YlfAppInfo & {
  accessMode?: AppAccessMode
  releaseStage?: AppReleaseStage
  isOfficial?: boolean
  privacyPolicyUrl?: string
  supportUrl?: string
}

/**
 * 把 CloudBase `apps` 集合文档（AppRecord）映射为前端展示用的 YlfAppInfo。
 *
 * 字段已与集合命名对齐（themeColor/websiteUrl/logo），这里只做默认值兜底：
 * - 图标优先级 `logo > emoji > 📱`
 * - themeColor 默认 #007AFF
 * - 业务主键用 slug；id 取文档 _id
 */
export function recordToAppInfo(record: AppRecord): CatalogAppInfo {
  return withCanonicalAppIcon(withCanonicalAppDomain({
    id: record._id,
    slug: record.slug,
    name: record.name,
    description: record.description,
    emoji: record.emoji || '📱',
    themeColor: record.themeColor || '#007AFF',
    logo: record.logo || undefined,
    iconAssets: record.iconAssets,
    websiteUrl: record.websiteUrl || '',
    privacyPolicyUrl: record.privacyPolicyUrl || undefined,
    supportUrl: record.supportUrl || undefined,
    trustedHosts: record.trustedHosts,
    category: record.category,
    tags: record.tags,
    rating: record.rating,
    ratingCount: record.ratingCount,
    age: record.age,
    screenshots: record.screenshots,
    developer: record.ownerLogin || undefined,
    developerName: record.developerName || undefined,
    coinCost: record.coinCost,
    requiresMembership: record.requiresMembership,
    accessMode: record.accessMode || 'public',
    releaseStage: record.releaseStage || 'stable',
    isOfficial: record.isOfficial === true,
  }))
}
