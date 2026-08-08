<script lang="ts" setup>
import type { YlfAppInfo } from '@yunlefun/types'
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
          class="app-list-item cursor-pointer py-3"
          :class="{ 'app-list-item--last': index === apps.length - 1 }"
          @click="openAppDetail(app)"
        >
          <div class="flex items-center gap-3">
            <!-- 应用图标 -->
            <AppIconBox
              class="flex-shrink-0"
              :icon="app.logo"
              :icon-assets="app.iconAssets"
              :emoji="app.emoji"
              :color="app.themeColor"
              size="md"
            />

            <!-- 应用信息 -->
            <div class="min-w-0 flex flex-1 flex-col gap-1">
              <div class="truncate text-base font-medium">
                {{ app.name }}
              </div>
              <div class="truncate text-sm text-gray-500 dark:text-gray-400">
                {{ app.description }}
              </div>
              <div class="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
                <!-- 仅在有真实评分（ratingCount>0）时展示星级，避免显示写死的假分 -->
                <div v-if="app.ratingCount && app.rating" class="flex items-center gap-0.5">
                  <IonIcon
                    v-for="(starIcon, idx) in renderStars(app.rating)"
                    :key="idx"
                    :icon="starIcon"
                    class="text-xs"
                    style="color: #FFCC00"
                  />
                  <span class="ml-1">{{ app.rating }}</span>
                </div>
                <span v-if="app.ratingCount && app.rating && app.category">·</span>
                <span>{{ app.category }}</span>
              </div>
            </div>

            <!-- 安装按钮 -->
            <AppInstallButton :app="app" />
          </div>
        </div>
      </div>

      <!-- 空状态 -->
      <div v-else class="py-16 text-center">
        <div class="mb-3 text-5xl opacity-30">
          🔍
        </div>
        <p class="text-base font-medium text-gray-400 dark:text-gray-500">
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
/* iOS 风格分隔线：从图标右侧起始 */
.app-list-item {
  position: relative;
  transition: opacity 0.15s ease;
}

.app-list-item:not(.app-list-item--last)::after {
  content: '';
  position: absolute;
  bottom: 0;
  left: 76px; /* 图标 64px + gap 12px */
  right: 0;
  height: 0.5px;
  background: var(--ion-border-color, rgba(0, 0, 0, 0.1));
}

.app-list-item:active {
  opacity: 0.7;
}

.dark .app-list-item:not(.app-list-item--last)::after {
  background: rgba(255, 255, 255, 0.1);
}
</style>
