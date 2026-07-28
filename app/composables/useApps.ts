import type {
  AppRecord,
  AppSubmissionAccess,
  AppSubmissionResult,
  CreateAppForm,
} from '~/types/app'

/**
 * 应用提交与所有者管理统一走 Nitro 服务端 API。
 *
 * 浏览器不再直写 CloudBase `apps`：服务端负责身份验证、维护者 allowlist、
 * 字段校验、submission 快照、不可变审核事件与状态机。
 * 公开目录也经 Nitro API 返回白名单投影；客户端缓存保留弱网与离线能力。
 */
export function useApps() {
  const { $api } = useNuxtApp()

  async function getSubmissionAccess(): Promise<AppSubmissionAccess> {
    return $api<AppSubmissionAccess>('/api/apps/access')
  }

  async function getMyApps(): Promise<AppRecord[]> {
    const response = await $api<{ items: AppRecord[] }>('/api/apps/mine')
    return response.items
  }

  async function getMyAppById(id: string): Promise<AppRecord | null> {
    if (!id)
      return null
    const apps = await getMyApps()
    return apps.find(app => app._id === id) ?? null
  }

  async function getMyAppBySlug(slug: string): Promise<AppRecord | null> {
    if (!slug)
      return null
    try {
      const response = await $api<{ app: AppRecord }>(`/api/apps/mine/${encodeURIComponent(slug)}`)
      return response.app
    }
    catch (error: unknown) {
      if (statusCode(error) === 404)
        return null
      throw error
    }
  }

  /** 公开目录也走服务端白名单投影，浏览器不依赖 CloudBase 凭据或数据库结构。 */
  async function getPublicAppBySlug(slug: string): Promise<AppRecord | null> {
    if (!slug)
      return null
    try {
      const response = await $api<{ app: AppRecord }>(`/api/apps/public/${encodeURIComponent(slug)}`)
      return response.app
    }
    catch (error: unknown) {
      if (statusCode(error) === 404)
        return null
      throw error
    }
  }

  async function getAppBySlug(slug: string): Promise<AppRecord | null> {
    try {
      const mine = await getMyAppBySlug(slug)
      if (mine)
        return mine
    }
    catch (error: unknown) {
      if (statusCode(error) !== 401)
        throw error
    }
    return getPublicAppBySlug(slug)
  }

  async function createApp(form: CreateAppForm): Promise<string> {
    const response = await $api<AppSubmissionResult>('/api/apps/submissions', {
      method: 'POST',
      body: { kind: 'first_party', ...form },
    })
    return response.app._id
  }

  async function updateApp(id: string, updates: Partial<CreateAppForm>): Promise<void> {
    const current = await getMyAppById(id)
    if (!current)
      throw new Error('应用不存在或无权更新')
    await $api<AppSubmissionResult>(`/api/apps/${encodeURIComponent(id)}/submissions`, {
      method: 'POST',
      body: {
        kind: 'first_party',
        ...toForm(current),
        ...updates,
      },
    })
  }

  async function deleteApp(id: string): Promise<void> {
    await $api(`/api/apps/${encodeURIComponent(id)}`, { method: 'DELETE' })
  }

  async function submitPublicMarket(id: string): Promise<void> {
    await $api(`/api/apps/${encodeURIComponent(id)}/public-market`, {
      method: 'POST',
    })
  }

  async function isSlugTaken(slug: string): Promise<boolean> {
    if (!slug)
      return false
    const response = await $api<{ taken: boolean }>('/api/apps/slug', {
      query: { slug },
    })
    return response.taken
  }

  return {
    getSubmissionAccess,
    getMyApps,
    getMyAppById,
    getAppBySlug,
    getPublicAppBySlug,
    getMyAppBySlug,
    createApp,
    updateApp,
    deleteApp,
    submitPublicMarket,
    isSlugTaken,
  }
}

function toForm(app: AppRecord): CreateAppForm {
  return {
    name: app.name,
    slug: app.slug,
    description: app.description || '',
    githubRepo: app.githubRepo || '',
    websiteUrl: app.websiteUrl || '',
    privacyPolicyUrl: app.privacyPolicyUrl || '',
    supportUrl: app.supportUrl || '',
    trustedHosts: app.trustedHosts || [],
    backupUrl: app.backupUrl || '',
    logo: app.logo || '',
    emoji: app.emoji || '📱',
    themeColor: app.themeColor || '#007AFF',
    category: app.category || '其他',
    tags: app.tags || [],
    isPublic: true,
    audience: app.audience || (app.isPublic ? 'public' : 'owner'),
    accessMode: app.accessMode || 'public',
    releaseStage: app.releaseStage || 'stable',
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
