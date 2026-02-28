/**
 * OAuth 第三方登录 / 绑定 / 解绑
 * 参考 www.yunle.fun 的 useOAuth.ts，适配 Ionic Toast
 */
import { getErrorMessage } from '@yunlefun/auth'

export function useCloudbaseOAuth(core: ReturnType<typeof useCloudbaseAuthCore>) {
  const { auth, loading, error, toast } = core

  const loginWithOAuth = async (provider: 'github' | 'wx_open') => {
    try {
      loading.value = true
      error.value = null

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
  }
}
