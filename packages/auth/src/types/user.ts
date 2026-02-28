/**
 * 用户信息
 */
export interface YlfUserInfo {
  /** CloudBase 用户 ID */
  id?: string
  /** 用户名 (login name) */
  login?: string | null
  /** 邮箱 */
  email?: string | null
  /** 手机号 */
  phone?: string | null
  /** 头像 */
  avatar: string
  /** 昵称 */
  nickname: string
  /** 是否已设置密码 */
  hasPassword?: boolean
  /** 认证提供商列表 */
  providers?: string[]
  /** 微信资料（兼容旧版） */
  profile?: YlfUserProfile
}

/**
 * 用户资料
 */
export interface YlfUserProfile {
  openid: string
  nickname: string
  sex: 1 | 2 | 0
  province: string
  city: string
  country: string
  headimgurl: string
  privilege: string[]
  unionid: string
}
