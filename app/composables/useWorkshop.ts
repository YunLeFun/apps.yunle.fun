import type { YlfAppInfo } from '@yunlefun/types'
import { useDebounceFn } from '@vueuse/core'
import { APP_CATEGORIES } from '~/constants/apps'

/**
 * 工坊数据 composable
 *
 * 候选数据源统一走 useAppCatalog().catalog（集合优先 + 内置兜底已在 catalog 内部合并），
 * 本 composable 只负责分类筛选、搜索与客户端分页。
 */
export function useWorkshop() {
  const { catalog, ensureLoaded } = useAppCatalog()

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
   * 全量候选列表（来自 catalog，含分类 + 搜索过滤）
   * 重置查询时重新构建，懒加载时直接从这里取
   */
  const allCandidates = useState<YlfAppInfo[]>('workshop:candidates', () => [])
  /** 已从 allCandidates 展示到第几条 */
  const displayOffset = useState('workshop:displayOffset', () => 0)

  /** 分类列表 */
  const categories = APP_CATEGORIES

  /** 获取当前分类 + 搜索词过滤后的候选应用列表（数据源为 catalog） */
  function getFilteredStaticApps(): YlfAppInfo[] {
    let list = catalog.value

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

  /** 展示 allCandidates 中的下一页 */
  function showNextPage() {
    const nextSlice = allCandidates.value.slice(
      displayOffset.value,
      displayOffset.value + PAGE_SIZE,
    )
    apps.value = [...apps.value, ...nextSlice]
    displayOffset.value += nextSlice.length

    // 候选列表未展示完则还有更多
    hasMore.value = displayOffset.value < allCandidates.value.length
  }

  /** 查询应用（reset=true 重置并重新加载，reset=false 加载更多） */
  async function queryApps(reset = false) {
    if (reset) {
      // 重置所有状态
      apps.value = []
      allCandidates.value = []
      displayOffset.value = 0
      hasMore.value = true
      error.value = null
    }

    if (!hasMore.value)
      return

    loading.value = true

    try {
      if (reset) {
        // 确保 catalog 已加载（集合优先，内置兜底），再构建候选列表
        await ensureLoaded()
        allCandidates.value = getFilteredStaticApps()
        showNextPage()
      }
      else {
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
