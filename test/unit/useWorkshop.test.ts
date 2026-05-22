import { beforeEach, describe, expect, it, vi } from 'vitest'

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
  })

  async function loadWorkshop() {
    const { useWorkshop } = await import('../../app/composables/useWorkshop')
    return useWorkshop()
  }

  describe('queryApps', () => {
    it('首次加载从 CloudBase 查询公开应用', async () => {
      const cloudApps = [
        { _id: 'c1', name: 'Cloud App 1', slug: 'cloud-1', description: 'Desc 1', isPublic: true, category: '工具', updatedAt: 1000 },
        { _id: 'c2', name: 'Cloud App 2', slug: 'cloud-2', description: 'Desc 2', isPublic: true, category: '工具', updatedAt: 900 },
      ]
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: cloudApps })

      const { queryApps, apps, initialized } = await loadWorkshop()
      await queryApps(true)

      expect(mockDbSetup.db.collection).toHaveBeenCalledWith('apps')
      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({ isPublic: true, status: 'approved' })
      expect(apps.value).toHaveLength(2)
      expect(apps.value[0].id).toBe('c1')
      expect(apps.value[0].name).toBe('Cloud App 1')
      expect(initialized.value).toBe(true)
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

    it('分页查询带正确的 skip 和 limit', async () => {
      const page1 = Array.from({ length: 20 }, (_, i) => ({
        _id: `p1-${i}`,
        name: `App ${i}`,
        slug: `app-${i}`,
        description: '',
        isPublic: true,
        updatedAt: 1000 - i,
      }))

      mockDbSetup.mockCollection.get.mockResolvedValue({ data: page1 })

      const { queryApps, apps, hasMore } = await loadWorkshop()
      await queryApps(true)

      expect(apps.value).toHaveLength(20)
      expect(hasMore.value).toBe(true)
      expect(mockDbSetup.mockCollection.skip).toHaveBeenCalledWith(0)
      expect(mockDbSetup.mockCollection.limit).toHaveBeenCalledWith(20)
    })

    it('加载更多时追加数据', async () => {
      const page1 = Array.from({ length: 20 }, (_, i) => ({
        _id: `p1-${i}`,
        name: `App ${i}`,
        slug: `app-${i}`,
        description: '',
        isPublic: true,
        updatedAt: 1000,
      }))
      const page2 = Array.from({ length: 5 }, (_, i) => ({
        _id: `p2-${i}`,
        name: `App P2 ${i}`,
        slug: `app-p2-${i}`,
        description: '',
        isPublic: true,
        updatedAt: 900,
      }))

      mockDbSetup.mockCollection.get
        .mockResolvedValueOnce({ data: page1 })
        .mockResolvedValueOnce({ data: page2 })

      const { queryApps, apps, hasMore } = await loadWorkshop()
      await queryApps(true) // 第一页
      expect(apps.value).toHaveLength(20)

      await queryApps(false) // 第二页
      expect(apps.value).toHaveLength(25)
      expect(hasMore.value).toBe(false) // 不足 20 条，无更多
    })

    it('reset=true 时清空旧数据', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({
        data: [{ _id: 'new', name: 'New', slug: 'new', description: '', isPublic: true, updatedAt: 1 }],
      })

      const { queryApps, apps } = await loadWorkshop()

      // 模拟已有旧数据
      apps.value = [{ id: 'old', name: 'Old' } as any]

      await queryApps(true)

      expect(apps.value).toHaveLength(1)
      expect(apps.value[0].id).toBe('new')
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
    it('有更多数据时触发查询', async () => {
      const page1 = Array.from({ length: 20 }, (_, i) => ({
        _id: `${i}`,
        name: `App ${i}`,
        slug: `a-${i}`,
        description: '',
        isPublic: true,
        updatedAt: 1,
      }))
      mockDbSetup.mockCollection.get
        .mockResolvedValueOnce({ data: page1 })
        .mockResolvedValueOnce({ data: [] })

      const { queryApps, loadMore } = await loadWorkshop()
      await queryApps(true)
      await loadMore()

      // loadMore 调用了第二次 get
      expect(mockDbSetup.mockCollection.get).toHaveBeenCalledTimes(2)
    })

    it('无更多数据时不触发查询', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({
        data: [{ _id: '1', name: 'A', slug: 'a', description: '', isPublic: true, updatedAt: 1 }],
      })

      const { queryApps, loadMore, hasMore } = await loadWorkshop()
      await queryApps(true)

      // 只有 1 条 < 20，hasMore = false
      expect(hasMore.value).toBe(false)

      await loadMore()
      // 不应该额外调用 get
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
