import { useStorage } from '@vueuse/core'
import { acceptHMRUpdate, defineStore } from 'pinia'

export type ThemeMode = 'system' | 'light' | 'dark'
export type AppIconStyle = 'original' | 'liquid-glass' | 'flat-color' | 'gradient' | 'minimal'
/** Preferred number of native WebView sessions; automatic mode follows the device memory tier. */
export type SessionLimitPreference = 'auto' | 2 | 3 | 4 | 5 | 6 | 7
/**
 * iOS 内嵌浏览器模式（用户可在设置中选择）：
 * titlebar = 标题栏视图（顶部固定导航栏，自动套用应用主题色，右上角单菜单按钮，底部仍铺满）；
 * system = 手机内置浏览器（SFSafariViewController）。
 *
 * 沉浸视图（全屏平铺 + 悬浮胶囊）不再作为用户全局选项，仅由官方应用经目录声明
 * `YlfAppInfo.displayMode = 'immersive'` 启用（详见 docs/dev/in-app-browser.md）；
 * 故打开时透传给原生的 displayMode 仍可能是 'immersive'，但它来自应用声明而非此设置。
 */
export type InAppBrowserMode = 'titlebar' | 'system'
/** 沉浸/标题栏模式内点击跨站外链的打开方式：safari-view = App 内系统浏览器视图（不跳出）；default-browser = 跳出到手机默认浏览器 */
export type ExternalLinkMode = 'safari-view' | 'default-browser'

/** 应用图标风格选项（设置页渲染用） */
export const APP_ICON_STYLE_OPTIONS: { value: AppIconStyle, label: string }[] = [
  { value: 'original', label: '原始图标' },
  { value: 'liquid-glass', label: '液态玻璃' },
  { value: 'flat-color', label: '平铺色彩' },
  { value: 'gradient', label: '渐变立体' },
  { value: 'minimal', label: '极简描边' },
]

/** Session limits available to active members. */
export const SESSION_LIMIT_OPTIONS: { value: SessionLimitPreference, label: string }[] = [
  { value: 'auto', label: '自动（推荐）' },
  { value: 2, label: '2 个' },
  { value: 3, label: '3 个' },
  { value: 4, label: '4 个' },
  { value: 5, label: '5 个' },
  { value: 6, label: '6 个' },
  { value: 7, label: '7 个' },
]

/** 所有 localStorage 的 key 前缀 */
const STORAGE_KEYS = [
  'ylf_theme_mode',
  'ylf_icon_style',
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
  'ylf:in-app-browser-mode',
  'ylf:external-link-mode',
  'ylf:session-limit-preference',
  'ylf:purchased-apps',
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

  // ==================== 外观设置 ====================

  /** 主屏幕应用图标风格 */
  const appIconStyle = useStorage<AppIconStyle>('ylf_icon_style', 'original')

  function setAppIconStyle(style: AppIconStyle) {
    appIconStyle.value = style
  }

  // ==================== 云同步设置 ====================

  /** 云同步开关（总开关，关闭后不会与 CloudBase 进行任何同步） */
  const cloudSyncEnabled = useStorage<boolean>('ylf:cloud-sync-enabled', true)
  /** 自动同步开关（开启后本地变更自动同步到云端） */
  const cloudAutoSync = useStorage<boolean>('ylf:cloud-auto-sync', true)

  // ==================== 浏览设置 ====================

  /** iOS 内嵌浏览器模式（默认标题栏视图；沉浸模式已下线为官方应用专属） */
  const inAppBrowserMode = useStorage<InAppBrowserMode>('ylf:in-app-browser-mode', 'titlebar')
  // 迁移：老用户曾选过已下线的「沉浸模式」，回落到标题栏（沉浸现仅由应用声明启用）
  if ((inAppBrowserMode.value as string) === 'immersive')
    inAppBrowserMode.value = 'titlebar'

  /** 沉浸模式内跨站外链的打开方式（默认 App 内系统浏览器视图，不跳出） */
  const externalLinkMode = useStorage<ExternalLinkMode>('ylf:external-link-mode', 'safari-view')

  /** Members may override the automatic native WebView session limit with a value from 2 to 7. */
  const sessionLimitPreference = useStorage<SessionLimitPreference>('ylf:session-limit-preference', 'auto')
  if (!SESSION_LIMIT_OPTIONS.some(option => option.value === sessionLimitPreference.value))
    sessionLimitPreference.value = 'auto'

  function setSessionLimitPreference(preference: SessionLimitPreference) {
    sessionLimitPreference.value = preference
  }

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
    // 外观
    appIconStyle,
    setAppIconStyle,
    // 浏览
    inAppBrowserMode,
    externalLinkMode,
    sessionLimitPreference,
    setSessionLimitPreference,
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
