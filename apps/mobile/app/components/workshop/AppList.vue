<script setup lang="ts">
import type { YlfAppInfo } from '@yunlefun/types'
import { IonSpinner } from '@ionic/vue'

export interface WorkshopScopedApp {
  key: string
  app: YlfAppInfo
  private: boolean
  sourceName?: string
}

defineProps<{
  items: WorkshopScopedApp[]
  loading?: boolean
  emptyTitle?: string
  emptyHint?: string
}>()

const emit = defineEmits<{
  open: [item: WorkshopScopedApp]
}>()
</script>

<template>
  <div class="scoped-list">
    <div v-if="loading" class="scoped-loading">
      <IonSpinner name="crescent" />
    </div>
    <div v-else-if="items.length" class="scoped-items">
      <WorkshopCatalogRow
        v-for="item in items"
        :key="item.key"
        :app="item.app"
        :is-private="item.private"
        :source-name="item.sourceName"
        @open="emit('open', item)"
      />
    </div>
    <div v-else class="scoped-empty">
      <strong>{{ emptyTitle || '这里还没有应用' }}</strong>
      <span>{{ emptyHint || '换个分类或关键词试试' }}</span>
    </div>
  </div>
</template>

<style scoped>
.scoped-loading {
  min-height: 220px;
  display: grid;
  place-items: center;
}

.scoped-items {
  display: grid;
  grid-template-columns: minmax(0, 1fr);
}

.scoped-empty {
  min-height: 240px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: var(--ylf-catalog-text-secondary);
  text-align: center;
}

.scoped-empty strong {
  color: var(--ylf-catalog-text);
  font-size: 16px;
  font-weight: 600;
}

.scoped-empty span {
  margin-top: 8px;
  font-size: 13px;
}

@media (min-width: 1100px) {
  .scoped-items {
    grid-template-columns: repeat(2, minmax(0, 1fr));
    column-gap: 32px;
  }
}
</style>
