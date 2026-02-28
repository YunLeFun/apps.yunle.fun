<script setup lang="ts">
/**
 * Home Page - 云居主页
 *
 * @description
 * 展示用户的应用桌面，支持点击打开应用、长按显示菜单、扫码等功能
 */

import type { YlfAppInfo } from '~~/packages/types'
import type { DockItem } from '~/components/layout/AppDock.vue'
import { Haptics, ImpactStyle } from '@capacitor/haptics'
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonPage,
  IonSearchbar,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { add, addCircleOutline, downloadOutline, qrCodeOutline } from 'ionicons/icons'

import { homeApps } from '~/constants/apps'
import { cloudOneApp } from '~/constants/apps/builtin'

definePageMeta({
  alias: ['/', '/home'],
})

const router = useRouter()
const appStore = useAppStore()
const searchQuery = ref('')
const showMenu = ref(false)
const menuPosition = ref({ x: 0, y: 0 })

// ==================== 顶部菜单 ====================

/**
 * 打开顶部下拉菜单
 */
function openMenu(event: MouseEvent) {
  event.stopPropagation()
  const target = event.currentTarget as HTMLElement
  const rect = target.getBoundingClientRect()
  menuPosition.value = {
    x: rect.right - 180 - 8,
    y: rect.bottom + 8,
  }
  showMenu.value = true
}

/**
 * 关闭顶部菜单
 */
function closeMenu() {
  showMenu.value = false
}

// ==================== 扫码功能 ====================

const { showScanner, openScanner, closeScanner } = useScanner()
const { handleScanResult } = useScanResult()

/**
 * 扫一扫
 */
async function handleScan() {
  closeMenu()
  const result = await openScanner()
  if (result) {
    handleScanResult(result)
  }
}

/**
 * 添加应用
 */
function handleAddApp() {
  closeMenu()
  router.push('/apps')
}

/**
 * 下载应用
 */
function handleDownload() {
  closeMenu()
  // TODO: 实现下载应用功能
}

// ==================== 应用交互 ====================

const selectedApp = ref<YlfAppInfo | null>(null)
const showContextMenuOverlay = ref(false)

/**
 * 处理长按事件
 */
function handleLongPress(app: YlfAppInfo, _event: PointerEvent | TouchEvent) {
  selectedApp.value = app
  showContextMenuOverlay.value = true

  // 触发触觉反馈
  try {
    Haptics.impact({ style: ImpactStyle.Medium })
  }
  catch (error) {
    console.warn('Haptic feedback failed:', error)
  }
}

// ==================== Dock 配置 ====================

const dockItems: DockItem[] = [
  {
    path: '/tabs/home',
    emoji: '📱',
    gradient: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
    label: '云居',
  },
  {
    path: '/tabs/discovery',
    emoji: '🧭',
    gradient: 'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)',
    label: '发现',
  },
  {
    path: '/tabs/apps',
    emoji: '🎨',
    gradient: 'linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)',
    label: '工坊',
  },
  {
    path: '/tabs/me',
    emoji: '👤',
    gradient: 'linear-gradient(135deg, #43e97b 0%, #38f9d7 100%)',
    label: '我的',
  },
]
</script>

