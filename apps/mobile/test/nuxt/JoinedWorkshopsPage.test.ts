import { mockNuxtImport } from '@nuxt/test-utils/runtime'
import { flushPromises, mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { defineComponent, h, onMounted } from 'vue'
import JoinedWorkshopsPage from '../../app/pages/user/workshops.vue'

vi.mock('@ionic/vue', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@ionic/vue')>()
  return {
    ...actual,
    onIonViewWillEnter: (callback: () => void | Promise<void>) => onMounted(callback),
  }
})

const mockGetJoined = vi.fn()

mockNuxtImport('usePersonalWorkshop', () => () => ({
  getJoined: mockGetJoined,
}))

const containerStub = defineComponent({
  setup(_, { slots }) {
    return () => h('div', slots.default?.())
  },
})

const buttonStub = defineComponent({
  emits: ['click'],
  setup(_, { emit, slots }) {
    return () => h('button', {
      type: 'button',
      onClick: () => emit('click'),
    }, slots.default?.())
  },
})

const stubs = {
  AppPageLoading: containerStub,
  IonBackButton: containerStub,
  IonButton: buttonStub,
  IonButtons: containerStub,
  IonContent: containerStub,
  IonHeader: containerStub,
  IonIcon: containerStub,
  IonItem: containerStub,
  IonLabel: containerStub,
  IonList: containerStub,
  IonPage: containerStub,
  IonTitle: containerStub,
  IonToolbar: containerStub,
}

describe('joined workshops page', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockGetJoined.mockRejectedValue(new Error('网络连接失败'))
  })

  it('shows a retryable error instead of a misleading empty state', async () => {
    const wrapper = mount(JoinedWorkshopsPage, {
      global: { stubs },
    })
    await flushPromises()

    expect(wrapper.text()).toContain('无法加载已加入的工坊')
    expect(wrapper.text()).toContain('网络连接失败')
    expect(wrapper.text()).not.toContain('还没有加入个人工坊')
    expect(wrapper.get('button').text()).toContain('重试')
  })
})
