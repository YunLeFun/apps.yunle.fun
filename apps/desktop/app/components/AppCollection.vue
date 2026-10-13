<script setup lang="ts">
import type { CatalogEntry } from '../../shared/desktop'
import { appSummary } from '../utils/app-presentation'

const props = defineProps<{ apps: readonly CatalogEntry[], available: boolean }>()
defineEmits<{ open: [appId: string] }>()

const rows = computed(() => props.apps.map(app => ({
  app,
  summary: appSummary(app),
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
  column-gap: 32px;
  margin: 0;
  padding: 0;
  list-style: none;
}
.app-row {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 16px;
  min-height: 84px;
  padding: 14px 0;
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
  font-size: 15px;
  font-weight: 600;
  line-height: 20px;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.app-summary {
  overflow: hidden;
  margin: 0;
  color: var(--muted);
  font-size: 12px;
  line-height: 18px;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.open-button {
  min-width: 64px;
  flex-shrink: 0;
  padding: 5px 12px;
  border: 1px solid transparent;
  border-radius: 999px;
  background: var(--pill, var(--surface));
  color: var(--accent);
  font-size: 12px;
  font-weight: 600;
  line-height: 18px;
  cursor: pointer;
}
.open-button:hover:not(:disabled) {
  background: var(--selection, var(--surface));
}
.open-button:disabled {
  color: var(--muted);
  opacity: 0.6;
  cursor: default;
}
@container discovery (max-width: 750px) {
  .app-collection {
    grid-template-columns: minmax(0, 1fr);
  }
}
</style>
