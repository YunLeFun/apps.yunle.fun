import { flushPromises, mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ref } from 'vue'
import SmsLogin from '../../app/components/auth/SmsLogin.vue'

// 创建可控的 mock 状态
function createMockComposable() {
  const phoneNumber = ref('')
  const verifyCode = ref('')
  const sendingCode = ref(false)
  const loggingIn = ref(false)
  const countdown = ref(0)
  const sendVerifyCode = vi.fn().mockResolvedValue({ success: true, message: '验证码已发送' })
  const loginWithSms = vi.fn().mockResolvedValue({ success: true, message: '登录成功', user: {} })

  return {
    phoneNumber,
    verifyCode,
    sendingCode,
    loggingIn,
    countdown,
    sendVerifyCode,
    loginWithSms,
  }
}

let mockComposable: ReturnType<typeof createMockComposable>

// Mock composable
vi.mock('../../app/composables/wx/useSmsLogin', () => ({
  useSmsLogin: () => mockComposable,
}))

describe('smsLogin.vue', () => {
  beforeEach(() => {
    mockComposable = createMockComposable()
    vi.clearAllMocks()
  })

  it('应该正确渲染', () => {
    const wrapper = mount(SmsLogin)

    expect(wrapper.find('input[type="tel"]').exists()).toBe(true)
    expect(wrapper.find('input[type="text"]').exists()).toBe(true)
    expect(wrapper.findAll('button')).toHaveLength(2) // 获取验证码 + 登录
  })

  it('应该显示正确的按钮文本', async () => {
    const wrapper = mount(SmsLogin)
    await wrapper.vm.$nextTick()

    const buttons = wrapper.findAll('button')
    expect(buttons[0]!.text()).toBe('获取验证码')
    expect(buttons[1]!.text()).toBe('登录')
  })

  it('应该在发送验证码时显示加载状态', async () => {
    mockComposable.sendingCode.value = true
    mockComposable.phoneNumber.value = '13800000000'

    const wrapper = mount(SmsLogin)
    await wrapper.vm.$nextTick()

    const sendButton = wrapper.findAll('button')[0]!
    expect(sendButton.text()).toBe('发送中...')
    expect(sendButton.attributes('disabled')).toBeDefined()
  })

  it('应该在倒计时期间显示剩余时间', async () => {
    mockComposable.countdown.value = 30
    mockComposable.phoneNumber.value = '13800000000'

    const wrapper = mount(SmsLogin)
    await wrapper.vm.$nextTick()

    const sendButton = wrapper.findAll('button')[0]!
    expect(sendButton.text()).toBe('30s')
    expect(sendButton.attributes('disabled')).toBeDefined()
  })

  it('应该在登录时显示加载状态', async () => {
    mockComposable.loggingIn.value = true
    mockComposable.phoneNumber.value = '13800000000'
    mockComposable.verifyCode.value = '123456'

    const wrapper = mount(SmsLogin)
    await wrapper.vm.$nextTick()

    const loginButton = wrapper.findAll('button')[1]!
    expect(loginButton.text()).toBe('登录中...')
    expect(loginButton.attributes('disabled')).toBeDefined()
  })

  it('应该在登录成功时触发 success 事件', async () => {
    mockComposable.phoneNumber.value = '13800000000'
    mockComposable.verifyCode.value = '123456'

    const mockUser = { uid: 'test-uid', phone: '13800000000' }
    mockComposable.loginWithSms.mockResolvedValue({
      success: true,
      message: '登录成功',
      user: mockUser,
    })

    const wrapper = mount(SmsLogin)
    await wrapper.vm.$nextTick()

    const loginButton = wrapper.findAll('button')[1]!
    await loginButton.trigger('click')
    await wrapper.vm.$nextTick()

    expect(mockComposable.loginWithSms).toHaveBeenCalled()
    expect(wrapper.emitted('success')).toBeTruthy()
    expect(wrapper.emitted('success')?.[0]).toEqual([mockUser])
  })

  it('应该显示错误消息', async () => {
    mockComposable.phoneNumber.value = '123'
    mockComposable.sendVerifyCode.mockResolvedValue({
      success: false,
      message: '手机号格式不正确',
    })

    const wrapper = mount(SmsLogin)
    await wrapper.vm.$nextTick()

    const sendButton = wrapper.findAll('button')[0]!
    await sendButton.trigger('click')

    // 等待所有 Promise 完成
    await flushPromises()
    await wrapper.vm.$nextTick()

    expect(mockComposable.sendVerifyCode).toHaveBeenCalled()
    expect(wrapper.text()).toContain('手机号格式不正确')
  })

  it('应该显示成功消息', async () => {
    mockComposable.phoneNumber.value = '13800000000'
    mockComposable.sendVerifyCode.mockResolvedValue({
      success: true,
      message: '验证码已发送',
    })

    const wrapper = mount(SmsLogin)
    await wrapper.vm.$nextTick()

    const sendButton = wrapper.findAll('button')[0]!
    await sendButton.trigger('click')

    // 等待所有 Promise 完成
    await flushPromises()
    await wrapper.vm.$nextTick()

    expect(mockComposable.sendVerifyCode).toHaveBeenCalled()
    expect(wrapper.text()).toContain('验证码已发送')
  })

  it('应该在手机号或验证码为空时禁用登录按钮', async () => {
    const wrapper = mount(SmsLogin)
    await wrapper.vm.$nextTick()

    const loginButton = wrapper.findAll('button')[1]!
    expect(loginButton.attributes('disabled')).toBeDefined()

    // 只输入手机号
    mockComposable.phoneNumber.value = '13800000000'
    await wrapper.vm.$nextTick()
    expect(loginButton.attributes('disabled')).toBeDefined()

    // 输入验证码
    mockComposable.verifyCode.value = '123456'
    await wrapper.vm.$nextTick()
    expect(loginButton.attributes('disabled')).toBeUndefined()
  })
})
