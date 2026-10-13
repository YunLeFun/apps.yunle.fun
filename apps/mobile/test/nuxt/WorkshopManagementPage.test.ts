import { mockNuxtImport } from '@nuxt/test-utils/runtime'
import { flushPromises, mount } from '@vue/test-utils'
import QRCode from 'qrcode'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { defineComponent, h, onMounted } from 'vue'
import WorkshopManagementPage from '../../app/pages/user/workshop.vue'

vi.mock('@ionic/vue', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@ionic/vue')>()
  return {
    ...actual,
    onIonViewWillEnter: (callback: () => void | Promise<void>) => onMounted(callback),
  }
})

vi.mock('qrcode', () => ({
  default: {
    toDataURL: vi.fn().mockResolvedValue('data:image/png;base64,workshop'),
  },
}))

const mockGetManagement = vi.fn()

mockNuxtImport('usePersonalWorkshop', () => () => ({
  create: vi.fn(),
  decide: vi.fn(),
  getManagement: mockGetManagement,
  update: vi.fn(),
}))

mockNuxtImport('useToast', () => () => ({
  showError: vi.fn(),
  showSuccess: vi.fn(),
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
  IonInput: containerStub,
  IonItem: containerStub,
  IonLabel: containerStub,
  IonList: containerStub,
  IonNote: containerStub,
  IonPage: containerStub,
  IonSelect: containerStub,
  IonSelectOption: containerStub,
  IonSpinner: containerStub,
  IonTextarea: containerStub,
  IonTitle: containerStub,
  IonToolbar: containerStub,
  UserAvatar: containerStub,
}

describe('workshop management page', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockGetManagement.mockResolvedValue({
      workshop: {
        _id: 'EJ83N5',
        ownerUid: 'owner-1',
        ownerName: '坊主',
        name: '灵感工坊',
        description: '分享有趣的云应用',
        joinPolicy: 'approval',
        status: 'active',
      },
      pending: [],
      guests: [],
      blocked: [],
    })
  })

  it('renders the stable public HTTPS share URL', async () => {
    const wrapper = mount(WorkshopManagementPage, {
      global: { stubs },
    })
    await flushPromises()

    expect(wrapper.text()).toContain('https://apps.yunle.fun/w/EJ83N5')
    expect(wrapper.text()).not.toContain('capacitor://localhost')
    expect(wrapper.text()).toContain('二维码固定使用 apps.yunle.fun 在线地址')
    expect(QRCode.toDataURL).toHaveBeenCalledWith(
      'https://apps.yunle.fun/w/EJ83N5',
      expect.any(Object),
    )
  })
})
