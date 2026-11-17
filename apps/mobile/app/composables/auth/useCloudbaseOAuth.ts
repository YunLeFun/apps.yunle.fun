/**
 * OAuth 第三方登录 / 绑定 / 解绑
 * 参考 www.yunle.fun 的 useOAuth.ts，适配全局 AppToast
 */
import { getErrorMessage } from '@yunlefun/auth'
import { useAppsAuthAcquisition } from './useAppsAcquisition'

export function useCloudbaseOAuth(core: ReturnType<typeof useCloudbaseAuthCore>) {
  const { auth, loading, error, toast } = core
  const { beginAuthentication, bindOAuthState } = useAppsAuthAcquisition(core)

  const loginWithOAuth = async (provider: 'github' | 'wx_open') => {
    try {
      loading.value = true
      error.value = null

      const callbackUrl = `${window.location.origin}/auth/callback`
      const state = `apps-${provider}_${globalThis.crypto?.randomUUID?.() || Math.random().toString(36).slice(2)}`
      const attempt = beginAuthentication(provider, state)
      const { data, error: oauthError } = await auth.signInWithOAuth({
        provider,
        options: { redirectTo: callbackUrl, state, skipBrowserRedirect: true },
      })
      if (oauthError)
        throw new Error(oauthError.message || 'OAuth 登录失败')
      if (!data?.url)
        throw new Error('未获取到授权地址')
      bindOAuthState(attempt.id, readReturnedOAuthState(data.url, state))
      window.location.assign(data.url)
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
  }
}

function readReturnedOAuthState(url: string, requested: string) {
  try {
    return new URL(url).searchParams.get('state') || requested
  }
  catch {
    return requested
  }
}
