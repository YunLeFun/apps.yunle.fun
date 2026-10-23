/**
 * OTP 验证码登录（手机号/邮箱）
 * 参考 www.yunle.fun 的 useOtp.ts，适配全局 AppToast
 */
import { getErrorMessage } from '@yunlefun/auth'
import { useAppsAuthAcquisition } from './useAppsAcquisition'

/** OTP data type - 从 CloudBase Auth SDK 返回 */
export type TcbOtpData = Awaited<ReturnType<ReturnType<typeof useCloudbase>['auth']['signInWithOtp']>>['data']
export type TcbSignUpData = Awaited<ReturnType<ReturnType<typeof useCloudbase>['auth']['signUp']>>['data']

export function useCloudbaseOtp(core: ReturnType<typeof useCloudbaseAuthCore>) {
  const { auth, router, toast, loading, error, fetchUser } = core
  const { beginAuthentication, recordAfterAuthentication } = useAppsAuthAcquisition(core)

  const sendPhoneOtp = async (phone: string) => {
    try {
      loading.value = true
      error.value = null
      beginAuthentication('phone_otp')
      const { data, error: otpError } = await auth.signInWithOtp({ phone })
      if (otpError)
        throw new Error(otpError.message || '发送验证码失败')
      toast.showSuccess('验证码已发送，请查看手机短信')
      return data
    }
    catch (err: unknown) {
      console.error('发送验证码失败:', err)
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err) || '发送失败，请稍后重试')
      throw err
    }
    finally {
      loading.value = false
    }
  }

  const verifyPhoneOtp = async (otpData: TcbOtpData, token: string) => {
    try {
      loading.value = true
      error.value = null
      if (!otpData?.verifyOtp)
        throw new Error('OTP 验证回调不可用')
      const { error: verifyError } = await otpData.verifyOtp({ token })
      if (verifyError)
        throw new Error(verifyError.message || '验证码验证失败')
      await fetchUser()
      await recordAfterAuthentication()
      toast.showSuccess('登录成功，欢迎回来！')
      await router.replace('/tabs/me')
    }
    catch (err: unknown) {
      console.error('验证失败:', err)
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err) || '验证码错误或已过期')
      throw err
    }
    finally {
      loading.value = false
    }
  }

  const sendEmailOtp = async (email: string) => {
    try {
      loading.value = true
      error.value = null
      beginAuthentication('email_otp')
      const { data, error: otpError } = await auth.signInWithOtp({ email })
      if (otpError)
        throw new Error(otpError.message || '发送验证码失败')
      toast.showSuccess('验证码已发送，请查看邮箱')
      return data
    }
    catch (err: unknown) {
      console.error('发送邮箱验证码失败:', err)
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err) || '发送失败，请稍后重试')
      throw err
    }
    finally {
      loading.value = false
    }
  }

  const verifyEmailOtp = async (otpData: TcbOtpData, token: string) => {
    try {
      loading.value = true
      error.value = null
      if (!otpData?.verifyOtp)
        throw new Error('OTP 验证回调不可用')
      const { error: verifyError } = await otpData.verifyOtp({ token })
      if (verifyError)
        throw new Error(verifyError.message || '验证码验证失败')
      await fetchUser()
      await recordAfterAuthentication()
      toast.showSuccess('登录成功，欢迎回来！')
      await router.replace('/tabs/me')
    }
    catch (err: unknown) {
      console.error('邮箱验证失败:', err)
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err) || '验证码错误或已过期')
      throw err
    }
    finally {
      loading.value = false
    }
  }

  const signUpWithPhone = async (phone: string) => {
    try {
      loading.value = true
      error.value = null
      beginAuthentication('phone_otp')
      const { data, error: signUpError } = await auth.signUp({ phone } as Parameters<typeof auth.signUp>[0])
      if (signUpError)
        throw new Error(signUpError.message || '注册失败')
      toast.showSuccess('验证码已发送，请查看手机短信')
      return data
    }
    catch (err: unknown) {
      console.error('注册失败:', err)
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err) || '注册失败，请稍后重试')
      throw err
    }
    finally {
      loading.value = false
    }
  }

  const verifySignUpOtp = async (signUpData: TcbSignUpData, token: string) => {
    try {
      loading.value = true
      error.value = null
      if (!signUpData?.verifyOtp)
        throw new Error('注册验证回调不可用')
      const { error: verifyError } = await signUpData.verifyOtp({ token })
      if (verifyError)
        throw new Error(verifyError.message || '验证码验证失败')
      await fetchUser()
      await recordAfterAuthentication()
      toast.showSuccess('注册成功，欢迎加入！')
      await router.replace('/tabs/me')
    }
    catch (err: unknown) {
      console.error('注册验证失败:', err)
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err) || '验证码错误或已过期')
      throw err
    }
    finally {
      loading.value = false
    }
  }

  const signInWithPassword = async (params: { email?: string, phone?: string, username?: string, password: string }) => {
    try {
      loading.value = true
      error.value = null
      const email = params.email?.trim()
      const phone = params.phone?.trim()
      const username = params.username?.trim()
      const credentials = email
        ? { email, password: params.password }
        : phone
          ? { phone, password: params.password }
          : username
            ? { username, password: params.password }
            : null
      if (!credentials)
        throw new Error('请输入用户名、邮箱或手机号')
      if (!params.password)
        throw new Error('请输入密码')
      beginAuthentication('unknown')
      const { error: signInError } = await auth.signInWithPassword(credentials)
      if (signInError)
        throw new Error(signInError.message || '密码登录失败')
      await fetchUser()
      await recordAfterAuthentication()
      toast.showSuccess('登录成功，欢迎回来！')
      await router.replace('/tabs/me')
    }
    catch (err: unknown) {
      console.error('密码登录失败:', err)
      error.value = getErrorMessage(err)
      toast.showError(getErrorMessage(err) || '用户名/邮箱/手机号或密码错误')
      throw err
    }
    finally {
      loading.value = false
    }
  }

  return {
    sendPhoneOtp,
    verifyPhoneOtp,
    sendEmailOtp,
    verifyEmailOtp,
    signUpWithPhone,
    verifySignUpOtp,
    signInWithPassword,
  }
}
