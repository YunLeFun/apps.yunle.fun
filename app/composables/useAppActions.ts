import type { YlfAppInfo } from '@yunlefun/types'
import { consola } from 'consola'
import { homeApps } from '~/constants/apps'

export function useAppActions() {
  const appStore = useAppStore()
  const router = useRouter()
  const { showSuccess, showError, showInfo } = useToast()

  /**
   * 打开应用
   */
  function openApp(app: YlfAppInfo) {
    // 添加到最近使用列表
    appStore.addRecentApp(app)

    // 打开应用
    if (app.websiteUrl) {
      openCatalogAppInBrowser(app)
    }
  }

  /**
   * 移除应用
   */
  function removeApp(app: YlfAppInfo) {
    const index = homeApps.value.findIndex(item => item.id === app.id)
    if (index > -1) {
      homeApps.value.splice(index, 1)
      showInfo('应用已移除')
    }
  }

  /**
   * 编辑应用 — 跳转到工坊编辑页
   */
  function editApp(app: YlfAppInfo) {
    if (!app.slug) {
      showError('该应用暂不支持编辑')
      return
    }
    router.push(`/workshop/${app.slug}/edit`)
  }

  /**
   * 生成应用分享链接
   */
  function getShareUrl(app: YlfAppInfo) {
    const path = app.slug ? `/app/${app.slug}` : `/app/${app.id}`
    if (import.meta.client) {
      return `${window.location.origin}${path}`
    }
    return `https://yunle.fun${path}`
  }

  /**
   * 分享应用
   *
   * 优先级：Web Share API（含 Capacitor iOS WebView）→ 复制链接到剪贴板
   */
  async function shareApp(app: YlfAppInfo) {
    const url = getShareUrl(app)
    const title = app.name
    const text = app.description || app.tagline || `来云乐坊看看「${app.name}」`

    if (import.meta.client && typeof navigator !== 'undefined' && navigator.share) {
      try {
        await navigator.share({ title, text, url })
        return
      }
      catch (err) {
        if ((err as Error).name === 'AbortError')
          return
        consola.debug('[share] navigator.share failed', err)
      }
    }

    try {
      if (import.meta.client && navigator.clipboard) {
        await navigator.clipboard.writeText(url)
        showSuccess('链接已复制到剪贴板')
        return
      }
    }
    catch (err) {
      consola.debug('[share] clipboard failed', err)
    }

    showError('当前环境不支持分享')
  }

  return {
    openApp,
    removeApp,
    shareApp,
    editApp,
    getShareUrl,
  }
}
