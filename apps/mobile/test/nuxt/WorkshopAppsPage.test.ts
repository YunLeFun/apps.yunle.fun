import { mockNuxtImport } from '@nuxt/test-utils/runtime'
import { flushPromises, mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { defineComponent, h, onMounted, ref } from 'vue'
import WorkshopAppsPage from '../../app/pages/tabs/apps.vue'

vi.mock('@ionic/vue', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@ionic/vue')>()
  return {
    ...actual,
    onIonViewWillEnter: (callback: () => void | Promise<void>) => onMounted(callback),
  }
})

const mockPush = vi.fn()
const mockQueryApps = vi.fn()
const mockGetJoined = vi.fn()
const mockGetManagement = vi.fn()

mockNuxtImport('useWorkshop', () => () => ({
  searchQuery: ref(''),
  selectedCategory: ref('全部'),
  categories: [],
  changeCategory: vi.fn(),
  debouncedSearch: vi.fn(),
  queryApps: mockQueryApps,
}))
mockNuxtImport('useUserStore', () => () => ({ isLoggedIn: true }))
mockNuxtImport('usePersonalWorkshop', () => () => ({
  getJoined: mockGetJoined,
  getManagement: mockGetManagement,
  getView: vi.fn(),
}))
mockNuxtImport('useAppCatalog', () => () => ({ catalog: ref([]) }))
mockNuxtImport('useScanBridge', () => () => ({ navigateToScan: vi.fn() }))
mockNuxtImport('useWorkshopScan', () => () => ({ handleScanResult: vi.fn() }))

const containerStub = defineComponent({
  setup(_, { slots }) {
    return () => h('div', slots.default?.())
  },
})

const pickerStub = defineComponent({
  emits: ['manage'],
  setup(_, { emit }) {
    return () => h('button', {
      'type': 'button',
      'data-testid': 'manage-workshops',
      'onClick': () => emit('manage'),
    }, '管理入口')
  },
})

const stubs = {
  AppList: containerStub,
  IonButton: containerStub,
  IonButtons: containerStub,
  IonContent: containerStub,
  IonHeader: containerStub,
  IonIcon: containerStub,
  IonLabel: containerStub,
  IonPage: containerStub,
  IonSearchbar: containerStub,
  IonSegment: containerStub,
  IonSegmentButton: containerStub,
  IonToolbar: containerStub,
  WorkshopAppList: containerStub,
  WorkshopPickerSheet: pickerStub,
}

describe('workshop apps page', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.spyOn(useRouter(), 'push').mockImplementation((to) => {
      mockPush(to)
      return Promise.resolve()
    })
    useState<string>('workshop:selected-scope').value = 'public'
    mockQueryApps.mockResolvedValue(undefined)
    mockGetJoined.mockResolvedValue([])
    mockGetManagement.mockResolvedValue(null)
  })

  it('opens personal workshop setup from the manage action when no workshop exists', async () => {
    const wrapper = mount(WorkshopAppsPage, {
      global: { stubs },
    })
    await flushPromises()

    await wrapper.get('[data-testid="manage-workshops"]').trigger('click')

    expect(mockPush).toHaveBeenCalledWith('/user/workshop')
  })
})
