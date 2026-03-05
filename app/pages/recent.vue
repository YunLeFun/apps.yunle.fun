<script setup lang="ts">
/**
 * Recent Apps Page - 全部最近使用
 *
 * 支持编辑模式：删除单条记录 / 清空全部
 */

import type { YlfAppInfo } from '~~/packages/types'
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonPage,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { ALL_APPS } from '~/constants/apps'

const homeScreenStore = useHomeScreenStore()
const isEditMode = ref(false)

const allRecentApps = computed(() => {
  return homeScreenStore.recentApps
    .map((r) => {
      const app = ALL_APPS.find(a => a.id === r.appId || a.slug === r.appId)
      return app ? { ...app, _recentAppId: r.appId } : null
    })
    .filter((a): a is YlfAppInfo & { _recentAppId: string } => a !== null)
})

function toggleEdit() {
  isEditMode.value = !isEditMode.value
}

function removeApp(appId: string) {
  homeScreenStore.removeRecentApp(appId)
  // 删完后如果列表空了，自动退出编辑模式
  if (homeScreenStore.recentApps.length === 0) {
    isEditMode.value = false
  }
}

function clearAll() {
  homeScreenStore.clearRecentApps()
  isEditMode.value = false
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/home" text="返回" />
        </IonButtons>
        <IonTitle>最近使用</IonTitle>
        <IonButtons slot="end">
          <IonButton v-if="allRecentApps.length > 0" @click="toggleEdit">
            {{ isEditMode ? '完成' : '编辑' }}
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent>
      <!-- 清空全部按钮 -->
      <div v-if="isEditMode" class="clear-bar">
        <button class="clear-btn" @click="clearAll">
          清空全部记录
        </button>
      </div>

      <div v-if="allRecentApps.length > 0" class="recent-grid">
        <div
          v-for="app in allRecentApps"
          :key="app.id"
          class="grid-item"
          :class="{ 'edit-wobble': isEditMode }"
        >
          <!-- 删除按钮 -->
          <button
            v-if="isEditMode"
            class="delete-badge"
            @click.stop="removeApp(app._recentAppId)"
          >
            <span class="delete-icon">−</span>
          </button>
          <AppItem :app="app" />
        </div>
      </div>
      <div v-else class="empty-state">
        <p>暂无最近使用的应用</p>
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.clear-bar {
  display: flex;
  justify-content: center;
  padding: 12px 20px 0;
}

.clear-btn {
  color: #ff3b30;
  font-size: 14px;
  background: none;
  border: none;
  cursor: pointer;
  padding: 6px 12px;
}

.recent-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 20px;
  padding: 16px 20px;
}

.grid-item {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
}

@media (max-width: 480px) {
  .recent-grid {
    gap: 16px;
    padding: 16px;
  }
}

/* ==================== 编辑模式抖动动画 ==================== */
.edit-wobble {
  animation: wobble 0.3s ease-in-out infinite alternate;
}

.edit-wobble:nth-child(2n) {
  animation-delay: 0.1s;
  animation-direction: alternate-reverse;
}

.edit-wobble:nth-child(3n) {
  animation-delay: 0.15s;
}

@keyframes wobble {
  0% {
    transform: rotate(-1deg);
  }
  100% {
    transform: rotate(1deg);
  }
}

@media (prefers-reduced-motion: reduce) {
  .edit-wobble {
    animation: none;
  }
}

/* ==================== 删除按钮 ==================== */
.delete-badge {
  position: absolute;
  top: -6px;
  left: -2px;
  width: 22px;
  height: 22px;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.45);
  border: none;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 10;
  cursor: pointer;
  padding: 0;
}

.delete-icon {
  color: white;
  font-size: 16px;
  font-weight: 600;
  line-height: 1;
}

.empty-state {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 60px 20px;
  color: var(--ion-color-medium);
  font-size: 15px;
}
</style>
