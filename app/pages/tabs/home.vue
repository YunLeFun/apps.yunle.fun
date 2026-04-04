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
const settingsStore = useSettingsStore()
const { loadFromCloud, recordRecentUse, uninstallApp, installApp, removeRecentApp, updateDock, finishEditing } = useHomeScreen()
const { shareApp } = useAppActions()

const searchQuery = ref('')

/** Dock 是否可见（设置开启或编辑模式下） */
const showDock = computed(() => settingsStore.dockVisible || homeScreenStore.isEditMode)

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

  return recent.slice(0, RECENT_DEFAULT_DISPLAY).map((r) => {
    const app = ALL_APPS.find(a => a.id === r.appId || a.slug === r.appId)
    return app || null
  }).filter((a): a is YlfAppInfo => a !== null)
})

const hasMoreRecent = computed(() => homeScreenStore.recentApps.length > RECENT_DEFAULT_DISPLAY)

// ==================== 最近使用拖拽 ====================

const recentDrag = useRecentDrag({
  onDrop(zone, app) {
    const appId = app.id || app.slug
    if (zone === 'add') {
      installApp(appId)
    }
    else if (zone === 'delete') {
      removeRecentApp(appId)
    }
  },
})

/** 拖拽浮动图标样式 */
const dragPreviewStyle = computed(() => ({
  position: 'fixed' as const,
  left: `${recentDrag.dragPosition.value.x}px`,
  top: `${recentDrag.dragPosition.value.y}px`,
  transform: 'translate(-50%, -50%) scale(1.1)',
  zIndex: 100001,
  pointerEvents: 'none' as const,
  filter: 'drop-shadow(0 8px 24px rgba(0, 0, 0, 0.3))',
}))

/** 最近使用 - 长按开始拖拽 */
function handleRecentLongPress(app: YlfAppInfo, event: PointerEvent | TouchEvent) {
  recentDrag.startDrag(app, event)
}

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

const { navigateToScan } = useScanBridge()
const { handleScanResult } = useScanResult()

