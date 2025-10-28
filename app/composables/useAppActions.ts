import type { YlfAppInfo } from '~~/packages/types'
import { consola } from 'consola'
import { homeApps } from '~/constants/apps'

export function useAppActions() {
  const appStore = useAppStore()
  const { showInfo } = useToast()

  /**
   * 打开应用
   */
  function openApp(app: YlfAppInfo) {
  // 添加到最近使用列表
    appStore.addRecentApp(app)

    // 打开应用
    if (app.url) {
      openInAppBrowser(app.url)
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
   * 编辑应用
   */
  function editApp(app: YlfAppInfo) {
    consola.log('编辑应用', app)
    // TODO: 实现编辑功能
    showInfo('编辑功能开发中...')
  }

  /**
   * 分享应用
   */
  function shareApp(app: YlfAppInfo) {
    consola.log('分享应用', app)
    // TODO: 实现分享功能
    showInfo('分享功能开发中...')
  }

  return {
    openApp,
    removeApp,
    shareApp,
    editApp,
  }
}
