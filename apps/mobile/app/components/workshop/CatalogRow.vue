<script setup lang="ts">
import type { YlfAppInfo } from '@yunlefun/types'
import { IonIcon } from '@ionic/vue'
import { lockClosed, star } from 'ionicons/icons'
import { getBrowseCategory } from '~/utils/appBrowseCategories'

defineProps<{
  app: YlfAppInfo
  isPrivate?: boolean
  sourceName?: string
}>()

const emit = defineEmits<{
  open: []
}>()
</script>

<template>
  <article class="catalog-row">
    <button
      type="button"
      class="catalog-row-main"
      :aria-label="`查看${app.name}`"
      @click="emit('open')"
    >
      <AppIconBox
        class="catalog-row-icon"
        :icon="app.logo"
        :icon-assets="app.iconAssets"
        :emoji="app.emoji"
        :color="app.themeColor"
        size="md"
      />
      <span class="catalog-row-copy">
        <span class="catalog-row-name">{{ app.name }}</span>
        <span class="catalog-row-description">{{ app.description || '暂时没有应用介绍' }}</span>
        <span class="catalog-row-meta">
          <span v-if="isPrivate" class="catalog-private-badge">
            <IonIcon :icon="lockClosed" aria-hidden="true" />
            坊客专属
          </span>
          <span v-if="sourceName" class="catalog-source-name">{{ sourceName }}</span>
          <span>{{ getBrowseCategory(app) }}</span>
          <span v-if="app.ratingCount && app.rating" class="catalog-rating">
            <IonIcon :icon="star" aria-hidden="true" />
            {{ app.rating }}
          </span>
        </span>
      </span>
    </button>
    <AppInstallButton class="catalog-row-action" :app="app" />
  </article>
</template>

<style scoped>
.catalog-row {
  min-width: 0;
  min-height: 102px;
  display: flex;
  align-items: center;
  gap: 12px;
  border-bottom: 0.5px solid var(--ylf-catalog-divider);
}

.catalog-row-main {
  min-width: 0;
  min-height: 92px;
  display: flex;
  flex: 1;
  align-items: center;
  gap: 14px;
  padding: 12px 0;
  border: 0;
  border-radius: 6px;
  background: transparent;
  color: var(--ylf-catalog-text);
  text-align: start;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.catalog-row-main:hover .catalog-row-name {
  color: var(--ylf-catalog-accent-text);
}

.catalog-row-main:focus-visible {
  outline: 2px solid var(--ylf-catalog-accent);
  outline-offset: 3px;
}

.catalog-row-icon {
  flex: 0 0 auto;
}

.catalog-row-copy {
  min-width: 0;
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 4px;
}

.catalog-row-name {
  overflow: hidden;
  font-size: 16px;
  font-weight: 600;
  line-height: 1.3;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.catalog-row-description {
  overflow: hidden;
  color: var(--ylf-catalog-text-secondary);
  font-size: 13px;
  line-height: 1.4;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.catalog-row-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  overflow: hidden;
  color: var(--ylf-catalog-text-secondary);
  font-size: 11px;
  line-height: 1.4;
  white-space: nowrap;
}

.catalog-private-badge,
.catalog-rating {
  display: inline-flex;
  align-items: center;
  gap: 3px;
}

.catalog-private-badge {
  color: var(--ylf-catalog-accent-text);
}

.catalog-source-name {
  max-width: 90px;
  overflow: hidden;
  text-overflow: ellipsis;
}

.catalog-rating ion-icon {
  color: var(--ylf-color-yellow);
}

.catalog-row .catalog-row-action.install-btn:not(.install-btn--installing) {
  min-width: 64px;
  height: 30px;
  flex: 0 0 auto;
  padding-inline: 15px;
  background: var(--ylf-catalog-control);
  color: var(--ylf-catalog-accent-text);
  font-size: 13px;
  letter-spacing: 0;
}

.catalog-row .catalog-row-action.install-btn:not(.install-btn--installing):hover {
  background: var(--ylf-catalog-control-hover);
}

.catalog-row .catalog-row-action.install-btn:not(.install-btn--installing):active {
  background: var(--ylf-catalog-control-pressed);
  opacity: 1;
}

.catalog-row-action:focus-visible {
  outline: 2px solid var(--ylf-catalog-accent);
  outline-offset: 3px;
}

.catalog-row-action.install-btn--installing {
  min-width: 30px;
  padding: 0;
  background: transparent;
}

@media (max-width: 359px) {
  .catalog-row,
  .catalog-row-main {
    gap: 10px;
  }

  .catalog-row .catalog-row-action.install-btn:not(.install-btn--installing) {
    min-width: 56px;
    padding-inline: 11px;
  }
}

@media (prefers-reduced-motion: reduce) {
  .catalog-row-action {
    transition: none;
  }
}
</style>
