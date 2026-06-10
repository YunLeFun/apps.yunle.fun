import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useOpenApp } from '../../app/composables/useOpenApp'

// --- alertController mock：通过 alertRole 控制用户点了「确认」还是「取消」---
let alertRole = 'confirm'
vi.mock('@ionic/vue', () => ({
  alertController: {
    create: vi.fn(async () => ({
      present: vi.fn(),
      onDidDismiss: vi.fn(async () => ({ role: alertRole })),
    })),
  },
}))

// --- 全局 composable / 工具 mock ---
const mockPush = vi.fn()
const mockOpenInAppBrowser = vi.fn()
const mockDeduct = vi.fn(async () => ({ balance: 0, deduped: false }))
const mockRefresh = vi.fn()

let mockUserStore: { isLoggedIn: boolean }
let mockCoin: {
  account: { value: unknown }
  balance: { value: number }
  isMember: { value: boolean }
  refresh: typeof mockRefresh
  deduct: typeof mockDeduct
}

vi.stubGlobal('useRouter', () => ({ push: mockPush }))
vi.stubGlobal('useUserStore', () => mockUserStore)
vi.stubGlobal('useCoin', () => mockCoin)
vi.stubGlobal('useToast', () => ({
  showSuccess: vi.fn(),
  showError: vi.fn(),
  showWarning: vi.fn(),
  showInfo: vi.fn(),
}))
vi.stubGlobal('openInAppBrowser', mockOpenInAppBrowser)

function makeApp(overrides: Record<string, unknown> = {}) {
  return {
    id: 'demo',
    slug: 'demo',
    name: 'Demo',
    color: '#000',
    emoji: '🎯',
    websiteUrl: 'https://demo.example.com',
    ...overrides,
  } as any
}

describe('useOpenApp', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    alertRole = 'confirm'
    mockUserStore = { isLoggedIn: true }
    mockCoin = {
      account: { value: { coin: 100, membership: { isActive: false, level: null, expireAt: null } } },
      balance: { value: 100 },
      isMember: { value: false },
      refresh: mockRefresh,
      deduct: mockDeduct,
    }
  })

  it('免费应用直接打开（外链走浏览器）', async () => {
    const { openApp } = useOpenApp()
    const opened = await openApp(makeApp())
    expect(opened).toBe(true)
    expect(mockOpenInAppBrowser).toHaveBeenCalledWith('https://demo.example.com')
    expect(mockDeduct).not.toHaveBeenCalled()
  })

  it('会员专属应用：非会员被拦截并引导去开通', async () => {
    const { openApp } = useOpenApp()
    const opened = await openApp(makeApp({ requiresMembership: true }))
    expect(opened).toBe(false)
    expect(mockOpenInAppBrowser).not.toHaveBeenCalled()
    expect(mockPush).toHaveBeenCalledWith('/wallet')
  })

  it('付费应用：非会员余额充足，确认后扣云币并打开', async () => {
    const { openApp } = useOpenApp()
    const opened = await openApp(makeApp({ coinCost: 10 }))
    expect(opened).toBe(true)
    expect(mockDeduct).toHaveBeenCalledWith(expect.objectContaining({ appId: 'demo', amount: 10 }))
    expect(mockOpenInAppBrowser).toHaveBeenCalled()
  })

  it('付费应用：非会员余额不足，引导去充值且不扣费', async () => {
    mockCoin.balance.value = 5
    const { openApp } = useOpenApp()
    const opened = await openApp(makeApp({ coinCost: 10 }))
    expect(opened).toBe(false)
    expect(mockDeduct).not.toHaveBeenCalled()
    expect(mockPush).toHaveBeenCalledWith('/wallet')
  })

  it('付费应用：会员免扣，直接打开', async () => {
    mockCoin.isMember.value = true
    const { openApp } = useOpenApp()
    const opened = await openApp(makeApp({ coinCost: 10 }))
    expect(opened).toBe(true)
    expect(mockDeduct).not.toHaveBeenCalled()
    expect(mockOpenInAppBrowser).toHaveBeenCalled()
  })

  it('付费应用：用户取消消费则不打开、不扣费', async () => {
    alertRole = 'cancel'
    const { openApp } = useOpenApp()
    const opened = await openApp(makeApp({ coinCost: 10 }))
    expect(opened).toBe(false)
    expect(mockDeduct).not.toHaveBeenCalled()
    expect(mockOpenInAppBrowser).not.toHaveBeenCalled()
  })

  it('未登录访问受控应用：引导去登录', async () => {
    mockUserStore.isLoggedIn = false
    const { openApp } = useOpenApp()
    const opened = await openApp(makeApp({ coinCost: 10 }))
    expect(opened).toBe(false)
    expect(mockPush).toHaveBeenCalledWith('/login')
  })

  it('站内路由应用通过 router.push 打开', async () => {
    const { openApp } = useOpenApp()
    const opened = await openApp(makeApp({ websiteUrl: '/tabs/apps' }))
    expect(opened).toBe(true)
    expect(mockPush).toHaveBeenCalledWith('/tabs/apps')
  })

  it('未登录的账户快照为空时会触发 refresh', async () => {
    mockCoin.account.value = null
    const { openApp } = useOpenApp()
    await openApp(makeApp({ coinCost: 10 }))
    expect(mockRefresh).toHaveBeenCalled()
  })
})
