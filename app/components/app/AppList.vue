<script lang="ts" setup>
import type { YlfAppInfo } from '~~/packages/types'
import { IonButton, IonIcon } from '@ionic/vue'
import { chevronForward, star, starOutline } from 'ionicons/icons'
import { openInAppBrowser } from '~/composables/useBrowser'
import { ALL_APPS } from '~/constants/apps'

interface Props {
  selectedCategory?: string
}

const props = withDefaults(defineProps<Props>(), {
  selectedCategory: '全部',
})

const router = useRouter()
const allApps = ref<YlfAppInfo[]>(ALL_APPS)

// 根据选中的分类筛选应用
const apps = computed(() => {
  if (props.selectedCategory === '全部') {
    return allApps.value
  }
  return allApps.value.filter(app => app.category === props.selectedCategory)
})

function openAppDetail(app: YlfAppInfo) {
  router.push(`/app/${app.id}`)
}

function renderStars(rating?: number) {
  if (!rating) {
    return []
  }

  const stars = []
  const fullStars = Math.floor(rating)
  for (let i = 0; i < 5; i++) {
    stars.push(i < fullStars ? star : starOutline)
  }
  return stars
}

function openAppLink(app: YlfAppInfo) {
  // window.open(app.url, '_blank')

  openInAppBrowser(app.url)
}
</script>

<template>
  <div class="app-store-list">
    <!-- 应用列表 -->
    <div>
      <div class="mb-3 flex items-center justify-between">
        <h2 class="text-xl font-bold">
          {{ props.selectedCategory === '全部' ? '精选应用' : props.selectedCategory }}
        </h2>
        <IonButton fill="clear" size="small">
          查看全部
          <IonIcon slot="end" :icon="chevronForward" />
        </IonButton>
      </div>

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
              {{ app.icon }}
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
                <div class="flex items-center gap-0.5">
                  <IonIcon
                    v-for="(starIcon, idx) in renderStars(app.rating)"
                    :key="idx"
                    :icon="starIcon"
                    class="text-xs"
                    style="color: #FFCC00"
                  />
                  <span class="ml-1">{{ app.rating }}</span>
                </div>
                <span>·</span>
                <span>{{ app.category }}</span>
              </div>
            </div>

            <!-- 获取按钮 -->
            <IonButton
              fill="solid"
              size="small"
              color="light"
              class="get-button flex-shrink-0"
              style="--border-radius: 14px; font-weight: 600; min-width: 72px"
              @click.stop="openAppLink(app)"
            >
              获取
            </IonButton>
          </div>
        </div>
      </div>

      <!-- 空状态 -->
      <div v-else class="py-12 text-center">
        <p class="text-gray-500 dark:text-gray-400">
          暂无应用
        </p>
      </div>
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
