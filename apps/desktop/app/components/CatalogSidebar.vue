<script setup lang="ts">
import type { CatalogEntry, CatalogState } from '../../shared/desktop'

const props = defineProps<{ catalog?: Omit<Readonly<CatalogState>, 'apps'> & { readonly apps: readonly CatalogEntry[] }, available: boolean, activeAppId?: string }>()
defineEmits<{ open: [appId: string], refresh: [] }>()
const query = ref('')
const category = ref('全部')
const categories = computed(() => ['全部', ...new Set(props.catalog?.apps.map(app => app.category) || [])])
const visibleApps = computed(() => {
  const search = query.value.trim().toLocaleLowerCase()
  return (props.catalog?.apps || []).filter(app =>
    (category.value === '全部' || category.value === app.category)
    && (!search || `${app.name} ${app.description} ${app.slug}`.toLocaleLowerCase().includes(search)),
  )
})
const sourceLabel = computed(() => props.catalog?.loading
  ? '正在刷新目录…'
  : props.catalog?.source === 'online' ? '应用目录已更新' : props.catalog?.source === 'cache' ? '正在使用缓存目录' : '离线可用应用')
</script>

<template>
  <aside class="catalog-sidebar" aria-label="应用目录">
    <div class="catalog-heading">
      <div>
        <h1>云乐坊</h1>
        <p>发现有趣的云应用</p>
      </div>
      <button class="button compact" :disabled="!available || catalog?.loading" aria-label="刷新目录" @click="$emit('refresh')">
        ↻
      </button>
    </div>
    <label class="search-label" for="catalog-search">搜索应用</label>
    <input id="catalog-search" v-model="query" class="search-input" type="search" placeholder="名称、简介或关键词">
    <label class="search-label" for="catalog-category">应用分类</label>
    <select id="catalog-category" v-model="category" class="search-input">
      <option v-for="item in categories" :key="item" :value="item">
        {{ item }}
      </option>
    </select>
    <p class="catalog-status" aria-live="polite">
      {{ sourceLabel }} · {{ visibleApps.length }} 个应用
    </p>
    <p v-if="catalog?.error" class="catalog-notice">
      {{ catalog.error }}
    </p>
    <div class="catalog-list">
      <button
        v-for="app in visibleApps" :key="app.id"
        class="catalog-app" :class="{ selected: activeAppId === app.id }"
        :disabled="!available || !app.available" :title="app.unavailableReason || app.description"
        :aria-label="`打开${app.name}`" @click="$emit('open', app.id)"
      >
        <span class="app-emoji" aria-hidden="true">{{ app.emoji }}</span>
        <span class="app-summary">
          <span class="app-name">{{ app.name }}</span>
          <span class="app-description">{{ app.unavailableReason || app.description || app.category }}</span>
        </span>
      </button>
      <p v-if="!visibleApps.length" class="empty-catalog">
        没有匹配的应用
      </p>
    </div>
    <NuxtLink class="text-link about-link" to="/about">
      关于云乐坊桌面端
    </NuxtLink>
  </aside>
</template>

<style scoped>
.catalog-sidebar {
  width: 304px;
  min-width: 264px;
  display: flex;
  flex-direction: column;
  border-right: 1px solid var(--border);
  padding: 24px 18px;
  background: var(--surface);
}
.catalog-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 22px;
}
.catalog-heading h1 {
  font-size: 24px;
  margin: 0 0 6px;
}
.catalog-heading p {
  font-size: 12px;
  margin: 0;
  color: var(--muted);
}
.search-label {
  font-size: 11px;
  color: var(--muted);
  margin-bottom: 6px;
}
.search-input {
  width: 100%;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--background);
  color: var(--text);
  padding: 10px;
  font: inherit;
  font-size: 13px;
  margin-bottom: 12px;
}
.catalog-status,
.catalog-notice {
  font-size: 11px;
  color: var(--muted);
  margin: 0 0 12px;
  line-height: 1.5;
}
.catalog-list {
  flex: 1;
  min-height: 0;
  overflow: auto;
  margin: 0 -6px;
  padding: 0 6px;
}
.catalog-app {
  width: 100%;
  display: flex;
  gap: 12px;
  align-items: center;
  text-align: left;
  border: 1px solid transparent;
  background: transparent;
  color: var(--text);
  border-radius: 10px;
  padding: 12px 10px;
  cursor: pointer;
  margin: 2px 0;
}
.catalog-app:hover:not(:disabled),
.catalog-app.selected {
  background: var(--accent-soft);
  border-color: var(--border);
}
.catalog-app:disabled {
  opacity: 0.45;
  cursor: default;
}
.app-emoji {
  font-size: 26px;
  width: 34px;
  flex-shrink: 0;
  text-align: center;
}
.app-summary {
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.app-name {
  font-size: 13px;
  font-weight: 600;
}
.app-description {
  font-size: 11px;
  line-height: 1.4;
  color: var(--muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.empty-catalog {
  color: var(--muted);
  font-size: 13px;
  text-align: center;
  padding: 28px 0;
}
.about-link {
  margin-top: 18px;
  font-size: 12px;
}
</style>
