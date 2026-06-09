import type { YlfAppInfo } from '@yunlefun/types'
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
  { id: 'tools', name: '工具', icon: '🔧' },
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
  id: 'valaxy',
  slug: 'valaxy',
  name: 'Valaxy',
  description: '新一代静态博客框架，快速、优雅、强大',
  emoji: '🌌',
  themeColor: '#0078e7',
  websiteUrl: 'https://valaxy.yyj.moe',
  category: '应用',
  rating: 4.9,
  downloads: '10万+',
  size: '2.5 MB',
  age: '4+',
  subtitle: '编辑精选',
  tagline: '新一代静态博客框架',
}

/**
 * 所有应用列表
 */
export const ALL_APPS: YlfAppInfo[] = GENERATED_APPS

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
