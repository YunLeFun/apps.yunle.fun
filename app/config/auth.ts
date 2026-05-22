/**
 * 登录方式开关配置
 *
 * 控制登录页面各登录方式的启用/禁用
 * 可通过修改此文件快速开关特定登录方式
 */

import { Capacitor } from '@capacitor/core'

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
 * 是否运行在 iOS / Android 原生 WebView 中
 *
 * 原生平台需要规避 App Store 指南 4.8（Sign in with Apple 要求）：
 * 只要 App 提供任何第三方/社交登录，就必须同时提供 Apple 登录。
 *
 * 当前策略：原生平台只暴露「手机号 / 邮箱 / 密码 + 微信」，隐藏 GitHub。
 * 短信/邮箱属于「自有账号系统」（4.8 例外 #1），微信单独按区域服务争取通过。
 *
 * 详见 docs/roadmap.md「iOS 端隐藏 GitHub 登录入口」。
 */
const isNativePlatform = typeof window !== 'undefined' && Capacitor.isNativePlatform()

/**
 * 基础登录方式配置（修改此处启用/禁用）
 */
const baseAuthMethods: AuthMethodConfig = {
  phoneOtp: true,
  emailOtp: true,
  password: true,
  github: false,
  wechat: false,
  phoneSignup: true,
}

/**
 * 当前启用的登录方式（已应用平台规则）
 */
export const authMethods: AuthMethodConfig = {
  ...baseAuthMethods,
  // 原生平台强制关闭 GitHub OAuth，规避 App Store 4.8 拒审
  github: isNativePlatform ? false : baseAuthMethods.github,
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
