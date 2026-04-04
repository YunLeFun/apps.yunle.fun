/**
 * 共享校验工具
 */

// 中国大陆手机号正则（1 开头 + 第二位 3-9 + 9 位数字）
const PHONE_REGEX = /^1[3-9]\d{9}$/

// 邮箱地址正则
const EMAIL_REGEX = /^[^\s@]+@[^\s@][^\s.@]*\.[^\s@]+$/

/** 中国大陆手机号校验 (+86) */
export function isValidPhone(phone: string): boolean {
  return PHONE_REGEX.test(phone)
}

/** 邮箱地址校验 */
export function isValidEmail(email: string): boolean {
  return EMAIL_REGEX.test(email)
}
