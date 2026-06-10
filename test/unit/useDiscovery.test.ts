import type { YlfAppInfo } from '@yunlefun/types'
import { beforeEach, describe, expect, it, vi } from 'vitest'

// --- Mock ~/constants/apps ---
// 用可控的小集合替换静态兜底数据（FEATURED_APP / ALL_APPS），便于精确断言回退行为。
const { mockAllApps, mockFeaturedApp } = vi.hoisted(() => {
  function make(slug: string) {
    return {
      id: slug,
      slug,
      name: `App ${slug}`,
      emoji: '📱',
      themeColor: '#000000',
      websiteUrl: `https://example.com/${slug}`,
      category: '整活',
    }
  }
  return {
    mockFeaturedApp: {
      id: 'valaxy',
      slug: 'valaxy',
      name: 'Valaxy',
      emoji: '🌌',
      themeColor: '#0078e7',
      websiteUrl: 'https://valaxy.yyj.moe',
      category: '应用',
      subtitle: '编辑精选',
      tagline: '新一代静态博客框架',
    },
    mockAllApps: ['a1', 'a2', 'a3', 'a4', 'a5', 'a6'].map(make),
  }
})

vi.mock('~/constants/apps', () => ({
  ALL_APPS: mockAllApps,
  FEATURED_APP: mockFeaturedApp,
}))

/** 构造一个目录应用（YlfAppInfo） */
function makeApp(slug: string, overrides: Partial<YlfAppInfo> = {}): YlfAppInfo {
  return {
    id: slug,
    slug,
    name: `App ${slug}`,
    emoji: '📱',
    themeColor: '#000000',
    websiteUrl: `https://example.com/${slug}`,
    category: '整活',
    ...overrides,
  }
}

// --- Mock helpers ---

// CloudBase db 仅服务 featured_apps / weekly_charts 集合（apps 集合已收敛到 useAppCatalog）
function createMockDb() {
  const mockCollection = {
    where: vi.fn().mockReturnThis(),
    orderBy: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
    get: vi.fn(),
  }
  const db = {
    collection: vi.fn(() => mockCollection),
    command: {
      lte: vi.fn((v: any) => ({ $lte: v })),
      gte: vi.fn((v: any) => ({ $gte: v })),
    },
  }
  return { db, mockCollection }
}

let mockDbSetup: ReturnType<typeof createMockDb>

vi.stubGlobal('useCloudbase', () => ({
  app: { database: () => mockDbSetup.db },
}))

vi.stubGlobal('useState', (key: string, init: () => any) => ref(init()))

// --- stub useAppCatalog（应用解析统一走 catalog.getApp，集合优先 + 内置兜底在其内部保证） ---

interface CatalogStub {
  getApp: ReturnType<typeof vi.fn>
  ensureLoaded: ReturnType<typeof vi.fn>
}

let catalogApps: YlfAppInfo[]
let catalogStub: CatalogStub

vi.stubGlobal('useAppCatalog', () => catalogStub)

