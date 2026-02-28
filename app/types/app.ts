/** 应用数据模型 - 对应 CloudBase NoSQL 集合 `apps` */
export interface AppRecord {
  /** 文档 ID（CloudBase 自动生成） */
  _id: string
  /** 创建者 ID（CloudBase openid） */
  _openid: string
  /** 应用所有者 User ID */
  ownerId: string
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
  /** 应用图标 URL 或 emoji */
  icon?: string
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
  icon?: string
  category?: string
  tags?: string[]
  isPublic: boolean
}
