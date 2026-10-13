<script setup lang="ts">
import { APP_CATEGORIES } from '~/types/app'

const category = defineModel<string>({ required: true })
</script>

<template>
  <div class="section-header">
    分类
  </div>
  <div class="picker-section">
    <div class="category-grid">
      <button
        v-for="c in APP_CATEGORIES"
        :key="c.label"
        type="button"
        class="category-chip"
        :class="{ 'category-chip--active': category === c.label }"
        @click="category = category === c.label ? '' : c.label"
      >
        <span class="category-icon">{{ c.icon }}</span>
        <span class="category-label">{{ c.label }}</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.section-header {
  padding: 24px 20px 6px;
  font-size: 13px;
  font-weight: 400;
  color: var(--ion-color-medium);
  text-transform: uppercase;
  letter-spacing: 0.02em;
}

.picker-section {
  margin: 0 16px;
  padding: 12px 12px;
  background: var(--ion-item-background, var(--ion-background-color, #fff));
  border-radius: 12px;
  margin-bottom: 8px;
}

.category-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  justify-content: flex-start;
}

.category-chip {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 6px 12px;
  border-radius: 20px;
  border: 1.5px solid rgba(142, 142, 147, 0.2);
  background: transparent;
  font-size: 14px;
  cursor: pointer;
  transition: all 0.2s ease;
  -webkit-tap-highlight-color: transparent;
}

.category-chip:active {
  transform: scale(0.95);
}

.category-chip--active {
  background: rgba(0, 122, 255, 0.1);
  border-color: var(--ion-color-primary);
  color: var(--ion-color-primary);
}

.category-icon {
  font-size: 16px;
  line-height: 1;
}

.category-label {
  font-size: 13px;
  font-weight: 500;
}

.dark .category-chip {
  border-color: rgba(118, 118, 128, 0.3);
}

.dark .category-chip--active {
  background: rgba(10, 132, 255, 0.15);
  border-color: var(--ion-color-primary);
}
</style>
