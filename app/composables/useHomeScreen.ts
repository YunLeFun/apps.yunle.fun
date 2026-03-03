import type { InstalledApp } from '~/types/homeScreen'
import { useDebounceFn } from '@vueuse/core'

const COLLECTION = 'user_desktops'

/**
 * Home Screen 数据管理 composable
 * 负责 CloudBase 数据同步和 Home Screen 操作
 */
export function useHomeScreen() {
  const { app, auth } = useCloudbase()
  const homeScreenStore = useHomeScreenStore()
  const userStore = useUserStore()
  const db = app.database()

  /** 确保认证 */
  async function ensureAuth(): Promise<string | null> {
    if (userStore.isLoggedIn && userStore.userInfo?.id)
      return userStore.userInfo.id
    const { data, error } = await auth.getSession()
    if (error || !data?.session?.access_token)
      return null
    const { data: userData, error: userError } = await auth.getUser()
    if (userError || !userData?.user)
      return null
    return (userData.user as any).uid || (userData.user as any).id || null
  }

  /** 从 CloudBase 加载 Home Screen 数据 */
  async function loadFromCloud() {
    const uid = await ensureAuth()
    if (!uid)
      return

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
      }, doc._id)
    }
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

    if (homeScreenStore.cloudDocId) {
      await db.collection(COLLECTION).doc(homeScreenStore.cloudDocId).update({
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
    homeScreenStore.isSyncing = false
  }, 500)

  /** 自动同步：同时受云同步总开关和自动同步开关控制 */
  function autoSyncToCloud() {
    if (settingsStore.cloudSyncEnabled && settingsStore.cloudAutoSync)
      syncToCloud()
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

  return {
    loadFromCloud,
    syncToCloud,
    installApp,
    uninstallApp,
    updateOrder,
    updateDock,
    recordRecentUse,
  }
}
