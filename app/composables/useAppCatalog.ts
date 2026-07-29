import type { YlfAppInfo } from '@yunlefun/types'
import type { AppRecord } from '~/types/app'
import type {
  WorkshopManagementView,
  WorkshopPublicInfo,
  WorkshopView,
} from '~/types/workshop'
import { ALL_APPS } from '~/constants/apps'
import { recordToAppInfo } from '~/utils/appRecord'

/**
 * 应用目录统一出口（Phase 3 前端在线化）。
 *
 * 三层数据：
 *   CloudBase apps 集合（唯一事实源）→ Nitro 公开白名单投影
 *     ↓ 客户端运行时拉取
 *   localStorage 缓存（冷启动 / 弱网兜底）
 *     ↓ 缺失时
 *   内置快照 ALL_APPS（离线 / 首屏，编译时打包）
 *
 * 在线成功后集合是完整权威快照，不再把已删除/暂停项从内置快照合并回来。
 * 只有网络失败时才降级到上次缓存或构建时快照，保证离线与首屏可用。
 */

const CACHE_KEY = 'ylf:app-catalog:v2'

interface CachePayload {
  list: YlfAppInfo[]
  ts: number
}

export function useAppCatalog() {
  const { $api } = useNuxtApp()
  const userStore = useUserStore()

  /** 目录列表：默认内置快照，运行时被缓存 / 集合覆盖 */
  const catalog = useState<YlfAppInfo[]>('catalog:list', () => [...ALL_APPS])
  /** 是否已成功从公开目录 API 拉取过 */
  const loaded = useState('catalog:loaded', () => false)
  const loading = useState('catalog:loading', () => false)
  /**
   * 当前账号通过个人工坊授权可见的应用。
   *
   * 这部分数据包含非公开元数据，只保存在内存状态中，不写入公共目录缓存。
   */
  const accessibleAppState = useState<YlfAppInfo[]>('catalog:accessible-apps', () => [])
  const accessibleUserId = useState('catalog:accessible-user-id', () => '')
  const accessibleLoadedState = useState('catalog:accessible-loaded', () => false)
  const accessibleApps = computed(() =>
    accessibleUserId.value === (userStore.userInfo?.id || '')
      ? accessibleAppState.value
      : [],
  )
  const accessibleLoaded = computed(() =>
    accessibleUserId.value === (userStore.userInfo?.id || '')
    && accessibleLoadedState.value,
  )

  function readCache(): YlfAppInfo[] | null {
    if (!import.meta.client)
      return null
    try {
      const raw = localStorage.getItem(CACHE_KEY)
      if (!raw)
        return null
      const payload = JSON.parse(raw) as CachePayload
      return Array.isArray(payload.list) ? payload.list : null
    }
    catch {
      return null
    }
  }

  function writeCache(list: YlfAppInfo[]) {
    if (!import.meta.client)
      return
    try {
      localStorage.setItem(CACHE_KEY, JSON.stringify({ list, ts: Date.now() } satisfies CachePayload))
    }
    catch {
      // 忽略配额 / 隐私模式写入失败
    }
  }

  /** 从服务端白名单投影拉取全部「已审核 + 已发布 + 公开」应用。 */
  async function fetchFromCloud(): Promise<YlfAppInfo[]> {
    const response = await $api<{ items: AppRecord[] }>('/api/apps/public')
    return response.items.map(recordToAppInfo)
  }

  /**
   * 确保目录已加载：先用缓存即时覆盖，再后台拉集合刷新并写缓存。
   * 失败静默降级。重复调用幂等（已加载则跳过，force 可强制刷新）。
   */
  async function ensureLoaded(force = false) {
    if (loaded.value && !force)
      return

    const cached = readCache()
    if (cached?.length)
      catalog.value = cached

    loading.value = true
    try {
      const remote = await fetchFromCloud()
      // 空列表同样是权威结果：必须清掉已下架缓存。
      catalog.value = remote
      writeCache(remote)
      loaded.value = true
    }
    catch {
      // 静默降级：保留 seed / 缓存
    }
    finally {
      loading.value = false
    }
  }

  function clearAccessibleApps() {
    accessibleAppState.value = []
    accessibleUserId.value = ''
    accessibleLoadedState.value = false
  }

  /**
   * 加载当前账号通过个人工坊有权访问的应用元数据。
   *
   * 切换账号时先清空旧账号数据；单个工坊暂时加载失败时保留其他成功结果，
   * 并保持 loaded=false，允许后续页面进入时重试。
   */
  async function ensureAccessibleLoaded(userId: string, force = false) {
    const normalizedUserId = userId.trim()
    if (!normalizedUserId) {
      clearAccessibleApps()
      return
    }

    if (accessibleUserId.value === normalizedUserId && accessibleLoadedState.value && !force)
      return

    const accountChanged = accessibleUserId.value !== normalizedUserId
    accessibleUserId.value = normalizedUserId
    accessibleLoadedState.value = false
    if (accountChanged)
      accessibleAppState.value = []

    try {
      const [joinedResponse, mineResponse] = await Promise.all([
        $api<{ items: WorkshopPublicInfo[] }>('/api/workshops/joined'),
        $api<{ management: WorkshopManagementView | null }>('/api/workshops/mine'),
      ])
      if (accessibleUserId.value !== normalizedUserId)
        return

      const workshops = [
        ...(mineResponse.management?.workshop.status === 'active'
          ? [mineResponse.management.workshop]
          : []),
        ...joinedResponse.items.filter(workshop => workshop.status === 'active'),
      ]
      const workshopIds = Array.from(new Set(workshops.map(workshop => workshop._id)))
      const results = await Promise.allSettled(
        workshopIds.map(workshopId =>
          $api<WorkshopView>(`/api/workshops/${encodeURIComponent(workshopId)}`),
        ),
      )
      if (accessibleUserId.value !== normalizedUserId)
        return

      const appsById = new Map<string, YlfAppInfo>()
      for (const result of results) {
        if (result.status !== 'fulfilled')
          continue
        if (result.value.access !== 'active' && result.value.access !== 'owner')
          continue

        for (const record of result.value.apps) {
          const app = recordToAppInfo(record)
          appsById.set(app.id || app.slug, app)
        }
      }

      accessibleAppState.value = Array.from(appsById.values())
      accessibleLoadedState.value = results.every(result => result.status === 'fulfilled')
    }
    catch {
      // 身份尚未恢复或网络失败时保留同账号已有结果，等待后续重试。
    }
  }

  /** 按 slug 或 id 解析单个应用（公开目录优先，账号授权目录兜底） */
  function getApp(idOrSlug: string): YlfAppInfo | undefined {
    if (!idOrSlug)
      return undefined
    return catalog.value.find(a => a.slug === idOrSlug || a.id === idOrSlug)
      || accessibleApps.value.find(a => a.slug === idOrSlug || a.id === idOrSlug)
  }

  /** 按分类过滤（'全部' 返回全部） */
  function getByCategory(category: string): YlfAppInfo[] {
    if (!category || category === '全部')
      return catalog.value
    return catalog.value.filter(a => a.category === category)
  }

  /**
   * 按开发者（ownerLogin）聚合应用。
   *
   * 仅匹配目录中已回填 developer 的项（运行时从集合拉取后由 recordToAppInfo 写入）；
   * 离线 / 未加载时内置快照无 developer，返回空数组（调用方据此隐藏入口）。
   */
  function getAppsByDeveloper(login: string): YlfAppInfo[] {
    if (!login)
      return []
    return catalog.value.filter(a => a.developer === login)
  }

  return {
    catalog,
    loading,
    loaded,
    accessibleApps,
    accessibleLoaded,
    ensureLoaded,
    ensureAccessibleLoaded,
    clearAccessibleApps,
    getApp,
    getByCategory,
    getAppsByDeveloper,
  }
}
