<script lang="ts" setup>
import type { YlfAppInfo } from '~~/packages/types'
import { IonIcon, IonInfiniteScroll, IonInfiniteScrollContent, IonSpinner } from '@ionic/vue'
import { star, starOutline } from 'ionicons/icons'

const router = useRouter()
const { apps, loading, hasMore, initialized, loadMore } = useWorkshop()

function openAppDetail(app: YlfAppInfo) {
  router.push(`/app/${app.id}`)
}

function renderStars(rating?: number) {
  if (!rating)
    return []
  const stars = []
  const fullStars = Math.floor(rating)
  for (let i = 0; i < 5; i++) {
    stars.push(i < fullStars ? star : starOutline)
  }
  return stars
}

async function handleInfiniteScroll(event: CustomEvent) {
  loadMore()
  // 等待加载结束
  await nextTick()
  ;(event.target as HTMLIonInfiniteScrollElement).complete()
}
</script>

<template>
  <div class="app-store-list">
    <!-- 加载中骨架 -->
    <div v-if="loading && !initialized" class="py-8 text-center">
      <IonSpinner name="crescent" />
    </div>

    <!-- 应用列表 -->
    <template v-else>
      <div v-if="apps.length > 0" class="flex flex-col">
        <div
          v-for="(app, index) in apps"
          :key="app.id"
          class="app-list-item cursor-pointer border-b border-gray-200 py-4 transition-opacity dark:border-gray-700 active:opacity-60"
          :class="{ 'border-b-0': index === apps.length - 1 }"
          @click="openAppDetail(app)"
        >
          <div class="flex items-center gap-3">
            <!-- 应用图标 -->
            <div
              class="app-icon h-16 w-16 flex flex-shrink-0 items-center justify-center text-3xl shadow-sm"
              :style="{ backgroundColor: app.color }"
            >
              {{ app.icon || app.emoji }}
            </div>

            <!-- 应用信息 -->
            <div class="min-w-0 flex flex-1 flex-col gap-1">
              <div class="truncate text-base font-medium">
                {{ app.name }}
              </div>
              <div class="truncate text-sm text-gray-500 dark:text-gray-400">
                {{ app.description }}
              </div>
              <div class="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
                <div v-if="app.rating" class="flex items-center gap-0.5">
                  <IonIcon
                    v-for="(starIcon, idx) in renderStars(app.rating)"
                    :key="idx"
                    :icon="starIcon"
                    class="text-xs"
                    style="color: #FFCC00"
                  />
                  <span class="ml-1">{{ app.rating }}</span>
                </div>
                <span v-if="app.rating && app.category">·</span>
                <span>{{ app.category }}</span>
              </div>
            </div>

            <!-- 安装按钮 -->
            <AppInstallButton :app="app" />
          </div>
        </div>
      </div>

      <!-- 空状态 -->
      <div v-else class="py-12 text-center">
        <p class="text-lg text-gray-400 dark:text-gray-500">
          暂无应用
        </p>
        <p class="mt-1 text-sm text-gray-400 dark:text-gray-600">
          换个关键词试试吧
        </p>
      </div>

      <!-- 无限滚动 -->
      <IonInfiniteScroll
        v-if="hasMore && apps.length > 0"
        @ion-infinite="handleInfiniteScroll"
      >
        <IonInfiniteScrollContent loading-spinner="crescent" />
      </IonInfiniteScroll>
    </template>
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

.get-button {
  --padding-start: 16px;
  --padding-end: 16px;
  height: 32px;
  font-size: 15px;
}

.app-list-item:active {
  background-color: rgba(0, 0, 0, 0.02);
}

.dark .app-list-item:active {
  background-color: rgba(255, 255, 255, 0.05);
}
</style>
