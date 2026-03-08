import type { YlfAppInfo } from '~~/packages/types'
import type { FeaturedAppRecord, WeeklyChartRecord } from '~/types/homeScreen'
import { ALL_APPS, FEATURED_APP } from '~/constants/apps'

/**
 * 发现页数据 composable
 * 从 CloudBase 获取推荐和周榜数据，支持 fallback 到静态数据
 */
export function useDiscovery() {
  const { app } = useCloudbase()
  const db = app.database()
  const _ = db.command

  /** 今日推荐应用 */
  const featuredApp = useState<YlfAppInfo>('discovery:featured', () => FEATURED_APP)
  /** 今日推荐的 meta 信息 */
  const featuredMeta = useState<Partial<FeaturedAppRecord>>('discovery:featuredMeta', () => ({}))
  /** 本周热门列表 */
  const weeklyApps = useState<YlfAppInfo[]>('discovery:weekly', () => [])
  /** 加载状态 */
  const loading = useState('discovery:loading', () => false)
  /** 错误信息 */
  const error = useState<string | null>('discovery:error', () => null)

  /** 根据 appId（slug）解析完整应用信息：先查静态列表，再查 CloudBase */
  async function resolveApp(appId: string): Promise<YlfAppInfo | null> {
    // 先从静态列表查找
    const staticApp = ALL_APPS.find(a => a.id === appId || a.slug === appId)
    if (staticApp)
      return staticApp

    // 静态列表未命中，查 CloudBase
    try {
      const { data } = await db
        .collection('apps')
        .where({ slug: appId, isPublic: true })
        .limit(1)
        .get()
      if (!data || data.length === 0)
        return null
      const record = data[0] as any
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
        rating: record.rating,
      }
    }
    catch {
      return null
    }
  }

  /** 计算当周周一 00:00 时间戳 */
  function getWeekStart(): number {
    const now = new Date()
    const day = now.getDay()
    const diff = now.getDate() - day + (day === 0 ? -6 : 1)
    const monday = new Date(now.getFullYear(), now.getMonth(), diff)
    monday.setHours(0, 0, 0, 0)
    return monday.getTime()
  }

  /** 加载今日推荐 */
  async function loadFeatured() {
    try {
      const now = Date.now()
      const { data } = await db
        .collection('featured_apps')
        .where({
          isActive: true,
          type: 'daily',
          startDate: _.lte(now),
          endDate: _.gte(now),
        })
        .orderBy('sortOrder', 'asc')
        .limit(1)
        .get()

      if (data && data.length > 0) {
        const record = data[0] as FeaturedAppRecord
        featuredMeta.value = record
        const resolved = await resolveApp(record.appId)
        if (resolved) {
          featuredApp.value = {
            ...resolved,
            name: record.title || resolved.name,
            subtitle: record.subtitle || resolved.subtitle,
            tagline: record.tagline || resolved.tagline,
            color: record.coverColor || resolved.color,
          }
          return
        }
      }
    }
    catch (e: any) {
      console.warn('[Discovery] loadFeatured failed, using fallback:', e?.error || e?.message || e)
    }
    // fallback 到静态数据
    featuredApp.value = FEATURED_APP
  }

  /** 加载本周热门 */
  async function loadWeeklyChart() {
    try {
      const weekStart = getWeekStart()
      const { data } = await db
        .collection('weekly_charts')
        .where({ weekStart })
        .orderBy('rank', 'asc')
        .limit(10)
        .get()

      if (data && data.length > 0) {
        const resolved = await Promise.all(
          (data as WeeklyChartRecord[]).map(record => resolveApp(record.appId)),
        )
        weeklyApps.value = resolved.filter((a): a is YlfAppInfo => a !== null)
        return
      }
    }
    catch (e: any) {
      console.warn('[Discovery] loadWeeklyChart failed, using fallback:', e?.error || e?.message || e)
    }
    // fallback 到静态数据的前 5 个
    weeklyApps.value = ALL_APPS.slice(0, 5)
  }

  /** 加载所有发现页数据 */
  async function loadAll() {
    loading.value = true
    error.value = null
    try {
      await Promise.all([loadFeatured(), loadWeeklyChart()])
    }
    catch (e: any) {
      const msg = e?.error_description || e?.error || e?.message || '加载失败'
      error.value = msg
      // 确保有 fallback 数据
      if (!featuredApp.value || featuredApp.value === FEATURED_APP)
        featuredApp.value = FEATURED_APP
      if (!weeklyApps.value.length)
        weeklyApps.value = ALL_APPS.slice(0, 5)
    }
    finally {
      loading.value = false
    }
  }

  return {
    featuredApp,
    featuredMeta,
    weeklyApps,
    loading,
    error,
    loadFeatured,
    loadWeeklyChart,
    loadAll,
  }
}
