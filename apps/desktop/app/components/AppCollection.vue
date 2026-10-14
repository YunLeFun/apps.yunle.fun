<script setup lang="ts">
import type { CatalogEntry } from '../../shared/desktop'
import { getBrowseCategory } from '@yunlefun/app-core/utils/appBrowseCategories'
import { appSummary } from '../utils/app-presentation'

const props = defineProps<{ apps: readonly CatalogEntry[], available: boolean }>()
defineEmits<{ open: [appId: string] }>()

const rows = computed(() => props.apps.map(app => ({
  app,
  summary: appSummary(app),
  category: getBrowseCategory(app),
  disabled: !props.available || !app.available,
})))
</script>

<template>
  <ul class="app-collection">
    <li v-for="row in rows" :key="row.app.id" class="app-row">
      <AppIcon :app="row.app" />
      <div class="app-copy">
        <h3 class="app-name">
          {{ row.app.name }}
        </h3>
        <p class="app-summary" :title="row.summary">
          {{ row.summary }}
        </p>
        <p class="app-category">
          {{ row.category }}
        </p>
      </div>
      <button
        class="open-button" :disabled="row.disabled"
        :aria-label="`打开${row.app.name}`" :title="row.app.unavailableReason || `打开${row.app.name}`"
        @click="$emit('open', row.app.id)"
      >
        {{ row.app.available ? '打开' : '暂不可用' }}
      </button>
    </li>
  </ul>
</template>

<style scoped>
.app-collection {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  column-gap: var(--ylf-space-8);
  margin: 0;
  padding: 0;
  list-style: none;
}
.app-row {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: var(--ylf-space-4);
  min-height: 104px;
  padding: 18px 0;
  border-bottom: 1px solid var(--border);
}
.app-copy {
  flex: 1;
  min-width: 0;
}
.app-name {
  overflow: hidden;
  margin: 0 0 5px;
  color: var(--text);
  font-size: var(--ylf-desktop-text-title);
  font-weight: 600;
  line-height: 20px;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.app-summary {
  overflow: hidden;
  margin: 0;
  color: var(--muted);
  font-size: var(--ylf-desktop-text-control);
  line-height: 18px;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.app-category {
  margin: 4px 0 0;
  color: var(--muted);
  font-size: var(--ylf-desktop-text-meta);
  line-height: 16px;
}
.open-button {
  min-width: 64px;
  min-height: var(--ylf-desktop-control);
  flex-shrink: 0;
  padding: 5px 12px;
  border: 0;
  border-radius: var(--ylf-radius-pill);
  background: var(--ylf-desktop-button);
  color: var(--ylf-desktop-link);
  font-size: var(--ylf-desktop-text-control);
  font-weight: 600;
  line-height: 18px;
  cursor: pointer;
}
.open-button:hover:not(:disabled) {
  background: color-mix(in srgb, var(--text) 5%, var(--ylf-desktop-button));
  color: var(--ylf-desktop-link-hover);
}
.open-button:active:not(:disabled) {
  background: color-mix(in srgb, var(--text) 9%, var(--ylf-desktop-button));
  color: var(--ylf-desktop-link-hover);
}
.open-button:disabled {
  color: var(--muted);
  background: var(--ylf-desktop-inset);
  border-color: var(--border);
  cursor: default;
}
.app-row:nth-last-child(-n + 2) {
  border-bottom-color: transparent;
}
@container discovery (max-width: 750px) {
  .app-collection {
    grid-template-columns: minmax(0, 1fr);
  }
  .app-row:not(:last-child) {
    border-bottom-color: var(--border);
  }
}
@media (pointer: coarse) {
  .open-button {
    min-height: 40px;
  }
}
</style>
