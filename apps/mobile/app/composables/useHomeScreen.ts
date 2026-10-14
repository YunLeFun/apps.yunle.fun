import type { InstalledApp } from '~/types/homeScreen'
import { useDebounceFn } from '@vueuse/core'
import consola from 'consola'

const COLLECTION = 'user_home_screens'
let syncWriteQueue: Promise<void> = Promise.resolve()

interface DatabaseResult {
  code?: string | number
  message?: string
}

interface DatabaseUpdateResult extends DatabaseResult {
  updated?: number
}

interface DatabaseAddResult extends DatabaseResult {
  _id?: string
}

function assertDatabaseSuccess(result: DatabaseResult, fallbackMessage: string) {
  if (result.code)
    throw new Error(result.message || fallbackMessage)
}

function enqueueSyncWrite(task: () => Promise<void>): Promise<void> {
  const queuedTask = syncWriteQueue.then(task, task)
  syncWriteQueue = queuedTask.catch(() => {})
  return queuedTask
}

/**
 * Home Screen 数据管理 composable
 * 负责 CloudBase 数据同步和 Home Screen 操作
 */
export function useHomeScreen() {
  const { app, auth } = useCloudbase()
  const homeScreenStore = useHomeScreenStore()
  const userStore = useUserStore()
  const { showError } = useToast()
  const db = app.database()

  /**
   * 确保 CloudBase Auth session 有效，返回当前用户 ID
   *
   * 安全规则：doc._openid == auth.openid || doc._openid == auth.uid
   * - auth.openid: 微信登录方式的 openid
   * - auth.uid: 非微信登录方式的 user_id（Auth v2 的 sub）
   * - _openid: CloudBase 服务端 add() 时自动注入，客户端不可手动设置
   */
  async function ensureAuth(): Promise<string | null> {
    try {
      const { data, error } = await auth.getSession()
      if (error || !data?.session?.access_token)
        return null

      let u = data.session.user as any
      let uid = u?.sub || u?.uid || u?.id

      if (!uid) {
        const { data: userData, error: userError } = await auth.getUser()
        if (userError || !userData?.user)
          return null

        u = userData.user as any
        uid = u.sub || u.uid || u.id
      }
      if (!uid || u?.is_anonymous)
        return null

      // 会话身份可能已切换，始终让业务 store 与 CloudBase 当前会话保持一致。
      if (userStore.userInfo?.id !== uid) {
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
   * 从 CloudBase 加载 Home Screen 数据
   *
   * @param force 强制覆盖本地（切换账号时使用）
   */
  async function loadFromCloud(force = false) {
    const uid = await ensureAuth()
    if (!uid)
      return

    try {
      // 按 updatedAt 倒序取最新文档：历史 bug 可能产生过同一用户的多份文档
      const { data } = await db
        .collection(COLLECTION)
        .where({ _openid: uid })
        .orderBy('updatedAt', 'desc')
        .limit(1)
        .get()

      if (data && data.length > 0) {
        const doc = data[0] as any
        homeScreenStore.restoreFromCloud({
          installedApps: doc.installedApps || [],
          dockApps: doc.dockApps || [],
          recentApps: doc.recentApps || [],
          updatedAt: doc.updatedAt || 0,
        }, doc._id, force)
      }
    }
    catch (e) {
      consola.error('[HomeScreen] loadFromCloud failed:', e)
      showError('云端数据加载失败，请检查网络')
    }
  }

  /**
   * 切换账号后重新加载云端数据：先重置同步状态，再强制覆盖本地，
   * 避免上一个账号的 lastSyncAt 挡住新账号数据。
   */
  async function reloadForAccount() {
    homeScreenStore.resetCloudState()
    await loadFromCloud(true)
  }

  const settingsStore = useSettingsStore()

  async function findLatestCloudDocId(uid: string): Promise<string | null> {
    const { data } = await db
      .collection(COLLECTION)
      .where({ _openid: uid })
      .orderBy('updatedAt', 'desc')
      .limit(1)
      .get()

    return data && data.length > 0
      ? (data[0] as { _id: string })._id
      : null
  }

  /** 同步到 CloudBase（防抖 500ms），受云同步总开关控制 */
  async function performCloudSync() {
    if (!settingsStore.cloudSyncEnabled)
      return

    const uid = await ensureAuth()
    if (!uid)
      return

    homeScreenStore.isSyncing = true
    const config = homeScreenStore.getHomeScreenConfig()
    const payload = {
      installedApps: config.installedApps,
      dockApps: config.dockApps,
      recentApps: config.recentApps,
      updatedAt: config.updatedAt,
    }

    try {
      // 重启后 cloudDocId 为空：先按 _openid 查找既有文档，避免重复创建（upsert）
      if (!homeScreenStore.cloudDocId)
        homeScreenStore.cloudDocId = await findLatestCloudDocId(uid)

      let needCreate = !homeScreenStore.cloudDocId
      if (homeScreenStore.cloudDocId) {
        const attemptedDocId = homeScreenStore.cloudDocId
        const res = await db.collection(COLLECTION)
          .where({
            _id: attemptedDocId,
            _openid: uid,
          })
          .update(payload) as unknown as DatabaseUpdateResult
        assertDatabaseSuccess(res, '云端数据更新失败')
        if (res.updated === undefined)
          throw new Error('云端数据更新结果缺少 updated 字段')

        // 旧账号或已删除文档会命中 0 条。先重新解析当前账号文档，
        // 避免在账号切换与并发同步时直接创建重复记录。
        if (res.updated === 0) {
          homeScreenStore.cloudDocId = await findLatestCloudDocId(uid)
          if (homeScreenStore.cloudDocId && homeScreenStore.cloudDocId !== attemptedDocId) {
            const retryRes = await db.collection(COLLECTION)
              .where({
                _id: homeScreenStore.cloudDocId,
                _openid: uid,
              })
              .update(payload) as unknown as DatabaseUpdateResult
            assertDatabaseSuccess(retryRes, '云端数据更新失败')
            if (retryRes.updated !== 1)
              throw new Error('重新定位云端数据后仍未能更新')
            needCreate = false
          }
          else if (homeScreenStore.cloudDocId === attemptedDocId) {
            // CloudBase 对幂等更新可能返回 updated=0；重新查询仍能命中同一
            // owner 文档，说明记录没有丢失，也无需创建重复文档。
            needCreate = false
          }
          else {
            needCreate = true
          }
        }
      }

      if (needCreate) {
        const res = await db.collection(COLLECTION).add({
          ...payload,
          createdAt: Date.now(),
        }) as unknown as DatabaseAddResult
        assertDatabaseSuccess(res, '云端数据创建失败')
        if (!res._id)
          throw new Error('云端数据创建成功但未返回文档 ID')
        homeScreenStore.cloudDocId = res._id
      }

      homeScreenStore.lastSyncAt = config.updatedAt
    }
    catch (e) {
      consola.error('[HomeScreen] syncToCloud failed:', e)
      showError('云同步失败，变更已保存在本地')
    }
    finally {
      homeScreenStore.isSyncing = false
    }
  }

  const syncToCloud = useDebounceFn(
    () => enqueueSyncWrite(performCloudSync),
    500,
  )

  /** 自动同步：编辑模式下延迟到退出时批量同步 */
  function autoSyncToCloud() {
    if (!settingsStore.cloudSyncEnabled || !settingsStore.cloudAutoSync)
      return
    if (homeScreenStore.isEditMode) {
      homeScreenStore.markPendingChanges()
      return
    }
    syncToCloud()
  }

  /** 完成编辑：退出编辑模式，若有待同步变更则批量同步 */
  function finishEditing() {
    const hadPending = homeScreenStore.consumePendingChanges()
    homeScreenStore.exitEditMode()
    if (hadPending)
      autoSyncToCloud()
  }

  /** 安装应用并自动同步 */
  function installApp(appId: string) {
    homeScreenStore.installApp(appId)
    autoSyncToCloud()
  }

  /** 卸载应用并自动同步 */
  function uninstallApp(appId: string) {
    homeScreenStore.uninstallApp(appId)
    autoSyncToCloud()
  }

  /** 更新 Home Screen 排序并自动同步 */
  function updateOrder(apps: InstalledApp[]) {
    homeScreenStore.updateInstalledApps(apps)
    autoSyncToCloud()
  }

  /** 更新 Dock 并自动同步 */
  function updateDock(apps: InstalledApp[]) {
    homeScreenStore.updateDockApps(apps)
    autoSyncToCloud()
  }

  /** 记录最近使用并自动同步 */
  function recordRecentUse(appId: string) {
    homeScreenStore.addRecentApp(appId)
    autoSyncToCloud()
  }

  /** 从最近使用中移除并自动同步 */
  function removeRecentApp(appId: string) {
    homeScreenStore.removeRecentApp(appId)
    autoSyncToCloud()
  }

  return {
    loadFromCloud,
    reloadForAccount,
    syncToCloud,
    installApp,
    uninstallApp,
    updateOrder,
    updateDock,
    recordRecentUse,
    removeRecentApp,
    finishEditing,
  }
}
