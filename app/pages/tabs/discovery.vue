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

const searchQuery = ref('')
const selectedCategory = ref('全部')

// 分类列表
const categories = [
  { id: 'all', name: '全部', icon: '📱' },
  { id: 'health', name: '健康健身', icon: '💪' },
  { id: 'photo', name: '摄影与录像', icon: '📷' },
  { id: 'music', name: '音乐', icon: '🎵' },
  { id: 'productivity', name: '效率', icon: '✅' },
]

function handleSegmentChange(event: CustomEvent) {
  selectedCategory.value = event.detail.value
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonTitle>
          发现
        </IonTitle>
        <IonButtons slot="end">
          <IonButton>
            <IonIcon slot="icon-only" :icon="personCircleOutline" />
          </IonButton>
        </IonButtons>
      </IonToolbar>

      <!-- 搜索栏工具栏 -->
      <IonToolbar class="search-toolbar">
        <IonSearchbar
          v-model="searchQuery"
          placeholder="游戏、App 等"
          :animated="true"
          show-cancel-button="focus"
          class="app-store-searchbar"
          mode="ios"
        />
      </IonToolbar>

      <!-- 分类筛选工具栏 -->
      <IonToolbar class="segment-toolbar">
        <IonSegment
          :value="selectedCategory"
          scrollable
          @ion-change="handleSegmentChange"
        >
          <IonSegmentButton
            v-for="category in categories"
            :key="category.id"
            :value="category.name"
            class="category-segment-button"
          >
            <IonLabel class="segment-label">
              <span class="segment-icon">{{ category.icon }}</span>
              <span class="segment-text">{{ category.name }}</span>
            </IonLabel>
          </IonSegmentButton>
        </IonSegment>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <div class="content-wrapper">
        <AppList :selected-category="selectedCategory" />
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

/* ==================== 搜索栏工具栏 ==================== */
.search-toolbar {
  --background: transparent;
  --border-width: 0;
  --padding-top: 8px;
  --padding-bottom: 8px;
  --min-height: 52px;
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

.dark .app-store-searchbar::part(native):focus-within {
  --background: rgba(118, 118, 128, 0.32);
}

/* ==================== 分类筛选工具栏 ==================== */
.segment-toolbar {
  --background: transparent;
  --border-width: 0 0 0.5px 0;
  --border-color: rgba(60, 60, 67, 0.18);
  --padding-top: 0;
  --padding-bottom: 0;
  --min-height: 44px;
}

.dark .segment-toolbar {
  --border-color: rgba(84, 84, 88, 0.48);
}

.category-segment-button {
  --background: transparent;
  --background-checked: transparent;
  --background-hover: transparent;
  --background-focused: transparent;
  --color: #8e8e93;
  --color-checked: #007aff;
  --indicator-color: #007aff;
  --indicator-height: 2px;
  --padding-top: 0;
  --padding-bottom: 0;
  --padding-start: 12px;
  --padding-end: 12px;
  min-width: auto;
  font-size: 15px;
  font-weight: 500;
  transition: color 0.2s ease;
}

.segment-label {
  display: flex;
  align-items: center;
  gap: 6px;
  margin: 0;
  transition: transform 0.2s ease;
}

.category-segment-button:active .segment-label {
  transform: scale(0.95);
}

.segment-text {
  white-space: nowrap;
  font-size: 15px;
  font-weight: 500;
  letter-spacing: -0.24px;
}

/* Segment 指示器动画 */
.category-segment-button::part(indicator) {
  border-radius: 1px;
  transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}

.category-segment-button::part(indicator-background) {
  background: #007aff;
}

.category-segment-button.segment-button-checked {
  color: #007aff;
}

.dark .category-segment-button {
  --color: #8e8e93;
  --color-checked: #0a84ff;
  --indicator-color: #0a84ff;
}

.dark .category-segment-button.segment-button-checked {
  color: #0a84ff;
}

.dark .category-segment-button::part(indicator-background) {
  background: #0a84ff;
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
  .segment-label,
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
