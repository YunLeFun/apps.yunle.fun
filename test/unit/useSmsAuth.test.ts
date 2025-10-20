import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useSmsAuth } from '../../app/composables/wx/useSmsAuth'

describe('useSmsAuth', () => {
  let mockAuth: any
  let mockApp: any

  beforeEach(() => {
    vi.clearAllMocks()

    mockAuth = {
      getVerification: vi.fn(),
      verify: vi.fn(),
      signInWithSms: vi.fn(),
      signUp: vi.fn(),
      getLoginState: vi.fn(),
    }

    mockApp = {
      auth: vi.fn(() => mockAuth),
    }

    // @ts-expect-error mock
    globalThis.cloudbase = {
      init: vi.fn(() => mockApp),
    }

    vi.useFakeTimers()
  })

  describe('autoSignInOrUp', () => {
    it('应该在用户已存在时调用登录', async () => {
      const {
        phoneNumber,
        verifyCode,
        sendVerifyCode,
        autoSignInOrUp,
      } = useSmsAuth()

      phoneNumber.value = '13800000000'
      verifyCode.value = '123456'

      // 模拟已存在的用户
      mockAuth.getVerification.mockResolvedValue({
        verification_id: 'test-id',
        is_user: true, // 用户已存在
      })
      await sendVerifyCode()

      mockAuth.signInWithSms.mockResolvedValue({})
      mockAuth.getLoginState.mockResolvedValue({
        user: { uid: 'test-uid' },
      })

      const result = await autoSignInOrUp()

      expect(result.success).toBe(true)
      expect(mockAuth.signInWithSms).toHaveBeenCalled()
      expect(mockAuth.signUp).not.toHaveBeenCalled()
    })

    it('应该在用户不存在时调用注册', async () => {
      const {
        phoneNumber,
        verifyCode,
        nickname,
        sendVerifyCode,
        autoSignInOrUp,
      } = useSmsAuth()

      phoneNumber.value = '13800000000'
      verifyCode.value = '123456'
      nickname.value = '测试用户'

      // 模拟新用户
      mockAuth.getVerification.mockResolvedValue({
        verification_id: 'test-id',
        is_user: false, // 用户不存在
      })
      await sendVerifyCode()

      mockAuth.verify.mockResolvedValue({
        verification_token: 'test-token',
      })
      mockAuth.signUp.mockResolvedValue({})
      mockAuth.getLoginState.mockResolvedValue({
        user: { uid: 'test-uid' },
      })

      const result = await autoSignInOrUp()

      expect(result.success).toBe(true)
      expect(mockAuth.signUp).toHaveBeenCalled()
      expect(mockAuth.signInWithSms).not.toHaveBeenCalled()
    })
  })

  describe('signUp', () => {
    it('应该成功注册新用户', async () => {
      const {
        phoneNumber,
        verifyCode,
        nickname,
        password,
        username,
        sendVerifyCode,
        signUp,
      } = useSmsAuth()

      phoneNumber.value = '13800000000'
      verifyCode.value = '123456'
      nickname.value = '测试用户'
      password.value = 'password123'
      username.value = 'testuser'

      mockAuth.getVerification.mockResolvedValue({
        verification_id: 'test-id',
        is_user: false,
      })
      await sendVerifyCode()

      mockAuth.verify.mockResolvedValue({
        verification_token: 'test-token',
      })
      mockAuth.signUp.mockResolvedValue({})
      mockAuth.getLoginState.mockResolvedValue({
        user: { uid: 'test-uid' },
      })

      const result = await signUp()

      expect(result.success).toBe(true)
      expect(result.message).toBe('注册成功')
      expect(mockAuth.signUp).toHaveBeenCalledWith({
        phone_number: '+86 13800000000',
        verification_code: '123456',
        verification_token: 'test-token',
        name: '测试用户',
        password: 'password123',
        username: 'testuser',
      })
    })

    it('应该支持仅使用手机号注册', async () => {
      const {
        phoneNumber,
        verifyCode,
        sendVerifyCode,
        signUp,
      } = useSmsAuth()

      phoneNumber.value = '13800000000'
      verifyCode.value = '123456'

      mockAuth.getVerification.mockResolvedValue({
        verification_id: 'test-id',
        is_user: false,
      })
      await sendVerifyCode()

      mockAuth.verify.mockResolvedValue({
        verification_token: 'test-token',
      })
      mockAuth.signUp.mockResolvedValue({})
      mockAuth.getLoginState.mockResolvedValue({
        user: { uid: 'test-uid' },
      })

      const result = await signUp()

      expect(result.success).toBe(true)
      expect(mockAuth.signUp).toHaveBeenCalledWith({
        phone_number: '+86 13800000000',
        verification_code: '123456',
        verification_token: 'test-token',
      })
    })

    it('应该处理注册失败的情况', async () => {
      const {
        phoneNumber,
        verifyCode,
        sendVerifyCode,
        signUp,
      } = useSmsAuth()

      phoneNumber.value = '13800000000'
      verifyCode.value = '123456'

      mockAuth.getVerification.mockResolvedValue({
        verification_id: 'test-id',
        is_user: false,
      })
      await sendVerifyCode()

      mockAuth.verify.mockResolvedValue({
        verification_token: 'test-token',
      })
      mockAuth.signUp.mockRejectedValue(new Error('注册失败'))

      const result = await signUp()

      expect(result.success).toBe(false)
      expect(result.message).toContain('注册失败')
    })
  })

  describe('verifyVerificationCode', () => {
    it('应该成功验证验证码', async () => {
      const {
        phoneNumber,
        verifyCode,
        sendVerifyCode,
        signUp,
      } = useSmsAuth()

      phoneNumber.value = '13800000000'
      verifyCode.value = '123456'

      mockAuth.getVerification.mockResolvedValue({
        verification_id: 'test-id',
        is_user: false,
      })
      await sendVerifyCode()

      mockAuth.verify.mockResolvedValue({
        verification_token: 'test-token',
      })

      // 通过 signUp 间接测试 verifyVerificationCode
      mockAuth.signUp.mockResolvedValue({})
      mockAuth.getLoginState.mockResolvedValue({
        user: { uid: 'test-uid' },
      })

      await signUp()

      expect(mockAuth.verify).toHaveBeenCalledWith({
        verification_id: 'test-id',
        verification_code: '123456',
      })
    })
  })
})
