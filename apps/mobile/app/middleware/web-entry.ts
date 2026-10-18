import { Capacitor } from '@capacitor/core'
import { WEB_APP_ENTRY, WEB_ENTRY_STORAGE_KEY } from '~/constants/showcase'

/**
 * 根路径分流：展示页只面向浏览器访客。
 *
 * - Capacitor 原生壳（Android / 旧版 iOS）冷启动加载 `/`，必须直接进入应用。
 * - 已添加到主屏幕的网页（standalone）同样直接进入应用。
 * - 访客点过“打开网页版”后记住选择；`/?showcase` 可随时重新查看展示页。
 */
export default defineNuxtRouteMiddleware((to) => {
  if (import.meta.server)
    return
  if (Capacitor.isNativePlatform())
    return navigateTo(WEB_APP_ENTRY, { replace: true })

  const standalone = window.matchMedia?.('(display-mode: standalone)').matches
    || (navigator as Navigator & { standalone?: boolean }).standalone === true
  if (standalone)
    return navigateTo(WEB_APP_ENTRY, { replace: true })

  if ('showcase' in to.query)
    return
  let remembered: string | null = null
  try {
    remembered = localStorage.getItem(WEB_ENTRY_STORAGE_KEY)
  }
  catch {}
  if (remembered === 'app')
    return navigateTo(WEB_APP_ENTRY, { replace: true })
})