describe('useDiscovery', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockDbSetup = createMockDb()
    // 目录中可解析的应用
    catalogApps = [
      makeApp('valaxy', { name: 'Valaxy', themeColor: '#0078e7', subtitle: '编辑精选', tagline: '新一代静态博客框架' }),
      makeApp('air-conditioner', { name: '云空调' }),
    ]
    catalogStub = {
      getApp: vi.fn((idOrSlug: string) =>
        catalogApps.find(a => a.slug === idOrSlug || a.id === idOrSlug)),
      ensureLoaded: vi.fn().mockResolvedValue(undefined),
    }
  })

  // 动态导入以便每次使用最新 mock
  async function loadDiscovery() {
    const { useDiscovery } = await import('../../app/composables/useDiscovery')
    return useDiscovery()
  }

  describe('loadFeatured', () => {
    it('从 CloudBase 加载今日推荐并通过 catalog.getApp 解析', async () => {
      const featuredRecord = {
        _id: 'feat-1',
        appId: 'valaxy',
        type: 'daily',
        title: '推荐标题',
        subtitle: '今日精选',
        tagline: '推荐标语',
        coverColor: '#FF0000',
        isActive: true,
        startDate: Date.now() - 1000,
        endDate: Date.now() + 86400000,
      }

      mockDbSetup.mockCollection.get.mockResolvedValue({
        data: [featuredRecord],
      })

      const { loadFeatured, featuredApp, featuredMeta } = await loadDiscovery()
      await loadFeatured()

      expect(mockDbSetup.db.collection).toHaveBeenCalledWith('featured_apps')
      expect(catalogStub.getApp).toHaveBeenCalledWith('valaxy')
      expect(featuredMeta.value).toEqual(featuredRecord)
      // 推荐记录的 meta 字段覆盖目录应用信息
      expect(featuredApp.value.name).toBe('推荐标题')
      expect(featuredApp.value.subtitle).toBe('今日精选')
      expect(featuredApp.value.tagline).toBe('推荐标语')
      expect(featuredApp.value.themeColor).toBe('#FF0000')
      // 未覆盖字段保留目录应用原值
      expect(featuredApp.value.slug).toBe('valaxy')
    })

    it('推荐记录未填写覆盖字段时保留目录应用原值', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({
        data: [{
          appId: 'valaxy',
          type: 'daily',
          isActive: true,
          startDate: 0,
          endDate: Date.now() + 86400000,
        }],
      })

      const { loadFeatured, featuredApp } = await loadDiscovery()
      await loadFeatured()

      expect(featuredApp.value.name).toBe('Valaxy')
      expect(featuredApp.value.themeColor).toBe('#0078e7')
    })

    it('cloudBase 无数据时回退到静态 FEATURED_APP', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { loadFeatured, featuredApp } = await loadDiscovery()
      await loadFeatured()

      expect(featuredApp.value).toEqual(mockFeaturedApp)
    })

    it('catalog.getApp 解析失败时回退到 FEATURED_APP', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({
        data: [{ appId: 'nonexistent', type: 'daily', isActive: true, startDate: 0, endDate: Date.now() + 86400000 }],
      })

      const { loadFeatured, featuredApp } = await loadDiscovery()
      await loadFeatured()

      expect(catalogStub.getApp).toHaveBeenCalledWith('nonexistent')
      expect(featuredApp.value).toEqual(mockFeaturedApp)
    })

    it('查询失败时静默回退到 FEATURED_APP', async () => {
      const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {})
      mockDbSetup.mockCollection.get.mockRejectedValue(new Error('network down'))

      const { loadFeatured, featuredApp } = await loadDiscovery()
      await loadFeatured()

      expect(featuredApp.value).toEqual(mockFeaturedApp)
      warnSpy.mockRestore()
    })
  })

  describe('loadWeeklyChart', () => {
    it('从 CloudBase 加载周榜并通过 catalog 解析应用', async () => {
      const chartRecords = [
        { appId: 'air-conditioner', weekStart: getTestWeekStart(), rank: 1 },
        { appId: 'valaxy', weekStart: getTestWeekStart(), rank: 2 },
      ]

      mockDbSetup.mockCollection.get.mockResolvedValue({ data: chartRecords })

      const { loadWeeklyChart, weeklyApps } = await loadDiscovery()
      await loadWeeklyChart()

      expect(mockDbSetup.db.collection).toHaveBeenCalledWith('weekly_charts')
      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({ weekStart: getTestWeekStart() })
      expect(mockDbSetup.mockCollection.limit).toHaveBeenCalledWith(10)
      expect(weeklyApps.value).toHaveLength(2)
      expect(weeklyApps.value.map(a => a.id)).toEqual(['air-conditioner', 'valaxy'])
    })

    it('过滤掉目录中无法解析的应用', async () => {
      const chartRecords = [
        { appId: 'air-conditioner', weekStart: getTestWeekStart(), rank: 1 },
        { appId: 'nonexistent-app', weekStart: getTestWeekStart(), rank: 2 },
      ]

      mockDbSetup.mockCollection.get.mockResolvedValue({ data: chartRecords })

      const { loadWeeklyChart, weeklyApps } = await loadDiscovery()
      await loadWeeklyChart()

      // nonexistent-app 被过滤
      expect(weeklyApps.value).toHaveLength(1)
      expect(weeklyApps.value[0].id).toBe('air-conditioner')
    })

    it('cloudBase 无数据时回退到静态 ALL_APPS 前 5 个', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { loadWeeklyChart, weeklyApps } = await loadDiscovery()
      await loadWeeklyChart()

      expect(weeklyApps.value).toEqual(mockAllApps.slice(0, 5))
    })

    it('查询失败时静默回退到 ALL_APPS 前 5 个', async () => {
      const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {})
      mockDbSetup.mockCollection.get.mockRejectedValue(new Error('network down'))

      const { loadWeeklyChart, weeklyApps } = await loadDiscovery()
      await loadWeeklyChart()

      expect(weeklyApps.value).toEqual(mockAllApps.slice(0, 5))
      warnSpy.mockRestore()
    })
  })

  describe('loadAll', () => {
    it('先 ensureLoaded 应用目录，再加载推荐与周榜', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { loadAll, loading, error } = await loadDiscovery()

      expect(loading.value).toBe(false)
      await loadAll()

      expect(catalogStub.ensureLoaded).toHaveBeenCalledTimes(1)
      // ensureLoaded 先于 featured/weekly 的 DB 查询执行
      expect(catalogStub.ensureLoaded.mock.invocationCallOrder[0])
        .toBeLessThan(mockDbSetup.db.collection.mock.invocationCallOrder[0])
      expect(loading.value).toBe(false)
      expect(error.value).toBeNull()
    })

    it('ensureLoaded 抛错时记录 error 并保证 fallback 数据', async () => {
      catalogStub.ensureLoaded.mockRejectedValue(new Error('boom'))

      const { loadAll, loading, error, featuredApp, weeklyApps } = await loadDiscovery()
      await loadAll()

      expect(error.value).toBe('boom')
      expect(featuredApp.value).toEqual(mockFeaturedApp)
      expect(weeklyApps.value).toEqual(mockAllApps.slice(0, 5))
      expect(loading.value).toBe(false)
    })
  })
})

/** 计算当周周一 00:00 时间戳（与 useDiscovery 中保持一致） */
function getTestWeekStart(): number {
  const now = new Date()
  const day = now.getDay()
  const diff = now.getDate() - day + (day === 0 ? -6 : 1)
  const monday = new Date(now.getFullYear(), now.getMonth(), diff)
  monday.setHours(0, 0, 0, 0)
  return monday.getTime()
}
