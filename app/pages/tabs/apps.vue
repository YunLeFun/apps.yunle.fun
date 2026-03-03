<script setup lang="ts">
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonLabel,
  IonPage,
  IonSearchbar,
  IonSegment,
  IonSegmentButton,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { personCircleOutline } from 'ionicons/icons'

const {
  searchQuery,
  selectedCategory,
  categories,
  changeCategory,
  debouncedSearch,
  queryApps,
} = useWorkshop()

onMounted(() => queryApps(true))

function handleSegmentChange(event: CustomEvent) {
  changeCategory(event.detail.value)
}

function handleSearchInput() {
  debouncedSearch()
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonTitle>
          工坊
        </IonTitle>
        <IonButtons slot="end">
          <IonButton router-link="/tabs/me">
            <IonIcon slot="icon-only" :icon="personCircleOutline" />
          </IonButton>
        </IonButtons>
      </IonToolbar>

      <!-- 搜索栏工具栏 -->
      <IonToolbar>
        <IonSearchbar
          v-model="searchQuery"
          placeholder="游戏、App 等"
          :animated="true"
          show-cancel-button="focus"
          class="app-store-searchbar"
          mode="ios"
          @ion-input="handleSearchInput"
          @ion-clear="handleSearchInput"
        />
      </IonToolbar>

      <!-- 分类筛选工具栏 -->
      <IonToolbar>
        <IonSegment
          :value="selectedCategory"
          scrollable
          mode="ios"
          @ion-change="handleSegmentChange"
        >
          <IonSegmentButton
            v-for="category in categories"
            :key="category.id"
            :value="category.name"
          >
            <IonLabel class="inline-flex gap-2">
              <span>{{ category.icon }}</span>
              <span>{{ category.name }}</span>
            </IonLabel>
          </IonSegmentButton>
        </IonSegment>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <div class="content-wrapper">
        <AppList />
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.large-title {
  font-size: 34px;
  font-weight: 700;
  letter-spacing: 0.374px;
  padding-left: 16px;
  padding-right: 0;
  padding-top: 0;
  padding-bottom: 0;
}

/* 用户头像按钮 */
.avatar-button {
  --padding-start: 8px;
  --padding-end: 16px;
  --border-radius: 50%;
  margin: 0;
}

.avatar-icon {
  font-size: 32px;
  color: #007aff;
  transition: opacity 0.2s ease;
}

.dark .avatar-icon {
  color: #0a84ff;
}

.app-store-searchbar {
  --background: rgba(142, 142, 147, 0.12);
  --border-radius: 10px;
  --box-shadow: none;
  --cancel-button-color: #007aff;
  --placeholder-color: rgba(60, 60, 67, 0.6);
  --icon-color: rgba(60, 60, 67, 0.6);
  --clear-button-color: rgba(60, 60, 67, 0.6);
  padding: 0 16px;
  font-size: 17px;
  font-weight: 400;
}

.app-store-searchbar::part(native) {
  height: 36px;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}

.app-store-searchbar::part(native):focus-within {
  --background: rgba(142, 142, 147, 0.18);
}

.dark .app-store-searchbar {
  --background: rgba(118, 118, 128, 0.24);
  --placeholder-color: rgba(235, 235, 245, 0.6);
  --icon-color: rgba(235, 235, 245, 0.6);
  --clear-button-color: rgba(235, 235, 245, 0.6);
}

/* ==================== Content 区域 ==================== */
.app-store-content {
  --background: #f2f2f7;
  --padding-top: 0;
  --padding-bottom: 0;
}

.dark .app-store-content {
  --background: #000000;
}

/* Condensed Header（滚动时的大标题） */
.content-header {
  --background: transparent;
}

.condensed-toolbar {
  --background: transparent;
  --border-width: 0;
  --padding-top: 0;
  --padding-bottom: 0;
}

.condensed-title {
  font-size: 34px;
  font-weight: 700;
  letter-spacing: 0.374px;
  padding-left: 16px;
  padding-right: 0;
}

.content-wrapper {
  padding: 0 16px 16px;
}

/* ==================== 响应式设计 ==================== */
@media (min-width: 768px) {
  .large-title {
    font-size: 40px;
  }

  .condensed-title {
    font-size: 40px;
  }

  .content-wrapper {
    max-width: 980px;
    margin: 0 auto;
    padding: 0 24px 24px;
  }
}

@media (min-width: 1024px) {
  .content-wrapper {
    max-width: 1200px;
    padding: 0 32px 32px;
  }
}

/* ==================== 动画效果 ==================== */
@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translateY(-10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.app-store-header {
  animation: fadeIn 0.3s ease-out;
}

/* 滚动时的过渡效果 */
.app-store-header::part(native) {
  transition:
    backdrop-filter 0.3s ease,
    background-color 0.3s ease;
}

/* ==================== 无障碍优化 ==================== */
@media (prefers-reduced-motion: reduce) {
  .app-store-header,
  .category-segment-button::part(indicator),
  .app-store-searchbar::part(native) {
    animation: none;
    transition: none;
  }
}

/* ==================== 触摸反馈优化 ==================== */
.avatar-button:active {
  opacity: 0.6;
  transition: opacity 0.1s ease;
}

.category-segment-button:active {
  opacity: 0.8;
  transition: opacity 0.1s ease;
}
</style>
