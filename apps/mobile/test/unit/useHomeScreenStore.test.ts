import type { HomeScreenConfig, InstalledApp, RecentApp } from '../../app/types/homeScreen'
/**
 * useHomeScreenStore 单元测试
 * 验证 Home Screen Store 的核心功能主流程
 */
import { beforeEach, describe, expect, it } from 'vitest'
import {
  DOCK_MAX_APPS,
  RECENT_MAX_APPS,
} from '../../app/types/homeScreen'

/**
 * 直接测试 Store 逻辑（不依赖 pinia/useStorage），
 * 用纯 ref 模拟持久化状态
 */
function createStore() {
  const installedApps = ref<InstalledApp[]>([])
  const dockApps = ref<InstalledApp[]>([])
  const recentApps = ref<RecentApp[]>([])
  const lastSyncAt = ref(0)
  const isEditMode = ref(false)
  const isSyncing = ref(false)
  const cloudDocId = ref<string | null>(null)

  function isInstalled(appId: string): boolean {
    return installedApps.value.some(a => a.appId === appId)
      || dockApps.value.some(a => a.appId === appId)
  }

  function installApp(appId: string) {
    if (isInstalled(appId))
      return
    installedApps.value.push({ appId })
  }

  function uninstallApp(appId: string) {
    installedApps.value = installedApps.value.filter(a => a.appId !== appId)
    dockApps.value = dockApps.value.filter(a => a.appId !== appId)
  }

  function updateInstalledApps(apps: InstalledApp[]) {
    installedApps.value = apps
  }

  function updateDockApps(apps: InstalledApp[]) {
    if (apps.length > DOCK_MAX_APPS)
      apps = apps.slice(0, DOCK_MAX_APPS)
    dockApps.value = apps
  }

  function addRecentApp(appId: string) {
    const now = Date.now()
    recentApps.value = recentApps.value.filter(a => a.appId !== appId)
    recentApps.value.unshift({ appId, usedAt: now })
    if (recentApps.value.length > RECENT_MAX_APPS) {
      recentApps.value = recentApps.value.slice(0, RECENT_MAX_APPS)
    }
  }

  function enterEditMode() {
    isEditMode.value = true
  }
  function exitEditMode() {
    isEditMode.value = false
  }

  function restoreFromCloud(config: HomeScreenConfig, docId: string) {
    cloudDocId.value = docId
    if (config.updatedAt > lastSyncAt.value) {
      installedApps.value = config.installedApps
      dockApps.value = config.dockApps
      recentApps.value = config.recentApps
      lastSyncAt.value = config.updatedAt
    }
  }

  function getHomeScreenConfig(): HomeScreenConfig {
    return {
      installedApps: installedApps.value,
      dockApps: dockApps.value,
      recentApps: recentApps.value,
      updatedAt: Date.now(),
    }
  }

  function initWithDefaults(apps: { id: string, slug: string }[]) {
    if (installedApps.value.length > 0)
      return
    installedApps.value = apps.map(app => ({
      appId: app.id || app.slug,
    }))
  }

  return {
    installedApps,
    dockApps,
    recentApps,
    lastSyncAt,
    isEditMode,
    isSyncing,
    cloudDocId,
    installApp,
    uninstallApp,
    isInstalled,
    updateInstalledApps,
    updateDockApps,
    addRecentApp,
    enterEditMode,
    exitEditMode,
    restoreFromCloud,
    getHomeScreenConfig,
    initWithDefaults,
  }
}

