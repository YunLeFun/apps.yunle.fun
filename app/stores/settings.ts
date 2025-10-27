import { acceptHMRUpdate, defineStore } from 'pinia'

export type ThemeMode = 'system' | 'light' | 'dark'

export const useSettingsStore = defineStore('settings', () => {
  // 使用 Cookie 存储主题设置
  const themeMode = useCookie<ThemeMode>('ylf_theme_mode', {
    default: () => 'system',
    maxAge: 60 * 60 * 24 * 365, // 1 年过期
    sameSite: 'strict',
    secure: import.meta.env.PROD,
  })

  const colorMode = useColorMode()

  // 应用主题设置
  function applyTheme(mode: ThemeMode) {
    themeMode.value = mode

    if (mode === 'system') {
      // 跟随系统
      colorMode.preference = 'system'
    }
    else {
      // 固定模式
      colorMode.preference = mode
    }

    // 立即更新 DOM 类名以确保主题生效
    if (import.meta.client) {
      const html = document.documentElement
      if (mode === 'system') {
        // 检测系统主题
        const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
        html.classList.toggle('dark', prefersDark)
      }
      else {
        html.classList.toggle('dark', mode === 'dark')
      }
    }
  }

  // 初始化时应用保存的主题
  function initTheme() {
    applyTheme(themeMode.value)
  }

  // 获取当前实际的主题（考虑系统设置）
  const currentTheme = computed(() => {
    if (themeMode.value === 'system') {
      return colorMode.value
    }
    return themeMode.value
  })

  // 监听系统主题变化（仅在跟随系统模式下）
  if (import.meta.client) {
    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
    mediaQuery.addEventListener('change', (e) => {
      if (themeMode.value === 'system') {
        const html = document.documentElement
        html.classList.toggle('dark', e.matches)
      }
    })
  }

  return {
    themeMode,
    currentTheme,
    applyTheme,
    initTheme,
  }
})

if (import.meta.hot)
  import.meta.hot.accept(acceptHMRUpdate(useSettingsStore, import.meta.hot))
