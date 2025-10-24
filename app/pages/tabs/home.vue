<script setup lang="ts">
/**
 * Home Page - 云居主页
 *
 * @description
 * 展示用户的应用桌面，支持点击打开应用、长按显示菜单、扫码等功能
 */

import type { YlfAppInfo } from '~~/packages/types'
import type { DockItem } from '~/components/layout/AppDock.vue'
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

definePageMeta({
  alias: ['/', '/home'],
})

const router = useRouter()
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

const showScanner = ref(false)
const { startScan, stopScan, isScanning } = useBarcodeScan()
const { showError, showInfo } = useToast()

/**
 * 扫一扫
 */
async function handleScan() {
  closeMenu()

  try {
    // 在 Web 环境下显示扫码界面
    if (import.meta.client && !(window as any).Capacitor) {
      showScanner.value = true
      return
    }

    // 在原生环境下使用 Capacitor 扫码
    const result = await startScan()
    if (result?.ScanResult) {
      handleScanResult(result.ScanResult)
    }
  }
  catch (error) {
    console.error('扫码失败:', error)
    showError('扫码失败，请检查相机权限')
  }
}

/**
 * 处理扫码结果
 */
function handleScanResult(content: string) {
  if (content.startsWith('http://') || content.startsWith('https://')) {
    const appIdMatch = content.match(/\/app\/(\d+)/)
    if (appIdMatch) {
      router.push(`/app/${appIdMatch[1]}`)
      return
    }
    window.open(content, '_blank')
  }
  else {
    showInfo(`扫码内容：${content}`)
  }
}

/**
 * 取消扫码
 */
