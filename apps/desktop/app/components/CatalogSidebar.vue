<script setup lang="ts">
import type { CatalogEntry } from '../../shared/desktop'

defineProps<{ categories: readonly string[], view: string, category: string, query: string, activeApp?: CatalogEntry, appearance: string }>()
defineEmits<{
  'navigate': [view: 'explore' | 'all' | 'recent' | 'workspace']
  'category': [category: string]
  'update:query': [value: string]
  'update:appearance': [value: string]
}>()
const navigation = [
  { view: 'explore', label: '探索', icon: 'explore' },
  { view: 'all', label: '全部应用', icon: 'grid' },
  { view: 'recent', label: '最近打开', icon: 'clock' },
] as const
function categoryIcon(category: string) {
  if (category === '游戏')
    return 'game'
  if (category === '设计')
    return 'pen'
  if (category === '生活')
    return 'house'
  if (category === '开发' || category === '插件')
    return 'code'
  if (category === 'AI' || category === '整活')
    return 'spark'
  if (category.includes('工具'))
    return 'tool'
  return 'grid'
}
</script>

<template>
  <aside class="catalog-sidebar" aria-label="应用目录">
    <div class="sidebar-titlebar" aria-hidden="true" />
    <div class="brand">
      <img src="/pwa-192x192.png" alt="" width="40" height="40"><h1>云乐坊</h1>
    </div>
    <label class="sidebar-search">
      <ShellIcon name="search" />
      <input :value="query" type="search" aria-label="搜索应用" placeholder="搜索应用" @input="$emit('update:query', ($event.target as HTMLInputElement).value)">
    </label>
    <div class="sidebar-scroll">
      <nav class="primary-nav" aria-label="浏览应用">
        <button v-for="item in navigation" :key="item.view" class="nav-item" :class="{ selected: view === item.view && !query }" :aria-current="view === item.view && !query ? 'page' : undefined" @click="$emit('navigate', item.view)">
          <ShellIcon :name="item.icon" /><span>{{ item.label }}</span>
        </button>
      </nav>
      <nav v-if="categories.length" class="category-nav" aria-label="应用分类">
        <h2>分类</h2>
        <button v-for="item in categories" :key="item" class="nav-item" :class="{ selected: view === 'category' && category === item && !query }" :aria-current="view === 'category' && category === item && !query ? 'page' : undefined" @click="$emit('category', item)">
          <ShellIcon :name="categoryIcon(item)" /><span>{{ item }}</span>
        </button>
      </nav>
      <div v-if="activeApp" class="current-app">
        <h2>正在使用</h2>
        <button class="nav-item" :class="{ selected: view === 'workspace' }" :aria-label="`继续使用${activeApp.name}`" @click="$emit('navigate', 'workspace')">
          <span class="current-emoji" aria-hidden="true">{{ activeApp.emoji }}</span><span>{{ activeApp.name }}</span><span class="running-dot" aria-hidden="true" />
        </button>
      </div>
    </div>
    <footer class="sidebar-footer">
      <NuxtLink class="nav-item about-link" to="/about" aria-label="关于云乐坊桌面端">
        <ShellIcon name="info" /><span>关于云乐坊</span>
      </NuxtLink>
      <label class="appearance-control"><ShellIcon name="sun" /><span>外观</span><select :value="appearance" aria-label="外观" @change="$emit('update:appearance', ($event.target as HTMLSelectElement).value)"><option value="system">跟随系统</option><option value="light">浅色</option><option value="dark">深色</option></select></label>
    </footer>
  </aside>
</template>

<style scoped>
.catalog-sidebar {
  width: var(--sidebar-width);
  flex: none;
  min-height: 0;
  display: flex;
  flex-direction: column;
  padding: 0 12px 12px;
  background: var(--sidebar);
  border-right: 1px solid var(--border);
}
.sidebar-titlebar {
  height: 20px;
  flex: none;
  -webkit-app-region: drag;
}
.mac .sidebar-titlebar {
  height: var(--mac-titlebar-height);
}
.brand {
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 2px 8px 20px;
}
.brand img {
  border-radius: 10px;
}
.brand h1 {
  margin: 0;
  font-size: 21px;
  letter-spacing: -0.6px;
  font-weight: 650;
}
.sidebar-search {
  display: flex;
  align-items: center;
  gap: 8px;
  height: 32px;
  padding: 0 9px;
  margin: 0 4px 18px;
  border: 1px solid var(--border);
  border-radius: 7px;
  background: var(--search);
  color: var(--muted);
}
.sidebar-search .shell-icon {
  width: 15px;
  height: 15px;
}
.sidebar-search input {
  width: 100%;
  min-width: 0;
  border: 0;
  outline: 0;
  background: transparent;
  color: var(--text);
  font: inherit;
  font-size: 12px;
}
.sidebar-search:focus-within {
  outline: 2px solid var(--accent);
  outline-offset: 1px;
}
.sidebar-search input:focus-visible {
  outline: 0;
}
.sidebar-search input::placeholder {
  color: var(--muted);
}
.sidebar-scroll {
  min-height: 0;
  flex: 1;
  overflow: auto;
  scrollbar-width: thin;
}
.nav-item {
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
  min-height: 34px;
  padding: 7px 10px;
  border: 0;
  border-radius: 7px;
  background: transparent;
  text-decoration: none;
  color: var(--text);
  cursor: pointer;
  font-size: 13px;
  text-align: left;
}
.nav-item > span:not(.running-dot) {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.nav-item .shell-icon {
  color: var(--muted);
}
.nav-item:hover {
  background: var(--hover);
}
.nav-item.selected {
  background: var(--selection);
}
.nav-item.selected .shell-icon {
  color: var(--accent);
}
.primary-nav .nav-item {
  margin-bottom: 3px;
}
.category-nav,
.current-app {
  margin-top: 19px;
}
.current-app h2,
.category-nav h2 {
  font-size: 11px;
  font-weight: 500;
  color: var(--muted);
  margin: 0 10px 5px;
}
.current-emoji {
  width: 18px;
  text-align: center;
  font-size: 16px;
  flex: none;
}
.running-dot {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: #30b36b;
  margin-left: auto;
  flex: none;
}
.sidebar-footer {
  padding-top: 8px;
}
.appearance-control {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 7px 10px 0;
  font-size: 12px;
  color: var(--muted);
}
.appearance-control select {
  margin-left: auto;
  min-width: 0;
  width: 90px;
  padding: 5px 2px 5px 6px;
  font-size: 11px;
  border: 1px solid var(--border);
  border-radius: 6px;
  background: var(--search);
  color: var(--text);
}
</style>
