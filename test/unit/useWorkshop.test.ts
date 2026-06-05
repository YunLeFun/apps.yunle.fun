import type { YlfAppInfo } from '~~/packages/types'
import { beforeEach, describe, expect, it, vi } from 'vitest'

// --- Mock ~/constants/apps ---
// 用可控的小集合替换 ALL_APPS，便于精确断言「静态优先 + CloudBase 后台合并」分页逻辑。
// mockApps 是稳定引用，setMockApps 原地替换内容，import 绑定始终指向同一数组。
const { mockApps, mockCategories } = vi.hoisted(() => ({
  mockApps: [] as YlfAppInfo[],
  mockCategories: [
    { id: 'all', name: '全部', icon: '📱' },
    { id: 'interesting', name: '整活', icon: '🤣' },
    { id: 'tools', name: '工具', icon: '🔧' },
    { id: 'design', name: '设计', icon: '🎨' },
  ],
}))

vi.mock('~/constants/apps', () => ({
  ALL_APPS: mockApps,
  APP_CATEGORIES: mockCategories,
}))

function setMockApps(apps: YlfAppInfo[]) {
  mockApps.length = 0
  mockApps.push(...apps)
}

/** 构造一个静态应用（YlfAppInfo） */
function makeApp(slug: string, category: string): YlfAppInfo {
  return {
    id: slug,
    slug,
    name: `App ${slug}`,
    description: `desc ${slug}`,
    emoji: '📱',
    color: '#000000',
    url: `https://example.com/${slug}`,
    category,
  }
}

/** 构造一条 CloudBase 原始记录（AppRecord 形态） */
function makeDbApp(slug: string, updatedAt: number) {
  return {
    _id: slug,
    slug,
    name: `Cloud ${slug}`,
    description: '',
    category: '整活',
    isPublic: true,
    status: 'approved',
    updatedAt,
  }
}

/** 等待所有微任务结算（后台 fetchDbPage 的 get + 合并完成） */
function flushPromises() {
  return new Promise(resolve => setTimeout(resolve, 0))
}

// --- Mock helpers ---

function createMockDb() {
  const mockCollection = {
    where: vi.fn().mockReturnThis(),
    orderBy: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
    skip: vi.fn().mockReturnThis(),
    get: vi.fn(),
    RegExp: vi.fn((opts: any) => ({ $regex: opts.regexp, $options: opts.options })),
  }
  const db = {
    collection: vi.fn(() => mockCollection),
    RegExp: vi.fn((opts: any) => ({ $regex: opts.regexp, $options: opts.options })),
  }
  return { db, mockCollection }
}

let mockDbSetup: ReturnType<typeof createMockDb>

vi.stubGlobal('useCloudbase', () => ({
  app: { database: () => mockDbSetup.db },
}))

vi.stubGlobal('useState', (key: string, init: () => any) => ref(init()))

// Mock useDebounceFn to execute immediately
vi.mock('@vueuse/core', () => ({
  useDebounceFn: (fn: () => void) => fn,
}))

