import type { Ref } from 'vue'
import type { AgentChatMessage } from '../../app/types/agent'
import { mockNuxtImport } from '@nuxt/test-utils/runtime'
import { flushPromises, mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { computed, defineComponent, h, ref } from 'vue'

const mockPush = vi.fn()
const mockEnsureLoaded = vi.fn()
const mockRefresh = vi.fn()
const mockSendMessage = vi.fn()
const mockRetryLast = vi.fn()
const mockStop = vi.fn()
const mockReset = vi.fn()

interface MockUserStore {
  isLoggedIn: boolean
  userInfo: {
    id: string
    nickname: string
    avatar: string
  }
}

function createMockUserStore(isLoggedIn = true): MockUserStore {
  return {
    isLoggedIn,
    userInfo: {
      id: isLoggedIn ? 'user-1' : '',
      nickname: isLoggedIn ? 'tester' : '',
      avatar: '',
    },
  }
}

let mockUserStore = createMockUserStore()
let mockCatalog: Ref<unknown[]>
let mockAccount: Ref<unknown>
let mockIsMember: Ref<boolean>
let mockMessages: Ref<AgentChatMessage[]>
let mockInput: Ref<string>
let mockRunning: Ref<boolean>
let mockReasoning: Ref<boolean>
let mockError: Ref<string | null>
let mockConfigurationReady: Ref<boolean>
let mockCanSend: Ref<boolean>

mockNuxtImport('useUserStore', () => () => mockUserStore)
mockNuxtImport('useAppCatalog', () => () => ({
  catalog: mockCatalog,
  ensureLoaded: mockEnsureLoaded,
}))
mockNuxtImport('useCoin', () => () => ({
  account: mockAccount,
  isMember: mockIsMember,
  refresh: mockRefresh,
}))
mockNuxtImport('useAgentChat', () => () => ({
  input: mockInput,
  messages: mockMessages,
  hasMessages: computed(() => mockMessages.value.length > 0),
  running: mockRunning,
  reasoning: mockReasoning,
  error: mockError,
  configurationReady: mockConfigurationReady,
  canSend: mockCanSend,
  sendMessage: mockSendMessage,
  retryLast: mockRetryLast,
  stop: mockStop,
  reset: mockReset,
}))

const ionStubs = {
  IonButton: defineComponent({
    props: ['disabled', 'shape'],
    emits: ['click'],
    setup(props, { attrs, emit, slots }) {
      return () => h('button', {
        ...attrs,
        disabled: props.disabled || undefined,
        onClick: () => emit('click'),
      }, slots.default?.())
    },
  }),
  IonTextarea: defineComponent({
    props: ['modelValue', 'placeholder'],
    emits: ['update:modelValue', 'keydown'],
    setup(props, { attrs, emit }) {
      return () => h('textarea', {
        ...attrs,
        value: props.modelValue,
        placeholder: props.placeholder,
        onInput: (event: Event) => emit('update:modelValue', (event.target as HTMLTextAreaElement).value),
        onKeydown: (event: KeyboardEvent) => emit('keydown', event),
      })
    },
  }),
  IonIcon: defineComponent({
    props: ['icon'],
    setup(_, { attrs }) {
      return () => h('span', { ...attrs, class: ['ion-icon', attrs.class] })
    },
  }),
  IonSpinner: defineComponent({
    props: ['name'],
    setup() {
      return () => h('span', { class: 'ion-spinner' })
    },
  }),
  AgentMessageBubble: defineComponent({
    props: {
      message: {
        type: Object,
        required: true,
      },
    },
    setup(props) {
      return () => {
        const message = props.message as AgentChatMessage
        return h('div', { class: 'agent-message-stub' }, [
          h('p', message.content),
          ...(message.appCards ?? []).map(card => h('span', { class: 'agent-card-stub' }, card.name)),
        ])
      }
    },
  }),
  AgentAppCard: defineComponent({
    props: {
      card: {
        type: Object,
        required: true,
      },
    },
    setup(props) {
      return () => h('article', { class: 'agent-sample-card-stub' }, (props.card as { name?: string }).name)
    },
  }),
}

describe('agent screen', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.spyOn(useRouter(), 'push').mockImplementation((to) => {
      mockPush(to)
      return Promise.resolve()
    })
    mockUserStore = createMockUserStore()
    mockCatalog = ref([])
    mockAccount = ref({ coin: 100, membership: { isActive: true, level: 'basic', expireAt: Date.now() + 1000 } })
    mockIsMember = ref(true)
    mockMessages = ref([])
    mockInput = ref('')
    mockRunning = ref(false)
    mockReasoning = ref(false)
    mockError = ref(null)
    mockConfigurationReady = ref(true)
    mockCanSend = ref(true)
    mockEnsureLoaded.mockResolvedValue(undefined)
    mockRefresh.mockResolvedValue(undefined)
    mockSendMessage.mockResolvedValue(true)
    mockRetryLast.mockResolvedValue(true)
  })

  async function mountScreen() {
    const AgentScreen = (await import('../../app/components/agent/Screen.vue')).default
    const wrapper = mount(AgentScreen, {
      global: {
        stubs: ionStubs,
      },
    })

    await flushPromises()
    await wrapper.vm.$nextTick()
    return wrapper
  }

  it('routes logged-in non-members to the membership page from the locked action', async () => {
    mockIsMember.value = false

    const wrapper = await mountScreen()
    await wrapper.find('.agent-status-action').trigger('click')

    expect(mockPush).toHaveBeenCalledWith('/membership')
  })

  it('routes logged-out users to login from the locked action', async () => {
    mockUserStore = createMockUserStore(false)
    mockIsMember.value = false

    const wrapper = await mountScreen()
    await wrapper.find('.agent-status-action').trigger('click')

    expect(mockPush).toHaveBeenCalledWith('/login')
  })

  it('sends the current prompt from the input bar', async () => {
    mockInput.value = '找一个开发工具'

    const wrapper = await mountScreen()
    await wrapper.find('.agent-send-button').trigger('click')

    expect(mockSendMessage).toHaveBeenCalledWith()
  })

  it('renders streamed assistant cards from messages', async () => {
    mockMessages.value = [
      { id: 'u1', role: 'user', content: '找开发工具', status: 'done' },
      {
        id: 'a1',
        role: 'assistant',
        content: '推荐这个',
        status: 'done',
        appCards: [
          { slug: 'code-helper', name: 'Code Helper', reason: '适合写代码' },
        ],
      },
    ]

    const wrapper = await mountScreen()

    expect(wrapper.text()).toContain('推荐这个')
    expect(wrapper.find('.agent-card-stub').text()).toContain('Code Helper')
  })

  it('retries the last prompt from the error bar', async () => {
    mockMessages.value = [
      { id: 'u1', role: 'user', content: '找应用', status: 'done' },
    ]
    mockError.value = 'AI 助手暂时不可用'

    const wrapper = await mountScreen()
    await wrapper.find('.agent-error-bar button').trigger('click')

    expect(mockRetryLast).toHaveBeenCalled()
  })
})