<template>
  <IonPage>
    <!-- Ionic 标准 Header -->
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonTitle>云居</IonTitle>
        <IonButtons slot="end">
          <IonButton @click="openMenu">
            <IonIcon slot="icon-only" :icon="add" />
          </IonButton>
        </IonButtons>
      </IonToolbar>
      <IonToolbar>
        <IonSearchbar
          v-model="searchQuery"
          placeholder="搜索应用"
          :animated="true"
          show-cancel-button="focus"
          mode="ios"
        />
      </IonToolbar>

      <!-- 下拉菜单 -->
      <div
        v-if="showMenu"
        class="menu-overlay"
        @click="closeMenu"
      >
        <div
          class="dropdown-menu"
          :style="{
            left: `${menuPosition.x}px`,
            top: `${menuPosition.y}px`,
          }"
          @click.stop
        >
          <div class="menu-item" @click="handleScan">
            <IonIcon :icon="qrCodeOutline" class="menu-icon" />
            <span>扫一扫</span>
          </div>
          <div class="menu-item" @click="handleAddApp">
            <IonIcon :icon="addCircleOutline" class="menu-icon" />
            <span>添加应用</span>
          </div>
          <div class="menu-item" @click="handleDownload">
            <IonIcon :icon="downloadOutline" class="menu-icon" />
            <span>下载应用</span>
          </div>
        </div>
      </div>
    </IonHeader>

    <IonContent class="phone-desktop">
      <!-- 最近使用 -->
      <div v-if="appStore.recentApps.length > 0" class="recent-section">
        <div class="section-header px-5.5">
          <ion-note class="text-black/60 dark:text-white/60">
            最近使用的云 APP
          </ion-note>
        </div>
        <div class="recent-apps px-5 py-3">
          <AppItem
            v-for="app in appStore.recentApps"
            :key="app.id"
            :app="app"
          />
        </div>
      </div>

      <!-- 应用网格 -->
      <div class="px-5.5">
        <ion-note class="text-black/60 dark:text-white/60">
          常用的云 APP
        </ion-note>
      </div>
      <AppGrid
        :apps="homeApps"
        @long-press="handleLongPress"
      >
        <template #pre>
          <AppIcon
            :app="cloudOneApp"
          />
        </template>
      </AppGrid>

      <!-- 底部 Dock 导航栏 -->
      <AppDock :items="dockItems" />

      <!-- 扫码界面 -->
      <BarcodeScanner
        :is-visible="showScanner"
        :show-flashlight="true"
        @cancel="closeScanner"
        @result="handleScanResult"
      />
    </IonContent>
  </IonPage>
</template>

<style scoped>
.dark .phone-desktop {
  --background: linear-gradient(180deg, #1c1c1e 0%, #000000 100%);
}

/* ==================== 最近使用区域 ==================== */
.recent-section {
  padding-top: 16px;
}

.section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.recent-apps {
  display: flex;
  gap: 16px;
  overflow-x: auto;
  padding-bottom: 12px;
  margin-bottom: 8px;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
}

.recent-apps::-webkit-scrollbar {
  display: none;
}

.recent-apps :deep(.app-icon) {
  flex-shrink: 0;
}

/* ==================== 扫码时隐藏背景 ==================== */
:global(body.scanner-active) {
  background: transparent !important;
}

:global(body.scanner-active) ion-app,
:global(body.scanner-active) ion-page,
:global(body.scanner-active) ion-content {
  background: transparent !important;
  --background: transparent !important;
}

/* ==================== 下拉菜单 ==================== */
.menu-overlay {
  position: fixed;
  inset: 0;
  z-index: 9999;
  background: transparent;
}

.dropdown-menu {
  position: fixed;
  background: rgba(255, 255, 255, 0.95);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border-radius: 12px;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
  overflow: hidden;
  min-width: 180px;
  z-index: 10000;
  animation: slideDown 0.2s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.dark .dropdown-menu {
  background: rgba(28, 28, 30, 0.95);
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.4);
}

.menu-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 14px 16px;
  font-size: 15px;
  color: #000;
  cursor: pointer;
  border-bottom: 1px solid rgba(0, 0, 0, 0.08);
  transition: background 0.15s ease;
}

.dark .menu-item {
  color: #fff;
  border-bottom-color: rgba(255, 255, 255, 0.08);
}

.menu-item:last-child {
  border-bottom: none;
}

.menu-item:active {
  background: rgba(0, 0, 0, 0.05);
}

.dark .menu-item:active {
  background: rgba(255, 255, 255, 0.1);
}

.menu-icon {
  font-size: 20px;
  color: #007aff;
}

.dark .menu-icon {
  color: #0a84ff;
}

@keyframes slideDown {
  from {
    opacity: 0;
    transform: translateY(-10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

/* ==================== 滚动条美化 ==================== */
.phone-desktop::-webkit-scrollbar {
  width: 4px;
}

.phone-desktop::-webkit-scrollbar-track {
  background: transparent;
}

.phone-desktop::-webkit-scrollbar-thumb {
  background: rgba(0, 0, 0, 0.2);
  border-radius: 2px;
}

.dark .phone-desktop::-webkit-scrollbar-thumb {
  background: rgba(255, 255, 255, 0.2);
}

.phone-desktop::-webkit-scrollbar-thumb:hover {
  background: rgba(0, 0, 0, 0.3);
}

.dark .phone-desktop::-webkit-scrollbar-thumb:hover {
  background: rgba(255, 255, 255, 0.3);
}
</style>
