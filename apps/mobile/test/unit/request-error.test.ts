import { describe, expect, it } from 'vitest'
import { getRequestErrorInfo } from '../../app/utils/requestError'

describe('request error info', () => {
  it('prefers the server message and creates copy-safe diagnostics', () => {
    const info = getRequestErrorInfo({
      statusCode: 403,
      message: '[POST] "/api/workshops": 403 Forbidden',
      data: {
        statusMessage: '请使用正式账号登录',
      },
      request: '/api/workshops',
    }, '创建失败')

    expect(info.message).toBe('请使用正式账号登录')
    expect(info.copyText).toBe([
      '错误：请使用正式账号登录',
      '状态：403',
      '请求：/api/workshops',
    ].join('\n'))
    expect(info.copyText).not.toContain('Authorization')
  })

  it('falls back without serializing unknown error data', () => {
    const info = getRequestErrorInfo({
      headers: { Authorization: 'Bearer secret' },
    }, '操作失败')

    expect(info).toEqual({
      message: '操作失败',
      copyText: '错误：操作失败',
    })
  })
})
