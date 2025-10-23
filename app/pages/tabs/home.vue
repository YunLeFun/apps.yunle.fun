<script setup lang="ts">
import type { YlfAppInfo } from '~~/packages/types'
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
  popoverController,
} from '@ionic/vue'
import { add, addCircleOutline, downloadOutline, qrCodeOutline } from 'ionicons/icons'

definePageMeta({
  alias: ['/', '/home'],
})

const router = useRouter()
const searchQuery = ref('')
const showMenu = ref(false)
const menuPosition = ref({ x: 0, y: 0 })

// 打开菜单
function openMenu(event: MouseEvent) {
  event.stopPropagation()
  const target = event.currentTarget as HTMLElement
  const rect = target.getBoundingClientRect()
  menuPosition.value = {
    x: rect.right - 180 - 8, // 菜单宽度 200px，右对齐
    y: rect.bottom + 8,
  }
  showMenu.value = true
}

// 关闭菜单
function closeMenu() {
  showMenu.value = false
}

// 扫一扫
function handleScan() {
  closeMenu()
  // TODO: 实现扫一扫功能
  console.log('打开扫一扫')
  // 这里可以集成相机扫码功能
}

// 添加应用
function handleAddApp() {
  closeMenu()
  console.log('添加应用')
  router.push('/apps')
}

// 下载应用
function handleDownload() {
  closeMenu()
  console.log('下载应用')
}

// 模拟应用数据 - 手机桌面风格
const homeApps = ref<YlfAppInfo[]>([
  {
    id: '1',
    code: 'valaxy',
    name: 'Valaxy',
    icon: '🌌',
    color: '#0078e7',
    url: 'https://valaxy.yyj.moe',
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

const selectedApp = ref<YlfAppInfo | null>(null)
const showContextMenu = ref(false)
const contextMenuPos = ref({ x: 0, y: 0 })

function openApp(app: YlfAppInfo) {
  router.push(`/app/${app.id}`)
}

function handleAppClick(app: YlfAppInfo) {
  openApp(app)
}

function handleAppLongPress(app: YlfAppInfo, event: PointerEvent) {
  event.preventDefault()
  selectedApp.value = app
  showContextMenu.value = true
  contextMenuPos.value = {
    x: event.clientX,
    y: event.clientY,
  }
}

function closeContextMenu() {
  showContextMenu.value = false
  selectedApp.value = null
}

function removeApp() {
  if (selectedApp.value) {
    const index = homeApps.value.findIndex(app => app.id === selectedApp.value?.id)
    if (index > -1) {
      homeApps.value.splice(index, 1)
    }
  }
  closeContextMenu()
}
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
      <!-- 应用网格 - 可滚动区域 -->
      <div class="apps-grid">
        <div
          v-for="app in homeApps"
          :key="app.id"
          class="app-icon-item"
          @click="handleAppClick(app)"
          @pointerdown.prevent="handleAppLongPress(app, $event)"
        >
          <div
            class="app-icon-box"
            :style="{ backgroundColor: app.color }"
          >
            <div class="app-emoji">
              {{ app.icon }}
            </div>
            <!-- 红点通知 -->
            <div v-if="Math.random() > 0.7" class="badge">
              {{ Math.floor(Math.random() * 99) + 1 }}
            </div>
          </div>
          <div class="app-label">
            {{ app.name }}
          </div>
        </div>
      </div>

      <!-- iPhone 风格 Dock - 绝对定位 -->
      <div class="iphone-dock">
        <div class="dock-container flex gap-4">
          <div class="dock-item" @click="router.push('/tabs/home')">
            <div class="dock-icon" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%)">
              <span class="dock-emoji">📱</span>
            </div>
          </div>
          <div class="dock-item" @click="router.push('/tabs/discovery')">
            <div class="dock-icon" style="background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%)">
              <span class="dock-emoji">🧭</span>
            </div>
          </div>
          <div class="dock-item" @click="router.push('/tabs/apps')">
            <div class="dock-icon" style="background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)">
              <span class="dock-emoji">🎨</span>
            </div>
          </div>
          <div class="dock-item" @click="router.push('/tabs/me')">
            <div class="dock-icon" style="background: linear-gradient(135deg, #43e97b 0%, #38f9d7 100%)">
              <span class="dock-emoji">👤</span>
            </div>
          </div>
        </div>
      </div>

      <!-- 长按菜单 -->
      <div
        v-if="showContextMenu"
        class="context-menu-overlay"
        @click="closeContextMenu"
      >
        <div
          class="context-menu"
          :style="{
            left: `${contextMenuPos.x}px`,
            top: `${contextMenuPos.y}px`,
          }"
          @click.stop
        >
          <div class="context-menu-item" @click="openApp(selectedApp!)">
            打开
          </div>
          <div class="context-menu-item" @click="removeApp">
            移除
          </div>
          <div class="context-menu-item cancel" @click="closeContextMenu">
            取消
          </div>
        </div>
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.dark .phone-desktop {
  --background: linear-gradient(180deg, #1c1c1e 0%, #000000 100%);
}

/* ==================== 应用网格 ==================== */
.apps-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 20px;
  padding: 20px 20px 120px 20px;
  max-width: 100%;
}

/* ==================== 应用图标项 ==================== */
.app-icon-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  user-select: none;
  -webkit-user-select: none;
  -webkit-tap-highlight-color: transparent;
  transition: transform 0.15s cubic-bezier(0.4, 0, 0.2, 1);
  position: relative;
}

