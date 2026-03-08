import { useStorage } from '@vueuse/core'
import { acceptHMRUpdate, defineStore } from 'pinia'

export type ThemeMode = 'system' | 'light' | 'dark'

/** 所有 localStorage 的 key 前缀 */
const STORAGE_KEYS = [
  'ylf_theme_mode',
  'ylf_developer_mode',
  'ylf_api_environment',
  'ylf:homescreen-apps',
  'ylf:dock-apps',
  'ylf:recent-apps',
  'ylf:recent-apps-v2',
  'ylf:homescreen-sync-at',
  'ylf:cloud-sync-enabled',
  'ylf:cloud-auto-sync',
  'ylf:dock-visible',
] as const

export const useSettingsStore = defineStore('settings', () => {
  // ==================== 主题设置 ====================

  const themeMode = useStorage<ThemeMode>('ylf_theme_mode', 'system')
  const colorMode = useColorMode()

  function applyTheme(mode: ThemeMode) {
    themeMode.value = mode

    if (mode === 'system') {
      colorMode.preference = 'system'
    }
    else {
      colorMode.preference = mode
    }

    if (import.meta.client) {
      const html = document.documentElement
      if (mode === 'system') {
        const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
        html.classList.toggle('dark', prefersDark)
      }
      else {
        html.classList.toggle('dark', mode === 'dark')
      }
    }
  }

  function initTheme() {
    applyTheme(themeMode.value)
  }

  const currentTheme = computed(() => {
    if (themeMode.value === 'system') {
      return colorMode.value
    }
    return themeMode.value
  })

  if (import.meta.client) {
    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
    mediaQuery.addEventListener('change', (e) => {
      if (themeMode.value === 'system') {
        const html = document.documentElement
        html.classList.toggle('dark', e.matches)
      }
    })
  }

  // ==================== 云同步设置 ====================

  /** 云同步开关（总开关，关闭后不会与 CloudBase 进行任何同步） */
  const cloudSyncEnabled = useStorage<boolean>('ylf:cloud-sync-enabled', true)
  /** 自动同步开关（开启后本地变更自动同步到云端） */
  const cloudAutoSync = useStorage<boolean>('ylf:cloud-auto-sync', true)

  // ==================== 主屏幕设置 ====================

  /** 是否显示 Dock 栏（默认隐藏） */
  const dockVisible = useStorage<boolean>('ylf:dock-visible', false)

  // ==================== 存储空间 ====================

  /** 计算本地存储已用空间（字节） */
  function getLocalStorageUsage(): { used: number, keys: number } {
    if (!import.meta.client)
      return { used: 0, keys: 0 }

    let totalSize = 0
    let keyCount = 0

    for (const key of STORAGE_KEYS) {
      const value = localStorage.getItem(key)
      if (value !== null) {
        totalSize += key.length + value.length
        keyCount++
      }
    }

    return { used: totalSize * 2, keys: keyCount } // UTF-16 编码，每字符 2 字节
  }

  /** 清除所有应用本地缓存（不含认证信息） */
  function clearLocalStorage() {
    if (!import.meta.client)
      return

    for (const key of STORAGE_KEYS) {
      localStorage.removeItem(key)
    }
  }

  return {
    // 主题
    themeMode,
    currentTheme,
    applyTheme,
    initTheme,
    // 云同步
    cloudSyncEnabled,
    cloudAutoSync,
    // 主屏幕
    dockVisible,
    // 存储
    getLocalStorageUsage,
    clearLocalStorage,
  }
})

if (import.meta.hot)
  import.meta.hot.accept(acceptHMRUpdate(useSettingsStore, import.meta.hot))
