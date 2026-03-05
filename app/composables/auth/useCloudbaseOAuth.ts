/**
 * OAuth 第三方登录 / 绑定 / 解绑
 * 参考 www.yunle.fun 的 useOAuth.ts，适配 Ionic Toast
 *
 * 移动端（Capacitor）使用 Browser.open() 打开授权页，
 * 线上 callback 通过 deeplink (yunlefun://) 把 code+state 传回 App，
 * App 内手动完成 code → provider_token → signIn 流程。
 */
import { Capacitor } from '@capacitor/core'
import { getErrorMessage } from '@yunlefun/auth'

/** state 前缀，用于标识来自原生 App 的 OAuth 请求 */
export const NATIVE_OAUTH_STATE_PREFIX = 'app-'

/** 线上 OAuth 回调地址 */
const ONLINE_CALLBACK_URL = 'https://www.yunle.fun/auth/callback'

export function useCloudbaseOAuth(core: ReturnType<typeof useCloudbaseAuthCore>) {
  const { auth, loading, error, toast } = core

  /**
   * 移动端原生 OAuth 登录
   * 使用 Browser.open() 打开授权页，回调通过 deeplink 返回
   */
  const loginWithOAuthNative = async (provider: 'github' | 'wx_open') => {
    const { Browser } = await import('@capacitor/browser')

    // 生成带 app- 前缀的 state，让 callback 页面识别来源
    // 格式：app-{provider}_{random}（用 _ 分隔 provider 和 random，避免和 provider 名中的 - 冲突）
    const state = `${NATIVE_OAUTH_STATE_PREFIX}${provider}_${Math.random().toString(36).slice(2)}`

    const { data, error: oauthError } = await auth.signInWithOAuth({
      provider,
      options: {
        skipBrowserRedirect: true,
        redirectTo: ONLINE_CALLBACK_URL,
        state,
      },
    })

    if (oauthError)
      throw new Error(oauthError.message || 'OAuth 登录失败')

    if (!data?.url)
      throw new Error('未获取到授权地址')

    // 用系统浏览器打开授权页（iOS: SFSafariViewController）
    await Browser.open({ url: data.url })
  }

  /**
   * 处理从 deeplink 传回的 OAuth 回调参数
   * 由 deeplink.client.ts 插件调用
   */
  const handleNativeOAuthCallback = async (code: string, state: string) => {
    try {
      loading.value = true
      error.value = null

      // 从 state 中解析 provider（格式: app-{provider}_{random}）
      const withoutPrefix = state.replace(NATIVE_OAUTH_STATE_PREFIX, '')
      const underscoreIdx = withoutPrefix.indexOf('_')
      const provider = underscoreIdx > 0 ? withoutPrefix.slice(0, underscoreIdx) : withoutPrefix
      if (!provider)
        throw new Error('无法识别登录来源')

      // 1. 用 code 换取 provider_token
      //    provider_redirect_uri 必须和 signInWithOAuth 时 SDK 传给 genProviderRedirectUri 的一致
      const { provider_token: providerToken } = await (auth as any).grantProviderToken({
        provider_id: provider,
        provider_redirect_uri: ONLINE_CALLBACK_URL,
        provider_code: code,
      })

      if (!providerToken)
        throw new Error('获取第三方令牌失败')

      // 2. 用 provider_token 登录
      const res = await auth.signInWithIdToken({ token: providerToken })
      if (res.error)
        throw new Error(res.error.message || '登录失败')

      // 3. 刷新用户数据
      await core.fetchUser()
      toast.showSuccess(`欢迎回来，${core.user.value?.nickname || core.user.value?.login || ''}！`)

      // 4. 跳转到个人页
      core.router.push('/tabs/me')
    }
    catch (err: unknown) {
      console.error('原生 OAuth 回调处理失败:', err)
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err) || '登录失败，请重试')
    }
    finally {
      loading.value = false
    }
  }

  const loginWithOAuth = async (provider: 'github' | 'wx_open') => {
    try {
      loading.value = true
      error.value = null

      if (Capacitor.isNativePlatform()) {
        await loginWithOAuthNative(provider)
        // 原生模式下，loading 保持到 deeplink 回调处理完毕
        return
      }

      // Web 端：走原有 SDK 自动跳转流程
      const callbackUrl = `${window.location.origin}/auth/callback`
      const { error: oauthError } = await auth.signInWithOAuth({
        provider,
        options: { redirectTo: callbackUrl },
      })
      if (oauthError)
        throw new Error(oauthError.message || 'OAuth 登录失败')
      // SDK 会自动执行 window.location.assign 跳转到授权页面
    }
    catch (err: unknown) {
      console.error(`OAuth 登录失败 (${provider}):`, err)
      loading.value = false
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err) || '登录失败，请稍后重试')
      throw err
    }
  }

  const loginWithGitHub = () => loginWithOAuth('github')
  const loginWithWeChat = () => loginWithOAuth('wx_open')

  /**
   * 解绑第三方身份源
   */
  const unlinkProvider = async (provider: string) => {
    try {
      loading.value = true
      error.value = null
      const res = await auth.unlinkIdentity({ provider })
      if (res.error)
        throw new Error(res.error.message || '解绑失败')
      await core.fetchUser()
      toast.showSuccess('已解绑')
      return true
    }
    catch (err: unknown) {
      console.error(`解绑失败 (${provider}):`, err)
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err))
      return false
    }
    finally {
      loading.value = false
    }
  }

  /**
   * 绑定第三方身份源（跳转授权）
   */
  const linkProvider = async (provider: string) => {
    try {
      loading.value = true
      error.value = null
      const res = await auth.linkIdentity({ provider })
      if (res.error)
        throw new Error(res.error.message || '绑定失败')
      // SDK 会跳转到授权页面
    }
    catch (err: unknown) {
      console.error(`绑定失败 (${provider}):`, err)
      loading.value = false
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err))
      return false
    }
  }

  return {
    loginWithOAuth,
    loginWithGitHub,
    loginWithWeChat,
    unlinkProvider,
    linkProvider,
    handleNativeOAuthCallback,
  }
}