.app-icon-item:active {
  transform: scale(0.88);
}

.app-icon-box {
  width: 64px;
  height: 64px;
  border-radius: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  position: relative;
  box-shadow: 0 3px 10px rgba(0, 0, 0, 0.12);
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}

.dark .app-icon-box {
  box-shadow: 0 3px 10px rgba(0, 0, 0, 0.35);
}

.app-icon-item:active .app-icon-box {
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.08);
}

.app-icon-box::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: 16px;
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.08);
  pointer-events: none;
}

.app-emoji {
  font-size: 32px;
  line-height: 1;
  display: flex;
  align-items: center;
  justify-content: center;
}

/* 红点通知 */
.badge {
  position: absolute;
  top: -4px;
  right: -4px;
  background: #ff3b30;
  color: white;
  border-radius: 50%;
  width: 24px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 11px;
  font-weight: 700;
  border: 2px solid white;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
}

.dark .badge {
  border-color: #1c1c1e;
}

.app-label {
  font-size: 12px;
  font-weight: 500;
  color: #000;
  text-align: center;
  line-height: 1.3;
  max-width: 64px;
  overflow: hidden;
  text-overflow: ellipsis;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  white-space: normal;
}

.dark .app-label {
  color: #fff;
}

/* ==================== iPhone Dock ==================== */
.iphone-dock {
  position: fixed;
  bottom: 24px;
  left: 0;
  right: 0;
  display: flex;
  justify-content: center;
  align-items: center;
  padding: 0 16px 8px 16px;
  z-index: 50;
  pointer-events: none;
}

.dock-container {
  display: flex;
  gap: 20px;
  background: rgba(255, 255, 255, 0.7);
  backdrop-filter: blur(30px) saturate(180%);
  -webkit-backdrop-filter: blur(30px) saturate(180%);
  border-radius: 20px;
  padding: 8px 16px;
  box-shadow:
    0 8px 32px rgba(0, 0, 0, 0.12),
    0 0 0 0.5px rgba(0, 0, 0, 0.05);
  pointer-events: auto;
}

.dark .dock-container {
  background: rgba(28, 28, 30, 0.7);
  box-shadow:
    0 8px 32px rgba(0, 0, 0, 0.4),
    0 0 0 0.5px rgba(255, 255, 255, 0.1);
}

.dock-item {
  cursor: pointer;
  transition: transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.dock-item:active {
  transform: scale(0.85);
}

.dock-icon {
  width: 64px;
  height: 64px;
  border-radius: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 3px 10px rgba(0, 0, 0, 0.12);
  position: relative;
  overflow: hidden;
}

.dock-icon::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: 16px;
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.08);
  pointer-events: none;
}

.dark .dock-icon {
  box-shadow: 0 3px 10px rgba(0, 0, 0, 0.35);
}