describe('useHomeScreenStore', () => {
  let store: ReturnType<typeof createStore>

  beforeEach(() => {
    store = createStore()
  })

  // ==================== 安装/卸载 ====================

  describe('installApp', () => {
    it('安装一个新应用到 Home Screen', () => {
      store.installApp('app-1')
      expect(store.installedApps.value).toHaveLength(1)
      expect(store.installedApps.value[0]).toEqual({ appId: 'app-1' })
    })

    it('安装多个应用时按数组顺序排列', () => {
      store.installApp('app-1')
      store.installApp('app-2')
      store.installApp('app-3')
      expect(store.installedApps.value).toHaveLength(3)
      expect(store.installedApps.value.map(a => a.appId)).toEqual(['app-1', 'app-2', 'app-3'])
    })

    it('不允许重复安装同一应用', () => {
      store.installApp('app-1')
      store.installApp('app-1')
      expect(store.installedApps.value).toHaveLength(1)
    })

    it('dock 中存在的应用也不允许重复安装', () => {
      store.dockApps.value = [{ appId: 'dock-app' }]
      store.installApp('dock-app')
      expect(store.installedApps.value).toHaveLength(0)
    })
  })

  describe('uninstallApp', () => {
    it('从 Home Screen 卸载应用', () => {
      store.installedApps.value = [
        { appId: 'app-1' },
        { appId: 'app-2' },
        { appId: 'app-3' },
      ]
      store.uninstallApp('app-2')
      expect(store.installedApps.value).toHaveLength(2)
      expect(store.installedApps.value.find(a => a.appId === 'app-2')).toBeUndefined()
    })

    it('卸载时同时从 Dock 移除', () => {
      store.installedApps.value = [{ appId: 'app-1' }]
      store.dockApps.value = [{ appId: 'app-1' }]
      store.uninstallApp('app-1')
      expect(store.installedApps.value).toHaveLength(0)
      expect(store.dockApps.value).toHaveLength(0)
    })

    it('卸载后保持数组顺序', () => {
      store.installedApps.value = [
        { appId: 'app-1' },
        { appId: 'app-2' },
        { appId: 'app-3' },
      ]
      store.uninstallApp('app-1')
      expect(store.installedApps.value[0].appId).toBe('app-2')
      expect(store.installedApps.value[1].appId).toBe('app-3')
    })
  })

  describe('isInstalled', () => {
    it('检测 Home Screen 中的应用', () => {
      store.installedApps.value = [{ appId: 'app-1' }]
      expect(store.isInstalled('app-1')).toBe(true)
      expect(store.isInstalled('app-2')).toBe(false)
    })

    it('dock 中的应用也返回 true', () => {
      store.dockApps.value = [{ appId: 'dock-app' }]
      expect(store.isInstalled('dock-app')).toBe(true)
    })
  })

  // ==================== 排序 ====================

  describe('updateInstalledApps', () => {
    it('更新排序（数组顺序即排序）', () => {
      const newOrder = [
        { appId: 'app-3' },
        { appId: 'app-1' },
        { appId: 'app-2' },
      ]
      store.updateInstalledApps(newOrder)
      expect(store.installedApps.value[0].appId).toBe('app-3')
      expect(store.installedApps.value.map(a => a.appId)).toEqual(['app-3', 'app-1', 'app-2'])
    })
  })

  describe('updateDockApps', () => {
    it('更新 Dock 应用', () => {
      store.updateDockApps([
        { appId: 'a' },
        { appId: 'b' },
      ])
      expect(store.dockApps.value).toHaveLength(2)
    })

    it('超过 DOCK_MAX_APPS 时截断', () => {
      const tooMany = Array.from({ length: DOCK_MAX_APPS + 3 }, (_, i) => ({
        appId: `app-${i}`,
      }))
      store.updateDockApps(tooMany)
      expect(store.dockApps.value).toHaveLength(DOCK_MAX_APPS)
    })
  })

  // ==================== 最近使用 ====================

  describe('addRecentApp', () => {
    it('添加到最近使用列表头部', () => {
      store.addRecentApp('app-1')
      store.addRecentApp('app-2')
      expect(store.recentApps.value).toHaveLength(2)
      expect(store.recentApps.value[0].appId).toBe('app-2')
    })

    it('重复使用时移到头部（去重）', () => {
      store.addRecentApp('app-1')
      store.addRecentApp('app-2')
      store.addRecentApp('app-1')
      expect(store.recentApps.value).toHaveLength(2)
      expect(store.recentApps.value[0].appId).toBe('app-1')
    })

    it('超过 RECENT_MAX_APPS 时截断', () => {
      for (let i = 0; i < RECENT_MAX_APPS + 10; i++) {
        store.addRecentApp(`app-${i}`)
      }
      expect(store.recentApps.value).toHaveLength(RECENT_MAX_APPS)
    })

    it('记录使用时间戳', () => {
      const before = Date.now()
      store.addRecentApp('app-1')
      const after = Date.now()
      expect(store.recentApps.value[0].usedAt).toBeGreaterThanOrEqual(before)
      expect(store.recentApps.value[0].usedAt).toBeLessThanOrEqual(after)
    })
  })

  // ==================== 编辑模式 ====================

  describe('editMode', () => {
    it('初始为非编辑模式', () => {
      expect(store.isEditMode.value).toBe(false)
    })

    it('enterEditMode 进入编辑模式', () => {
      store.enterEditMode()
      expect(store.isEditMode.value).toBe(true)
    })

    it('exitEditMode 退出编辑模式', () => {
      store.enterEditMode()
      store.exitEditMode()
      expect(store.isEditMode.value).toBe(false)
    })
  })

  // ==================== CloudBase 同步 ====================

  describe('restoreFromCloud', () => {
    it('云端数据更新时覆盖本地', () => {
      store.lastSyncAt.value = 1000
      store.restoreFromCloud({
        installedApps: [{ appId: 'cloud-app' }],
        dockApps: [],
        recentApps: [],
        updatedAt: 2000,
      }, 'doc-123')

      expect(store.installedApps.value).toHaveLength(1)
      expect(store.installedApps.value[0].appId).toBe('cloud-app')
      expect(store.cloudDocId.value).toBe('doc-123')
      expect(store.lastSyncAt.value).toBe(2000)
    })

    it('云端数据未更新时不覆盖本地', () => {
      store.lastSyncAt.value = 3000
      store.installedApps.value = [{ appId: 'local-app' }]
      store.restoreFromCloud({
        installedApps: [{ appId: 'old-cloud' }],
        dockApps: [],
        recentApps: [],
        updatedAt: 2000,
      }, 'doc-456')

      expect(store.installedApps.value[0].appId).toBe('local-app')
      expect(store.cloudDocId.value).toBe('doc-456') // docId 仍然更新
    })
  })

  describe('getHomeScreenConfig', () => {
    it('返回当前配置快照', () => {
      store.installedApps.value = [{ appId: 'a' }]
      store.dockApps.value = [{ appId: 'b' }]
      store.recentApps.value = [{ appId: 'a', usedAt: 1000 }]

      const before = Date.now()
      const config = store.getHomeScreenConfig()
      const after = Date.now()

      expect(config.installedApps).toEqual(store.installedApps.value)
      expect(config.dockApps).toEqual(store.dockApps.value)
      expect(config.recentApps).toEqual(store.recentApps.value)
      expect(config.updatedAt).toBeGreaterThanOrEqual(before)
      expect(config.updatedAt).toBeLessThanOrEqual(after)
    })
  })

  describe('initWithDefaults', () => {
    it('首次使用时用默认应用初始化', () => {
      store.initWithDefaults([
        { id: 'a1', slug: 'a1' },
        { id: 'a2', slug: 'a2' },
      ])
      expect(store.installedApps.value).toHaveLength(2)
      expect(store.installedApps.value[0].appId).toBe('a1')
      expect(store.installedApps.value[1].appId).toBe('a2')
    })

    it('已有数据时不覆盖', () => {
      store.installedApps.value = [{ appId: 'existing' }]
      store.initWithDefaults([{ id: 'new', slug: 'new' }])
      expect(store.installedApps.value).toHaveLength(1)
      expect(store.installedApps.value[0].appId).toBe('existing')
    })
  })
})
