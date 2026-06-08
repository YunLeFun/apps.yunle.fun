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

/**
 * 应用审核状态
 *
 * - `pending`：等待审核（新创建或重新提交后默认状态）
 * - `approved`：审核通过，配合 `isPublic: true` 才会在工坊/寻乐对所有人可见
 * - `rejected`：审核被拒，用户可在工坊看到 `rejectedReason` 后修改重新提交
 */
export type AppStatus = 'pending' | 'approved' | 'rejected'

/** 默认审核状态 */
export const DEFAULT_APP_STATUS: AppStatus = 'pending'

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
  /** 评分（展示用，0-5；当前为运营预设，后续可接真实数据） */
  rating?: number
  /** 下载量文案（展示用，如「10万+」） */
  downloads?: string
  /** 应用大小文案（展示用，如「2.5 MB」） */
  size?: string
  /** 年龄分级文案（展示用，如「4+」） */
  age?: string
  /** 用户是否愿意公开（默认 false；与 status=approved 同时满足才会真正对外可见） */
  isPublic: boolean
  /** 审核状态（必填，默认 pending） */
  status: AppStatus
  /** 拒绝原因（仅 status=rejected 时有值） */
  rejectedReason?: string
  /** 最近一次审核时间戳 */
  reviewedAt?: number
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
