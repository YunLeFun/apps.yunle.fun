import type { YlfAppInfo } from '@yunlefun/types'
import type { AppRecord } from '../../app/types/app'
import type { WorkshopPublicInfo, WorkshopView } from '../../app/types/workshop'
import { mockNuxtImport } from '@nuxt/test-utils/runtime'
import { flushPromises, mount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { computed, defineComponent, h, onMounted, ref } from 'vue'
import WorkshopAppsPage from '../../app/pages/tabs/apps.vue'
import { getAvailableBrowseCategories } from '../../app/utils/appBrowseCategories'

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
const mockGetView = vi.fn()
const searchQuery = ref('')
const selectedCategory = ref('全部')
const mockChangeCategory = vi.fn((category: string) => {
  selectedCategory.value = category
})
const mockDebouncedSearch = vi.fn()
const publicCatalog = ref<YlfAppInfo[]>([])
const publicTotalCount = ref(27)
const publicLoading = ref(false)

mockNuxtImport('useWorkshop', () => () => ({
  searchQuery,
  selectedCategory,
  categories: computed(() => getAvailableBrowseCategories(publicCatalog.value)),
  totalCount: publicTotalCount,
  loading: publicLoading,
  apps: publicCatalog,
  hasMore: ref(false),
  initialized: ref(true),
  loadMore: vi.fn(),
  changeCategory: mockChangeCategory,
  debouncedSearch: mockDebouncedSearch,
  queryApps: mockQueryApps,
}))
mockNuxtImport('useUserStore', () => () => ({ isLoggedIn: true }))
mockNuxtImport('usePersonalWorkshop', () => () => ({
  getJoined: mockGetJoined,
  getManagement: mockGetManagement,
  getView: mockGetView,
}))
mockNuxtImport('useAppCatalog', () => () => ({ catalog: publicCatalog }))
mockNuxtImport('useScanBridge', () => () => ({ navigateToScan: vi.fn() }))
mockNuxtImport('useWorkshopScan', () => () => ({ handleScanResult: vi.fn() }))

const containerStub = defineComponent({
  setup(_, { slots }) {
    return () => h('div', slots.default?.())
  },
})

const buttonStub = defineComponent({
  emits: ['click'],
  setup(_, { emit, slots }) {
    return () => h('button', { type: 'button', onClick: () => emit('click') }, slots.default?.())
  },
})

const modalStub = defineComponent({
  props: { isOpen: Boolean },
  setup(props, { slots }) {
    return () => props.isOpen ? h('section', { role: 'dialog' }, slots.default?.()) : null
  },
})

const stubs = {
  AppIconBox: containerStub,
  AppInstallButton: containerStub,
  IonButton: buttonStub,
  IonButtons: containerStub,
  IonContent: containerStub,
  IonHeader: containerStub,
  IonIcon: containerStub,
  IonLabel: containerStub,
  IonModal: modalStub,
  IonPage: containerStub,
  IonSearchbar: containerStub,
  IonSegment: containerStub,
  IonSegmentButton: containerStub,
  IonSpinner: containerStub,
  IonTitle: containerStub,
  IonToolbar: containerStub,
}

function app(id: string, name: string, category: string): YlfAppInfo {
  return {
    id,
    slug: id,
    name,
    category,
    description: `${name}的应用介绍`,
    emoji: '📱',
    themeColor: '#007AFF',
    websiteUrl: `https://example.com/${id}`,
  }
}

function record(id: string, name: string, category: string, audience: AppRecord['audience'] = 'workshop'): AppRecord {
  return {
    _id: id,
    slug: id,
    name,
    category,
    audience,
    ownerLogin: 'owner',
    isPublic: audience === 'public',
    status: 'approved',
    createdAt: 1,
    updatedAt: 1,
  }
}

const ownedWorkshop: WorkshopPublicInfo = {
  _id: 'owned-workshop',
  ownerName: '坊主',
  name: '个人设计工坊',
  joinPolicy: 'approval',
  status: 'active',
}
const joinedWorkshop: WorkshopPublicInfo = {
  ...ownedWorkshop,
  _id: 'joined-workshop',
  name: '朋友的工坊',
}
const views: Record<string, WorkshopView> = {
  [ownedWorkshop._id]: {
    surface: 'workshop',
    access: 'owner',
    workshop: ownedWorkshop,
    apps: [
      record('shared-note', '重复的公开便签', '工具'),
      record('private-canvas', '专属画板', '设计'),
      record('private-note', '专属便签', '效率工具'),
    ],
  },
  [joinedWorkshop._id]: {
    surface: 'workshop',
    access: 'active',
    workshop: joinedWorkshop,
    apps: [
      record('private-canvas', '重复的专属画板', '设计'),
      record('workshop-game', '工坊小游戏', '游戏', 'public'),
    ],
  },
}

const mountedWrappers: ReturnType<typeof mount>[] = []

async function mountPage() {
  const wrapper = mount(WorkshopAppsPage, { global: { stubs } })
  mountedWrappers.push(wrapper)
  await flushPromises()
  return wrapper
}

async function selectScope(wrapper: Awaited<ReturnType<typeof mountPage>>, name: string) {
  await wrapper.get('button[aria-label="切换工坊"]').trigger('click')
  const option = wrapper.get('[role="dialog"]').findAll('button').find(button => button.find('strong').exists() && button.get('strong').text() === name)
  expect(option, `scope option ${name}`).toBeDefined()
  await option!.trigger('click')
  await flushPromises()
  expect(wrapper.find('[role="dialog"]').exists()).toBe(false)
}

function displayedNames(wrapper: Awaited<ReturnType<typeof mountPage>>) {
  return wrapper.findAll('button[aria-label^="查看"]').map(button => button.attributes('aria-label')?.slice(2))
}

describe('workshop apps page', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.spyOn(useRouter(), 'push').mockImplementation((to) => {
      mockPush(to)
      return Promise.resolve()
    })
    localStorage.removeItem('ylf:workshop-scope:v1')
    useState<string>('workshop:selected-scope').value = 'public'
    searchQuery.value = ''
    selectedCategory.value = '全部'
    publicCatalog.value = [app('shared-note', '公开便签', '工具'), app('public-canvas', '公开画布', '设计')]
    publicTotalCount.value = 27
    publicLoading.value = false
    mockQueryApps.mockResolvedValue(undefined)
    mockGetJoined.mockResolvedValue([])
    mockGetManagement.mockResolvedValue(null)
    mockGetView.mockImplementation(async (id: string) => views[id])
  })

  afterEach(() => {
    mountedWrappers.splice(0).forEach(wrapper => wrapper.unmount())
    localStorage.removeItem('ylf:workshop-scope:v1')
  })

  it('opens personal workshop setup from the manage action when no workshop exists', async () => {
    const wrapper = await mountPage()
    await wrapper.get('button[aria-label="切换工坊"]').trigger('click')
    const manageButton = wrapper.get('[role="dialog"]').findAll('button').find(button => button.text() === '开启工坊')
    await manageButton!.trigger('click')

    expect(mockPush).toHaveBeenCalledWith('/user/workshop')
  })

  it('passes public category and search actions to the catalog and reports the complete result count', async () => {
    const wrapper = await mountPage()

    expect(displayedNames(wrapper)).toEqual(['公开便签', '公开画布'])
    expect(wrapper.get('[role="status"]').text()).toBe('27 款应用')

    await wrapper.get('button[title="效率工具"]').trigger('click')
    expect(mockChangeCategory).toHaveBeenCalledWith('效率工具')
    expect(wrapper.get('h1').text()).toBe('效率工具')
    expect(wrapper.get('button[title="效率工具"]').attributes('aria-pressed')).toBe('true')

    await wrapper.get('input[aria-label="搜索应用"]').setValue('便签')
    expect(mockDebouncedSearch).toHaveBeenCalledTimes(1)
    expect(wrapper.get('h1').text()).toBe('搜索结果')
    expect(wrapper.get<HTMLInputElement>('input[aria-label="搜索应用"]').element.value).toBe('便签')

    await wrapper.get('button[aria-label="清除搜索"]').trigger('click')
    expect(mockDebouncedSearch).toHaveBeenCalledTimes(2)
    expect(wrapper.get<HTMLInputElement>('input[aria-label="搜索应用"]').element.value).toBe('')
    expect(wrapper.get('h1').text()).toBe('效率工具')
    expect(wrapper.find('button[aria-label="清除搜索"]').exists()).toBe(false)
  })

  it('filters a personal workshop without losing exclusive badges and resets an unavailable category after a scope switch', async () => {
    mockGetJoined.mockResolvedValue([joinedWorkshop])
    mockGetManagement.mockResolvedValue({ workshop: ownedWorkshop })
    const wrapper = await mountPage()
    await selectScope(wrapper, ownedWorkshop.name)

    expect(wrapper.get('[role="status"]').text()).toBe('3 款应用')
    expect(wrapper.findAll('.catalog-private-badge')).toHaveLength(3)
    expect(wrapper.get('input[aria-label="搜索应用"]').attributes('placeholder')).toBe('搜索个人设计工坊中的应用')

    await wrapper.get('button[title="效率工具"]').trigger('click')
    expect(displayedNames(wrapper)).toEqual(['重复的公开便签', '专属便签'])
    expect(wrapper.get('[role="status"]').text()).toBe('2 款应用')

    await wrapper.get('input[aria-label="搜索应用"]').setValue('专属')
    expect(displayedNames(wrapper)).toEqual(['专属便签'])
    expect(wrapper.get('[role="status"]').text()).toBe('1 款应用')
    expect(wrapper.findAll('.catalog-private-badge')).toHaveLength(1)
    expect(mockDebouncedSearch).not.toHaveBeenCalled()

    await wrapper.get('button[aria-label="清除搜索"]').trigger('click')
    expect(displayedNames(wrapper)).toEqual(['重复的公开便签', '专属便签'])
    expect(wrapper.get('[role="status"]').text()).toBe('2 款应用')

    await selectScope(wrapper, joinedWorkshop.name)
    expect(wrapper.get('h1').text()).toBe('全部应用')
    expect(wrapper.get('button[title="全部"]').attributes('aria-pressed')).toBe('true')
    expect(wrapper.get('[role="status"]').text()).toBe('2 款应用')
    expect(mockChangeCategory).not.toHaveBeenCalled()

    await wrapper.get('input[aria-label="搜索应用"]').setValue('找不到的应用')
    expect(displayedNames(wrapper)).toEqual([])
    expect(wrapper.get('[role="status"]').text()).toBe('0 款应用')
    expect(wrapper.text()).toContain('没有匹配的应用')
  })

  it('deduplicates public and joined apps in all scope while retaining source names and exclusive badges', async () => {
    mockGetJoined.mockResolvedValue([ownedWorkshop, joinedWorkshop])
    mockGetManagement.mockResolvedValue({ workshop: ownedWorkshop })
    const wrapper = await mountPage()
    await selectScope(wrapper, '全部动态')

    expect(wrapper.get('button[aria-label="切换工坊"]').text()).toContain('3 个工坊')
    expect(wrapper.get('[role="status"]').text()).toBe('5 款应用')
    expect(displayedNames(wrapper)).toEqual(['公开便签', '公开画布', '专属画板', '专属便签', '工坊小游戏'])
    expect(wrapper.text()).not.toContain('重复的公开便签')
    expect(wrapper.text()).not.toContain('重复的专属画板')
    expect(wrapper.findAll('.catalog-private-badge')).toHaveLength(2)
    expect(wrapper.findAll('.catalog-source-name').map(source => source.text())).toEqual([
      '云乐坊',
      '云乐坊',
      ownedWorkshop.name,
      ownedWorkshop.name,
      joinedWorkshop.name,
    ])
    expect(wrapper.get('button[title="全部"]').text()).toContain('5')
    expect(wrapper.get('button[title="创意设计"]').text()).toContain('2')

    await wrapper.get('button[title="创意设计"]').trigger('click')
    expect(displayedNames(wrapper)).toEqual(['公开画布', '专属画板'])
    expect(wrapper.get('[role="status"]').text()).toBe('2 款应用')
    expect(wrapper.findAll('.catalog-private-badge')).toHaveLength(1)

    await wrapper.get('input[aria-label="搜索应用"]').setValue('专属')
    expect(displayedNames(wrapper)).toEqual(['专属画板'])
    expect(wrapper.get('[role="status"]').text()).toBe('1 款应用')
    expect(wrapper.get('.catalog-source-name').text()).toBe(ownedWorkshop.name)
  })
})
