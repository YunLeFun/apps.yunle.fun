import type { YlfAppInfo } from '@yunlefun/types'
import type { AppRecord } from '~/types/app'

/**
 * 把 CloudBase `apps` 集合文档（AppRecord）映射为前端展示用的 YlfAppInfo。
 *
 * 字段已与集合命名对齐（themeColor/websiteUrl/logo），这里只做默认值兜底：
 * - 图标优先级 `logo > emoji > 📱`
 * - themeColor 默认 #007AFF
 * - 业务主键用 slug；id 取文档 _id
 */
export function recordToAppInfo(record: AppRecord): YlfAppInfo {
  return {
    id: record._id,
    slug: record.slug,
    name: record.name,
    description: record.description,
    emoji: record.emoji || '📱',
    themeColor: record.themeColor || '#007AFF',
    logo: record.logo || undefined,
    websiteUrl: record.websiteUrl || '',
    category: record.category,
    rating: record.rating,
    downloads: record.downloads,
    size: record.size,
    age: record.age,
  }
}
