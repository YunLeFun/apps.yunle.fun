/**
 * CloudBase 认证会话错误分类与序列化（纯函数，便于单元测试）
 *
 * 错误对象结构依据 @cloudbase/oauth 的 AuthError 类：
 * - category: SDK 推断的错误分类（INVALID_CREDENTIALS / SERVICE_ERROR / ...）
 * - status: OAuth2 / SDK ErrorType 错误码（invalid_grant / unreachable / server_error / ...）
 * - code / error / error_description / message: 各调用链路可能附带的错误描述
 */

/**
 * 刷新结果对应的错误性质：
 * - invalid：凭证确已失效/撤销，需要重新登录
 * - transient：临时失败（网络不可达、超时、服务端 5xx 等），应保留登录态稍后重试
 */
export type AuthErrorKind = 'invalid' | 'transient'

/**
 * 会话恢复窗口：refresh_token 最大有效期（与 user.ts cookie 的 31 天对齐）。
 * access_token 过期超过该窗口后，refresh_token 必然已失效，
 * 即使刷新因网络原因失败也应按凭证失效处理，避免悬空登录态无限滞留。
 */
export const SESSION_RECOVERY_WINDOW_MS = 31 * 24 * 60 * 60 * 1000

/** AuthError.category 中凭证确已失效的分类 */
const INVALID_CATEGORIES = new Set([
  'INVALID_CREDENTIALS',
  'USER_NOT_FOUND',
  'USER_STATUS_ABNORMAL',
])

/** AuthError.category 中明确属于临时故障的分类（网络/服务端） */
const TRANSIENT_CATEGORIES = new Set([
  'SERVICE_ERROR',
])

/** 错误码/文本中表示凭证确已失效的标记（SDK ErrorType + OAuth2 标准错误码） */
const INVALID_CODES = [
  'invalid_grant',
  'unauthenticated',
  'login_required',
  'invalid_token',
  'invalid_credentials',
  'access_denied',
  'user_blocked',
  'user_not_found',
]

/** 根据 CloudBase SDK 错误对象判断是凭证失效还是临时失败 */
export function classifyAuthError(err: unknown): AuthErrorKind {
  const e = err as Record<string, unknown> | null | undefined

  // 优先使用 SDK AuthError 自带的分类
  const category = typeof e?.category === 'string' ? e.category : ''
  if (INVALID_CATEGORIES.has(category))
    return 'invalid'
  if (TRANSIENT_CATEGORIES.has(category))
    return 'transient'

  const text = [e?.status, e?.error, e?.code, e?.error_description, e?.message]
    .filter(v => typeof v === 'string')
    .join(' ')
    .toLowerCase()
  if (INVALID_CODES.some(code => text.includes(code)))
    return 'invalid'

  // 其余（网络异常、5xx、未知错误）一律视为临时失败，避免网络抖动误登出；
  // 长期无法刷新的兜底由 SESSION_RECOVERY_WINDOW_MS 恢复窗口负责
  return 'transient'
}

/**
 * 提取错误对象的关键字段用于日志（Error 直接 JSON.stringify 会得到 {}）。
 * 线上收集到的原始错误码用于持续校准 INVALID_CODES 分类表。
 */
export function serializeAuthError(err: unknown): unknown {
  if (err instanceof Error || (typeof err === 'object' && err !== null)) {
    const e = err as Record<string, unknown>
    return {
      name: e.name,
      message: e.message,
      code: e.code,
      status: e.status,
      category: e.category,
      error: e.error,
      error_description: e.error_description,
      requestId: e.requestId,
    }
  }
  return err
}

/**
 * access_token 过期时间是否已超出会话恢复窗口（refresh_token 必然失效）
 * @param expiry 上次记录的 access_token 过期时间戳，0 表示无记录
 */
export function isBeyondSessionRecovery(expiry: number, now = Date.now()): boolean {
  if (!expiry)
    return false
  return now - expiry > SESSION_RECOVERY_WINDOW_MS
}
