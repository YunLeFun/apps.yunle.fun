import { beforeEach, describe, expect, it, vi } from 'vitest'

// --- Mock helpers ---

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

// Mock global composables
vi.stubGlobal('useCloudbase', () => ({
  app: { database: () => mockDbSetup.db },
}))

vi.stubGlobal('useState', (key: string, init: () => any) => ref(init()))

describe('useDiscovery', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockDbSetup = createMockDb()
  })

  // 动态导入以便每次使用最新 mock
  async function loadDiscovery() {
    // 直接模拟 composable 的核心逻辑
    const { useDiscovery } = await import('../../app/composables/useDiscovery')
    return useDiscovery()
  }

  describe('loadFeatured', () => {
    it('从 CloudBase 加载今日推荐', async () => {
      const featuredRecord = {
        _id: 'feat-1',
        appId: 'valaxy',
        type: 'daily',
        title: '推荐标题',
        subtitle: '编辑精选',
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
      expect(featuredMeta.value).toEqual(featuredRecord)
      // 推荐记录的 title 覆盖原应用名称
      expect(featuredApp.value.name).toBe('推荐标题')
      expect(featuredApp.value.color).toBe('#FF0000')
    })

    it('cloudBase 无数据时回退到静态 FEATURED_APP', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { loadFeatured, featuredApp } = await loadDiscovery()
      await loadFeatured()

      // 回退到静态 FEATURED_APP（Valaxy）
      expect(featuredApp.value.id).toBe('valaxy')
      expect(featuredApp.value.name).toBe('Valaxy')
    })

    it('cloudBase 应用解析失败时回退', async () => {
      mockDbSetup.mockCollection.get
        .mockResolvedValueOnce({
          data: [{ appId: 'nonexistent', type: 'daily', isActive: true, startDate: 0, endDate: Date.now() + 86400000 }],
        })

      const { loadFeatured, featuredApp } = await loadDiscovery()
      await loadFeatured()

      // 静态应用中找不到 nonexistent，回退到 FEATURED_APP
      expect(featuredApp.value.id).toBe('valaxy')
    })
  })

  describe('loadWeeklyChart', () => {
    it('从 CloudBase 加载周榜数据', async () => {
      const chartRecords = [
        { appId: 'air-conditioner', weekStart: getTestWeekStart(), rank: 1 },
        { appId: 'valaxy', weekStart: getTestWeekStart(), rank: 2 },
      ]

      mockDbSetup.mockCollection.get.mockResolvedValue({ data: chartRecords })

      const { loadWeeklyChart, weeklyApps } = await loadDiscovery()
      await loadWeeklyChart()

      expect(mockDbSetup.db.collection).toHaveBeenCalledWith('weekly_charts')
      expect(weeklyApps.value).toHaveLength(2)
      expect(weeklyApps.value[0].id).toBe('air-conditioner')
    })

    it('cloudBase 无数据时回退到静态 ALL_APPS 前 5 个', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { loadWeeklyChart, weeklyApps } = await loadDiscovery()
      await loadWeeklyChart()

      expect(weeklyApps.value).toHaveLength(5)
    })

    it('过滤掉无法解析的应用', async () => {
      const chartRecords = [
        { appId: 'air-conditioner', weekStart: getTestWeekStart(), rank: 1 },
        { appId: 'nonexistent-app', weekStart: getTestWeekStart(), rank: 2 },
      ]

      // 第一次 get() 返回周榜数据，后续 get() 查 apps 集合时返回空（nonexistent-app 找不到）
      mockDbSetup.mockCollection.get
        .mockResolvedValueOnce({ data: chartRecords })
        .mockResolvedValue({ data: [] })

      const { loadWeeklyChart, weeklyApps } = await loadDiscovery()
      await loadWeeklyChart()

      // nonexistent-app 被过滤
      expect(weeklyApps.value).toHaveLength(1)
      expect(weeklyApps.value[0].id).toBe('air-conditioner')
    })
  })

  describe('loadAll', () => {
    it('并行加载推荐和周榜，管理 loading 状态', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { loadAll, loading } = await loadDiscovery()

      expect(loading.value).toBe(false)
      const promise = loadAll()
      // loading 应该在 loadAll 执行完毕后变回 false
      await promise
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
