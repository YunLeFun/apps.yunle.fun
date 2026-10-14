import { mockNuxtImport } from '@nuxt/test-utils/runtime'
import { flushPromises, mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { defineComponent, h, reactive, ref } from 'vue'
import HomePage from '../../app/pages/tabs/home.vue'

const privateApp = {
  id: 'private-app-id',
  slug: 'private-app',
  name: '私人工坊应用',
  websiteUrl: 'https://private.example.com/',
}

const homeScreenStore = reactive({
  installedApps: [{ appId: privateApp.slug }],
  dockApps: [],
  recentApps: [],
  isEditMode: false,
  installApp: vi.fn(),
  uninstallApp: vi.fn(),
  updateInstalledApps: vi.fn((apps) => {
    homeScreenStore.installedApps = apps
  }),
  updateDockApps: vi.fn(),
  initWithDefaults: vi.fn(),
  enterEditMode: vi.fn(),
})

const publicCatalog = ref([{
  id: 'public-app-id',
  slug: 'public-app',
  name: '公开应用',
  websiteUrl: 'https://public.example.com/',
}])
const accessibleApps = ref<typeof publicCatalog.value>([])
const ensureAccessibleLoaded = vi.fn(async () => {
  accessibleApps.value = [privateApp]
})

mockNuxtImport('useHomeScreenStore', () => () => homeScreenStore)
mockNuxtImport('useSettingsStore', () => () => ({
  dockVisible: false,
  initTheme: vi.fn(),
}))
mockNuxtImport('useUserStore', () => () => ({
  userInfo: { id: 'user-1' },
}))
mockNuxtImport('useHomeScreen', () => () => ({
  loadFromCloud: vi.fn(),
  reloadForAccount: vi.fn(),
  recordRecentUse: vi.fn(),
  uninstallApp: vi.fn(),
  installApp: vi.fn(),
  removeRecentApp: vi.fn(),
  updateDock: vi.fn(),
  finishEditing: vi.fn(),
  syncToCloud: vi.fn(),
}))
mockNuxtImport('useAppActions', () => () => ({ shareApp: vi.fn() }))
mockNuxtImport('useOpenApp', () => () => ({ openApp: vi.fn() }))
mockNuxtImport('useAppCatalog', () => () => ({
  catalog: publicCatalog,
  ensureLoaded: vi.fn(),
  ensureAccessibleLoaded,
  getApp: (key: string) => [...accessibleApps.value, ...publicCatalog.value]
    .find(app => app.id === key || app.slug === key),
}))
mockNuxtImport('useRecentDrag', () => () => ({
  dragPosition: ref({ x: 0, y: 0 }),
  isDragging: ref(false),
  dragApp: ref(null),
  activeDropZone: ref(null),
  startDrag: vi.fn(),
}))
mockNuxtImport('useScanBridge', () => () => ({ navigateToScan: vi.fn() }))
mockNuxtImport('useScanResult', () => () => ({ handleScanResult: vi.fn() }))

const containerStub = defineComponent({
  setup(_, { slots }) {
    return () => h('div', slots.default?.())
  },
})

const gridStub = defineComponent({
  props: { apps: Array },
  setup(props) {
    return () => h('div', { 'data-testid': 'home-grid' }, JSON.stringify(props.apps))
  },
})

const stubs = {
  AppContextMenu: containerStub,
  AppHomeScreenDock: containerStub,
  AppHomeScreenGrid: gridStub,
  AppIconBox: containerStub,
  AppItem: containerStub,
  AppRecentDropZone: containerStub,
  AppRunningEntry: containerStub,
  IonButton: containerStub,
  IonButtons: containerStub,
  IonContent: containerStub,
  IonHeader: containerStub,
  IonIcon: containerStub,
  IonItem: containerStub,
  IonLabel: containerStub,
  IonList: containerStub,
  IonPage: containerStub,
  IonPopover: containerStub,
  IonSearchbar: containerStub,
  IonTitle: containerStub,
  IonToolbar: containerStub,
}

describe('home page private workshop apps', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    accessibleApps.value = []
    homeScreenStore.installedApps = [{ appId: privateApp.slug }]
  })

  it('loads accessible workshop metadata before resolving installed apps', async () => {
    const wrapper = mount(HomePage, {
      global: { stubs },
    })

    await flushPromises()

    expect(ensureAccessibleLoaded).toHaveBeenCalledWith('user-1')
    expect(homeScreenStore.installedApps).toContainEqual({ appId: privateApp.slug })
    expect(wrapper.get('[data-testid="home-grid"]').text()).toContain(privateApp.slug)
  })
})
