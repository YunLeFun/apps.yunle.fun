import type { YlfAppInfo } from '~~/packages/types'
import { useStorage } from '@vueuse/core'
import { acceptHMRUpdate, defineStore } from 'pinia'

export const useAppStore = defineStore('app', () => {
  /**
   * 最近使用应用的最大数量
   */
  const MAX_RECENT_APPS = 20

  // 使用 useStorage 自动处理响应式和持久化
  const recentApps = useStorage<YlfAppInfo[]>('ylf:recent-apps', [])

  /**
   * 添加应用到最近使用列表
   */
  function addRecentApp(app: YlfAppInfo) {
    // 移除已存在的相同应用
    const index = recentApps.value.findIndex(item => item.id === app.id)
    if (index > -1) {
      recentApps.value.splice(index, 1)
    }

    // 添加到列表开头
    recentApps.value.unshift(app)

    // 限制列表长度
    if (recentApps.value.length > MAX_RECENT_APPS) {
      recentApps.value = recentApps.value.slice(0, MAX_RECENT_APPS)
    }
  }

  /**
   * 清空最近使用列表
   */
  function clearRecentApps() {
    recentApps.value = []
  }

  return {
    recentApps,
    addRecentApp,
    clearRecentApps,
  }
})

if (import.meta.hot)
  import.meta.hot.accept(acceptHMRUpdate(useAppStore, import.meta.hot))
