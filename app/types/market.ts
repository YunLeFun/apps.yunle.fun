import type { YlfAppInfo } from '~~/packages/types'

/** 应用市场来源 */
export interface AppMarketSource {
  /** 唯一标识 */
  id: string
  /** 市场名称 */
  name: string
  /** 市场图标（emoji 或 URL） */
  icon?: string
  /** 市场描述 */
  description?: string
  /** 数据源 URL（用于去重和刷新） */
  url?: string
  /** 应用列表 */
  apps: YlfAppInfo[]
  /** 添加时间戳 */
  addedAt: number
}

/**
 * 校验数据是否为合法的 AppMarketSource
 * 至少需要 name 字段存在且 apps 为数组
 */
export function validateMarketSource(data: unknown): data is AppMarketSource {
  if (!data || typeof data !== 'object')
    return false

  const obj = data as Record<string, unknown>

  if (typeof obj.name !== 'string' || !obj.name.trim())
    return false

  if (!Array.isArray(obj.apps))
    return false

  // 校验每个 app 至少有 name 和 url
  return obj.apps.every((app: unknown) => {
    if (!app || typeof app !== 'object')
      return false
    const a = app as Record<string, unknown>
    return typeof a.name === 'string' && typeof a.url === 'string'
  })
}
