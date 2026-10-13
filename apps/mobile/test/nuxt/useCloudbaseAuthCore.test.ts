import { mockNuxtImport } from '@nuxt/test-utils/runtime'
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { SESSION_RECOVERY_WINDOW_MS } from '~/utils/auth-session'

// @cloudbase/js-sdk 的 ESM 产物在 Nuxt 测试环境下解析失败（见 SmsLogin.test.ts），
// 本测试通过 mockNuxtImport(useCloudbase) 注入 auth mock，仅需打断 import 链
vi.mock('@cloudbase/js-sdk', () => ({
  default: {
    init: () => ({
      auth: () => ({}),
    }),
  },
}))

const TOKEN_EXPIRY_KEY = 'ylf_token_expiry'

const getSession = vi.fn()
const getUser = vi.fn()

mockNuxtImport('useCloudbase', () => () => ({
  auth: {
    getSession,
    getUser,
    onAuthStateChange: vi.fn(),
  },
}))

const storeState = { token: '' }
const storeLogin = vi.fn((token: string) => {
  storeState.token = token
})
const storeLogout = vi.fn(() => {
  storeState.token = ''
})

mockNuxtImport('useUserStore', () => () => ({
  get accessToken() {
    return storeState.token
  },
  get isLoggedIn() {
    return !!storeState.token
  },
  get userInfo() {
    return { nickname: 'tester', avatar: '' }
  },
  login: storeLogin,
  logout: storeLogout,
}))

mockNuxtImport('useToast', () => () => ({
  showSuccess: vi.fn(),
  showError: vi.fn(),
  showInfo: vi.fn(),
}))

/** 模拟"本地缓存已登录 + access_token 已过期"的状态 */
function setLoggedInWithExpiredToken(expiredAgoMs = 1000) {
  storeState.token = 'stale-token'
  localStorage.setItem(TOKEN_EXPIRY_KEY, String(Date.now() - expiredAgoMs))
}

beforeAll(async () => {
  // 等初始路由就绪并预热首页组件链，
  // 避免测试文件结束销毁环境时仍有 in-flight 动态导入报 EnvironmentTeardownError
  await useRouter().isReady()
  await import('~/pages/tabs/home.vue')
})

beforeEach(() => {
  vi.clearAllMocks()
  localStorage.clear()
  storeState.token = ''
  // 重置单例，让每个用例拿到全新 core（含刷新锁）
  const nuxtApp = useNuxtApp() as unknown as Record<string, unknown>
  nuxtApp._cloudbaseAuthCore = undefined
})

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('ensureValidToken 凭证失效自动登出', () => {
  it('refresh token 失效（invalid_grant）→ 清除登录态', async () => {
    setLoggedInWithExpiredToken()
    getSession.mockResolvedValue({
      data: null,
      error: { status: 'invalid_grant', message: 'refresh token expired' },
    })

    const { ensureValidToken } = useCloudbaseAuthCore()
    await expect(ensureValidToken()).resolves.toBe(false)

    expect(storeLogout).toHaveBeenCalled()
    expect(localStorage.getItem(TOKEN_EXPIRY_KEY)).toBeNull()
  })

  it('网络异常 → 保留登录态稍后重试', async () => {
    setLoggedInWithExpiredToken()
    getSession.mockRejectedValue(new TypeError('Failed to fetch'))

    const { ensureValidToken } = useCloudbaseAuthCore()
    await expect(ensureValidToken()).resolves.toBe(false)

    expect(storeLogout).not.toHaveBeenCalled()
    expect(storeState.token).toBe('stale-token')
  })

  it('无错误但无会话（SDK 凭证丢失）→ 清除登录态', async () => {
    setLoggedInWithExpiredToken()
    getSession.mockResolvedValue({ data: { session: null }, error: null })

    const { ensureValidToken } = useCloudbaseAuthCore()
    await expect(ensureValidToken()).resolves.toBe(false)

    expect(storeLogout).toHaveBeenCalled()
  })

  it('本地记录未过期时默认跳过刷新，force 时强制真刷（401 回归）', async () => {
    storeState.token = 'stale-token'
    localStorage.setItem(TOKEN_EXPIRY_KEY, String(Date.now() + 60 * 60 * 1000))
    getSession.mockResolvedValue({
      data: { session: { access_token: 'fresh-token', expires_in: 7200 } },
      error: null,
    })

    const { ensureValidToken } = useCloudbaseAuthCore()

    // 默认：本地记录说没过期 → 不发起刷新
    await expect(ensureValidToken()).resolves.toBe(true)
    expect(getSession).not.toHaveBeenCalled()

    // force：服务端 401 不信任本地记录 → 必须真刷，并把新 token 同步到 store
    await expect(ensureValidToken({ force: true })).resolves.toBe(true)
    expect(getSession).toHaveBeenCalledTimes(1)
    expect(storeLogin).toHaveBeenCalledWith('fresh-token', expect.anything())
    expect(Number(localStorage.getItem(TOKEN_EXPIRY_KEY))).toBeGreaterThan(Date.now())
  })

  it('并发调用共享同一次刷新（单例 + 刷新锁，防 refresh_token 轮换竞态）', async () => {
    setLoggedInWithExpiredToken()
    let resolveSession: (value: unknown) => void
    getSession.mockReturnValue(new Promise((resolve) => {
      resolveSession = resolve
    }))

    // 两次独立调用 composable，验证单例共享刷新锁
    const coreA = useCloudbaseAuthCore()
    const coreB = useCloudbaseAuthCore()
    const pending = Promise.all([coreA.ensureValidToken(), coreB.ensureValidToken()])

    resolveSession!({
      data: { session: { access_token: 'fresh-token', expires_in: 7200 } },
      error: null,
    })
    await expect(pending).resolves.toEqual([true, true])
    expect(getSession).toHaveBeenCalledTimes(1)
  })

  it('临时失败但过期超出恢复窗口（refresh_token 必死）→ 升级为登出', async () => {
    storeState.token = 'stale-token'
    localStorage.setItem(
      TOKEN_EXPIRY_KEY,
      String(Date.now() - SESSION_RECOVERY_WINDOW_MS - 60 * 1000),
    )
    getSession.mockRejectedValue(new TypeError('Failed to fetch'))

    const { ensureValidToken } = useCloudbaseAuthCore()
    await expect(ensureValidToken()).resolves.toBe(false)

    expect(storeLogout).toHaveBeenCalled()
  })
})

