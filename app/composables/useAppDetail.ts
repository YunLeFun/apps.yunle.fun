import type { YlfAppInfo } from '~~/packages/types'
import type { AppRecord } from '~/types/app'
import { ALL_APPS, getAppById } from '~/constants/apps'

/**
 * 应用详情扩展数据
 */
export interface AppDetailData extends YlfAppInfo {
  /** 开发者 */
  developer: string
  /** 版本号 */
  version: string
  /** 更新日期 */
  updateDate: string
  /** 新功能说明 */
  whatsNew: string
  /** 支持语言 */
  languages: string[]
  /** 兼容性 */
  compatibility: string
  /** GitHub 仓库 */
  githubRepo?: string
  /** 标签 */
  tags?: string[]
}

/**
 * 将静态应用转为详情数据（填充默认值）
 */
function toDetailData(app: YlfAppInfo, extra?: Partial<AppDetailData>): AppDetailData {
  return {
    ...app,
    developer: extra?.developer ?? 'YunYouJun',
    version: extra?.version ?? '1.0.0',
    updateDate: extra?.updateDate ?? '',
    whatsNew: extra?.whatsNew ?? '',
    languages: extra?.languages ?? ['简体中文', 'English'],
    compatibility: extra?.compatibility ?? 'iOS 16.0+',
    githubRepo: extra?.githubRepo,
    tags: extra?.tags,
  }
}

/**
 * 将 CloudBase AppRecord 转为详情数据
 */
function recordToDetailData(record: AppRecord): AppDetailData {
  return toDetailData({
    id: record._id,
    slug: record.slug,
    name: record.name,
    description: record.description,
    emoji: record.emoji || '📱',
    color: record.themeColor || '#007AFF',
    icon: record.logo || undefined,
    url: record.websiteUrl || '',
    category: record.category,
  }, {
    developer: record.ownerLogin || 'Unknown',
    updateDate: record.updatedAt
      ? new Date(record.updatedAt).toLocaleDateString('zh-CN')
      : '',
    githubRepo: record.githubRepo,
    tags: record.tags,
  })
}

/**
 * 应用详情页数据获取 composable
 *
 * 采用静态优先 + CloudBase 补充的两级查找策略：
 * 1. 先在 ALL_APPS 中通过 id/slug 匹配（同步）
 * 2. 未命中则通过 CloudBase where({ _id, isPublic: true }) 按文档 ID 查询
 * 3. 仍未命中则按 where({ slug, isPublic: true }) 查询
 */
export function useAppDetail(appId: MaybeRef<string>) {
  const { app: cloudbaseApp } = useCloudbase()
  const db = cloudbaseApp.database()

  const appData = ref<AppDetailData | null>(null)
  const loading = ref(true)
  const error = ref<string | null>(null)

  async function resolve() {
    const id = toValue(appId)
    if (!id) {
      loading.value = false
      error.value = '应用 ID 不能为空'
      return
    }

    loading.value = true
    error.value = null

    // 1. 静态数据查找
    const staticApp = getAppById(id)
      || ALL_APPS.find(a => a.slug === id)
    if (staticApp) {
      appData.value = toDetailData(staticApp)
      loading.value = false
      return
    }

    // 2. CloudBase 查询
    try {
      // 先按 _id 查
      let record = await queryPublicAppById(id)

      // 再按 slug 查
      if (!record) {
        record = await queryPublicAppBySlug(id)
      }

      if (record) {
        appData.value = recordToDetailData(record)
      }
      else {
        error.value = '应用未找到'
      }
    }
    catch {
      error.value = '加载失败，请稍后重试'
    }
    finally {
      loading.value = false
    }
  }

  /** 按 _id 查询公开应用 */
  async function queryPublicAppById(id: string): Promise<AppRecord | null> {
    const { data } = await db
      .collection('apps')
      .where({ _id: id, isPublic: true })
      .limit(1)
      .get()
    return (data as AppRecord[])?.[0] || null
  }

  /** 按 slug 查询公开应用 */
  async function queryPublicAppBySlug(slug: string): Promise<AppRecord | null> {
    const { data } = await db
      .collection('apps')
      .where({ slug, isPublic: true })
      .limit(1)
      .get()
    return (data as AppRecord[])?.[0] || null
  }

  // 监听 appId 变化时重新加载
  watch(() => toValue(appId), () => {
    resolve()
  }, { immediate: true })

  return {
    appData,
    loading,
    error,
    refresh: resolve,
  }
}
