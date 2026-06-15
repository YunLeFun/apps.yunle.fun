import { afterEach, describe, expect, it, vi } from 'vitest'
import { bootstrapJsapiLogin } from '../../app/utils/jsapiBootstrapLogin'

// 端到端跑通收敛后的自举登录：经真实 @yunlefun/sso 的 requestSsoNative
// （stub 原生桥 window.ylf + 兑换 fetch）直到写入 userStore。

function setBridge(ylf: unknown) {
  vi.stubGlobal('window', { ylf })
}

function makeStore(isLoggedIn = false) {
  return { isLoggedIn, login: vi.fn() }
}

function stubExchange(session: Record<string, unknown>, user: Record<string, unknown>) {
  const fetchMock = vi.fn(async () => ({ ok: true, json: async () => ({ data: { session, user } }) }))
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

afterEach(() => {
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe('bootstrapJsapiLogin（详情页自举登录）', () => {
  it('容器内取回会话后写入 userStore（授权码 → 兑换 → login）', async () => {
    setBridge({ inYunleApp: true, getAuthCode: async () => ({ code: 'C' }) })
    const fetchMock = stubExchange(
      { access_token: 'at', refresh_token: 'rt' },
      { id: 'u1', nickname: 'Alice', avatar: 'a.png' },
    )
    const store = makeStore(false)

    expect(await bootstrapJsapiLogin(store)).toBe(true)
    expect(store.login).toHaveBeenCalledWith('at', { nickname: 'Alice', avatar: 'a.png' })
    expect(fetchMock).toHaveBeenCalledWith('/api/jsapi/auth/exchange', expect.objectContaining({ method: 'POST' }))
  })

  it('优先用 getCloudbaseSession（无需兑换 fetch）', async () => {
    setBridge({
      inYunleApp: true,
      getCloudbaseSession: async () => ({ access_token: 'at', refresh_token: 'rt', user: { nickname: 'Bob' } }),
    })
    const store = makeStore(false)

    expect(await bootstrapJsapiLogin(store)).toBe(true)
    expect(store.login).toHaveBeenCalledWith('at', { nickname: 'Bob', avatar: '' })
  })

  it('已登录则跳过', async () => {
    const store = makeStore(true)
    expect(await bootstrapJsapiLogin(store)).toBe(false)
    expect(store.login).not.toHaveBeenCalled()
  })

  it('不在容器内则不登录', async () => {
    const store = makeStore(false)
    expect(await bootstrapJsapiLogin(store)).toBe(false)
    expect(store.login).not.toHaveBeenCalled()
  })

  it('缺 nickname 不写入（避免半残登录态）', async () => {
    setBridge({ inYunleApp: true, getAuthCode: async () => ({ code: 'C' }) })
    stubExchange({ access_token: 'at', refresh_token: 'rt' }, {})
    const store = makeStore(false)
    expect(await bootstrapJsapiLogin(store)).toBe(false)
    expect(store.login).not.toHaveBeenCalled()
  })

  it('兑换失败不登录', async () => {
    setBridge({ inYunleApp: true, getAuthCode: async () => ({ code: 'C' }) })
    vi.stubGlobal('fetch', vi.fn(async () => ({ ok: false })))
    const store = makeStore(false)
    expect(await bootstrapJsapiLogin(store)).toBe(false)
    expect(store.login).not.toHaveBeenCalled()
  })
})
