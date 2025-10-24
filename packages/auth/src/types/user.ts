/**
 * 用户信息
 */
export interface YlfUserInfo {
  avatar: string
  nickname: string
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
