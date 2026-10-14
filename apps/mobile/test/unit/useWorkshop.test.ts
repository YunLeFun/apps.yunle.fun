import type { YlfAppInfo } from '@yunlefun/types'
import { beforeEach, describe, expect, it, vi } from 'vitest'

// --- Mock ~/constants/apps ---
// 应用目录在线化后 useWorkshop 仅用 APP_CATEGORIES 保持已有分类的展示顺序，
// 候选数据源统一走 useAppCatalog().catalog（在下方 stub）。
vi.mock('~/constants/apps', () => ({
  APP_CATEGORIES: [
    { id: 'all', name: '全部', icon: '📱' },
    { id: 'interesting', name: '整活', icon: '🤣' },
    { id: 'tools', name: '工具', icon: '🔧' },
    { id: 'design', name: '设计', icon: '🎨' },
  ],
}))

// Mock useDebounceFn to execute immediately
vi.mock('@vueuse/core', () => ({
  useDebounceFn: (fn: () => void) => fn,
}))

/** 构造一个目录应用（YlfAppInfo，字段对齐 @yunlefun/types） */
function makeApp(slug: string, category: string, overrides: Partial<YlfAppInfo> = {}): YlfAppInfo {
  return {
    id: slug,
    slug,
    name: `App ${slug}`,
    description: `desc ${slug}`,
    emoji: '📱',
    themeColor: '#000000',
    websiteUrl: `https://example.com/${slug}`,
    category,
    ...overrides,
  }
}

/** 等待未 await 的 queryApps（changeCategory / debouncedSearch 触发）结算 */
function flushPromises() {
  return new Promise(resolve => setTimeout(resolve, 0))
}

// --- stub useAppCatalog（新架构唯一数据源） ---

interface CatalogStub {
  catalog: { value: YlfAppInfo[] }
  ensureLoaded: ReturnType<typeof vi.fn>
}

let catalogStub: CatalogStub

vi.stubGlobal('useAppCatalog', () => catalogStub)

vi.stubGlobal('useState', (key: string, init: () => any) => ref(init()))

