<script setup lang="ts">
import type { GuestCommand } from '../../shared/desktop'
import { MACOS_TITLEBAR_HEIGHT, SHELL_TOOLBAR_HEIGHT, SIDEBAR_WIDTH } from '../../shared/window-layout'
import { deriveBrowseCategories, resolveRecentApps } from '../utils/catalog-view'

type CatalogView = 'explore' | 'all' | 'recent' | 'category'
const { state, error, available, openApp, refreshCatalog, command } = useDesktop()
const { slugs, record } = useRecentApps()
const colorMode = useColorMode()
const view = ref<CatalogView | 'workspace'>('explore')
const category = ref('')
const query = ref('')
const opening = ref('')
const apps = computed(() => state.value?.catalog.apps || [])
const categories = computed(() => deriveBrowseCategories(apps.value).filter(item => item.id !== 'all'))
const recentApps = computed(() => resolveRecentApps(apps.value, slugs.value))
const activeApp = computed(() => apps.value.find(app => app.id === state.value?.guest.appId))
const inWorkspace = computed(() => view.value === 'workspace' && !!state.value?.guest.open)
const catalogView = computed(() => view.value === 'workspace' ? 'explore' : view.value)
const toolbarTitle = computed(() => query.value.trim() ? '搜索' : view.value === 'category' ? category.value : view.value === 'all' ? '全部应用' : view.value === 'recent' ? '最近打开' : '探索')
const sourceLabel = computed(() => state.value?.catalog.loading ? '正在更新目录…' : state.value?.catalog.source === 'online' ? '目录已更新' : state.value?.catalog.source === 'cache' ? '缓存目录' : '离线目录')
const layoutStyle = {
  '--sidebar-width': `${SIDEBAR_WIDTH}px`,
  '--toolbar-height': `${SHELL_TOOLBAR_HEIGHT}px`,
  '--mac-titlebar-height': `${MACOS_TITLEBAR_HEIGHT}px`,
}
let openSequence = 0
let openingSlug = ''
function cancelOpening() {
  openSequence++
  openingSlug = ''
  opening.value = ''
}
function navigate(next: CatalogView | 'workspace') {
  cancelOpening()
  query.value = ''
  view.value = next
}
function selectCategory(value: string) {
  category.value = value
  navigate('category')
}
function search(value: string) {
  cancelOpening()
  query.value = value
  if (value.trim())
    view.value = 'all'
}
async function open(appId: string) {
  const entry = apps.value.find(app => app.id === appId && app.available)
  if (!entry || !available.value)
    return
  if (openingSlug === entry.slug)
    return
  const sequence = ++openSequence
  openingSlug = entry.slug
  opening.value = entry.name
  const result = await openApp(appId)
  if (sequence !== openSequence)
    return
  opening.value = ''
  openingSlug = ''
  if (!result?.guest.open)
    return
  const opened = result.catalog.apps.find(app => app.id === result.guest.appId)
  if (opened?.slug !== entry.slug)
    return
  navigate('workspace')
  if (!result.guest.error && !result.guest.loading)
    record(entry.slug)
}
onBeforeUnmount(cancelOpening)
async function runCommand(value: GuestCommand) {
  if (value === 'close')
    cancelOpening()
  await command(value)
}
watch(() => state.value?.guest.open, (open) => {
  if (!open && view.value === 'workspace')
    navigate('explore')
})
watch([view, () => state.value?.guest], ([currentView, guest]) => {
  if (currentView !== 'workspace' || !guest?.open || guest.loading || guest.error)
    return
  const app = apps.value.find(app => app.id === guest.appId && app.available)
  if (app)
    record(app.slug)
})
</script>

<template>
  <main class="desktop" :class="{ mac: state?.platform === 'darwin' }" :style="layoutStyle">
    <CatalogSidebar :categories="categories" :view="view" :category="category" :query="query" :active-app="activeApp" :appearance="colorMode.preference" @navigate="navigate" @category="selectCategory" @update:query="search" @update:appearance="colorMode.preference = $event" />
    <section class="workspace" :aria-label="inWorkspace ? '应用工作区' : '发现应用'">
      <template v-if="inWorkspace">
        <GuestToolbar :guest="state?.guest" :app="activeApp" :refreshing="state?.catalog.loading" @command="runCommand" @browse="navigate('explore')" @refresh="refreshCatalog" />
        <p v-if="error || state?.guest.error" role="alert" class="inline-notice error">
          {{ error || state?.guest.error }}
        </p>
        <AppViewport :open="true" />
      </template>
      <template v-else>
        <header class="shell-toolbar">
          <span class="toolbar-title">{{ toolbarTitle }}</span>
          <div class="toolbar-trailing">
            <span class="catalog-status" aria-live="polite">{{ opening ? `正在打开${opening}…` : sourceLabel }}</span><button class="icon-button" :disabled="!available || state?.catalog.loading" aria-label="刷新目录" title="刷新目录" @click="refreshCatalog">
              <ShellIcon name="refresh" />
            </button>
          </div>
        </header>
        <p v-if="error || state?.catalog.error" :role="error ? 'alert' : 'status'" class="inline-notice" :class="{ error }">
          {{ error || state?.catalog.error }}
        </p>
        <p v-if="!available" class="inline-notice">
          在云乐坊桌面客户端中打开和使用应用。
        </p>
        <DiscoveryContent :apps="apps" :view="catalogView" :category="category" :query="query" :recent-apps="recentApps" :available="available" :loading="state?.catalog.loading" @open="open" @navigate="navigate" />
      </template>
    </section>
  </main>
</template>
