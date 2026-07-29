import { afterEach, describe, expect, it, vi } from 'vitest'
import { useToast } from '../../app/composables/useToast'

describe('useToast', () => {
  afterEach(() => {
    useToast().close()
    vi.useRealTimers()
  })

  it('keeps copyable error details available long enough for an action', () => {
    vi.useFakeTimers()
    const toast = useToast()

    toast.showError('请使用正式账号登录', '错误：请使用正式账号登录\n状态：403\n请求：/api/workshops')

    expect(toast.opened.value).toBe(true)
    expect(toast.type.value).toBe('error')
    expect(toast.copyText.value).toContain('状态：403')

    vi.advanceTimersByTime(3000)
    expect(toast.opened.value).toBe(true)

    vi.advanceTimersByTime(3000)
    expect(toast.opened.value).toBe(false)
  })
})
