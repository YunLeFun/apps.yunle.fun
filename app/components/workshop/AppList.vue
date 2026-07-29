<script setup lang="ts">
import type { YlfAppInfo } from '@yunlefun/types'
import { IonIcon, IonSpinner } from '@ionic/vue'
import { lockClosed, star } from 'ionicons/icons'

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
      <article
        v-for="(item, index) in items"
        :key="item.key"
        class="scoped-item"
        :class="{ 'scoped-item--last': index === items.length - 1 }"
        @click="emit('open', item)"
      >
        <AppIconBox
          class="scoped-app-icon"
          :icon="item.app.logo"
          :emoji="item.app.emoji"
          :color="item.app.themeColor"
          size="md"
        />

        <div class="scoped-copy">
          <div class="scoped-name-row">
            <h2>{{ item.app.name }}</h2>
            <span v-if="item.private" class="private-badge">
              <IonIcon :icon="lockClosed" />
              坊客专属
            </span>
          </div>
          <p>{{ item.app.description || '暂时没有应用介绍' }}</p>
          <div class="scoped-meta">
            <span v-if="item.sourceName" class="source-name">{{ item.sourceName }}</span>
            <span v-if="item.app.category">{{ item.app.category }}</span>
            <span v-if="item.app.ratingCount && item.app.rating" class="rating">
              <IonIcon :icon="star" />
              {{ item.app.rating }}
            </span>
          </div>
        </div>

        <AppInstallButton :app="item.app" />
      </article>
    </div>

    <div v-else class="scoped-empty">
      <div class="empty-mark">
        ◌
      </div>
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
  display: flex;
  flex-direction: column;
}

.scoped-item {
  position: relative;
  min-height: 88px;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 0;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.scoped-item:not(.scoped-item--last)::after {
  content: '';
  position: absolute;
  right: 0;
  bottom: 0;
  left: 76px;
  height: 0.5px;
  background: var(--ylf-separator);
  opacity: 0.5;
}

.scoped-item:active {
  opacity: 0.68;
}

.scoped-app-icon {
  flex: 0 0 auto;
}

.scoped-copy {
  min-width: 0;
  flex: 1;
}

.scoped-name-row {
  display: flex;
  align-items: center;
  gap: 6px;
}

.scoped-name-row h2 {
  min-width: 0;
  overflow: hidden;
  margin: 0;
  font-size: 16px;
  font-weight: 600;
  line-height: 1.3;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.private-badge {
  flex: 0 0 auto;
  display: inline-flex;
  align-items: center;
  gap: 3px;
  padding: 2px 5px;
  border-radius: 5px;
  color: var(--ylf-color-indigo);
  background: color-mix(in srgb, var(--ylf-color-indigo) 11%, transparent);
  font-size: 10px;
  font-weight: 600;
}

.private-badge ion-icon {
  font-size: 9px;
}

.scoped-copy > p {
  overflow: hidden;
  margin: 4px 0 5px;
  color: var(--ylf-label-secondary);
  font-size: 13px;
  line-height: 1.35;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.scoped-meta {
  display: flex;
  align-items: center;
  gap: 6px;
  overflow: hidden;
  color: var(--ylf-label-secondary);
  font-size: 11px;
  white-space: nowrap;
}

.scoped-meta > span + span::before {
  content: '·';
  margin-right: 6px;
}

.source-name {
  max-width: 112px;
  overflow: hidden;
  color: var(--ylf-color-indigo);
  text-overflow: ellipsis;
}

.rating {
  display: inline-flex;
  align-items: center;
}

.rating ion-icon {
  margin-right: 2px;
  color: var(--ylf-color-yellow);
}

.scoped-empty {
  min-height: 280px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: var(--ylf-label-secondary);
  text-align: center;
}

.empty-mark {
  margin-bottom: 8px;
  color: var(--ylf-label-tertiary);
  font-size: 48px;
  font-weight: 200;
  line-height: 1;
}

.scoped-empty strong {
  color: var(--ion-text-color);
  font-size: 15px;
}

.scoped-empty span {
  margin-top: 5px;
  font-size: 13px;
}
</style>
