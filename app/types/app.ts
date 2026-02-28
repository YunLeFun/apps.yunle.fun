/** 默认 emoji */
export const DEFAULT_EMOJI = '📱'

/** 默认主题色 */
export const DEFAULT_THEME_COLOR = '#007AFF'

/** 预设主题色列表 */
export const THEME_COLORS = [
  '#007AFF', // iOS 蓝
  '#34C759', // iOS 绿
  '#FF9500', // iOS 橙
  '#FF3B30', // iOS 红
  '#AF52DE', // iOS 紫
  '#FF2D55', // iOS 粉
  '#5856D6', // iOS 靛蓝
  '#00C7BE', // iOS 青
  '#FFD60A', // iOS 黄
  '#8E8E93', // iOS 灰
] as const

/** 预设分类列表 */
export const APP_CATEGORIES = [
  { label: '工具', icon: '🔧' },
  { label: '效率', icon: '⚡' },
  { label: '社交', icon: '💬' },
  { label: '娱乐', icon: '🎮' },
  { label: '教育', icon: '📚' },
  { label: '生活', icon: '🏠' },
  { label: '开发', icon: '💻' },
  { label: '设计', icon: '🎨' },
  { label: '整活', icon: '🤡' },
  { label: '其他', icon: '📦' },
] as const

/** 应用数据模型 - 对应 CloudBase NoSQL 集合 `apps` */
export interface AppRecord {
  /** 文档 ID（CloudBase 自动生成） */
  _id: string
  /** 创建者用户 ID（CloudBase 服务端自动注入，用于安全规则校验） */
  _openid: string
  /** 应用所有者用户名 */
  ownerLogin: string
  /** 应用名称 */
  name: string
  /** 唯一标识符（URL slug） */
  slug: string
  /** 应用描述 */
  description?: string
  /** 绑定的 GitHub 仓库（可选，格式：owner/repo） */
  githubRepo?: string
  /** 应用网页链接 */
  websiteUrl?: string
  /** 备用链接 */
  backupUrl?: string
  /** 自定义 Logo 图片 URL（优先于 emoji 展示） */
  logo?: string
  /** 应用 emoji 图标（无 logo 时展示，默认 📱） */
  emoji?: string
  /** 主题色（十六进制色值，默认 #007AFF） */
  themeColor?: string
  /** 分类 */
  category?: string
  /** 标签 */
  tags?: string[]
  /** 是否公开 */
  isPublic: boolean
  /** 创建时间 */
  createdAt: number
  /** 更新时间 */
  updatedAt: number
}

/** 创建/编辑应用时的表单数据 */
export interface CreateAppForm {
  name: string
  slug: string
  description?: string
  githubRepo?: string
  websiteUrl?: string
  backupUrl?: string
  logo?: string
  emoji?: string
  themeColor?: string
  category?: string
  tags?: string[]
  isPublic: boolean
}