describe('checkAuthStatus 启动时悬空登录态清理', () => {
  it('会话确已失效 → 清除登录态（启动路径回归）', async () => {
    setLoggedInWithExpiredToken()
    getSession.mockResolvedValue({
      data: null,
      error: { category: 'INVALID_CREDENTIALS', status: 'invalid_grant' },
    })

    const { checkAuthStatus } = useCloudbaseAuthCore()
    await checkAuthStatus()

    expect(storeLogout).toHaveBeenCalled()
  })

  it('刷新临时失败 → 保留登录态', async () => {
    setLoggedInWithExpiredToken()
    getSession.mockResolvedValue({
      data: null,
      error: { category: 'SERVICE_ERROR', status: 'unreachable' },
    })

    const { checkAuthStatus } = useCloudbaseAuthCore()
    await checkAuthStatus()

    expect(storeLogout).not.toHaveBeenCalled()
    expect(storeState.token).toBe('stale-token')
  })

  it('本地 SDK 凭证丢失但业务缓存仍显示已登录（悬空态）→ 清除登录态', async () => {
    storeState.token = 'stale-token'
    getSession.mockResolvedValue({ data: { session: null }, error: null })

    const { checkAuthStatus } = useCloudbaseAuthCore()
    await checkAuthStatus()

    expect(storeLogout).toHaveBeenCalled()
  })

  it('本地 SDK 凭证丢失且本就未登录 → 保持未登录，不触发清理', async () => {
    getSession.mockResolvedValue({ data: { session: null }, error: null })

    const { checkAuthStatus } = useCloudbaseAuthCore()
    await checkAuthStatus()

    expect(storeLogout).not.toHaveBeenCalled()
  })

  it('会话有效 → 记录过期时间并同步用户到 store', async () => {
    getSession.mockResolvedValue({
      data: { session: { access_token: 'fresh-token', expires_in: 7200 } },
      error: null,
    })
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ sub: 'uid-1', name: 'tester', picture: '' }),
    }))

    const { checkAuthStatus } = useCloudbaseAuthCore()
    await checkAuthStatus()

    expect(Number(localStorage.getItem(TOKEN_EXPIRY_KEY))).toBeGreaterThan(Date.now())
    expect(storeLogin).toHaveBeenCalledWith('fresh-token', expect.objectContaining({ id: 'uid-1' }))
  })
})

describe('fetchUser 临时故障不清登录态', () => {
  it('获取用户资料网络异常 → 保留登录态', async () => {
    storeState.token = 'stale-token'
    getSession.mockResolvedValue({
      data: { session: { access_token: 'fresh-token', expires_in: 7200 } },
      error: null,
    })
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')))

    const { fetchUser } = useCloudbaseAuthCore()
    await expect(fetchUser()).resolves.toBeNull()

    expect(storeLogout).not.toHaveBeenCalled()
  })

  it('会话失效 → 完整清除登录态（cookie/镜像一并清）', async () => {
    storeState.token = 'stale-token'
    getSession.mockResolvedValue({
      data: null,
      error: { status: 'invalid_grant' },
    })

    const { fetchUser } = useCloudbaseAuthCore()
    await expect(fetchUser()).resolves.toBeNull()

    expect(storeLogout).toHaveBeenCalled()
  })
})
