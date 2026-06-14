import { beforeEach, describe, expect, it, vi } from 'vitest'
import { openInAppBrowser } from '../../app/composables/useBrowser'

// --- Capacitor mock：固定 iOS 原生环境 ---
const { mockInAppOpen, mockBrowserOpen } = vi.hoisted(() => ({
  mockInAppOpen: vi.fn(async () => {}),
  mockBrowserOpen: vi.fn(async () => {}),
}))

vi.mock('@capacitor/core', () => ({
  Capacitor: {
    isNativePlatform: () => true,
    getPlatform: () => 'ios',
  },
  registerPlugin: () => ({
    open: mockInAppOpen,
    close: vi.fn(),
    updateAppInfo: vi.fn(),
    addListener: vi.fn(),
    removeAllListeners: vi.fn(),
  }),
}))

vi.mock('@capacitor/browser', () => ({
  Browser: {
    open: mockBrowserOpen,
    close: vi.fn(),
    addListener: vi.fn(),
    removeAllListeners: vi.fn(),
  },
}))

let mockSettings: { inAppBrowserMode: string, externalLinkMode: string }
let mockUserStore: { isLoggedIn: boolean, accessToken: string }
const mockEnsureValidToken = vi.fn(async () => true)
const mockGetSession = vi.fn(async () => ({
  data: {
    session: {
      access_token: 'session-access-token',
      refresh_token: 'refresh-token',
    },
  },
}))
vi.stubGlobal('useSettingsStore', () => mockSettings)
vi.stubGlobal('useUserStore', () => mockUserStore)
vi.stubGlobal('useCloudbaseAuth', () => ({ ensureValidToken: mockEnsureValidToken }))
vi.stubGlobal('useCloudbase', () => ({ auth: { getSession: mockGetSession } }))
vi.stubGlobal('useRuntimeConfig', () => ({ public: { apiBaseUrl: 'https://api.example.com' } }))

describe('openInAppBrowser 形态优先级', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockSettings = { inAppBrowserMode: 'titlebar', externalLinkMode: 'safari-view' }
    mockUserStore = { isLoggedIn: false, accessToken: '' }
  })

  it('无应用声明时跟随用户全局设置（默认标题栏）', async () => {
    await openInAppBrowser('https://demo.example.com')
    expect(mockInAppOpen).toHaveBeenCalledWith(
      expect.objectContaining({ displayMode: 'titlebar' }),
    )
  })

  it('官方应用声明的形态优先于用户全局设置', async () => {
    // 声明 immersive 的官方应用覆盖全局标题栏（沉浸现仅由应用声明启用）
    mockSettings.inAppBrowserMode = 'titlebar'
    await openInAppBrowser('https://demo.example.com', { displayMode: 'immersive' })
    expect(mockInAppOpen).toHaveBeenLastCalledWith(
      expect.objectContaining({ displayMode: 'immersive' }),
    )

    // 显式声明 titlebar 同样透传
    await openInAppBrowser('https://demo.example.com', { displayMode: 'titlebar' })
    expect(mockInAppOpen).toHaveBeenLastCalledWith(
      expect.objectContaining({ displayMode: 'titlebar' }),
    )
  })

  it('用户全局选「手机内置」时整体退出自定义容器，应用声明不生效', async () => {
    mockSettings.inAppBrowserMode = 'system'
    await openInAppBrowser('https://demo.example.com', { displayMode: 'titlebar' })
    expect(mockInAppOpen).not.toHaveBeenCalled()
    expect(mockBrowserOpen).toHaveBeenCalled()
  })

  it('自定义容器打开时透传登录上下文给原生容器', async () => {
    mockUserStore = { isLoggedIn: true, accessToken: 'access-token' }
    await openInAppBrowser('https://gmm.yunyoujun.cn', { trustedHosts: ['yunyoujun.cn'] })

    expect(mockEnsureValidToken).toHaveBeenCalled()
    expect(mockGetSession).toHaveBeenCalled()
    expect(mockInAppOpen).toHaveBeenCalledWith(
      expect.objectContaining({
        trustedHosts: ['yunyoujun.cn'],
        auth: {
          accessToken: 'session-access-token',
          refreshToken: 'refresh-token',
          apiBaseUrl: 'https://api.example.com',
        },
      }),
    )
  })
})
