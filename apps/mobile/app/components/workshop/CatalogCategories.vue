<script setup lang="ts">
import type { BrowseCategory } from '~/utils/appBrowseCategories'
import { IonIcon } from '@ionic/vue'
import { briefcaseOutline, brushOutline, codeSlashOutline, gameControllerOutline, gridOutline, happyOutline, heartOutline, shapesOutline, sparklesOutline } from 'ionicons/icons'

defineProps<{
  categories: BrowseCategory[]
  selected: string
}>()

const emit = defineEmits<{
  select: [category: string]
}>()

const icons: Record<string, string> = {
  全部: gridOutline,
  效率工具: briefcaseOutline,
  创意设计: brushOutline,
  生活方式: heartOutline,
  游戏: gameControllerOutline,
  趣味娱乐: happyOutline,
  AI: sparklesOutline,
  开发: codeSlashOutline,
}
</script>

<template>
  <nav class="catalog-categories" aria-label="应用分类">
    <p class="category-heading">
      分类
    </p>
    <div class="category-options">
      <button
        v-for="category in categories"
        :key="category.id"
        type="button"
        class="category-option"
        :class="{ 'is-selected': selected === category.name }"
        :title="category.name"
        :aria-pressed="selected === category.name"
        @click="emit('select', category.name)"
      >
        <IonIcon :icon="icons[category.name] || shapesOutline" aria-hidden="true" />
        <span class="category-name">{{ category.name }}</span>
        <span class="category-count" aria-hidden="true">{{ category.count }}</span>
      </button>
    </div>
  </nav>
</template>

<style scoped>
.catalog-categories {
  min-width: 0;
}

.category-heading {
  display: none;
  margin: 0 12px 12px;
  color: var(--ylf-catalog-control-secondary);
  font-size: 12px;
  font-weight: 600;
}

.category-options {
  display: flex;
  gap: 6px;
  overflow-x: auto;
  padding: 3px 0 8px;
  scrollbar-width: none;
}

.category-options::-webkit-scrollbar {
  display: none;
}

.category-option {
  min-height: 44px;
  display: flex;
  flex: 0 0 auto;
  align-items: center;
  gap: 9px;
  padding: 0 14px;
  border: 0;
  border-radius: 9px;
  background: transparent;
  color: var(--ylf-catalog-control-secondary);
  font-size: 14px;
  font-weight: 500;
  text-align: start;
  white-space: nowrap;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.category-option ion-icon {
  display: none;
  flex: 0 0 auto;
  font-size: 19px;
}

.category-option:hover {
  background: var(--ylf-catalog-control-hover);
}

.category-option.is-selected {
  background: var(--ylf-catalog-accent-soft);
  color: var(--ylf-catalog-accent-text);
  font-weight: 600;
}

.category-option:focus-visible {
  outline: 2px solid var(--ylf-catalog-accent);
  outline-offset: 2px;
}

.category-count {
  display: none;
  margin-inline-start: auto;
  color: var(--ylf-catalog-control-secondary);
  font-size: 12px;
  font-variant-numeric: tabular-nums;
}

@media (min-width: 900px) {
  .catalog-categories {
    position: sticky;
    top: 24px;
    padding: 18px 10px;
    border-radius: 14px;
    background: var(--ylf-catalog-sidebar);
  }

  .category-heading,
  .category-option ion-icon,
  .category-count {
    display: block;
  }

  .category-options {
    flex-direction: column;
    overflow: visible;
    padding: 0;
  }

  .category-option {
    min-height: 43px;
    padding: 0 12px;
  }

  .category-name {
    min-width: 0;
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .category-count {
    flex-shrink: 0;
  }
}
</style>
