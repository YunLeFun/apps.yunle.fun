import { flushPromises, mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { defineComponent, h, ref } from 'vue'

// @cloudbase/js-sdk 的 ESM 产物（@cloudbase/app/dist/esm/index.node.js）使用无扩展名子路径
// import，在 Nuxt 测试环境下会被外部化并触发 Node 原生 ESM 解析失败。组件测试已 mock
// useSmsAuth，运行时并不真正用到 SDK，这里 mock 掉模块以打断该 import 链。
vi.mock('@cloudbase/js-sdk', () => ({
  default: {
    init: () => ({
      auth: () => ({}),
      database: () => ({}),
    }),
  },
}))

// 创建可控的 mock 状态
function createMockComposable() {
  const phoneNumber = ref('')
  const verifyCode = ref('')
  const sendingCode = ref(false)
  const processing = ref(false)
  const countdown = ref(0)
  const sendVerifyCode = vi.fn().mockResolvedValue({ success: true, message: '验证码已发送' })
  const loginWithSms = vi.fn().mockResolvedValue({ success: true, message: '登录成功', user: {} })

  return {
    phoneNumber,
    verifyCode,
    sendingCode,
    processing,
    countdown,
    sendVerifyCode,
    loginWithSms,
  }
}

let mockComposable: ReturnType<typeof createMockComposable>

// Mock the composable
vi.mock('~/composables/auth/useSmsAuth', () => ({
  useSmsAuth: () => mockComposable,
}))

// Mock useToast
vi.mock('#app', async (importOriginal) => {
  const original = await importOriginal<Record<string, any>>()
  return {
    ...original,
    useRouter: () => ({ push: vi.fn() }),
  }
})

// Stub Ionic components to render as simple HTML elements
const ionStubs = {
  IonButton: defineComponent({
    props: ['expand', 'fill', 'size', 'color', 'disabled'],
    emits: ['click'],
    setup(props, { slots, emit }) {
      return () => h('button', {
        disabled: props.disabled || undefined,
        onClick: () => emit('click'),
      }, slots.default?.())
    },
  }),
  IonInput: defineComponent({
    props: ['modelValue', 'type', 'placeholder', 'maxlength'],
    emits: ['update:modelValue', 'keyup'],
    setup(props) {
      return () => h('input', {
        type: props.type || 'text',
        value: props.modelValue,
      })
    },
  }),
  IonItem: defineComponent({
    props: ['lines'],
    setup(_, { slots }) {
      return () => h('div', { class: 'ion-item' }, slots.default?.())
    },
  }),
  IonLabel: defineComponent({
    props: ['position'],
    setup(_, { slots }) {
      return () => h('label', slots.default?.())
    },
  }),
  IonIcon: defineComponent({
    props: ['icon'],
    setup() {
      return () => h('span', { class: 'icon' })
    },
  }),
  IonNote: defineComponent({
    props: ['color'],
    setup(_, { slots }) {
      return () => h('span', { class: 'note' }, slots.default?.())
    },
  }),
}

// Stub useToast composable
vi.stubGlobal('useToast', () => ({
  showSuccess: vi.fn(),
  showError: vi.fn(),
}))

describe('smsLogin.vue', () => {
  beforeEach(() => {
    mockComposable = createMockComposable()
    vi.clearAllMocks()
  })

  async function mountSmsLogin() {
    const SmsLogin = (await import('../../app/components/auth/SmsLogin.vue')).default
    return mount(SmsLogin, {
      global: {
        stubs: ionStubs,
      },
    })
  }

  it('应该正确渲染', async () => {
    const wrapper = await mountSmsLogin()
    await wrapper.vm.$nextTick()

    expect(wrapper.find('input[type="tel"]').exists()).toBe(true)
    expect(wrapper.find('input[type="text"]').exists()).toBe(true)
    expect(wrapper.findAll('button')).toHaveLength(2)
  })

  it('应该显示正确的按钮文本', async () => {
    const wrapper = await mountSmsLogin()
    await wrapper.vm.$nextTick()

    const buttons = wrapper.findAll('button')
    expect(buttons[0]!.text()).toBe('获取验证码')
    expect(buttons[1]!.text()).toBe('登录')
  })

  it('应该在发送验证码时显示加载状态', async () => {
    mockComposable.sendingCode.value = true
    mockComposable.phoneNumber.value = '13800000000'

    const wrapper = await mountSmsLogin()
    await wrapper.vm.$nextTick()

    const sendButton = wrapper.findAll('button')[0]!
    expect(sendButton.text()).toBe('发送中...')
    expect(sendButton.attributes('disabled')).toBeDefined()
  })

  it('应该在倒计时期间显示剩余时间', async () => {
    mockComposable.countdown.value = 30
    mockComposable.phoneNumber.value = '13800000000'

    const wrapper = await mountSmsLogin()
    await wrapper.vm.$nextTick()

    const sendButton = wrapper.findAll('button')[0]!
    expect(sendButton.text()).toContain('30s')
    expect(sendButton.attributes('disabled')).toBeDefined()
  })

  it('应该在登录时显示加载状态', async () => {
    mockComposable.processing.value = true
    mockComposable.phoneNumber.value = '13800000000'
    mockComposable.verifyCode.value = '123456'

    const wrapper = await mountSmsLogin()
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

    const wrapper = await mountSmsLogin()
    await wrapper.vm.$nextTick()

    const loginButton = wrapper.findAll('button')[1]!
    await loginButton.trigger('click')
    await flushPromises()
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

    const wrapper = await mountSmsLogin()
    await wrapper.vm.$nextTick()

    const sendButton = wrapper.findAll('button')[0]!
    await sendButton.trigger('click')

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

    const wrapper = await mountSmsLogin()
    await wrapper.vm.$nextTick()

    const sendButton = wrapper.findAll('button')[0]!
    await sendButton.trigger('click')

    await flushPromises()
    await wrapper.vm.$nextTick()

    expect(mockComposable.sendVerifyCode).toHaveBeenCalled()
    // 成功消息通过 toast 显示，不在 DOM 中
    expect(wrapper.text()).not.toContain('手机号格式不正确')
  })

  it('应该在手机号或验证码为空时禁用登录按钮', async () => {
    const wrapper = await mountSmsLogin()
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
