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
  const { app, auth } = useCloudbase()
  const userStore = useUserStore()
  const db = app.database()
  const _ = db.command

  /**
   * 确保 CloudBase Auth session 有效，返回当前用户 ID
   *
   * 直接依赖 CloudBase SDK auth 单例实例（通过 useNuxtApp 缓存）
   * 和 Pinia userStore（全局单例），不再使用 useCloudbaseAuth() 的非单例 user ref
   */
  async function ensureAuth(): Promise<string | null> {
    // 快速路径：userStore 中已有用户 ID（Cookie 持久化）
    if (userStore.isLoggedIn && userStore.userInfo?.id)
      return userStore.userInfo.id

    // 通过 CloudBase SDK 恢复 session
    try {
      const { data, error } = await auth.getSession()
      if (error || !data?.session?.access_token)
        return null

      // session 有效，获取用户信息
      const { data: userData, error: userError } = await auth.getUser()
      if (userError || !userData?.user)
        return null

      const uid = (userData.user as any).uid || (userData.user as any).id
      if (!uid)
        return null

      // 同步到 userStore 以便后续快速路径命中
      if (!userStore.userInfo?.id) {
        userStore.login(data.session.access_token, {
          ...userStore.userInfo,
          id: uid,
          nickname: (userData.user as any).nickname || userStore.userInfo?.nickname || '',
          avatar: (userData.user as any).avatar_url || userStore.userInfo?.avatar || '',
        })
      }

      return uid
    }
    catch {
      return null
    }
  }

  /**
   * 获取当前用户的所有应用（含公开 + 私有）
   */
  async function getMyApps(): Promise<AppRecord[]> {
    const uid = await ensureAuth()
    if (!uid)
      return []
    const { data } = await db
      .collection(COLLECTION)
      .where({ _openid: uid })
      .orderBy('updatedAt', 'desc')
      .limit(100)
      .get()
    return data as AppRecord[]
  }

  /**
   * 根据文档 _id 获取当前用户自己的应用
   * 使用 doc(id).get() 直接查询，安全规则会自动校验 _openid
   */
  async function getMyAppById(id: string): Promise<AppRecord | null> {
    const uid = await ensureAuth()
    if (!uid)
      return null
    try {
      const { data } = await db
        .collection(COLLECTION)
        .where({ _id: id, _openid: uid })
        .limit(1)
        .get()
      return (data as AppRecord[])[0] || null
    }
    catch {
      return null
    }
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
    const uid = await ensureAuth()
    if (!uid)
      return null
    const { data } = await db
      .collection(COLLECTION)
      .where({ slug, _openid: uid })
      .limit(1)
      .get()
    return (data as AppRecord[])[0] || null
  }

  /**
   * 根据 slug 获取应用详情（优先查自己的，否则查公开的）
   */
  async function getAppBySlug(slug: string): Promise<AppRecord | null> {
    const myApp = await getMyAppBySlug(slug)
    if (myApp)
      return myApp
    return getPublicAppBySlug(slug)
  }

  /**
   * 创建应用，返回新文档 ID
   * _openid 由 CloudBase 服务端自动注入
   */
  async function createApp(form: CreateAppForm): Promise<string> {
    const uid = await ensureAuth()
    if (!uid)
      throw new Error('请先登录')

    const now = Date.now()
    const res = await db.collection(COLLECTION).add({
      ownerLogin: userStore.userInfo?.login || '',
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
    const { data: publicData } = await db
      .collection(COLLECTION)
      .where({ slug, isPublic: true })
      .limit(1)
      .get()
    if ((publicData as AppRecord[]).length > 0)
      return true
    const uid = await ensureAuth()
    if (uid) {
      const { data: myData } = await db
        .collection(COLLECTION)
        .where({ slug, _openid: uid })
        .limit(1)
        .get()
      if ((myData as AppRecord[]).length > 0)
        return true
    }
    return false
  }

  return {
    getMyApps,
    getMyAppById,
    getAppBySlug,
    getPublicAppBySlug,
    getMyAppBySlug,
    createApp,
    updateApp,
    deleteApp,
    isSlugTaken,
  }
}
