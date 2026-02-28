import type { AppRecord, CreateAppForm } from '~/types/app'

const COLLECTION = 'apps'

/**
 * 应用数据管理 composable
 * 基于 CloudBase NoSQL 数据库
 *
 * 安全规则（CUSTOM）：
 *   read:  "doc.isPublic == true || auth.uid == doc._openid"
 *   write: "auth.uid == doc._openid"
 *
 * where 查询必须包含安全规则可推导的条件：
 *   - 查自己的数据 → where 含 _openid
 *   - 查公开数据   → where 含 isPublic == true
 */
export function useApps() {
  const { app } = useCloudbase()
  const { user } = useCloudbaseAuth()
  const db = app.database()
  const _ = db.command

  /**
   * 获取当前用户的所有应用（含公开 + 私有）
   */
  async function getMyApps(): Promise<AppRecord[]> {
    if (!user.value)
      return []
    const { data } = await db
      .collection(COLLECTION)
      .where({ _openid: user.value.id })
      .orderBy('updatedAt', 'desc')
      .limit(100)
      .get()
    return data as AppRecord[]
  }

  /**
   * 根据 slug 获取公开应用详情
   * 安全规则要求 where 中必须包含 isPublic: true 才能查询非本人数据
   */
  async function getPublicAppBySlug(slug: string): Promise<AppRecord | null> {
    const { data } = await db
      .collection(COLLECTION)
      .where({ slug, isPublic: true })
      .limit(1)
      .get()
    return (data as AppRecord[])[0] || null
  }

  /**
   * 根据 slug 获取当前用户自己的应用（不限公开/私有）
   */
  async function getMyAppBySlug(slug: string): Promise<AppRecord | null> {
    if (!user.value)
      return null
    const { data } = await db
      .collection(COLLECTION)
      .where({ slug, _openid: user.value.id })
      .limit(1)
      .get()
    return (data as AppRecord[])[0] || null
  }

  /**
   * 根据 slug 获取应用详情（优先查自己的，否则查公开的）
   */
  async function getAppBySlug(slug: string): Promise<AppRecord | null> {
    // 已登录：先查自己的（含私有）
    const myApp = await getMyAppBySlug(slug)
    if (myApp)
      return myApp
    // 再查公开的
    return getPublicAppBySlug(slug)
  }

  /**
   * 创建应用，返回新文档 ID
   * _openid 由 CloudBase 服务端自动注入
   */
  async function createApp(form: CreateAppForm): Promise<string> {
    if (!user.value)
      throw new Error('请先登录')

    const now = Date.now()
    const res = await db.collection(COLLECTION).add({
      ownerLogin: user.value.login || '',
      name: form.name,
      slug: form.slug,
      description: form.description || '',
      githubRepo: form.githubRepo || '',
      websiteUrl: form.websiteUrl || '',
      backupUrl: form.backupUrl || '',
      logo: form.logo || '',
      emoji: form.emoji || '',
      themeColor: form.themeColor || '',
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
   * 检查 slug 是否已被占用（在本人数据 + 公开数据中查找）
   */
  async function isSlugTaken(slug: string): Promise<boolean> {
    // 查公开数据
    const { data: publicData } = await db
      .collection(COLLECTION)
      .where({ slug, isPublic: true })
      .limit(1)
      .get()
    if ((publicData as AppRecord[]).length > 0)
      return true
    // 查自己的私有数据
    if (user.value) {
      const { data: myData } = await db
        .collection(COLLECTION)
        .where({ slug, _openid: user.value.id })
        .limit(1)
        .get()
      if ((myData as AppRecord[]).length > 0)
        return true
    }
    return false
  }

  return {
    getMyApps,
    getAppBySlug,
    getPublicAppBySlug,
    getMyAppBySlug,
    createApp,
    updateApp,
    deleteApp,
    isSlugTaken,
  }
}
