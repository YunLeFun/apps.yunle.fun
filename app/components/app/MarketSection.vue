<script setup lang="ts">
import type { YlfAppInfo } from '~~/packages/types'
import type { AppMarketSource } from '~/types/market'

defineProps<{
  source?: AppMarketSource
}>()

function openApp(app: YlfAppInfo) {
  if (app.url) {
    openInAppBrowser(app.url)
  }
}
</script>

<template>
  <div v-if="source" class="market-section">
    <!-- 市场信息 -->
    <div v-if="source.description" class="mb-3 text-sm text-gray-500 dark:text-gray-400">
      {{ source.description }}
    </div>

    <!-- 应用列表 -->
    <div v-if="source.apps.length > 0" class="flex flex-col">
      <div
        v-for="(app, index) in source.apps"
        :key="app.slug || app.id || index"
        class="app-list-item cursor-pointer border-b border-gray-200 py-4 transition-opacity dark:border-gray-700 active:opacity-60"
        :class="{ 'border-b-0': index === source.apps.length - 1 }"
        @click="openApp(app)"
      >
        <div class="flex items-center gap-3">
          <div
            class="app-icon h-16 w-16 flex shrink-0 items-center justify-center text-3xl shadow-sm"
            :style="{ backgroundColor: app.color || '#e5e7eb' }"
          >
            {{ app.icon || app.emoji || '📦' }}
          </div>
          <div class="min-w-0 flex flex-1 flex-col gap-1">
            <div class="truncate text-base font-medium">
              {{ app.name }}
            </div>
            <div v-if="app.description" class="truncate text-sm text-gray-500 dark:text-gray-400">
              {{ app.description }}
            </div>
            <div v-if="app.category" class="text-xs text-gray-400 dark:text-gray-500">
              {{ app.category }}
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 空状态 -->
    <div v-else class="py-12 text-center">
      <p class="text-lg text-gray-400 dark:text-gray-500">
        暂无应用
      </p>
      <p class="mt-1 text-sm text-gray-400 dark:text-gray-600">
        该市场还没有添加任何应用
      </p>
    </div>
  </div>
</template>

<style scoped>
.app-icon {
  border-radius: 22.5%;
  position: relative;
  overflow: hidden;
}

.app-icon::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: 22.5%;
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.1);
  pointer-events: none;
}

.app-list-item:active {
  background-color: rgba(0, 0, 0, 0.02);
}

.dark .app-list-item:active {
  background-color: rgba(255, 255, 255, 0.05);
}
</style>
