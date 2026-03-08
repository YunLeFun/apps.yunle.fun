import type { AppMarketSource } from '~/types/market'
import { useStorage } from '@vueuse/core'
import { acceptHMRUpdate, defineStore } from 'pinia'

/** 官方市场的固定 ID */
export const OFFICIAL_MARKET_ID = '__official__'

export const useMarketSourcesStore = defineStore('marketSources', () => {
  const sources = useStorage<AppMarketSource[]>('ylf:market-sources', [])

  /** 当前选中的市场 ID（官方 or 第三方） */
  const activeSourceId = useStorage<string>('ylf:active-market', OFFICIAL_MARKET_ID)

  /** 当前是否为官方市场 */
  const isOfficial = computed(() => activeSourceId.value === OFFICIAL_MARKET_ID)

  /** 当前选中的第三方市场（如果选中了的话） */
  const activeSource = computed(() =>
    sources.value.find(s => s.id === activeSourceId.value),
  )

  /** 切换到指定市场 */
  function switchSource(id: string) {
    activeSourceId.value = id
  }

  /** 添加市场来源，URL 相同则视为重复 */
  function addSource(source: AppMarketSource): boolean {
    if (source.url && sources.value.some(s => s.url === source.url))
      return false
    sources.value.push(source)
    return true
  }

  /** 移除市场来源，若正在使用则切回官方 */
  function removeSource(id: string) {
    if (activeSourceId.value === id)
      activeSourceId.value = OFFICIAL_MARKET_ID
    sources.value = sources.value.filter(s => s.id !== id)
  }

  /** 检查 URL 是否已添加 */
  function hasSource(url: string): boolean {
    return sources.value.some(s => s.url === url)
  }

  return {
    sources,
    activeSourceId,
    isOfficial,
    activeSource,
    switchSource,
    addSource,
    removeSource,
    hasSource,
  }
})

if (import.meta.hot)
  import.meta.hot.accept(acceptHMRUpdate(useMarketSourcesStore, import.meta.hot))