function handleScanCancel() {
  showScanner.value = false
  if (isScanning.value) {
    stopScan()
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

// ==================== 应用数据 ====================

const homeApps = ref<YlfAppInfo[]>([
  {
    id: '1',
    code: 'valaxy',
    name: 'Valaxy',
    icon: '🌌',
    color: '#0078e7',
    url: 'https://valaxy.site',
    category: '应用',
  },
  {
    id: '2',
    code: 'fitness',
    name: 'Fitness',
    icon: '💪',
    color: '#FF3B30',
    url: '/apps/fitness',
    category: '健康',
  },
  {
    id: '3',
    code: 'photo',
    name: 'Photos',
    icon: '📷',
    color: '#34C759',
    url: '/apps/photo',
    category: '摄影',
  },
  {
    id: '4',
    code: 'music',
    name: 'Music',
    icon: '🎵',
    color: '#FF9500',
    url: '/apps/music',
    category: '音乐',
  },
  {
    id: '5',
    code: 'notes',
    name: 'Notes',
    icon: '📝',
    color: '#5AC8FA',
    url: '/apps/notes',
    category: '效率',
  },
  {
    id: '6',
    code: 'weather',
    name: 'Weather',
    icon: '⛅',
    color: '#50E3C2',
    url: '/apps/weather',
    category: '工具',
  },
  {
    id: '7',
    code: 'games',
    name: 'Games',
    icon: '🎮',
    color: '#B8E986',
    url: '/apps/games',
    category: '游戏',
  },
  {
    id: '8',
    code: 'social',
    name: 'Social',
    icon: '👥',
    color: '#FF2D55',
    url: '/apps/social',
    category: '社交',
  },
  {
    id: '9',
    code: 'camera',
    name: 'Camera',
    icon: '📹',
    color: '#A2845E',
    url: '/apps/camera',
    category: '摄像',
  },
  {
    id: '10',
    code: 'maps',
    name: 'Maps',
    icon: '🗺️',
    color: '#34C759',
    url: '/apps/maps',
    category: '地图',
  },
  {
    id: '11',
    code: 'mail',
    name: 'Mail',
    icon: '✉️',
    color: '#007AFF',
    url: '/apps/mail',
    category: '邮件',
  },
  {
    id: '12',
    code: 'calendar',
    name: 'Calendar',
    icon: '📅',
    color: '#FF3B30',
    url: '/apps/calendar',
    category: '日历',
  },
])

// ==================== 应用交互 ====================

const selectedApp = ref<YlfAppInfo | null>(null)
const showContextMenu = ref(false)
const contextMenuPos = ref({ x: 0, y: 0 })
const longPressTriggered = ref(false)

/**
 * 打开应用
 */
function openApp(app: YlfAppInfo) {
  openInAppBrowser(app.url)
}

/**
 * 点击应用 - 只有在没有触发长按时才打开
 */
function handleAppClick(app: YlfAppInfo) {
  if (!longPressTriggered.value) {
    openApp(app)
  }
  longPressTriggered.value = false
}

/**
 * 长按应用 - 显示上下文菜单
 */
function handleAppLongPress(app: YlfAppInfo, event: PointerEvent | TouchEvent) {
  longPressTriggered.value = true
  selectedApp.value = app

  // 获取触摸或鼠标位置
  let clientX = 0
  let clientY = 0

  if ('touches' in event && event.touches.length > 0) {
    const touch = event.touches[0]
    if (touch) {
      clientX = touch.clientX
      clientY = touch.clientY
    }
  }
  else if ('clientX' in event) {
    clientX = event.clientX
    clientY = event.clientY
  }

  if (clientX === 0 && clientY === 0) {
    return
  }

  // 计算菜单位置，确保不超出屏幕
  const menuWidth = 160
  const menuHeight = 240
  const padding = 16

  let x = clientX - menuWidth / 2
  let y = clientY - menuHeight / 2

  // 边界检查
  if (x < padding)
    x = padding
  if (x + menuWidth > window.innerWidth - padding)
    x = window.innerWidth - menuWidth - padding
  if (y < padding)
    y = padding
  if (y + menuHeight > window.innerHeight - padding)
    y = window.innerHeight - menuHeight - padding

  contextMenuPos.value = { x, y }
  showContextMenu.value = true

  // 触觉反馈
  if ('vibrate' in navigator) {
    navigator.vibrate(50)
  }
}

/**
 * 关闭上下文菜单
 */
function closeContextMenu() {
  showContextMenu.value = false
  selectedApp.value = null
}

/**
 * 移除应用
 */
function removeApp() {
  if (selectedApp.value) {
    const index = homeApps.value.findIndex(app => app.id === selectedApp.value?.id)
    if (index > -1) {
      homeApps.value.splice(index, 1)
    }
  }
  closeContextMenu()
}

/**
 * 编辑应用
 */
function editApp() {
  if (selectedApp.value) {
    // TODO: 实现编辑功能
    console.warn('编辑功能待实现')
  }
  closeContextMenu()
}

/**
 * 分享应用
 */
function shareApp() {
  if (selectedApp.value) {
    // TODO: 实现分享功能
    console.warn('分享功能待实现')
  }
  closeContextMenu()
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
      <!-- 应用网格 -->
      <AppGrid
        :apps="homeApps"
        @click="handleAppClick"
        @long-press="handleAppLongPress"
      />

      <!-- 底部 Dock 导航栏 -->
      <AppDock :items="dockItems" />

      <!-- 长按上下文菜单 -->
      <AppContextMenu
        v-if="selectedApp"
        :visible="showContextMenu"
        :position="contextMenuPos"
        :app="selectedApp"
        @open="openApp(selectedApp)"
        @edit="editApp"
        @share="shareApp"
        @remove="removeApp"
        @close="closeContextMenu"
      />

      <!-- 扫码界面 -->
      <BarcodeScanner
        :is-visible="showScanner"
        :show-flashlight="true"
        @cancel="handleScanCancel"
        @result="handleScanResult"
      />
    </IonContent>
  </IonPage>
</template>

<style scoped>
.dark .phone-desktop {
  --background: linear-gradient(180deg, #1c1c1e 0%, #000000 100%);
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