function handleScan() {
  closeMenu()
  navigateToScan(handleScanResult)
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
  recordRecentUse(installed.appId)

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

/** 长按上下文菜单 */
const contextMenuVisible = ref(false)
const contextMenuPosition = ref({ x: 0, y: 0 })
const contextMenuApp = ref<InstalledApp | null>(null)
const contextMenuIconRect = ref<{ x: number, y: number, width: number, height: number } | null>(null)

/** 解析 InstalledApp 为 YlfAppInfo */
function resolveApp(installed: InstalledApp): YlfAppInfo | null {
  return ALL_APPS.find(a => a.id === installed.appId || a.slug === installed.appId) || null
}

/** 长按处理：应用 → 上下文菜单，空白 → 编辑模式 */
function handleLongPress(app: InstalledApp | null, position: { x: number, y: number }, iconRect: DOMRect | null) {
  if (app) {
    contextMenuApp.value = app
    contextMenuPosition.value = position
    contextMenuIconRect.value = iconRect ? { x: iconRect.x, y: iconRect.y, width: iconRect.width, height: iconRect.height } : null
    contextMenuVisible.value = true
  }
  else {
    homeScreenStore.enterEditMode()
    Haptics.impact({ style: ImpactStyle.Medium }).catch(() => {})
  }
}

/** Dock 长按处理 */
function handleDockLongPress(app: InstalledApp, position: { x: number, y: number }, iconRect: DOMRect) {
  contextMenuApp.value = app
  contextMenuPosition.value = position
  contextMenuIconRect.value = { x: iconRect.x, y: iconRect.y, width: iconRect.width, height: iconRect.height }
  contextMenuVisible.value = true
}

/** 上下文菜单 - 编辑主屏幕 */
function handleContextEditHomeScreen() {
  closeContextMenu()
  homeScreenStore.enterEditMode()
  Haptics.impact({ style: ImpactStyle.Medium }).catch(() => {})
}

/** 关闭上下文菜单 */
function closeContextMenu() {
  contextMenuVisible.value = false
  contextMenuApp.value = null
  contextMenuIconRect.value = null
}

/** 上下文菜单 - 分享 */
function handleContextShare() {
  const app = contextMenuApp.value
  closeContextMenu()
  if (app) {
    const resolved = resolveApp(app)
    if (resolved)
      shareApp(resolved)
  }
}

/** 上下文菜单 - 移除 */
function handleContextRemove() {
  const app = contextMenuApp.value
  closeContextMenu()
  if (app) {
    uninstallApp(app.appId)
  }
}

/** 从 Home Screen 移除应用 */
function handleRemoveApp(installed: InstalledApp) {
  uninstallApp(installed.appId)
}

/** 点击空白区域退出编辑模式 */
function handleContentClick() {
  if (homeScreenStore.isEditMode) {
    finishEditing()
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
          <IonButton v-if="homeScreenStore.isEditMode" @click="finishEditing()">
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

    <IonContent
      class="phone-homescreen"
      :class="{ 'has-dock': showDock }"
      @click="handleContentClick"
    >
      <!-- 最近使用 -->
      <div v-if="displayRecentApps.length > 0" class="recent-section">
        <div class="section-header px-5.5">
          <ion-note class="text-black/60 dark:text-white/60">
            最近使用
          </ion-note>
          <ion-note
            v-if="hasMoreRecent"
            class="cursor-pointer text-sm text-[#007aff]"
            @click="router.push('/recent')"
          >
            更多
          </ion-note>
        </div>
        <div class="recent-apps">
          <AppItem
            v-for="app in displayRecentApps"
            :key="app.id"
            :app="app"
            :class="{ 'is-drag-source': recentDrag.isDragging.value && recentDrag.dragApp.value?.id === app.id }"
            @long-press="handleRecentLongPress"
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
        :hidden-app-id="contextMenuVisible && contextMenuApp ? contextMenuApp.appId : undefined"
        @open="handleOpenApp"
        @remove="handleRemoveApp"
        @long-press="handleLongPress"
      />

    </IonContent>

    <!-- 底部 Dock 常用栏：固定在屏幕底部，类似 iOS Home Screen -->
    <AppHomeScreenDock
      v-if="showDock"
      :apps="homeScreenStore.dockApps"
      :edit-mode="homeScreenStore.isEditMode"
      :hidden-app-id="contextMenuVisible && contextMenuApp ? contextMenuApp.appId : undefined"
      @open="handleOpenApp"
      @remove="handleRemoveApp"
      @update:apps="updateDock"
      @long-press="handleDockLongPress"
    />

    <!-- 应用上下文菜单（Teleport to body，不受 IonContent 影响） -->
    <AppContextMenu
      :visible="contextMenuVisible"
      :position="contextMenuPosition"
      :app="contextMenuApp ? resolveApp(contextMenuApp) : null"
      :icon-rect="contextMenuIconRect"
      @edit-home-screen="handleContextEditHomeScreen"
      @share="handleContextShare"
      @remove="handleContextRemove"
      @close="closeContextMenu"
    />

    <!-- 最近使用拖拽浮动图标 -->
    <Teleport to="body">
      <div v-if="recentDrag.isDragging.value && recentDrag.dragApp.value" :style="dragPreviewStyle">
        <AppIconBox
          :icon="recentDrag.dragApp.value.icon"
          :emoji="recentDrag.dragApp.value.emoji"
          :color="recentDrag.dragApp.value.color"
          :label="recentDrag.dragApp.value.name"
        />
      </div>
    </Teleport>

    <!-- 最近使用拖拽底部操作栏 -->
    <AppRecentDropZone
      :visible="recentDrag.isDragging.value"
      :active-zone="recentDrag.activeDropZone.value"
    />
  </IonPage>
</template>

<style scoped>
.dark .phone-homescreen {
  --background: linear-gradient(180deg, #1c1c1e 0%, #000000 100%);
}

/* Dock 显示时，内容区底部留出空间避免遮挡 */
.phone-homescreen.has-dock {
  --padding-bottom: 104px;
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
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 20px;
  padding: 12px 20px;
}

.recent-apps :deep(.app-icon-item) {
  display: flex;
  flex-direction: column;
  align-items: center;
}

@media (max-width: 480px) {
  .recent-apps {
    gap: 16px;
    padding: 12px 16px;
  }
}

/* 拖拽中原始图标变透明 */
.recent-apps :deep(.is-drag-source) {
  opacity: 0.3;
  pointer-events: none;
  transition: opacity 0.2s ease;
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

</style>
