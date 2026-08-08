import type { YlfAppInfo } from '@yunlefun/types'
import type { AppRecord } from '~/types/app'

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
  privacyPolicyUrl?: string
  supportUrl?: string
}

/**
 * 将静态应用转为详情数据（填充默认值）
 */
function toDetailData(app: YlfAppInfo, extra?: Partial<AppDetailData>): AppDetailData {
  const catalogApp = app as YlfAppInfo & Pick<Partial<AppDetailData>, 'privacyPolicyUrl' | 'supportUrl'>
  return {
    ...app,
    // 优先级：显式传入 > 目录回填的 developer（ownerLogin）> 站点默认
    developer: extra?.developer ?? app.developer ?? 'YunYouJun',
    version: extra?.version ?? '1.0.0',
    updateDate: extra?.updateDate ?? '',
    whatsNew: extra?.whatsNew ?? '',
    languages: extra?.languages ?? ['简体中文', 'English'],
    // 目录应用本质是网页，按网页应用而非原生 iOS 描述运行环境
    compatibility: extra?.compatibility ?? '需要联网 · 现代浏览器',
    githubRepo: extra?.githubRepo,
    tags: extra?.tags,
    privacyPolicyUrl: extra?.privacyPolicyUrl ?? catalogApp.privacyPolicyUrl,
    supportUrl: extra?.supportUrl ?? catalogApp.supportUrl,
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
    themeColor: record.themeColor || '#007AFF',
    logo: record.logo || undefined,
    iconAssets: record.iconAssets,
    websiteUrl: record.websiteUrl || '',
    category: record.category,
  }, {
    developer: record.ownerLogin || 'Unknown',
    updateDate: record.updatedAt
      ? new Date(record.updatedAt).toLocaleDateString('zh-CN')
      : '',
    githubRepo: record.githubRepo,
    tags: record.tags,
    privacyPolicyUrl: record.privacyPolicyUrl,
    supportUrl: record.supportUrl,
  })
}

/**
 * 应用详情页数据获取 composable
 *
 * 采用「目录优先 + 服务端公开投影兜底」的两级查找策略：
 * 1. 先确保应用目录已加载，再用 catalog 通过 id/slug 匹配（在线目录优先，内置快照兜底）
 * 2. 未命中则通过 `/api/apps/public/:key` 按文档 ID 或 slug 查询
 *
 * 浏览器不直接依赖 CloudBase 凭据、索引或安全规则细节；服务端仅返回已发布字段白名单。
 */
export function useAppDetail(appId: MaybeRef<string>) {
  const { $api } = useNuxtApp()
  const { getApp, ensureLoaded } = useAppCatalog()

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

    // 1. 应用目录查找（在线目录优先，内置兜底）
    await ensureLoaded()
    const catalogApp = getApp(id)
    if (catalogApp) {
      appData.value = toDetailData(catalogApp)
      loading.value = false
      return
    }

    // 2. 服务端公开投影查询
    try {
      const response = await $api<{ app: AppRecord }>(`/api/apps/public/${encodeURIComponent(id)}`)
      appData.value = recordToDetailData(response.app)
    }
    catch (queryError) {
      error.value = statusCode(queryError) === 404 ? '应用未找到' : '加载失败，请稍后重试'
    }
    finally {
      loading.value = false
    }
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

function statusCode(error: unknown): number | undefined {
  if (!error || typeof error !== 'object')
    return
  const record = error as Record<string, unknown>
  if (typeof record.statusCode === 'number')
    return record.statusCode
  if (typeof record.status === 'number')
    return record.status
  const response = record.response
  if (response && typeof response === 'object') {
    const status = (response as Record<string, unknown>).status
    return typeof status === 'number' ? status : undefined
  }
}
