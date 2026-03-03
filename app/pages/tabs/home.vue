<script setup lang="ts">
/**
 * Home Page - 云居主页
 *
 * 展示用户的 Home Screen，支持：
 * - 最近使用区域（默认 4 个，可展开查看更多）
 * - 主体 Home Screen（翻页 + 拖拽排序）
 * - 底部 Dock 常用栏
 * - 长按编辑模式
 */

import type { YlfAppInfo } from '~~/packages/types'
import type { InstalledApp } from '~/types/homeScreen'
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
import { ALL_APPS, homeApps } from '~/constants/apps'
import { RECENT_DEFAULT_DISPLAY } from '~/types/homeScreen'

definePageMeta({
  alias: ['/', '/home'],
})

const router = useRouter()
const homeScreenStore = useHomeScreenStore()
const { loadFromCloud, recordRecentUse, uninstallApp, updateDock } = useHomeScreen()

const searchQuery = ref('')
const showAllRecent = ref(false)

// ==================== 初始化 ====================

onMounted(async () => {
  // 用静态数据初始化 Home Screen（首次使用时）
  homeScreenStore.initWithDefaults(homeApps.value)

  // 异步加载云端数据
  loadFromCloud()
})

// ==================== 最近使用 ====================

const displayRecentApps = computed(() => {
  const recent = homeScreenStore.recentApps
  if (recent.length === 0)
    return []

  const limit = showAllRecent.value ? recent.length : RECENT_DEFAULT_DISPLAY
  return recent.slice(0, limit).map((r) => {
    const app = ALL_APPS.find(a => a.id === r.appId || a.code === r.appId)
    return app || null
  }).filter((a): a is YlfAppInfo => a !== null)
})

const hasMoreRecent = computed(() => homeScreenStore.recentApps.length > RECENT_DEFAULT_DISPLAY)

// ==================== 顶部菜单 ====================

const showMenu = ref(false)
const menuPosition = ref({ x: 0, y: 0 })

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

function closeMenu() {
  showMenu.value = false
}

// ==================== 扫码功能 ====================

const { showScanner, openScanner, closeScanner } = useScanner()
const { handleScanResult } = useScanResult()

async function handleScan() {
  closeMenu()
  const result = await openScanner()
  if (result) {
    handleScanResult(result)
  }
}

function handleAddApp() {
  closeMenu()
  router.push('/tabs/apps')
}

function handleDownload() {
  closeMenu()
}

// ==================== 桌面交互 ====================

/** 打开应用 */
function handleOpenApp(app: YlfAppInfo, installed: InstalledApp) {
  recordRecentUse(installed.appId, installed.source)

  if (app.callback) {
    app.callback()
  }
  else if (app.url) {
    if (app.url.startsWith('http')) {
      openInAppBrowser(app.url)
    }
    else {
      router.push(app.url)
    }
  }
}

/** 长按进入编辑模式 */
function handleLongPress() {
  homeScreenStore.enterEditMode()
  Haptics.impact({ style: ImpactStyle.Medium }).catch(() => {})
}

/** 从 Home Screen 移除应用 */
function handleRemoveApp(installed: InstalledApp) {
  uninstallApp(installed.appId)
}

/** 点击空白区域退出编辑模式 */
function handleContentClick() {
  if (homeScreenStore.isEditMode) {
    homeScreenStore.exitEditMode()
  }
}
</script>

<template>
  <IonPage>
    <!-- Ionic 标准 Header -->
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonTitle>云居</IonTitle>
        <IonButtons slot="end">
          <IonButton v-if="homeScreenStore.isEditMode" @click="homeScreenStore.exitEditMode()">
            完成
          </IonButton>
          <IonButton v-else @click="openMenu">
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

    <IonContent class="phone-homescreen" @click="handleContentClick">
      <!-- 最近使用 -->
      <div v-if="displayRecentApps.length > 0" class="recent-section">
        <div class="section-header px-5.5">
          <ion-note class="text-black/60 dark:text-white/60">
            最近使用
          </ion-note>
          <ion-note
            v-if="hasMoreRecent"
            class="cursor-pointer text-sm text-[#007aff]"
            @click="showAllRecent = !showAllRecent"
          >
            {{ showAllRecent ? '收起' : '更多' }}
          </ion-note>
        </div>
        <div class="recent-apps px-5 py-3">
          <AppItem
            v-for="app in displayRecentApps"
            :key="app.id"
            :app="app"
          />
        </div>
      </div>

      <!-- 主体 Home Screen -->
      <div class="px-5.5 pt-2">
        <ion-note class="text-black/60 dark:text-white/60">
          我的云应用
        </ion-note>
      </div>

      <AppHomeScreenGrid
        :pages="homeScreenStore.pagedApps"
        :edit-mode="homeScreenStore.isEditMode"
        @open="handleOpenApp"
        @remove="handleRemoveApp"
        @long-press="handleLongPress"
      />

      <!-- 底部 Dock 常用栏 -->
      <AppHomeScreenDock
        :apps="homeScreenStore.dockApps"
        :edit-mode="homeScreenStore.isEditMode"
        @open="handleOpenApp"
        @remove="handleRemoveApp"
        @update:apps="updateDock"
      />

      <!-- 扫码界面 -->
      <ScannerBarcode
        :is-visible="showScanner"
        :show-flashlight="true"
        @cancel="closeScanner"
        @result="handleScanResult"
      />
    </IonContent>
  </IonPage>
</template>

<style scoped>
.dark .phone-homescreen {
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

.recent-apps :deep(.app-icon-item) {
  flex-shrink: 0;
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

/* ==================== 扫码隐藏背景 ==================== */
:global(body.scanner-active) {
  background: transparent !important;
}

:global(body.scanner-active) ion-app,
:global(body.scanner-active) ion-page,
:global(body.scanner-active) ion-content {
  background: transparent !important;
  --background: transparent !important;
}
</style>
