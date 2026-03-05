import type { YlfAppInfo } from '~~/packages/types'
import type { HomeScreenConfig, InstalledApp, RecentApp } from '~/types/homeScreen'
import { useStorage } from '@vueuse/core'
import { acceptHMRUpdate, defineStore } from 'pinia'
import { DOCK_MAX_APPS, HOME_SCREEN_PAGE_SIZE, RECENT_MAX_APPS } from '~/types/homeScreen'

/**
 * Home Screen 状态 Store
 * localStorage 缓存 + CloudBase 异步同步
 */
export const useHomeScreenStore = defineStore('homeScreen', () => {
  // ==================== 持久化状态 ====================

  const installedApps = useStorage<InstalledApp[]>('ylf:homescreen-apps', [])
  const dockApps = useStorage<InstalledApp[]>('ylf:dock-apps', [])
  const recentApps = useStorage<RecentApp[]>('ylf:recent-apps-v2', [])
  const lastSyncAt = useStorage<number>('ylf:homescreen-sync-at', 0)

  // ==================== 运行时状态 ====================

  /** 编辑模式（长按进入） */
  const isEditMode = ref(false)
  /** 编辑模式期间是否有待同步的变更 */
  const hasPendingChanges = ref(false)
  /** 当前页码（0-based） */
  const currentPage = ref(0)
  /** 是否正在同步到 CloudBase */
  const isSyncing = ref(false)
  /** CloudBase 文档 ID */
  const cloudDocId = ref<string | null>(null)

  // ==================== 计算属性 ====================

  /** 分页后的 Home Screen 应用 */
  const pagedApps = computed(() => {
    const pages: InstalledApp[][] = []
    const apps = installedApps.value
    for (let i = 0; i < apps.length; i += HOME_SCREEN_PAGE_SIZE) {
      pages.push(apps.slice(i, i + HOME_SCREEN_PAGE_SIZE))
    }
    // 至少保留一个空页
    if (pages.length === 0)
      pages.push([])
    return pages
  })

  /** 总页数 */
  const totalPages = computed(() => pagedApps.value.length)

  // ==================== 安装/卸载 ====================

  /** 安装应用到 Home Screen */
  function installApp(appId: string) {
    // 检查是否已安装
    if (isInstalled(appId))
      return

    installedApps.value.push({ appId })
  }

  /** 从 Home Screen 卸载应用 */
  function uninstallApp(appId: string) {
    installedApps.value = installedApps.value.filter(a => a.appId !== appId)
    // 也从 Dock 移除
    dockApps.value = dockApps.value.filter(a => a.appId !== appId)
  }

  /** 检查应用是否已安装 */
  function isInstalled(appId: string): boolean {
    return installedApps.value.some(a => a.appId === appId)
      || dockApps.value.some(a => a.appId === appId)
  }

  // ==================== 排序 ====================

  /** 更新 Home Screen 应用排序（拖拽后调用） */
  function updateInstalledApps(apps: InstalledApp[]) {
    installedApps.value = apps
  }

  /** 更新 Dock 应用 */
  function updateDockApps(apps: InstalledApp[]) {
    if (apps.length > DOCK_MAX_APPS) {
      apps = apps.slice(0, DOCK_MAX_APPS)
    }
    dockApps.value = apps
  }

  // ==================== 最近使用 ====================

  /** 添加到最近使用 */
  function addRecentApp(appId: string) {
    const now = Date.now()
    // 移除已存在的
    recentApps.value = recentApps.value.filter(a => a.appId !== appId)
    // 添加到开头
    recentApps.value.unshift({ appId, usedAt: now })
    // 限制数量
    if (recentApps.value.length > RECENT_MAX_APPS) {
      recentApps.value = recentApps.value.slice(0, RECENT_MAX_APPS)
    }
  }

  /** 从最近使用中移除单个应用 */
  function removeRecentApp(appId: string) {
    recentApps.value = recentApps.value.filter(a => a.appId !== appId)
  }

  /** 清空最近使用 */
  function clearRecentApps() {
    recentApps.value = []
  }

  // ==================== 编辑模式 ====================

  function enterEditMode() {
    isEditMode.value = true
    hasPendingChanges.value = false
  }

  function exitEditMode() {
    isEditMode.value = false
  }

  /** 标记有待同步的变更 */
  function markPendingChanges() {
    hasPendingChanges.value = true
  }

  /** 消费并重置待同步标记，返回是否有待同步变更 */
  function consumePendingChanges(): boolean {
    const had = hasPendingChanges.value
    hasPendingChanges.value = false
    return had
  }

  // ==================== 同步 ====================

  /** 从 CloudBase 数据恢复 Home Screen */
  function restoreFromCloud(config: HomeScreenConfig, docId: string) {
    cloudDocId.value = docId
    // 仅当云端数据更新时才覆盖本地
    if (config.updatedAt > lastSyncAt.value) {
      installedApps.value = config.installedApps
      dockApps.value = config.dockApps
      recentApps.value = config.recentApps
      lastSyncAt.value = config.updatedAt
    }
  }

  /** 获取当前 Home Screen 配置（用于同步到 CloudBase） */
  function getHomeScreenConfig(): HomeScreenConfig {
    return {
      installedApps: installedApps.value,
      dockApps: dockApps.value,
      recentApps: recentApps.value,
      updatedAt: Date.now(),
    }
  }

  /** 用默认数据初始化 Home Screen（首次使用） */
  function initWithDefaults(apps: YlfAppInfo[]) {
    if (installedApps.value.length > 0)
      return // 已有数据不覆盖

    installedApps.value = apps.map(app => ({
      appId: app.id || app.slug,
    }))
  }

  return {
    // 持久化状态
    installedApps,
    dockApps,
    recentApps,
    lastSyncAt,
    // 运行时状态
    isEditMode,
    hasPendingChanges,
    currentPage,
    isSyncing,
    cloudDocId,
    // 计算属性
    pagedApps,
    totalPages,
    // 方法
    installApp,
    uninstallApp,
    isInstalled,
    updateInstalledApps,
    updateDockApps,
    addRecentApp,
    removeRecentApp,
    clearRecentApps,
    enterEditMode,
    exitEditMode,
    markPendingChanges,
    consumePendingChanges,
    restoreFromCloud,
    getHomeScreenConfig,
    initWithDefaults,
  }
})

if (import.meta.hot)
  import.meta.hot.accept(acceptHMRUpdate(useHomeScreenStore, import.meta.hot))
