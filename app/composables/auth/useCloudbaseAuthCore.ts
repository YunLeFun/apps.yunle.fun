/**
 * CloudBase Auth 核心状态管理
 * 参考 www.yunle.fun 的 useAuthCore.ts，适配 Ionic Toast + Pinia Store
 * 支持 refresh token 机制实现登录态长期保持
 */
import type { CloudbaseUser, TcbRawUser, YlfUserInfo } from '@yunlefun/auth'
import { getErrorMessage, mapCloudbaseUser } from '@yunlefun/auth'
import { clearInAppBrowserIdentitySessions } from '~/composables/useBrowser'
import { useAccountsStore } from '~/stores/accounts'
import { classifyAuthError, isBeyondSessionRecovery, serializeAuthError } from '~/utils/auth-session'

/** Token 过期时间存储 key */
const TOKEN_EXPIRY_KEY = 'ylf_token_expiry'
/** 提前刷新的时间余量（毫秒），提前 5 分钟刷新 */
const REFRESH_AHEAD_MS = 5 * 60 * 1000

/**
 * 刷新结果三态：
 * - ok：刷新成功，持有有效 token
 * - invalid：refresh token 确已失效/撤销，需要重新登录
 * - transient：临时失败（网络不可达、超时、服务端 5xx 等），应保留登录态稍后重试
 */
type RefreshResult = 'ok' | 'invalid' | 'transient'

/**
 * 单例：刷新锁、auth 状态监听、user 状态都必须全局唯一。
 * 多实例会导致并发 getSession 触发 refresh_token 轮换竞态（旧 token 被消费后
 * 另一实例再用即 invalid_grant），以及 onAuthStateChange 重复注册。
 */
export function useCloudbaseAuthCore() {
  const nuxtApp = useNuxtApp()
  const cached = nuxtApp._cloudbaseAuthCore as ReturnType<typeof createCloudbaseAuthCore> | undefined
  if (cached)
    return cached

  const core = createCloudbaseAuthCore()
  nuxtApp._cloudbaseAuthCore = core
  return core
}