describe('useWorkshop', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockDbSetup = createMockDb()
    // 默认静态集合：覆盖各分类，满足「回退到静态数据」相关断言
    setMockApps([
      makeApp('joke-1', '整活'),
      makeApp('joke-2', '整活'),
      makeApp('tool-1', '工具'),
      makeApp('design-1', '设计'),
    ])
  })

  async function loadWorkshop() {
    const { useWorkshop } = await import('../../app/composables/useWorkshop')
    return useWorkshop()
  }

  describe('queryApps', () => {
    it('首屏来自静态数据，CloudBase 后台以 limit 50 去重合并', async () => {
      // 静态 3 条，cloud 返回 2 条不同 slug
      setMockApps([
        makeApp('s1', '整活'),
        makeApp('s2', '整活'),
        makeApp('s3', '整活'),
      ])
      const cloudApps = [makeDbApp('cloud-1', 1000), makeDbApp('cloud-2', 900)]
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: cloudApps })

      const { queryApps, apps, loadMore, initialized } = await loadWorkshop()
      await queryApps(true)

      // 首屏：仅静态数据，cloud 尚未进入展示
      expect(apps.value.map(a => a.slug)).toEqual(['s1', 's2', 's3'])
      expect(initialized.value).toBe(true)

      // cloud 查询契约：where / collection / limit=50（不是旧实现的 20）
      expect(mockDbSetup.db.collection).toHaveBeenCalledWith('apps')
      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({ isPublic: true, status: 'approved' })
      expect(mockDbSetup.mockCollection.limit).toHaveBeenCalledWith(50)

      // 等后台合并完成，loadMore 才会展示 cloud 数据
      await flushPromises()
      loadMore()
      await flushPromises()

      expect(apps.value.map(a => a.slug)).toEqual(['s1', 's2', 's3', 'cloud-1', 'cloud-2'])
    })

    it('cloudBase 无数据时回退到静态 ALL_APPS', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { queryApps, apps } = await loadWorkshop()
      await queryApps(true)

      // fallback 到静态数据
      expect(apps.value.length).toBeGreaterThan(0)
    })

    it('分类筛选传入正确条件', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { queryApps, selectedCategory } = await loadWorkshop()
      selectedCategory.value = '工具'
      await queryApps(true)

      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({
        isPublic: true,
        status: 'approved',
        category: '工具',
      })
    })

    it('搜索时传入正则条件', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { queryApps, searchQuery } = await loadWorkshop()
      searchQuery.value = 'test'
      await queryApps(true)

      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith(
        expect.objectContaining({
          isPublic: true,
          status: 'approved',
          name: expect.any(Object),
        }),
      )
    })

    it('cloudBase 分页查询使用 skip=0 与 limit=50', async () => {
      // 静态置空，专注 cloud 查询契约
      setMockApps([])
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { queryApps } = await loadWorkshop()
      await queryApps(true)

      expect(mockDbSetup.mockCollection.skip).toHaveBeenCalledWith(0)
      expect(mockDbSetup.mockCollection.limit).toHaveBeenCalledWith(50)
    })

    it('loadMore 从候选列表切出下一页并追加', async () => {
      // 静态 25 条 → 首屏展示 PAGE_SIZE(20)，loadMore 再展示剩余 5 条
      setMockApps(Array.from({ length: 25 }, (_, i) => makeApp(`s${i}`, '整活')))
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { queryApps, apps, hasMore, loadMore } = await loadWorkshop()
      await queryApps(true)
      expect(apps.value).toHaveLength(20)
      expect(hasMore.value).toBe(true)

      await flushPromises() // cloud 无数据，dbFetched=true
      loadMore()
      await flushPromises()

      expect(apps.value).toHaveLength(25)
      expect(hasMore.value).toBe(false)
    })

    it('reset=true 时清空旧数据并以静态数据重新填充', async () => {
      setMockApps([makeApp('s1', '整活'), makeApp('s2', '整活')])
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { queryApps, apps } = await loadWorkshop()

      // 模拟已有旧数据
      apps.value = [{ id: 'old', slug: 'old', name: 'Old' } as any]

      await queryApps(true)

      expect(apps.value.map(a => a.slug)).toEqual(['s1', 's2'])
      expect(apps.value.find(a => a.slug === 'old')).toBeUndefined()
    })
  })

  describe('changeCategory', () => {
    it('切换分类时重新查询', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { changeCategory, selectedCategory } = await loadWorkshop()
      await changeCategory('设计')

      expect(selectedCategory.value).toBe('设计')
      // 应触发了一次查询
      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith(
        expect.objectContaining({ category: '设计' }),
      )
    })
  })

  describe('loadMore', () => {
    it('候选耗尽且 CloudBase 仍有数据时触发下一页 DB 查询', async () => {
      // 纯 CloudBase 分页场景：静态置空
      setMockApps([])
      // 首页满页（=DB_PAGE_SIZE 50）→ dbFetched 保持 false，表示仍有下一页
      const dbPage1 = Array.from({ length: 50 }, (_, i) => makeDbApp(`a${i}`, 1000 - i))
      const dbPage2 = Array.from({ length: 5 }, (_, i) => makeDbApp(`b${i}`, 500 - i))
      mockDbSetup.mockCollection.get
        .mockResolvedValueOnce({ data: dbPage1 })
        .mockResolvedValueOnce({ data: dbPage2 })

      const { queryApps, loadMore, hasMore, apps } = await loadWorkshop()
      await queryApps(true)
      await flushPromises()
      expect(mockDbSetup.mockCollection.get).toHaveBeenCalledTimes(1)

      // 连续 loadMore 切片展示候选；剩余不足一页且 cloud 未拉完时触发第二次 DB 查询
      while (hasMore.value && mockDbSetup.mockCollection.get.mock.calls.length < 2) {
        loadMore()
        await flushPromises()
      }

      expect(mockDbSetup.mockCollection.get).toHaveBeenCalledTimes(2)
      // 第二次查询 skip 推进到首页末尾（dbOffset=50）
      expect(mockDbSetup.mockCollection.skip).toHaveBeenLastCalledWith(50)
      expect(apps.value).toHaveLength(55)
    })

    it('无更多数据时不触发查询', async () => {
      setMockApps([
        makeApp('s1', '整活'),
        makeApp('s2', '整活'),
        makeApp('s3', '整活'),
      ])
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] }) // cloud 无数据

      const { queryApps, loadMore, hasMore, apps } = await loadWorkshop()
      await queryApps(true)
      await flushPromises()
      expect(apps.value).toHaveLength(3)
      expect(mockDbSetup.mockCollection.get).toHaveBeenCalledTimes(1)

      // 候选已展示完 + CloudBase 已拉完 → 这次 loadMore 收敛 hasMore=false（不再触发 DB 查询）
      loadMore()
      await flushPromises()
      expect(hasMore.value).toBe(false)
      expect(mockDbSetup.mockCollection.get).toHaveBeenCalledTimes(1)

      // hasMore=false 后再 loadMore 不应触发任何查询
      loadMore()
      await flushPromises()
      expect(mockDbSetup.mockCollection.get).toHaveBeenCalledTimes(1)
    })
  })

  describe('categories', () => {
    it('提供分类列表', async () => {
      const { categories } = await loadWorkshop()
      expect(categories.length).toBeGreaterThan(0)
      expect(categories[0].name).toBe('全部')
    })
  })

  describe('静态数据回退', () => {
    it('搜索无结果时返回空', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { queryApps, apps, searchQuery } = await loadWorkshop()
      searchQuery.value = 'zzzznonexistent999'
      await queryApps(true)

      // 静态搜索也找不到匹配
      expect(apps.value).toHaveLength(0)
    })

    it('分类筛选回退到静态数据', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { queryApps, apps, selectedCategory } = await loadWorkshop()
      selectedCategory.value = '整活'
      await queryApps(true)

      // 静态数据中应该有「整活」分类的应用
      expect(apps.value.length).toBeGreaterThan(0)
      expect(apps.value.every(a => a.category === '整活')).toBe(true)
    })
  })
})
