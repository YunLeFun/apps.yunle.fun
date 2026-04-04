import type { YlfAppInfo } from '~~/packages/types'
import type { AppRecord } from '~/types/app'
import { useDebounceFn } from '@vueuse/core'
import { ALL_APPS, APP_CATEGORIES } from '~/constants/apps'

/**
 * 工坊数据 composable
 * 静态应用为主数据源（支持客户端分页），CloudBase 公开应用去重追加
 */
export function useWorkshop() {
  const { app } = useCloudbase()
  const db = app.database()

  /** 应用列表（当前已展示的） */
  const apps = useState<YlfAppInfo[]>('workshop:apps', () => [])
  /** 当前选中分类 */
  const selectedCategory = useState('workshop:category', () => '全部')
  /** 搜索关键词 */
  const searchQuery = useState('workshop:search', () => '')
  /** 加载状态 */
  const loading = useState('workshop:loading', () => false)
  /** 错误信息 */
  const error = useState<string | null>('workshop:error', () => null)
  /** 是否还有更多数据 */
  const hasMore = useState('workshop:hasMore', () => true)
  /** 每页数量 */
  const PAGE_SIZE = 20
  /** 是否已初始化（区分首次加载和后续查询） */
  const initialized = useState('workshop:initialized', () => false)

  /**
   * 全量候选列表（静态 + CloudBase 去重合并）
   * 重置查询时重新构建，懒加载时直接从这里取
   */
  const allCandidates = useState<YlfAppInfo[]>('workshop:candidates', () => [])
  /** 已从 allCandidates 展示到第几条 */
  const displayOffset = useState('workshop:displayOffset', () => 0)
  /** CloudBase 是否已拉取完毕 */
  const dbFetched = useState('workshop:dbFetched', () => false)
  /** CloudBase 分页偏移 */
  const dbOffset = useState('workshop:dbOffset', () => 0)

  /** 分类列表 */
  const categories = APP_CATEGORIES

  /** 将 AppRecord 转为 YlfAppInfo */
  function toAppInfo(record: AppRecord): YlfAppInfo {
    return {
      id: record._id,
      slug: record.slug,
      name: record.name,
      description: record.description,
      emoji: record.emoji || '📱',
      color: record.themeColor || '#007AFF',
      icon: record.logo || undefined,
      url: record.websiteUrl || '',
      category: record.category,
    }
  }

  /** 获取当前分类 + 搜索词过滤后的静态应用列表 */
  function getFilteredStaticApps(): YlfAppInfo[] {
    let list = ALL_APPS

    if (selectedCategory.value !== '全部') {
      list = list.filter(a => a.category === selectedCategory.value)
    }

    const keyword = searchQuery.value.trim().toLowerCase()
    if (keyword) {
      list = list.filter(a =>
        a.name.toLowerCase().includes(keyword)
        || (a.description && a.description.toLowerCase().includes(keyword)),
      )
    }

    return list
  }

  /** 将 CloudBase 数据去重追加到 allCandidates（以 slug 为唯一标识） */
  function mergeDbApps(dbApps: YlfAppInfo[]) {
    const existingSlugs = new Set(allCandidates.value.map(a => a.slug || a.id))
    const newApps = dbApps.filter(a => !existingSlugs.has(a.slug || a.id))
    allCandidates.value = [...allCandidates.value, ...newApps]
  }

  /** 从 CloudBase 后台拉取一批数据并合并（不阻塞 UI） */
  async function fetchDbPage() {
    if (dbFetched.value)
      return

    try {
      const where: Record<string, any> = { isPublic: true }

      if (selectedCategory.value !== '全部') {
        where.category = selectedCategory.value
      }

      const keyword = searchQuery.value.trim()
      if (keyword) {
        where.name = db.RegExp({ regexp: keyword, options: 'i' })
      }

      const DB_PAGE_SIZE = 50
      const { data } = await db
        .collection('apps')
        .where(where)
        .orderBy('updatedAt', 'desc')
        .skip(dbOffset.value)
        .limit(DB_PAGE_SIZE)
        .get()

      if (data && data.length > 0) {
        const newApps = (data as AppRecord[]).map(toAppInfo)
        mergeDbApps(newApps)
        dbOffset.value += data.length

        if (data.length < DB_PAGE_SIZE) {
          dbFetched.value = true
        }
      }
      else {
        dbFetched.value = true
      }
    }
    catch (e: any) {
      console.warn('[Workshop] fetchDbPage failed:', e?.error || e?.message || e)
      dbFetched.value = true
    }
  }

  /** 展示 allCandidates 中的下一页 */
  function showNextPage() {
    const nextSlice = allCandidates.value.slice(
      displayOffset.value,
      displayOffset.value + PAGE_SIZE,
    )
    apps.value = [...apps.value, ...nextSlice]
    displayOffset.value += nextSlice.length

    // 判断是否还有更多：候选列表未展示完，或 CloudBase 还没拉完
    hasMore.value = displayOffset.value < allCandidates.value.length || !dbFetched.value
  }

  /** 查询应用（reset=true 重置并重新加载，reset=false 加载更多） */
  async function queryApps(reset = false) {
    if (reset) {
      // 重置所有状态
      apps.value = []
      allCandidates.value = []
      displayOffset.value = 0
      hasMore.value = true
      dbFetched.value = false
      dbOffset.value = 0
      error.value = null
    }

    if (!hasMore.value)
      return

    loading.value = true

    try {
      if (reset) {
        // 先用静态数据填充候选列表，立即展示第一页
        allCandidates.value = getFilteredStaticApps()
        showNextPage()

        // 后台拉取 CloudBase 数据（不阻塞首屏）
        fetchDbPage().catch(() => {})
      }
      else {
        // 懒加载：如候选列表当前页不够，先尝试从 CloudBase 补充
        const remaining = allCandidates.value.length - displayOffset.value
        if (remaining < PAGE_SIZE && !dbFetched.value) {
          await fetchDbPage()
        }
        showNextPage()
      }
    }
    finally {
      loading.value = false
      initialized.value = true
    }
  }

  /** 切换分类 */
  function changeCategory(category: string) {
    selectedCategory.value = category
    queryApps(true)
  }

  /** 搜索（防抖 300ms） */
  const debouncedSearch = useDebounceFn(() => {
    queryApps(true)
  }, 300)

  /** 加载更多 */
  function loadMore() {
    if (!loading.value && hasMore.value) {
      queryApps(false)
    }
  }

  return {
    apps,
    selectedCategory,
    searchQuery,
    loading,
    error,
    hasMore,
    categories,
    initialized,
    queryApps,
    changeCategory,
    debouncedSearch,
    loadMore,
  }
}