describe('useWorkshop', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    catalogStub = {
      // 默认目录：覆盖各分类，便于过滤断言
      catalog: ref<YlfAppInfo[]>([
        makeApp('joke-1', '整活'),
        makeApp('joke-2', '整活'),
        makeApp('tool-1', '工具'),
        makeApp('design-1', '设计'),
      ]),
      ensureLoaded: vi.fn().mockResolvedValue(undefined),
    }
  })

  function setCatalog(apps: YlfAppInfo[]) {
    catalogStub.catalog.value = apps
  }

  async function loadWorkshop() {
    const { useWorkshop } = await import('../../app/composables/useWorkshop')
    return useWorkshop()
  }

  describe('queryApps', () => {
    it('reset 时触发 ensureLoaded 并从 catalog 构建首屏', async () => {
      setCatalog([
        makeApp('s1', '整活'),
        makeApp('s2', '整活'),
        makeApp('s3', '整活'),
      ])

      const { queryApps, apps, initialized, error } = await loadWorkshop()
      await queryApps(true)

      expect(catalogStub.ensureLoaded).toHaveBeenCalledTimes(1)
      expect(apps.value.map(a => a.slug)).toEqual(['s1', 's2', 's3'])
      expect(initialized.value).toBe(true)
      expect(error.value).toBeNull()
    })

    it('ensureLoaded 合并的远端数据进入候选列表', async () => {
      setCatalog([makeApp('s1', '整活')])
      // 模拟 catalog 在 ensureLoaded 期间被集合数据覆盖（集合优先合并）
      catalogStub.ensureLoaded.mockImplementation(async () => {
        catalogStub.catalog.value = [
          ...catalogStub.catalog.value,
          makeApp('cloud-1', '整活', { name: 'Cloud cloud-1' }),
        ]
      })

      const { queryApps, apps } = await loadWorkshop()
      await queryApps(true)

      expect(apps.value.map(a => a.slug)).toEqual(['s1', 'cloud-1'])
    })

    it('分类筛选基于 catalog 客户端过滤', async () => {
      const { queryApps, apps, selectedCategory } = await loadWorkshop()
      selectedCategory.value = '工具'
      await queryApps(true)

      expect(apps.value.map(a => a.slug)).toEqual(['tool-1'])
      expect(apps.value.every(a => a.category === '工具')).toBe(true)
    })

    it('搜索按名称与描述过滤（大小写不敏感）', async () => {
      setCatalog([
        makeApp('alpha', '整活', { name: 'Alpha Tool', description: 'first app' }),
        makeApp('beta', '整活', { name: 'Beta', description: 'contains TOOL keyword' }),
        makeApp('gamma', '整活', { name: 'Gamma', description: 'unrelated' }),
      ])

      const { queryApps, apps, searchQuery } = await loadWorkshop()
      searchQuery.value = 'tool'
      await queryApps(true)

      // alpha 命中名称，beta 命中描述（大小写不敏感），gamma 被过滤
      expect(apps.value.map(a => a.slug)).toEqual(['alpha', 'beta'])
    })

    it('搜索忽略名称中的标点并按字段相关性排序', async () => {
      setCatalog([
        makeApp('description-match', '开发', { description: 'advjs helper' }),
        makeApp('slug-match', '开发', { slug: 'advjs' }),
        makeApp('adv-js-studio', '开发', { name: 'Adv.js Studio' }),
      ])

      const { queryApps, apps, searchQuery } = await loadWorkshop()
      searchQuery.value = 'advjs'
      await queryApps(true)

      expect(apps.value.map(a => a.slug)).toEqual([
        'adv-js-studio',
        'advjs',
        'description-match',
      ])
    })

    it('分类 + 搜索过滤可叠加', async () => {
      setCatalog([
        makeApp('tool-1', '工具', { name: 'Hammer' }),
        makeApp('tool-2', '工具', { name: 'Wrench' }),
        makeApp('joke-1', '整活', { name: 'Hammer Joke' }),
      ])

      const { queryApps, apps, selectedCategory, searchQuery } = await loadWorkshop()
      selectedCategory.value = '工具'
      searchQuery.value = 'hammer'
      await queryApps(true)

      expect(apps.value.map(a => a.slug)).toEqual(['tool-1'])
    })

    it('客户端分页：首屏展示 PAGE_SIZE(20)，loadMore 追加剩余', async () => {
      // 候选 25 条 → 首屏 20 条，loadMore 再展示剩余 5 条
      setCatalog(Array.from({ length: 25 }, (_, i) => makeApp(`s${i}`, '整活')))

      const { queryApps, apps, hasMore, loadMore } = await loadWorkshop()
      await queryApps(true)
      expect(apps.value).toHaveLength(20)
      expect(hasMore.value).toBe(true)

      loadMore()
      await flushPromises()

      expect(apps.value).toHaveLength(25)
      expect(hasMore.value).toBe(false)
    })

    it('候选恰好一页时 hasMore 收敛为 false', async () => {
      setCatalog(Array.from({ length: 20 }, (_, i) => makeApp(`s${i}`, '整活')))

      const { queryApps, apps, hasMore } = await loadWorkshop()
      await queryApps(true)

      expect(apps.value).toHaveLength(20)
      expect(hasMore.value).toBe(false)
    })

    it('reset=true 时清空旧数据并以 catalog 重新填充', async () => {
      setCatalog([makeApp('s1', '整活'), makeApp('s2', '整活')])

      const { queryApps, apps } = await loadWorkshop()

      // 模拟已有旧数据
      apps.value = [makeApp('old', '整活')]

      await queryApps(true)

      expect(apps.value.map(a => a.slug)).toEqual(['s1', 's2'])
      expect(apps.value.find(a => a.slug === 'old')).toBeUndefined()
    })

    it('搜索无结果时返回空且 hasMore=false', async () => {
      const { queryApps, apps, hasMore, searchQuery } = await loadWorkshop()
      searchQuery.value = 'zzzznonexistent999'
      await queryApps(true)

      expect(apps.value).toHaveLength(0)
      expect(hasMore.value).toBe(false)
    })
  })

  describe('changeCategory', () => {
    it('切换分类时重置查询并应用过滤', async () => {
      const { changeCategory, selectedCategory, apps } = await loadWorkshop()
      changeCategory('设计')
      await flushPromises()

      expect(selectedCategory.value).toBe('设计')
      expect(apps.value.map(a => a.slug)).toEqual(['design-1'])
    })
  })

  describe('debouncedSearch', () => {
    it('搜索触发重置查询', async () => {
      const { debouncedSearch, searchQuery, apps } = await loadWorkshop()
      searchQuery.value = 'joke-2'
      debouncedSearch()
      await flushPromises()

      expect(apps.value.map(a => a.slug)).toEqual(['joke-2'])
    })
  })

  describe('loadMore', () => {
    it('loadMore 走客户端切片，不重复触发 ensureLoaded', async () => {
      setCatalog(Array.from({ length: 25 }, (_, i) => makeApp(`s${i}`, '整活')))

      const { queryApps, loadMore, apps } = await loadWorkshop()
      await queryApps(true)
      expect(catalogStub.ensureLoaded).toHaveBeenCalledTimes(1)

      loadMore()
      await flushPromises()

      expect(apps.value).toHaveLength(25)
      // 加载更多只消费已有候选，不再请求目录
      expect(catalogStub.ensureLoaded).toHaveBeenCalledTimes(1)
    })

    it('无更多数据时 loadMore 不改变列表', async () => {
      setCatalog([
        makeApp('s1', '整活'),
        makeApp('s2', '整活'),
        makeApp('s3', '整活'),
      ])

      const { queryApps, loadMore, hasMore, apps } = await loadWorkshop()
      await queryApps(true)
      expect(apps.value).toHaveLength(3)
      expect(hasMore.value).toBe(false)

      loadMore()
      await flushPromises()

      expect(apps.value).toHaveLength(3)
      expect(catalogStub.ensureLoaded).toHaveBeenCalledTimes(1)
    })
  })

  describe('categories', () => {
    it('只提供当前目录应用实际使用的分类', async () => {
      const { categories } = await loadWorkshop()
      expect(categories.value.map(category => category.name)).toEqual([
        '全部',
        '整活',
        '工具',
        '设计',
      ])
    })

    it('保留应用提交的非预设分类', async () => {
      setCatalog([
        makeApp('tool-1', '工具'),
        makeApp('music-1', '音乐'),
      ])

      const { categories } = await loadWorkshop()
      expect(categories.value.map(category => category.name)).toEqual([
        '全部',
        '工具',
        '音乐',
      ])
    })
  })
})
