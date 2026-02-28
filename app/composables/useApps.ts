import type { AppRecord, CreateAppForm } from '~/types/app'

const COLLECTION = 'apps'

/**
 * 应用数据管理 composable
 * 基于 CloudBase NoSQL 数据库
 */
export function useApps() {
  const { app } = useCloudbase()
  const { user } = useCloudbaseAuth()
  const db = app.database()

  /**
   * 获取当前用户的所有应用
   */
  async function getMyApps(): Promise<AppRecord[]> {
    if (!user.value)
      return []
    const { data } = await db
      .collection(COLLECTION)
      .where({ ownerId: user.value.id })
      .orderBy('updatedAt', 'desc')
      .limit(100)
      .get()
    return data as AppRecord[]
  }

  /**
   * 根据 slug 获取应用详情
   */
  async function getAppBySlug(slug: string): Promise<AppRecord | null> {
    const { data } = await db
      .collection(COLLECTION)
      .where({ slug })
      .limit(1)
      .get()
    return (data as AppRecord[])[0] || null
  }

  /**
   * 创建应用，返回新文档 ID
   */
  async function createApp(form: CreateAppForm): Promise<string> {
    if (!user.value)
      throw new Error('请先登录')

    const now = Date.now()
    const res = await db.collection(COLLECTION).add({
      ownerId: user.value.id,
      ownerLogin: user.value.login || user.value.id,
      name: form.name,
      slug: form.slug,
      description: form.description || '',
      githubRepo: form.githubRepo || '',
      websiteUrl: form.websiteUrl || '',
      backupUrl: form.backupUrl || '',
      icon: form.icon || '',
      category: form.category || '',
      tags: form.tags || [],
      isPublic: form.isPublic,
      createdAt: now,
      updatedAt: now,
    }) as unknown as { id: string }
    return res.id
  }

  /**
   * 更新应用
   */
  async function updateApp(id: string, updates: Partial<CreateAppForm>): Promise<void> {
    await db.collection(COLLECTION).doc(id).update({
      ...updates,
      updatedAt: Date.now(),
    })
  }

  /**
   * 删除应用
   */
  async function deleteApp(id: string): Promise<void> {
    await db.collection(COLLECTION).doc(id).remove()
  }

  /**
   * 检查 slug 是否已被占用
   */
  async function isSlugTaken(slug: string): Promise<boolean> {
    const { data } = await db
      .collection(COLLECTION)
      .where({ slug })
      .limit(1)
      .get()
    return (data as AppRecord[]).length > 0
  }

  return {
    getMyApps,
    getAppBySlug,
    createApp,
    updateApp,
    deleteApp,
    isSlugTaken,
  }
}
