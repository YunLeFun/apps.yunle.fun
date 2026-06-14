import type { AppRecord, CreateAppForm } from '~/types/app'
import { DEFAULT_APP_STATUS } from '~/types/app'

const COLLECTION = 'apps'

interface CloudBaseWriteResult {
  updated?: number
  deleted?: number
  code?: string
  message?: string
  msg?: string
}

/**
 * 应用数据管理 composable
 * 基于 CloudBase NoSQL 数据库
 *
 * 安全规则（CUSTOM）—— 上线前需要在 CloudBase 控制台同步更新：
 *   read:  "(doc.isPublic == true && doc.status == 'approved') || auth.uid == doc._openid"
 *   create: "auth.uid != null && auth.loginType != 'ANONYMOUS'"
 *   update: "auth.uid == doc._openid"
 *   delete: "auth.uid == doc._openid"
 *
 * where 查询必须包含安全规则可推导的条件：
 *   - 查自己的数据 → where 含 _openid
 *   - 查公开数据   → where 同时含 isPublic == true 与 status == 'approved'
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

      const u = userData.user as any
      const uid = u.sub || u.uid || u.id
      if (!uid)
        return null

      // 同步到 userStore 以便后续快速路径命中
      if (!userStore.userInfo?.id) {
        userStore.login(data.session.access_token, {
          ...userStore.userInfo,
          id: uid,
          nickname: u.name || u.nickname || userStore.userInfo?.nickname || '',
          avatar: u.picture || u.avatar_url || userStore.userInfo?.avatar || '',
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
   * 安全规则要求 where 中必须同时包含 isPublic: true 与 status: 'approved' 才能查询非本人数据
   */
  async function getPublicAppBySlug(slug: string): Promise<AppRecord | null> {
    const { data } = await db
      .collection(COLLECTION)
      .where({ slug, isPublic: true, status: 'approved' })
      .limit(1)
      .get()
    return (data as AppRecord[])[0] || null
  }

  /**
   * 根据 slug 获取当前用户自己的应用（不限公开/私有）
   */
  async function getMyAppBySlug(slug: string): Promise<AppRecord | null> {
    if (!slug)
      return null
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
   *
   * 新创建的应用默认 status='pending'，即使用户勾选了 isPublic
   * 也需要审核通过（status 改为 'approved'）后才会真正对外公开
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
      trustedHosts: form.trustedHosts || [],
      backupUrl: form.backupUrl || '',
      logo: form.logo || '',
      emoji: form.emoji || '',
      themeColor: form.themeColor || '',
      category: form.category || '',
      tags: form.tags || [],
      isPublic: form.isPublic,
      status: DEFAULT_APP_STATUS,
      createdAt: now,
      updatedAt: now,
    }) as unknown as { id: string }
    return res.id
  }

  /**
   * 更新应用
   *
   * 用户编辑会把 status 重置为 'pending' 并清空 rejectedReason，
   * 触发重新审核（与 App Store「重新提交」逻辑一致）
   */
  async function updateApp(id: string, updates: Partial<CreateAppForm>): Promise<void> {
    const uid = await ensureAuth()
    if (!uid)
      throw new Error('请先登录')

    const res = await db.collection(COLLECTION)
      .where({ _id: id, _openid: uid })
      .update({
        ...updates,
        status: DEFAULT_APP_STATUS,
        rejectedReason: '',
        reviewedAt: 0,
        updatedAt: Date.now(),
      }) as unknown as CloudBaseWriteResult

    if (res.code)
      throw new Error(res.message || res.msg || res.code)

    if (!res.updated)
      throw new Error('应用不存在或无权更新')
  }

  /**
   * 删除应用
   */
  async function deleteApp(id: string): Promise<void> {
    const uid = await ensureAuth()
    if (!uid)
      throw new Error('请先登录')

    const res = await db
      .collection(COLLECTION)
      .where({ _id: id, _openid: uid })
      .remove() as unknown as CloudBaseWriteResult

    if (res.code)
      throw new Error(res.message || res.msg || res.code)

    if (!res.deleted)
      throw new Error('应用不存在或无权删除')
  }

  /**
   * 检查 slug 是否已被占用（在本人数据 + 公开数据中查找）
   * 注意：未审核通过的应用对查询本人不冲突，但若已被他人提交（无论审核与否）仍视为占用，
   * 避免审核期间多人提交同一 slug
   */
  async function isSlugTaken(slug: string): Promise<boolean> {
    const { data: publicData } = await db
      .collection(COLLECTION)
      .where({ slug, isPublic: true, status: 'approved' })
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
