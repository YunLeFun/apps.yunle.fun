import { describe, expect, it } from 'vitest'
import {
  classifyAuthError,
  isBeyondSessionRecovery,
  serializeAuthError,
  SESSION_RECOVERY_WINDOW_MS,
} from '../../app/utils/auth-session'

describe('classifyAuthError 错误分类', () => {
  describe('凭证失效（invalid）', () => {
    it('识别 SDK AuthError.category 的失效分类', () => {
      expect(classifyAuthError({ category: 'INVALID_CREDENTIALS', message: '凭据无效' })).toBe('invalid')
      expect(classifyAuthError({ category: 'USER_NOT_FOUND', message: '用户不存在' })).toBe('invalid')
      expect(classifyAuthError({ category: 'USER_STATUS_ABNORMAL', message: '账号被封禁' })).toBe('invalid')
    })

    it('识别 OAuth2/ErrorType 失效错误码（status/error/code 任一字段）', () => {
      expect(classifyAuthError({ status: 'invalid_grant' })).toBe('invalid')
      expect(classifyAuthError({ error: 'invalid_grant', error_description: 'refresh token revoked' })).toBe('invalid')
      expect(classifyAuthError({ code: 'unauthenticated' })).toBe('invalid')
      expect(classifyAuthError({ status: 'login_required' })).toBe('invalid')
      expect(classifyAuthError({ status: 'user_blocked' })).toBe('invalid')
      expect(classifyAuthError({ message: 'invalid_token: signature mismatch' })).toBe('invalid')
    })

    it('识别 Error 实例消息中的失效错误码', () => {
      expect(classifyAuthError(new Error('request failed: invalid_grant'))).toBe('invalid')
    })
  })

  describe('临时失败（transient）', () => {
    it('网络异常不判为失效', () => {
      expect(classifyAuthError(new TypeError('Failed to fetch'))).toBe('transient')
      expect(classifyAuthError(new Error('Network request timed out'))).toBe('transient')
      expect(classifyAuthError({ status: 'unreachable', message: 'network unreachable' })).toBe('transient')
    })

    it('服务端故障不判为失效', () => {
      expect(classifyAuthError({ category: 'SERVICE_ERROR', message: 'internal error' })).toBe('transient')
      expect(classifyAuthError({ status: 'server_error' })).toBe('transient')
      expect(classifyAuthError({ status: 'temporarily_unavailable' })).toBe('transient')
    })

    it('未知错误默认 transient（保守，避免误登出）', () => {
      expect(classifyAuthError(undefined)).toBe('transient')
      expect(classifyAuthError(null)).toBe('transient')
      expect(classifyAuthError({})).toBe('transient')
      expect(classifyAuthError('weird string error')).toBe('transient')
      expect(classifyAuthError({ category: 'UNKNOWN', message: '???' })).toBe('transient')
    })
  })

  it('category 优先于文本匹配：SERVICE_ERROR 即使消息含敏感词也不误判', () => {
    expect(classifyAuthError({ category: 'SERVICE_ERROR', message: 'gateway error while validating invalid_token' })).toBe('transient')
  })
})

describe('serializeAuthError 错误序列化', () => {
  it('提取 Error 实例的扩展字段（直接 stringify 会丢失）', () => {
    const err = Object.assign(new Error('boom'), {
      code: 'invalid_grant',
      status: 'invalid_grant',
      category: 'INVALID_CREDENTIALS',
      requestId: 'req-1',
    })
    expect(serializeAuthError(err)).toMatchObject({
      message: 'boom',
      code: 'invalid_grant',
      status: 'invalid_grant',
      category: 'INVALID_CREDENTIALS',
      requestId: 'req-1',
    })
    // 验证 JSON.stringify 后字段不丢
    expect(JSON.parse(JSON.stringify(serializeAuthError(err)))).toMatchObject({ code: 'invalid_grant' })
  })

  it('非对象错误原样返回', () => {
    expect(serializeAuthError('plain')).toBe('plain')
    expect(serializeAuthError(undefined)).toBeUndefined()
  })
})

describe('isBeyondSessionRecovery 会话恢复窗口', () => {
  const now = 1_750_000_000_000

  it('无过期记录（0）不升级', () => {
    expect(isBeyondSessionRecovery(0, now)).toBe(false)
  })

  it('过期未超窗口内不升级', () => {
    expect(isBeyondSessionRecovery(now - 60 * 60 * 1000, now)).toBe(false)
    expect(isBeyondSessionRecovery(now - SESSION_RECOVERY_WINDOW_MS, now)).toBe(false)
  })

  it('过期超出窗口升级为失效', () => {
    expect(isBeyondSessionRecovery(now - SESSION_RECOVERY_WINDOW_MS - 1, now)).toBe(true)
  })

  it('未过期不升级', () => {
    expect(isBeyondSessionRecovery(now + 60 * 60 * 1000, now)).toBe(false)
  })
})
