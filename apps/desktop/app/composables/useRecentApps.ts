import { onMounted, readonly, shallowRef } from 'vue'
import { parseRecentSlugs, promoteRecentSlug } from '../utils/catalog-view'

const STORAGE_KEY = 'yunlefun.desktop.recent.v1'

export function useRecentApps() {
  const slugs = shallowRef<string[]>([])

  onMounted(() => {
    try {
      slugs.value = parseRecentSlugs(window.localStorage.getItem(STORAGE_KEY))
    }
    catch { /* Storage may be unavailable; in-memory history remains usable. */ }
  })

  function record(slug: string) {
    const next = promoteRecentSlug(slugs.value, slug)
    if (next.length === slugs.value.length && next.every((value, index) => value === slugs.value[index]))
      return
    slugs.value = next
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(next))
    }
    catch { /* A quota or privacy restriction must not block opening apps. */ }
  }

  return { slugs: readonly(slugs), record }
}
