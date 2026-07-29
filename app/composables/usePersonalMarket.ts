import type { YlfAppInfo } from '@yunlefun/types'
import type { AppRecord } from '~/types/app'
import { recordToAppInfo } from '~/utils/appRecord'

export function usePersonalMarket(login: Ref<string>) {
  const { $api } = useNuxtApp()
  const apps = ref<YlfAppInfo[]>([])
  const loading = ref(false)
  const error = ref<string | null>(null)

  async function load() {
    const value = login.value.trim()
    if (!value) {
      apps.value = []
      return
    }

    loading.value = true
    error.value = null
    try {
      const response = await $api<{ items: AppRecord[] }>(
        `/api/markets/personal/${encodeURIComponent(value)}`,
      )
      apps.value = response.items.map(recordToAppInfo)
    }
    catch (reason: unknown) {
      apps.value = []
      error.value = reason instanceof Error ? reason.message : '个人主页加载失败'
    }
    finally {
      loading.value = false
    }
  }

  return {
    apps: readonly(apps),
    loading: readonly(loading),
    error: readonly(error),
    load,
  }
}
