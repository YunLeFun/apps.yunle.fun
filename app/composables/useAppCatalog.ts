import type { YlfAppInfo } from '@yunlefun/types'
import type { AppRecord } from '~/types/app'
import { ALL_APPS } from '~/constants/apps'
import { recordToAppInfo } from '~/utils/appRecord'

/**
 * 应用目录统一出口（Phase 3 前端在线化）。
 *
 * 三层数据：
 *   CloudBase apps 集合（唯一事实源）
 *     ↓ 运行时拉取
 *   localStorage 缓存（冷启动 / 弱网兜底）
 *     ↓ 缺失时
 *   内置快照 ALL_APPS（离线 / 首屏，编译时打包）
 *
 * 合并策略：集合优先——按 slug 覆盖内置快照，内置中集合没有的保留（离线覆盖）。
 * 失败静默降级到缓存 / 内置快照，保证离线与首屏始终有数据。
 */

const CACHE_KEY = 'ylf:app-catalog:v1'

interface CachePayload {
  list: YlfAppInfo[]
  ts: number
}

export function useAppCatalog() {
  const { app } = useCloudbase()
  const db = app.database()

  /** 目录列表：默认内置快照，运行时被缓存 / 集合覆盖 */
  const catalog = useState<YlfAppInfo[]>('catalog:list', () => [...ALL_APPS])
  /** 是否已成功从集合拉取过 */
  const loaded = useState('catalog:loaded', () => false)
  const loading = useState('catalog:loading', () => false)

  /** 集合优先合并：remote 按 slug 覆盖 seed */
  function merge(seed: YlfAppInfo[], remote: YlfAppInfo[]): YlfAppInfo[] {
    const map = new Map<string, YlfAppInfo>()
    for (const a of seed)
      map.set(a.slug, a)
    for (const a of remote)
      map.set(a.slug, a)
    return [...map.values()]
  }

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

  /** 从集合分页拉取全部「已审核 + 公开」应用 */
  async function fetchFromCloud(): Promise<YlfAppInfo[]> {
    const all: AppRecord[] = []
    const PAGE = 100
    for (let skip = 0; ; skip += PAGE) {
      const { data } = await db
        .collection('apps')
        .where({ isPublic: true, status: 'approved' })
        .orderBy('updatedAt', 'desc')
        .skip(skip)
        .limit(PAGE)
        .get()
      const page = (data as AppRecord[]) || []
      all.push(...page)
      if (page.length < PAGE)
        break
    }
    return all.map(recordToAppInfo)
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
      catalog.value = merge(ALL_APPS, cached)

    loading.value = true
    try {
      const remote = await fetchFromCloud()
      if (remote.length) {
        catalog.value = merge(ALL_APPS, remote)
        writeCache(remote)
      }
      loaded.value = true
    }
    catch {
      // 静默降级：保留 seed / 缓存
    }
    finally {
      loading.value = false
    }
  }

  /** 按 slug 或 id 解析单个应用（集合优先，内置兜底） */
  function getApp(idOrSlug: string): YlfAppInfo | undefined {
    if (!idOrSlug)
      return undefined
    return catalog.value.find(a => a.slug === idOrSlug || a.id === idOrSlug)
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

  return { catalog, loading, loaded, ensureLoaded, getApp, getByCategory, getAppsByDeveloper }
}