function createCloudbaseAuthCore() {
  const { auth } = useCloudbase()
  const router = useRouter()
  const toast = useToast()
  const userStore = useUserStore()

  const user = ref<CloudbaseUser | null>(null)
  const loading = ref(false)
  const error = ref<string | null>(null)
  const isAuthenticated = computed(() => !!user.value)

  /** 是否正在刷新 token（防止并发刷新） */
  let refreshingPromise: Promise<RefreshResult> | null = null

  const clearAuth = () => {
    user.value = null
    error.value = null
    if (import.meta.client) {
      localStorage.removeItem(TOKEN_EXPIRY_KEY)
    }
  }

  /**
   * 凭证确已失效：同时清除内存态与业务登录态（cookie + localStorage 镜像）。
   * 两套登录态必须一起清，否则 UI 维持"已登录"但所有请求 401 的悬空状态。
   */
  const invalidateAuth = (stage: string, err?: unknown) => {
    // 本就未登录的冷启动 SDK 也会返回 unauthenticated 类错误，属常态，不打告警
    if (userStore.isLoggedIn || user.value)
      console.warn(`[Auth] ${stage}: 登录凭证已失效，清除登录态`, err ? serializeAuthError(err) : '')
    clearAuth()
    userStore.logout()
  }

  /**
   * 保存 token 过期时间到 localStorage
   */
  const saveTokenExpiry = (expiresIn?: number) => {
    if (!import.meta.client)
      return
    // access_token 有效期默认 7200 秒（2 小时）
    const ttl = (expiresIn || 7200) * 1000
    localStorage.setItem(TOKEN_EXPIRY_KEY, String(Date.now() + ttl))
  }

  /**
   * 获取 token 过期时间戳
   */
  const getTokenExpiry = (): number => {
    if (!import.meta.client)
      return 0
    const raw = localStorage.getItem(TOKEN_EXPIRY_KEY)
    return raw ? Number(raw) : 0
  }

  /**
   * 检查 token 是否即将过期或已过期
   */
  const isTokenExpiringSoon = (): boolean => {
    const expiry = getTokenExpiry()
    if (!expiry)
      return true // 无记录则视为需要刷新
    return Date.now() >= expiry - REFRESH_AHEAD_MS
  }

  /**
   * 将 CloudbaseUser 同步到 Pinia userStore
   */
  const syncToStore = (cbUser: CloudbaseUser, accessToken: string) => {
    const info: YlfUserInfo = {
      id: cbUser.id,
      login: cbUser.login,
      email: cbUser.email,
      phone: cbUser.phone,
      avatar: cbUser.avatar || '',
      nickname: cbUser.nickname || '',
      hasPassword: cbUser.hasPassword,
      providers: cbUser.providers,
    }
    userStore.login(accessToken, info)
  }

  /**
   * 刷新 session（通过 CloudBase SDK 内部的 refresh token 机制）
   * CloudBase JS SDK 的 getSession() 内部会自动使用 refresh_token 获取新的 access_token
   */
  const refreshSessionDetailed = async (): Promise<RefreshResult> => {
    // 防止并发刷新
    if (refreshingPromise)
      return refreshingPromise

    refreshingPromise = (async () => {
      try {
        const { data, error: sessionError } = await auth.getSession()
        if (sessionError) {
          const kind = classifyAuthError(sessionError)
          // 完整记录原始错误码，用于线上校准 INVALID_CODES 分类表
          console.warn(`[Auth] 刷新 session 失败(${kind}):`, JSON.stringify(serializeAuthError(sessionError)))
          return kind
        }
        if (!data?.session?.access_token) {
          // 无错误但也无会话：本地没有可用凭证
          console.warn('[Auth] 无可用会话，需要重新登录')
          return 'invalid'
        }
        // 刷新成功，更新过期时间
        saveTokenExpiry(data.session.expires_in)
        // 同步新 token 到 store
        if (user.value) {
          syncToStore(user.value, data.session.access_token)
        }
        else {
          userStore.login(data.session.access_token, userStore.userInfo)
        }
        return 'ok'
      }
      catch (err) {
        console.error('[Auth] 刷新 session 异常:', JSON.stringify(serializeAuthError(err)))
        return classifyAuthError(err)
      }
      finally {
        refreshingPromise = null
      }
    })()

    return refreshingPromise
  }

  /** 刷新 session，返回是否刷新成功 */
  const refreshSession = async (): Promise<boolean> =>
    (await refreshSessionDetailed()) === 'ok'

  /**
   * 临时失败但 token 过期已超出恢复窗口：refresh_token 必然失效，
   * 不能让"永远 transient"导致悬空登录态无限滞留
   */
  const isExpiredBeyondRecovery = () => isBeyondSessionRecovery(getTokenExpiry())

  /**
   * 确保当前持有有效的 access_token
   * - 如果 token 即将过期或已过期，自动通过 refresh_token 刷新
   * - force：服务端已明确拒绝当前 token（如 401），本地过期记录不可信，必须真刷一次
   * - 仅在凭证确已失效时清除登录态；临时失败（网络等）保留状态稍后重试
   */
  const ensureValidToken = async (opts: { force?: boolean } = {}): Promise<boolean> => {
    if (!import.meta.client)
      return false

    if (!opts.force && !isTokenExpiringSoon()) {
      return true // token 仍有效
    }

    console.warn('[Auth] Token 即将过期或已过期，尝试刷新...')
    const result = await refreshSessionDetailed()
    if (result === 'invalid')
      invalidateAuth('ensureValidToken')
    else if (result === 'transient' && isExpiredBeyondRecovery())
      invalidateAuth('ensureValidToken', new Error('token 过期已超出 refresh_token 有效期'))
    return result === 'ok'
  }

  const fetchUser = async () => {
    try {
      loading.value = true
      error.value = null

      // 获取 session（SDK 内部会自动用 refresh_token 刷新过期的 access_token）
      const { data: sessionData, error: sessionError } = await auth.getSession()
      if (sessionError) {
        if (classifyAuthError(sessionError) === 'invalid')
          invalidateAuth('fetchUser', sessionError)
        return null
      }

      const session = sessionData?.session
      const accessToken = session?.access_token
      if (!session || !accessToken) {
        // 无错误但无会话：SDK 本地没有凭证，业务登录态若还在则是悬空状态
        if (userStore.isLoggedIn)
          invalidateAuth('fetchUser(no-session)')
        else
          clearAuth()
        return null
      }

      // 记录 token 过期时间
      saveTokenExpiry(session.expires_in)

      // 使用 HTTP API /user/me 获取完整用户数据（包含 providers/password/meta 等完整字段）
      const config = useRuntimeConfig()
      const envId = config.public.tcbEnvId as string
      const res = await fetch(`https://${envId}.api.tcloudbasegateway.com/auth/v1/user/me`, {
        headers: { Authorization: `Bearer ${accessToken}` },
      })

      if (!res.ok) {
        // fallback 到 SDK getUser
        const { data, error: authError } = await auth.getUser()
        if (authError || !data?.user) {
          if (authError && classifyAuthError(authError) === 'invalid')
            invalidateAuth('fetchUser(getUser)', authError)
          return null
        }
        user.value = mapCloudbaseUser(data.user as unknown as TcbRawUser)
      }
      else {
        const profile = await res.json()
        user.value = mapCloudbaseUser(profile as TcbRawUser)
      }

      // 同步到 userStore
      if (user.value) {
        syncToStore(user.value, accessToken)
      }

      return user.value
    }
    catch (err: unknown) {
      console.error('获取用户信息失败:', err)
      error.value = getErrorMessage(err)
      // 网络等临时故障保留登录态，仅凭证确已失效时清除
      if (classifyAuthError(err) === 'invalid')
        invalidateAuth('fetchUser', err)
      return null
    }
    finally {
      loading.value = false
    }
  }

  const checkAuthStatus = async () => {
    try {
      // getSession() 内部会自动用 refresh_token 刷新过期的 access_token
      const { data, error: sessionError } = await auth.getSession()
      if (sessionError) {
        const kind = classifyAuthError(sessionError)
        if (kind === 'invalid' || isExpiredBeyondRecovery())
          invalidateAuth('checkAuthStatus', sessionError)
        else
          console.warn('[Auth] checkAuthStatus 刷新临时失败，保留登录态:', JSON.stringify(serializeAuthError(sessionError)))
        return
      }
      if (!data?.session?.access_token) {
        // 无错误但无会话：SDK 本地没有凭证（如 WKWebView 清掉 localStorage）。
        // 业务登录态（cookie/镜像）若仍显示已登录则是悬空状态——access_token
        // 最长 2 小时后必死且无从刷新，立即清除，不让 UI 停留在假登录态
        if (userStore.isLoggedIn)
          invalidateAuth('checkAuthStatus(no-session)')
        return
      }
      saveTokenExpiry(data.session.expires_in)
      await fetchUser()
    }
    catch (err) {
      if (classifyAuthError(err) === 'invalid')
        invalidateAuth('checkAuthStatus', err)
      else
        console.warn('[Auth] checkAuthStatus 未恢复会话:', JSON.stringify(serializeAuthError(err)))
    }
  }

  /**
   * 监听 CloudBase Auth 状态变更
   * 处理 OAuth 登录成功 / 绑定身份完成等事件
   */
  const setupAuthListener = () => {
    if (!import.meta.client)
      return
    try {
      auth.onAuthStateChange((event: string, _session: unknown, info?: Record<string, unknown>) => {
        if (event === 'BIND_IDENTITY') {
          // 绑定第三方身份（如微信）完成，刷新用户数据以更新 providers 列表
          fetchUser()
        }
        else if (event === 'SIGNED_IN') {
          // OAuth 登录成功，刷新用户数据并保存账号
          fetchUser().then(() => {
            if (user.value) {
              const accountsStore = useAccountsStore()
              // 尝试从回调信息或用户 providers 推断登录方式
              const provider = (info?.provider as string) || ''
              const method = provider.includes('github')
                ? 'github'
                : provider.includes('wechat')
                  ? 'wechat'
                  : undefined
              accountsStore.saveAccount(userStore.userInfo, method)
            }
            // A signed-in identity is authoritative for first-party embedded
            // apps. Drop any previous BFF cookie and ask preserved WebViews to
            // bootstrap against the new Apps account.
            clearInAppBrowserIdentitySessions().catch((error) => {
              console.warn('[Auth] 同步内嵌应用身份失败:', error)
            })
          })
        }
      })
    }
    catch (err) {
      console.warn('[Auth] 监听状态变更失败:', err)
    }
  }

  // 初始化时自动设置监听
  setupAuthListener()

  /**
   * 更新用户信息（昵称、描述、性别等）
   */
  const updateUserInfo = async (params: {
    nickname?: string
    description?: string
    gender?: 'MALE' | 'FEMALE'
    avatar_url?: string
  }) => {
    try {
      loading.value = true
      error.value = null
      const res = await auth.updateUser(params)
      if ('error' in res && res.error)
        throw new Error(res.error.message || '更新失败')
      // 重新获取用户数据
      await fetchUser()
      toast.showSuccess('更新成功')
      return true
    }
    catch (err: unknown) {
      console.error('更新用户信息失败:', err)
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err))
      return false
    }
    finally {
      loading.value = false
    }
  }

  /**
   * 获取已绑定的身份源列表
   */
  const getUserIdentities = async () => {
    try {
      const res = await auth.getUserIdentities()
      if (res.error)
        return []
      return res.data?.identities || []
    }
    catch {
      return []
    }
  }

  /**
   * 通过旧密码重设新密码
   */
  const resetPasswordWithOld = async (oldPassword: string, newPassword: string) => {
    try {
      loading.value = true
      error.value = null
      const res = await auth.resetPasswordForOld({
        old_password: oldPassword,
        new_password: newPassword,
      })
      if ('error' in res && res.error)
        throw new Error(res.error.message || '重设密码失败')
      toast.showSuccess('密码已更新')
      return true
    }
    catch (err: unknown) {
      console.error('重设密码失败:', err)
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err))
      return false
    }
    finally {
      loading.value = false
    }
  }

  /**
   * 换绑邮箱（发送验证码到新邮箱）
   */
  const changeEmail = async (newEmail: string) => {
    try {
      loading.value = true
      error.value = null
      const res = await auth.updateUser({ email: newEmail })
      if ('error' in res && res.error)
        throw new Error(res.error.message || '换绑邮箱失败')
      // updateUser 会返回 verifyOtp 回调或直接成功
      if (res.data && 'verifyOtp' in res.data && res.data.verifyOtp) {
        toast.showInfo('验证邮件已发送，请查收')
        return { needVerify: true, verifyOtp: res.data.verifyOtp }
      }
      await fetchUser()
      toast.showSuccess('邮箱已更新')
      return { needVerify: false }
    }
    catch (err: unknown) {
      console.error('换绑邮箱失败:', err)
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err))
      return null
    }
    finally {
      loading.value = false
    }
  }

  /**
   * 验证邮箱验证码
   */
  const verifyEmailOtp = async (
    verifyFn: (params: { email: string, token: string }) => Promise<unknown>,
    email: string,
    token: string,
  ) => {
    try {
      loading.value = true
      error.value = null
      await verifyFn({ email, token })
      await fetchUser()
      toast.showSuccess('邮箱已更新')
      return true
    }
    catch (err: unknown) {
      console.error('验证码验证失败:', err)
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err))
      return false
    }
    finally {
      loading.value = false
    }
  }

  const logout = async () => {
    try {
      loading.value = true
      await auth.signOut()
      clearAuth()
      userStore.logout()
      toast.showSuccess('已退出登录')
      await router.push('/login')
    }
    catch (err: unknown) {
      console.error('退出登录失败:', err)
      clearAuth()
      userStore.logout()
      toast.showError(getErrorMessage(err))
    }
    finally {
      loading.value = false
    }
  }

  return {
    auth,
    router,
    toast,
    user,
    loading,
    error,
    isAuthenticated,
    clearAuth,
    fetchUser,
    checkAuthStatus,
    ensureValidToken,
    refreshSession,
    logout,
    syncToStore,
    updateUserInfo,
    getUserIdentities,
    resetPasswordWithOld,
    changeEmail,
    verifyEmailOtp,
  }
}
