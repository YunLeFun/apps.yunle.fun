import type { YlfAppInfo } from '~~/packages/types'
import type { AppRecord } from '~/types/app'
import { useDebounceFn } from '@vueuse/core'
import { ALL_APPS, APP_CATEGORIES } from '~/constants/apps'

/**
 * 工坊数据 composable
 * 从 CloudBase 查询公开应用，支持分类筛选、搜索和分页
 */
export function useWorkshop() {
  const { app } = useCloudbase()
  const db = app.database()

  /** 应用列表 */
  const apps = useState<YlfAppInfo[]>('workshop:apps', () => [])
  /** 当前选中分类 */
  const selectedCategory = useState('workshop:category', () => '全部')
  /** 搜索关键词 */
  const searchQuery = useState('workshop:search', () => '')
  /** 加载状态 */
  const loading = useState('workshop:loading', () => false)
  /** 是否还有更多数据 */
  const hasMore = useState('workshop:hasMore', () => true)
  /** 当前偏移量 */
  const offset = useState('workshop:offset', () => 0)
  /** 每页数量 */
  const PAGE_SIZE = 20
  /** 是否已初始化（区分首次加载和后续查询） */
  const initialized = useState('workshop:initialized', () => false)

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

  /** 从 CloudBase 查询公开应用 */
  async function queryApps(reset = false) {
    if (reset) {
      offset.value = 0
      apps.value = []
      hasMore.value = true
    }

    if (!hasMore.value)
      return

    loading.value = true

    // 构建查询条件
    const where: Record<string, any> = { isPublic: true }

    // 分类筛选
    if (selectedCategory.value !== '全部') {
      where.category = selectedCategory.value
    }

    // 搜索条件
    if (searchQuery.value.trim()) {
      where.name = db.RegExp({
        regexp: searchQuery.value.trim(),
        options: 'i',
      })
    }

    const { data } = await db
      .collection('apps')
      .where(where)
      .orderBy('updatedAt', 'desc')
      .skip(offset.value)
      .limit(PAGE_SIZE)
      .get()

    if (data && data.length > 0) {
      const newApps = (data as AppRecord[]).map(toAppInfo)
      apps.value = reset ? newApps : [...apps.value, ...newApps]
      offset.value += data.length
      hasMore.value = data.length >= PAGE_SIZE
    }
    else if (reset) {
      // CloudBase 无数据时使用静态数据
      if (!searchQuery.value.trim()) {
        apps.value = filterStaticApps()
      }
      else {
        apps.value = searchStaticApps(searchQuery.value.trim())
      }
      hasMore.value = false
    }
    else {
      hasMore.value = false
    }

    loading.value = false
    initialized.value = true
  }

  /** 按分类筛选静态应用（fallback） */
  function filterStaticApps(): YlfAppInfo[] {
    if (selectedCategory.value === '全部')
      return ALL_APPS
    return ALL_APPS.filter(a => a.category === selectedCategory.value)
  }

  /** 搜索静态应用（fallback） */
  function searchStaticApps(keyword: string): YlfAppInfo[] {
    const lower = keyword.toLowerCase()
    return ALL_APPS.filter(a =>
      a.name.toLowerCase().includes(lower)
      || (a.description && a.description.toLowerCase().includes(lower)),
    )
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
    hasMore,
    categories,
    initialized,
    queryApps,
    changeCategory,
    debouncedSearch,
    loadMore,
  }
}
