import { consola } from 'consola'
import { onUnmounted, ref } from 'vue'

/**
 * 短信验证码注册和登录（完整版）
 * 支持新用户注册和已有用户登录
 * @see https://docs.cloudbase.net/authentication-v2/method/sms-login
 */
export function useSmsAuth() {
  const { $tcbAuth } = useNuxtApp() as any
  if (!$tcbAuth) {
    throw new Error('CloudBase SDK 未加载')
  }

  const phoneNumber = ref('')
  const verifyCode = ref('')
  const password = ref('') // 可选，用于注册时设置密码
  const username = ref('') // 可选，用于注册时设置用户名
  const nickname = ref('') // 可选，用于注册时设置昵称

  interface VerificationInfo {
    verification_id: string
    is_user: boolean
  }

  const sendingCode = ref(false)
  const processing = ref(false)
  const countdown = ref(0)
  const verificationInfo = ref<VerificationInfo | null>(null)

  let countdownTimer: NodeJS.Timeout | null = null

  /**
   * 发送短信验证码
   */
  async function sendVerifyCode() {
    if (!phoneNumber.value) {
      consola.error('请输入手机号')
      return { success: false, message: '请输入手机号' }
    }

    // 验证手机号格式
    const phoneRegex = /^1[3-9]\d{9}$/
    if (!phoneRegex.test(phoneNumber.value)) {
      consola.error('手机号格式不正确')
      return { success: false, message: '手机号格式不正确' }
    }

    if (countdown.value > 0) {
      return { success: false, message: `请等待 ${countdown.value} 秒后重试` }
    }

    try {
      sendingCode.value = true

      // 发送短信验证码 - 需要加区号
      const phoneWithCode = `+86 ${phoneNumber.value}`
      const verification = await $tcbAuth.getVerification({
        phone_number: phoneWithCode,
      })

      // 保存验证信息，用于后续登录或注册
      verificationInfo.value = verification

      // 开始倒计时
      countdown.value = 60
      countdownTimer = setInterval(() => {
        countdown.value--
        if (countdown.value <= 0 && countdownTimer) {
          clearInterval(countdownTimer)
          countdownTimer = null
        }
      }, 1000)

      consola.success('验证码已发送')
      return {
        success: true,
        message: '验证码已发送',
        isUser: verification.is_user, // 标识该手机号是否已注册
      }
    }
    catch (error: unknown) {
      consola.error('发送验证码失败:', error)
      const message = error instanceof Error ? error.message : '发送验证码失败，请稍后重试'
      return {
        success: false,
        message,
      }
    }
    finally {
      sendingCode.value = false
    }
  }

  /**
   * 验证验证码并获取 verification_token
   */
  async function verifyVerificationCode() {
    if (!verificationInfo.value) {
      return { success: false, message: '请先获取验证码' }
    }

    if (!verifyCode.value) {
      return { success: false, message: '请输入验证码' }
    }

    try {
      // 验证验证码的正确性
      const verificationTokenRes = await $tcbAuth.verify({
        verification_id: verificationInfo.value.verification_id,
        verification_code: verifyCode.value,
      })

      return {
        success: true,
        verificationToken: verificationTokenRes.verification_token,
      }
    }
    catch (error: unknown) {
      consola.error('验证码验证失败:', error)
      const message = error instanceof Error ? error.message : '验证码验证失败'
      return {
        success: false,
        message,
      }
    }
  }

  /**
   * 短信验证码登录（已注册用户）
   */
  async function loginWithSms() {
    if (!phoneNumber.value) {
      consola.error('请输入手机号')
      return { success: false, message: '请输入手机号' }
    }

    if (!verifyCode.value) {
      consola.error('请输入验证码')
      return { success: false, message: '请输入验证码' }
    }

    if (!verificationInfo.value) {
      consola.error('请先获取验证码')
      return { success: false, message: '请先获取验证码' }
    }

    try {
      processing.value = true

      // 使用手机号和验证码登录
      await ($tcbAuth as {
        signInWithSms: (params: {
          verificationInfo: VerificationInfo
          verificationCode: string
          phoneNum: string
        }) => Promise<void>
      }).signInWithSms({
        verificationInfo: verificationInfo.value,
        verificationCode: verifyCode.value,
        phoneNum: phoneNumber.value,
      })

      // 获取当前用户信息
      const loginState = await $tcbAuth.getLoginState()

      if (loginState) {
        consola.success('登录成功')
        return {
          success: true,
          message: '登录成功',
          user: loginState.user,
        }
      }
      else {
        return { success: false, message: '登录失败' }
      }
    }
    catch (error: unknown) {
      consola.error('登录失败:', error)
      const message = error instanceof Error ? error.message : '登录失败，请检查验证码是否正确'
      return {
        success: false,
        message,
      }
    }
    finally {
      processing.value = false
    }
  }

  /**
   * 注册新用户
   */
  async function signUp() {
    if (!phoneNumber.value) {
      return { success: false, message: '请输入手机号' }
    }

    if (!verifyCode.value) {
      return { success: false, message: '请输入验证码' }
    }

    if (!verificationInfo.value) {
      return { success: false, message: '请先获取验证码' }
    }

    try {
      processing.value = true

      // 先验证验证码
      const verifyResult = await verifyVerificationCode()
      if (!verifyResult.success) {
        return verifyResult
      }

      const phoneWithCode = `+86 ${phoneNumber.value}`

      // 构建注册参数
      interface SignUpParams {
        phone_number: string
        verification_code: string
        verification_token: string
        name?: string
        password?: string
        username?: string
      }

      const signUpParams: SignUpParams = {
        phone_number: phoneWithCode,
        verification_code: verifyCode.value,
        verification_token: verifyResult.verificationToken,
      }

      // 可选参数
      if (nickname.value) {
        signUpParams.name = nickname.value
      }
      if (password.value) {
        signUpParams.password = password.value
      }
      if (username.value) {
        signUpParams.username = username.value
      }

      // 注册新用户（注册成功后会自动登录）
      await $tcbAuth.signUp(signUpParams)

      // 获取当前用户信息
      const loginState = await $tcbAuth.getLoginState()

      if (loginState) {
        consola.success('注册成功')
        return {
          success: true,
          message: '注册成功',
          user: loginState.user,
        }
      }
      else {
        return { success: false, message: '注册失败' }
      }
    }
    catch (error: unknown) {
      consola.error('注册失败:', error)
      const message = error instanceof Error ? error.message : '注册失败，请稍后重试'
      return {
        success: false,
        message,
      }
    }
    finally {
      processing.value = false
    }
  }

  /**
   * 自动处理登录或注册
   * 根据 verificationInfo.is_user 判断是登录还是注册
   */
  async function autoSignInOrUp() {
    if (!verificationInfo.value) {
      return { success: false, message: '请先获取验证码' }
    }

    // 如果用户已存在，则登录
    if (verificationInfo.value.is_user) {
      return await loginWithSms()
    }
    // 否则注册新用户
    else {
      return await signUp()
    }
  }

  /**
   * 清理定时器
   */
  function cleanup() {
    if (countdownTimer) {
      clearInterval(countdownTimer)
      countdownTimer = null
    }
  }

  // 组件卸载时清理
  onUnmounted(() => {
    cleanup()
  })

  return {
    phoneNumber,
    verifyCode,
    password,
    username,
    nickname,
    sendingCode,
    processing,
    countdown,
    verificationInfo,
    sendVerifyCode,
    loginWithSms,
    signUp,
    autoSignInOrUp,
  }
}
