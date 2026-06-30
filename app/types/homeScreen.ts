/**
 * Home Screen 相关类型定义
 * 对应 CloudBase NoSQL 集合 `user_desktops`
 */

/** 已安装的应用（Home Screen / Dock 中的应用引用） */
export interface InstalledApp {
  /** 应用 ID（统一使用 slug 标识） */
  appId: string
}

/** 最近使用的应用 */
export interface RecentApp {
  /** 应用 ID（统一使用 slug 标识） */
  appId: string
  /** 最近使用时间戳（ms） */
  usedAt: number
}

/** Home Screen 配置（前端 Store 使用） */
export interface HomeScreenConfig {
  /** 主屏已安装应用（有序） */
  installedApps: InstalledApp[]
  /** Dock 常用应用（最多 4 个） */
  dockApps: InstalledApp[]
  /** 最近使用的应用（最多 100 个） */
  recentApps: RecentApp[]
  /** 最后同步时间 */
  updatedAt: number
}

/** CloudBase user_home_screens 集合文档 */
export interface UserHomeScreenRecord {
  _id: string
  _openid: string
  installedApps: InstalledApp[]
  dockApps: InstalledApp[]
  recentApps: RecentApp[]
  createdAt: number
  updatedAt: number
}

/** CloudBase featured_apps 集合文档 */
export interface FeaturedAppRecord {
  _id: string
  _openid: string
  /** 应用 ID（统一使用 slug / code 标识） */
  appId: string
  type: 'daily' | 'editor'
  title?: string
  subtitle?: string
  tagline?: string
  coverColor?: string
  sortOrder: number
  startDate: number
  endDate: number
  isActive: boolean
  createdAt: number
  updatedAt: number
}

/** CloudBase weekly_charts 集合文档 */
export interface WeeklyChartRecord {
  _id: string
  _openid: string
  /** 应用 ID（统一使用 slug 标识） */
  appId: string
  weekStart: number
  rank: number
  score?: number
  createdAt: number
  updatedAt: number
}

/** Dock 最大应用数量 */
export const DOCK_MAX_APPS = 4

/** 最近使用最大数量 */
export const RECENT_MAX_APPS = 100

/** 最近使用默认展示数量 */
export const RECENT_DEFAULT_DISPLAY = 4
