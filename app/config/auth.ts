/**
 * 登录方式开关配置
 *
 * 控制登录页面各登录方式的启用/禁用
 * 可通过修改此文件快速开关特定登录方式
 */

export interface AuthMethodConfig {
  /** 手机号 OTP 登录 */
  phoneOtp: boolean
  /** 邮箱 OTP 登录 */
  emailOtp: boolean
  /** 密码登录 */
  password: boolean
  /** GitHub OAuth 登录 */
  github: boolean
  /** 微信 OAuth 登录 */
  wechat: boolean
  /** 手机号注册 */
  phoneSignup: boolean
}

/**
 * 当前启用的登录方式
 */
export const authMethods: AuthMethodConfig = {
  phoneOtp: true,
  emailOtp: true,
  password: true,
  github: false,
  wechat: false,
  phoneSignup: true,
}

/**
 * 获取启用的登录 Tab 列表
 */
export function getEnabledLoginTabs() {
  const tabs: { key: string, label: string }[] = []
  if (authMethods.phoneOtp)
    tabs.push({ key: 'phone', label: '手机号' })
  if (authMethods.emailOtp)
    tabs.push({ key: 'email', label: '邮箱' })
  if (authMethods.password)
    tabs.push({ key: 'password', label: '密码' })
  return tabs
}

/**
 * 获取启用的第三方登录列表
 */
export function getEnabledOAuthProviders() {
  const providers: { key: string, label: string }[] = []
  if (authMethods.github)
    providers.push({ key: 'github', label: 'GitHub' })
  if (authMethods.wechat)
    providers.push({ key: 'wechat', label: '微信' })
  return providers
}

/**
 * 是否有启用的第三方登录
 */
export function hasEnabledOAuthProviders() {
  return authMethods.github || authMethods.wechat
}
