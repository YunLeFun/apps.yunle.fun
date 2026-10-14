import { mockNuxtImport } from '@nuxt/test-utils/runtime'
import { flushPromises, mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { defineComponent, h, onMounted, reactive } from 'vue'
import WorkshopDetailPage from '../../app/pages/w/[id].vue'

vi.mock('@ionic/vue', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@ionic/vue')>()
  return {
    ...actual,
    onIonViewWillEnter: (callback: () => void | Promise<void>) => onMounted(callback),
  }
})

const mockGetView = vi.fn()
const mockRoute = reactive({
  params: { id: '' },
  fullPath: '/w/6MU9AG',
})

mockNuxtImport('useRoute', () => () => mockRoute)
mockNuxtImport('useUserStore', () => () => ({ isLoggedIn: true }))
mockNuxtImport('useToast', () => () => ({
  showSuccess: vi.fn(),
  showError: vi.fn(),
}))
mockNuxtImport('usePersonalWorkshop', () => () => ({
  getView: mockGetView,
  join: vi.fn(),
  leave: vi.fn(),
}))

const containerStub = defineComponent({
  setup(_, { slots }) {
    return () => h('div', slots.default?.())
  },
})

const buttonStub = defineComponent({
  emits: ['click'],
  setup(_, { emit, slots }) {
    return () => h('button', { onClick: () => emit('click') }, slots.default?.())
  },
})

const appPageLoadingStub = defineComponent({
  props: {
    label: String,
  },
  setup(props) {
    return () => h('div', { role: 'status' }, props.label)
  },
})

const stubs = {
  AppIconBox: containerStub,
  AppPageLoading: appPageLoadingStub,
  IonBackButton: containerStub,
  IonButton: buttonStub,
  IonButtons: containerStub,
  IonContent: containerStub,
  IonHeader: containerStub,
  IonIcon: containerStub,
  IonItem: containerStub,
  IonLabel: containerStub,
  IonList: containerStub,
  IonNote: containerStub,
  IonPage: containerStub,
  IonSpinner: containerStub,
  IonTitle: containerStub,
  IonToolbar: containerStub,
  UserAvatar: containerStub,
}

describe('workshop detail page', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    window.history.replaceState({}, '', '/w/6MU9AG')
    mockRoute.params.id = ''
    mockRoute.fullPath = '/w/6MU9AG'
    mockGetView.mockResolvedValue({
      access: 'active',
      workshop: {
        _id: '6MU9AG',
        ownerName: '云乐坊',
        name: '云乐坊内部工坊',
        description: '内部应用',
        joinPolicy: 'approval',
        status: 'active',
      },
      apps: [],
    })
  })

  it('finishes loading when Ionic enters before route params are synchronized', async () => {
    const wrapper = mount(WorkshopDetailPage, {
      global: { stubs },
    })

    await flushPromises()

    expect(mockGetView).toHaveBeenCalledWith('6MU9AG')
    expect(wrapper.text()).toContain('云乐坊内部工坊')
    expect(wrapper.find('[role="status"]').exists()).toBe(false)
  })
})
