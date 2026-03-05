/**
 * CloudBase Auth 核心状态管理
 * 参考 www.yunle.fun 的 useAuthCore.ts，适配 Ionic Toast + Pinia Store
 * 支持 refresh token 机制实现登录态长期保持
 */
import type { CloudbaseUser, TcbRawUser, YlfUserInfo } from '@yunlefun/auth'
import { getErrorMessage, mapCloudbaseUser } from '@yunlefun/auth'

/** Token 过期时间存储 key */
const TOKEN_EXPIRY_KEY = 'ylf_token_expiry'
/** 提前刷新的时间余量（毫秒），提前 5 分钟刷新 */
const REFRESH_AHEAD_MS = 5 * 60 * 1000

export function useCloudbaseAuthCore() {
  const { auth } = useCloudbase()
  const router = useRouter()
  const toast = useToast()
  const userStore = useUserStore()

  const user = ref<CloudbaseUser | null>(null)
  const loading = ref(false)
  const error = ref<string | null>(null)
  const isAuthenticated = computed(() => !!user.value)

  /** 是否正在刷新 token（防止并发刷新） */
  let refreshingPromise: Promise<boolean> | null = null

  const clearAuth = () => {
    user.value = null
    error.value = null
    if (import.meta.client) {
      localStorage.removeItem(TOKEN_EXPIRY_KEY)
    }
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
   * 返回是否刷新成功
   */
  const refreshSession = async (): Promise<boolean> => {
    // 防止并发刷新
    if (refreshingPromise)
      return refreshingPromise

    refreshingPromise = (async () => {
      try {
        const { data, error: sessionError } = await auth.getSession()
        if (sessionError || !data?.session?.access_token) {
          console.warn('[Auth] refresh token 刷新失败，需要重新登录')
          return false
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
        return true
      }
      catch (err) {
        console.error('[Auth] 刷新 session 异常:', err)
        return false
      }
      finally {
        refreshingPromise = null
      }
    })()

    return refreshingPromise
  }

  /**
   * 确保当前持有有效的 access_token
   * - 如果 token 即将过期或已过期，自动通过 refresh_token 刷新
   * - 刷新失败时返回 false（需要引导用户重新登录）
   */
  const ensureValidToken = async (): Promise<boolean> => {
    if (!import.meta.client)
      return false

    if (!isTokenExpiringSoon()) {
      return true // token 仍有效
    }

    console.warn('[Auth] Token 即将过期或已过期，尝试刷新...')
    const success = await refreshSession()
    if (!success) {
      console.warn('[Auth] Token 刷新失败，清除认证状态')
      clearAuth()
      userStore.logout()
    }
    return success
  }

  const fetchUser = async () => {
    try {
      loading.value = true
      error.value = null

      // 获取 session（SDK 内部会自动用 refresh_token 刷新过期的 access_token）
      const { data: sessionData, error: sessionError } = await auth.getSession()
      if (sessionError || !sessionData?.session) {
        clearAuth()
        return null
      }

      const accessToken = sessionData.session.access_token
      if (!accessToken) {
        clearAuth()
        return null
      }

      // 记录 token 过期时间
      saveTokenExpiry(sessionData.session.expires_in)

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
          clearAuth()
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
      clearAuth()
      return null
    }
    finally {
      loading.value = false
    }
  }

  const checkAuthStatus = async () => {
    try {
      // getSession() 内部会自动用 refresh_token 刷新过期的 access_token
      const { data } = await auth.getSession()
      if (data?.session) {
        saveTokenExpiry(data.session.expires_in)
        await fetchUser()
      }
    }
    catch {
      // CloudBase 未登录或 refresh_token 已过期
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
      auth.onAuthStateChange((event: string, _session: unknown, _info?: Record<string, unknown>) => {
        if (event === 'BIND_IDENTITY') {
          // 绑定第三方身份（如微信）完成，刷新用户数据以更新 providers 列表
          fetchUser()
        }
        else if (event === 'SIGNED_IN') {
          // OAuth 登录成功，刷新用户数据
          fetchUser()
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
