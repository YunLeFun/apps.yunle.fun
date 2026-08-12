import type { YlfAppInfo } from '@yunlefun/types'
import { withCanonicalAppDomain } from '~/utils/canonical-app-domain'
import { withCanonicalAppIcon } from '~/utils/canonical-app-icon'
import { yunHomeApp } from './builtin'
import { GENERATED_APPS } from './generated'

/**
 * 应用分类定义
 */
export interface AppCategory {
  id: string
  name: string
  icon: string
}

/**
 * 应用分类列表
 */
export const APP_CATEGORIES: AppCategory[] = [
  { id: 'all', name: '全部', icon: '📱' },
  { id: 'interesting', name: '整活', icon: '🤣' },
  { id: 'applets', name: '应用', icon: '📱' },
  { id: 'games', name: '游戏', icon: '🎮' },
  { id: 'tools', name: '工具', icon: '🔧' },
  { id: 'life', name: '生活', icon: '🏠' },
  { id: 'design', name: '设计', icon: '🎨' },
  { id: 'plugins', name: '插件', icon: '🔌' },
  { id: 'lab', name: '实验', icon: '🧪' },
  { id: 'open_source', name: '参与', icon: '👥' },
  { id: 'others', name: '其他', icon: '📂' },
]

/**
 * 今日推荐应用
 */
export const FEATURED_APP: YlfAppInfo = {
  ...yunHomeApp,
  subtitle: '编辑精选',
}

/**
 * 所有应用列表
 */
export const FIRST_PARTY_FALLBACK_APPS: YlfAppInfo[] = [
  yunHomeApp,
]

function mergeFallbackApps(seed: YlfAppInfo[], fallback: YlfAppInfo[]) {
  const map = new Map<string, YlfAppInfo>()
  for (const app of seed)
    map.set(app.slug, app)
  for (const app of fallback) {
    if (!map.has(app.slug))
      map.set(app.slug, app)
  }
  return [...map.values()]
}

export const ALL_APPS: YlfAppInfo[] = mergeFallbackApps(
  GENERATED_APPS.map(app => withCanonicalAppIcon(withCanonicalAppDomain(app))),
  FIRST_PARTY_FALLBACK_APPS.map(app => withCanonicalAppIcon(withCanonicalAppDomain(app))),
)

/**
 * 根据分类获取应用列表
 */
export function getAppsByCategory(categoryId: string): YlfAppInfo[] {
  if (categoryId === 'all') {
    return ALL_APPS
  }
  return ALL_APPS.filter(app => app.category === APP_CATEGORIES.find(c => c.id === categoryId)?.name)
}

/**
 * 根据 ID 或 slug 获取应用
 */
export function getAppById(id: string): YlfAppInfo | undefined {
  return ALL_APPS.find(app => app.id === id || app.slug === id)
}

export * from './builtin'
export * from './data'
