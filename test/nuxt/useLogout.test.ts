import { mockNuxtImport } from '@nuxt/test-utils/runtime'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const logoutCloudbase = vi.fn()

mockNuxtImport('useCloudbaseAuth', () => () => ({
  logout: logoutCloudbase,
}))

describe('useLogout', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('logs out CloudBase even when server session cleanup fails', async () => {
    vi.stubGlobal('$fetch', vi.fn().mockRejectedValue(new Error('session unavailable')))

    const { logout } = useLogout()
    await logout()

    expect(logoutCloudbase).toHaveBeenCalledOnce()
  })

  it('logs out CloudBase when the server reports an unsuccessful cleanup', async () => {
    vi.stubGlobal('$fetch', vi.fn().mockResolvedValue({
      success: false,
      message: 'Empty password',
    }))

    const { logout } = useLogout()
    await logout()

    expect(logoutCloudbase).toHaveBeenCalledOnce()
  })
})
