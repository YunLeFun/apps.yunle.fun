import type { InstalledApp } from '~/types/homeScreen'
import { useDebounceFn } from '@vueuse/core'
import consola from 'consola'

const COLLECTION = 'user_home_screens'

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
   * - _openid: CloudBase 服务端 add() 时自动注入，或代码手动设置
   */
  async function ensureAuth(): Promise<string | null> {
    if (userStore.isLoggedIn && userStore.userInfo?.id)
      return userStore.userInfo.id

    try {
      const { data, error } = await auth.getSession()
      if (error || !data?.session?.access_token)
        return null

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
   * 从 CloudBase 加载 Home Screen 数据
   *
   * @param force 强制覆盖本地（切换账号时使用）
   */
  async function loadFromCloud(force = false) {
    const uid = await ensureAuth()
    if (!uid)
      return

    try {
      const { data } = await db
        .collection(COLLECTION)
        .where({ _openid: uid })
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

  /** 同步到 CloudBase（防抖 500ms），受云同步总开关控制 */
  const syncToCloud = useDebounceFn(async () => {
    if (!settingsStore.cloudSyncEnabled)
      return

    const uid = await ensureAuth()
    if (!uid)
      return

    homeScreenStore.isSyncing = true
    const config = homeScreenStore.getHomeScreenConfig()

    try {
      if (homeScreenStore.cloudDocId) {
        await db.collection(COLLECTION)
          .doc(homeScreenStore.cloudDocId)
          .update({
            installedApps: config.installedApps,
            dockApps: config.dockApps,
            recentApps: config.recentApps,
            updatedAt: config.updatedAt,
          })
      }
      else {
        const res = await db.collection(COLLECTION).add({
          _openid: uid,
          installedApps: config.installedApps,
          dockApps: config.dockApps,
          recentApps: config.recentApps,
          createdAt: Date.now(),
          updatedAt: config.updatedAt,
        }) as unknown as { id: string }
        homeScreenStore.cloudDocId = res.id
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
  }, 500)

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