.dock-emoji {
  font-size: 32px;
  line-height: 1;
  filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.2));
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

/* ==================== 长按菜单 ==================== */
.context-menu-overlay {
  position: fixed;
  inset: 0;
  z-index: 1000;
  background: rgba(0, 0, 0, 0);
  animation: fadeIn 0.15s ease;
}

.context-menu {
  position: fixed;
  background: rgba(255, 255, 255, 0.95);
  backdrop-filter: blur(20px);
  border-radius: 14px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
  overflow: hidden;
  min-width: 140px;
  z-index: 1001;
  animation: popIn 0.2s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.dark .context-menu {
  background: rgba(28, 28, 30, 0.95);
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
}

.context-menu-item {
  padding: 12px 16px;
  font-size: 16px;
  color: #007aff;
  text-align: center;
  cursor: pointer;
  border-bottom: 1px solid rgba(0, 0, 0, 0.1);
  transition: background 0.15s ease;
}

.dark .context-menu-item {
  border-bottom-color: rgba(255, 255, 255, 0.1);
}

.context-menu-item:last-child {
  border-bottom: none;
}

.context-menu-item:active {
  background: rgba(0, 0, 0, 0.05);
}

.dark .context-menu-item:active {
  background: rgba(255, 255, 255, 0.1);
}

.context-menu-item.cancel {
  color: #ff3b30;
  font-weight: 600;
}

/* ==================== 动画 ==================== */
@keyframes fadeIn {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}

@keyframes popIn {
  from {
    opacity: 0;
    transform: scale(0.8);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}

/* ==================== 响应式设计 ==================== */
@media (max-width: 480px) {
  .apps-grid {
    grid-template-columns: repeat(4, 1fr);
    gap: 16px;
    padding: 16px 16px 110px 16px;
  }

  .app-icon-box {
    width: 60px;
    height: 60px;
    border-radius: 14px;
  }

  .app-emoji {
    font-size: 28px;
  }

  .app-label {
    font-size: 11px;
    max-width: 60px;
  }

  .dock-container {
    gap: 16px;
    padding: 8px 12px;
    border-radius: 18px;
  }

  .dock-icon {
    width: 60px;
    height: 60px;
    border-radius: 14px;
  }

  .dock-emoji {
    font-size: 28px;
  }
}

@media (min-width: 768px) {
  .apps-grid {
    grid-template-columns: repeat(5, 1fr);
    gap: 24px;
    padding: 24px 24px 120px 24px;
  }

  .app-icon-box {
    width: 72px;
    height: 72px;
    border-radius: 18px;
  }

  .app-emoji {
    font-size: 36px;
  }

  .app-label {
    font-size: 13px;
    max-width: 72px;
  }

  .dock-container {
    gap: 24px;
    padding: 10px 16px;
    border-radius: 22px;
  }

  .dock-icon {
    width: 72px;
    height: 72px;
    border-radius: 18px;
  }

  .dock-emoji {
    font-size: 36px;
  }
}

@media (min-width: 1024px) {
  .apps-grid {
    grid-template-columns: repeat(6, 1fr);
    gap: 28px;
    padding: 28px 32px 130px 32px;
  }

  .app-icon-box {
    width: 80px;
    height: 80px;
    border-radius: 20px;
  }

  .app-emoji {
    font-size: 40px;
  }

  .app-label {
    font-size: 14px;
    max-width: 80px;
  }

  .dock-container {
    gap: 28px;
    padding: 12px 20px;
    border-radius: 24px;
  }

  .dock-icon {
    width: 80px;
    height: 80px;
    border-radius: 20px;
  }

  .dock-emoji {
    font-size: 40px;
  }
}

/* ==================== 无障碍优化 ==================== */
@media (prefers-reduced-motion: reduce) {
  .app-icon-item,
  .dock-item,
  .context-menu {
    transition: none;
    animation: none;
  }
}

/* ==================== Dock 悬停效果（桌面端）==================== */
@media (hover: hover) {
  .dock-item:hover {
    transform: translateY(-4px) scale(1.05);
  }

  .dock-item:active {
    transform: translateY(-2px) scale(0.95);
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
