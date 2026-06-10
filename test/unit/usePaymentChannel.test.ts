import { beforeEach, describe, expect, it, vi } from 'vitest'

// --- Capacitor mock：通过变量控制平台 ---
let mockIsNative = false
let mockPlatform = 'web'

vi.mock('@capacitor/core', () => ({
  Capacitor: {
    isNativePlatform: () => mockIsNative,
    getPlatform: () => mockPlatform,
  },
}))

vi.mock('@capacitor/browser', () => ({
  Browser: {
    addListener: vi.fn(async () => ({ remove: vi.fn() })),
  },
}))

const mockOpenInAppBrowser = vi.fn()
vi.stubGlobal('openInAppBrowser', mockOpenInAppBrowser)
// usePaymentChannel 在组件外调用时 onMounted/onUnmounted 为空操作
vi.stubGlobal('onMounted', vi.fn())
vi.stubGlobal('onUnmounted', vi.fn())

const { getPaymentChannel, usePaymentChannel, WWW_PRICING_URL, WWW_WALLET_URL } = await import('../../app/composables/usePaymentChannel')

beforeEach(() => {
  vi.clearAllMocks()
  mockIsNative = false
  mockPlatform = 'web'
})

describe('getPaymentChannel', () => {
  it('web 环境走 web-redirect', () => {
    expect(getPaymentChannel()).toBe('web-redirect')
  })

  it('iOS 原生壳走 ios-iap', () => {
    mockIsNative = true
    mockPlatform = 'ios'
    expect(getPaymentChannel()).toBe('ios-iap')
  })

  it('android 原生壳走 web-redirect', () => {
    mockIsNative = true
    mockPlatform = 'android'
    expect(getPaymentChannel()).toBe('web-redirect')
  })
})

describe('usePaymentChannel', () => {
  it('web 通道可购买，跳转携带 from=apps', () => {
    const { canPurchase, goRecharge, goMembershipPurchase } = usePaymentChannel()
    expect(canPurchase.value).toBe(true)

    goRecharge()
    expect(mockOpenInAppBrowser).toHaveBeenCalledWith(WWW_WALLET_URL)
    expect(WWW_WALLET_URL).toContain('from=apps')

    goMembershipPurchase()
    expect(mockOpenInAppBrowser).toHaveBeenCalledWith(WWW_PRICING_URL)
    expect(WWW_PRICING_URL).toContain('from=apps')
  })

  it('iOS IAP 通道下外跳入口禁用（审核 3.1.1）', () => {
    mockIsNative = true
    mockPlatform = 'ios'
    const { canPurchase, goRecharge } = usePaymentChannel()
    expect(canPurchase.value).toBe(false)

    goRecharge()
    expect(mockOpenInAppBrowser).not.toHaveBeenCalled()
  })
})
