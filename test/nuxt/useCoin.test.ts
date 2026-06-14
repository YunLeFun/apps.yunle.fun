import type { AccountSnapshot } from '@yunlefun/types'
import { mockNuxtImport } from '@nuxt/test-utils/runtime'
import { beforeEach, describe, expect, it, vi } from 'vitest'

// @cloudbase/js-sdk 的 ESM 产物在 Nuxt 测试环境下解析失败（见 SmsLogin.test.ts），
// useCoin 不直接使用 SDK，mock 掉模块以打断 import 链
vi.mock('@cloudbase/js-sdk', () => ({
  default: {
    init: () => ({
      auth: () => ({}),
      database: () => ({}),
    }),
  },
}))

const ACCOUNT_CACHE_KEY = 'ylf_coin_account'

const callFunction = vi.fn()
let mockUser: { id?: string, nickname: string }

mockNuxtImport('useCloudbase', () => () => ({
  app: { callFunction },
}))

mockNuxtImport('useUserStore', () => () => ({
  get isLoggedIn() {
    return !!mockUser.id
  },
  get userInfo() {
    return mockUser
  },
}))

function makeSnapshot(coin: number): AccountSnapshot {
  return {
    coin,
    membership: { isActive: false, level: null, expireAt: null },
  }
}

beforeEach(() => {
  vi.clearAllMocks()
  localStorage.clear()
  mockUser = { id: 'user-1', nickname: 'tester' }
  // 重置 useState 共享状态，让下一次 useCoin() 重新执行缓存水合
  clearNuxtState('coin_account')
})

describe('useCoin 账户快照本地缓存', () => {
  it('无缓存时初始为 null（展示骨架而非 0）', () => {
    const { account, balance } = useCoin()
    expect(account.value).toBeNull()
    expect(balance.value).toBe(0)
  })

  it('命中同用户缓存：启动即展示上次余额', () => {
    localStorage.setItem(
      ACCOUNT_CACHE_KEY,
      JSON.stringify({ userId: 'user-1', account: makeSnapshot(1000) }),
    )

    const { account, balance } = useCoin()
    expect(account.value).not.toBeNull()
    expect(balance.value).toBe(1000)
  })

  it('缓存属于其他用户时不命中', () => {
    localStorage.setItem(
      ACCOUNT_CACHE_KEY,
      JSON.stringify({ userId: 'user-2', account: makeSnapshot(1000) }),
    )

    const { account } = useCoin()
    expect(account.value).toBeNull()
  })

  it('缓存数据损坏时安全降级为 null', () => {
    localStorage.setItem(ACCOUNT_CACHE_KEY, '{not-json')

    const { account } = useCoin()
    expect(account.value).toBeNull()
  })

  it('refresh 成功后回写缓存', async () => {
    callFunction.mockResolvedValue({ result: makeSnapshot(800) })

    const { refresh, balance } = useCoin()
    await refresh()

    expect(balance.value).toBe(800)
    const cached = JSON.parse(localStorage.getItem(ACCOUNT_CACHE_KEY)!)
    expect(cached).toEqual({ userId: 'user-1', account: makeSnapshot(800) })
  })

  it('deduct 扣减后同步缓存余额', async () => {
    localStorage.setItem(
      ACCOUNT_CACHE_KEY,
      JSON.stringify({ userId: 'user-1', account: makeSnapshot(1000) }),
    )
    callFunction.mockResolvedValue({ result: { balance: 900, deduped: false } })

    const { deduct } = useCoin()
    await deduct({ appId: 'demo', amount: 100 })

    const cached = JSON.parse(localStorage.getItem(ACCOUNT_CACHE_KEY)!)
    expect(cached.account.coin).toBe(900)
  })

  it('未登录时 refresh 不调用云函数且账户为空', async () => {
    mockUser = { nickname: '' }

    const { refresh, account } = useCoin()
    await refresh()

    expect(callFunction).not.toHaveBeenCalled()
    expect(account.value).toBeNull()
  })
})
