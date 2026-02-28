/**
 * CloudBase Auth 类型定义和工具函数
 * 从 www.yunle.fun 提取，供两个项目共用
 */

/** CloudBase Auth HTTP API /user/me 返回的用户类型 */
export interface TcbRawUser {
  /** user id (sub) */
  sub?: string
  /** SDK getUser 返回的 id */
  id?: string
  name?: string | null
  picture?: string | null
  username?: string | null
  email?: string | null
  phone_number?: string | null
  /** SDK 返回的 phone */
  phone?: string | null
  /** "SET" | "NOT_SET" */
  password?: string | null
  gender?: string | null
  meta?: {
    description?: string
    [key: string]: unknown
  } | null
  providers?: Array<{
    id: string
    provider_user_id?: string
    name?: string
  }> | null
  created_at?: string
  password_updated_at?: string

  // === SDK getUser 兼容字段 ===
  aud?: string
  role?: string[]
  app_metadata?: {
    provider?: string | null
    providers?: string[]
  }
  user_metadata?: {
    name?: string | null
    picture?: string | null
    username?: string | null
    nickName?: string | null
    avatarUrl?: string | null
    hasPassword?: boolean | null
    gender?: string | null
    description?: string | null
    [key: string]: unknown
  }
  identities?: Array<{
    id: string
    name: string
    picture: string
    accessToken?: string
  }> | null
  updated_at?: string
  [key: string]: unknown
}

export interface UserIdentity {
  id: string
  name: string
  picture: string
  accessToken?: string
}

export type UserGender = 'MALE' | 'FEMALE' | ''

export interface CloudbaseUser {
  id: string
  login?: string | null
  email?: string | null
  phone?: string | null
  nickname?: string
  avatar?: string | null
  description?: string
  gender?: UserGender
  role: string
  hasPassword: boolean
  providers: string[]
  identities: UserIdentity[]
  createdAt: string
  updatedAt: string
}

export interface AuthState {
  user: CloudbaseUser | null
  loading: boolean
  error: string | null
}

/**
 * 将 CloudBase User 转为本地 CloudbaseUser 结构
 * 兼容 HTTP API 扁平格式和 SDK getUser 嵌套格式
 */
export function mapCloudbaseUser(cbUser: TcbRawUser): CloudbaseUser | null {
  if (!cbUser)
    return null

  // ID: 优先 sub (HTTP API), 其次 id (SDK)
  const id = cbUser.sub || cbUser.id || ''

  // 昵称: 优先扁平 name, 其次嵌套
  const nickname = cbUser.name
    || cbUser.user_metadata?.nickName
    || cbUser.user_metadata?.name
    || cbUser.username
    || cbUser.user_metadata?.username
    || undefined

  // 头像: 优先扁平 picture, 其次嵌套
  const avatar = cbUser.picture
    || cbUser.user_metadata?.avatarUrl
    || cbUser.user_metadata?.picture
    || null

  // 用户名
  const login = cbUser.username || cbUser.user_metadata?.username || null

  // 邮箱
  const email = cbUser.email || null

  // 手机号: 扁平格式是 phone_number (带 +86 前缀), SDK 是 phone
  const rawPhone = cbUser.phone_number || cbUser.phone || null
  const phone = rawPhone ? rawPhone.replace(/^\+86\s*/, '') : null

  // 描述: 扁平格式在 meta.description, SDK 在 user_metadata.description
  const description = cbUser.meta?.description
    || (cbUser.user_metadata?.description as string)
    || ''

  // 性别
  const rawGender = cbUser.gender || cbUser.user_metadata?.gender
  const gender = (['MALE', 'FEMALE'].includes(rawGender as string) ? rawGender : '') as UserGender

  // 密码状态: 扁平格式 password="SET", 或之前注入的 _passwordStatus
  const passwordStatus = cbUser.password
    || (cbUser as Record<string, unknown>)._passwordStatus as string | undefined
  const hasPassword = passwordStatus === 'SET'

  // Providers: 扁平格式是 [{id, name}], SDK 是 app_metadata.providers (string[])
  let providers: string[] = []
  if (Array.isArray(cbUser.providers) && cbUser.providers.length > 0) {
    // HTTP API 扁平格式: providers 是对象数组
    providers = cbUser.providers.map(p => typeof p === 'string' ? p : p.id)
  }
  else if (cbUser.app_metadata?.providers) {
    providers = cbUser.app_metadata.providers
  }

  // Identities
  const identities = (cbUser.identities || []).map(i => ({
    id: i.id,
    name: i.name,
    picture: i.picture,
  }))

  return {
    id,
    login,
    email,
    phone,
    nickname,
    avatar,
    description,
    gender,
    role: cbUser.role?.[0] || 'USER',
    hasPassword,
    providers,
    identities,
    createdAt: cbUser.created_at || '',
    updatedAt: cbUser.updated_at || '',
  }
}

/** 错误信息映射 */
const ERROR_MESSAGE_MAP: Record<string, string> = {
  'Failed to fetch': '网络连接失败，请检查网络后重试',
  'NetworkError': '网络异常，请检查网络连接',
  'Load failed': '网络请求失败，请稍后重试',
  'The Internet connection appears to be offline': '网络已断开，请检查网络连接',
  'Network request failed': '网络请求失败，请稍后重试',
}

export function getErrorMessage(err: unknown): string {
  const raw = err instanceof Error ? err.message : String(err)
  return ERROR_MESSAGE_MAP[raw] || raw
}
