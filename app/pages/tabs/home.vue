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

import type { YlfAppInfo } from '@yunlefun/types'
import type { InstalledApp } from '~/types/homeScreen'
import { Haptics, ImpactStyle } from '@capacitor/haptics'
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonItem,
  IonLabel,
  IonList,
  IonPage,
  IonPopover,
  IonSearchbar,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { add, addCircleOutline, qrCodeOutline, searchOutline } from 'ionicons/icons'
import { homeApps } from '~/constants/apps'
import { RECENT_DEFAULT_DISPLAY } from '~/types/homeScreen'

definePageMeta({
  alias: ['/', '/home'],
})

const router = useRouter()
const homeScreenStore = useHomeScreenStore()
const settingsStore = useSettingsStore()
const userStore = useUserStore()
const { loadFromCloud, reloadForAccount, recordRecentUse, uninstallApp, installApp, removeRecentApp, updateDock, finishEditing } = useHomeScreen()
const { shareApp } = useAppActions()
const { openApp } = useOpenApp()
const { catalog, getApp, ensureLoaded } = useAppCatalog()

const searchQuery = ref('')

/** Dock 是否可见（用户在「设置 → 主屏幕 → 显示 Dock 栏」中控制，默认关闭） */
const showDock = computed(() => settingsStore.dockVisible)

// ==================== 搜索 ====================

/** 是否处于搜索状态（有非空关键词） */
const isSearching = computed(() => searchQuery.value.trim().length > 0)

/** 搜索结果：在全部应用中按名称 / 描述 / 分类匹配 */
const searchResults = computed<YlfAppInfo[]>(() => {
  const q = searchQuery.value.trim().toLowerCase()
  if (!q)
    return []
  return catalog.value.filter((app) => {
    return [app.name, app.description, app.category, app.tagline]
      .some(field => field?.toLowerCase().includes(q))
  })
})

/** 主屏幕是否为空（无已安装应用且非搜索态时展示空状态引导） */
const isHomeEmpty = computed(() => homeScreenStore.installedApps.length === 0)

// ==================== 初始化 ====================

onMounted(async () => {
  // 用静态数据初始化 Home Screen（首次使用时）
  homeScreenStore.initWithDefaults(homeApps.value)

  // 确保应用目录已加载（集合优先，内置兜底）
  ensureLoaded()

  // 异步加载云端数据
  loadFromCloud()
})

// 切换账号 / 登入登出时，强制按新账号重新拉取云端数据
watch(() => userStore.userInfo?.id, (newId, oldId) => {
  if (newId && newId !== oldId)
    reloadForAccount()
})

// ==================== 最近使用 ====================

const displayRecentApps = computed(() => {
  const recent = homeScreenStore.recentApps
  if (recent.length === 0)
    return []

  return recent.slice(0, RECENT_DEFAULT_DISPLAY).map((r) => {
    return getApp(r.appId) || null
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
const menuEvent = ref<Event | undefined>()

function openMenu(event: MouseEvent) {
  menuEvent.value = event
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

// ==================== 桌面交互 ====================

/** 打开应用（统一走 useOpenApp，含会员 / 云币门控；仅成功打开才计入最近使用） */
async function handleOpenApp(app: YlfAppInfo, installed: InstalledApp) {
  const opened = await openApp(app)
  if (opened)
    recordRecentUse(installed.appId)
}

/** 长按上下文菜单 */
const contextMenuVisible = ref(false)
const contextMenuPosition = ref({ x: 0, y: 0 })
const contextMenuApp = ref<InstalledApp | null>(null)
const contextMenuIconRect = ref<{ x: number, y: number, width: number, height: number } | null>(null)

/** 解析 InstalledApp 为 YlfAppInfo（集合优先，内置兜底） */
function resolveApp(installed: InstalledApp): YlfAppInfo | null {
  return getApp(installed.appId) ?? null
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
    </IonHeader>

    <!-- 顶部「+」下拉菜单（Ionic IonPopover，自动处理定位 / 边界 / 暗黑 / 安全区） -->
    <IonPopover
      :is-open="showMenu"
      :event="menuEvent"
      :dismiss-on-select="true"
      :show-backdrop="false"
      @did-dismiss="closeMenu"
    >
      <IonContent>
        <IonList lines="full">
          <IonItem button :detail="false" @click="handleScan">
            <IonIcon slot="start" :icon="qrCodeOutline" />
            <IonLabel>扫一扫</IonLabel>
          </IonItem>
          <IonItem button :detail="false" @click="handleAddApp">
            <IonIcon slot="start" :icon="addCircleOutline" />
            <IonLabel>添加应用</IonLabel>
          </IonItem>
        </IonList>
      </IonContent>
    </IonPopover>

    <IonContent
      class="phone-homescreen"
      :class="{ 'has-dock': showDock }"
      @click="handleContentClick"
    >
      <!-- 搜索结果 -->
      <template v-if="isSearching">
        <div class="px-5.5 pt-4">
          <ion-note class="text-black/60 dark:text-white/60">
            搜索结果（{{ searchResults.length }}）
          </ion-note>
        </div>
        <div v-if="searchResults.length > 0" class="recent-apps">
          <AppItem
            v-for="app in searchResults"
            :key="app.id || app.slug"
            :app="app"
          />
        </div>
        <div v-else class="empty-state">
          <IonIcon :icon="searchOutline" class="empty-icon" />
          <p class="empty-title">
            未找到「{{ searchQuery.trim() }}」相关应用
          </p>
          <p class="empty-desc">
            换个关键词，或前往工坊浏览全部应用
          </p>
        </div>
      </template>

      <!-- 正常布局（非搜索态） -->
      <template v-else>
        <!-- 最近使用 -->
        <div v-if="displayRecentApps.length > 0" class="recent-section">
          <div class="section-header px-5.5">
            <ion-note class="text-black/60 dark:text-white/60">
              最近使用
            </ion-note>
            <ion-note
              v-if="hasMoreRecent"
              class="cursor-pointer text-sm" style="color: var(--ion-color-primary)"
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

        <!-- 空状态引导 -->
        <div v-if="isHomeEmpty" class="empty-state">
          <IonIcon :icon="addCircleOutline" class="empty-icon" />
          <p class="empty-title">
            还没有添加任何应用
          </p>
          <p class="empty-desc">
            去工坊挑选喜欢的应用，添加到你的云居桌面
          </p>
          <IonButton size="small" @click="handleAddApp">
            前往工坊
          </IonButton>
        </div>

        <AppHomeScreenGrid
          v-else
          :pages="homeScreenStore.pagedApps"
          :edit-mode="homeScreenStore.isEditMode"
          :hidden-app-id="contextMenuVisible && contextMenuApp ? contextMenuApp.appId : undefined"
          @open="handleOpenApp"
          @remove="handleRemoveApp"
          @long-press="handleLongPress"
        />
      </template>
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
          :icon="recentDrag.dragApp.value.logo"
          :emoji="recentDrag.dragApp.value.emoji"
          :color="recentDrag.dragApp.value.themeColor"
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
  --background: linear-gradient(180deg, var(--ion-item-background, #1c1c1e) 0%, var(--ion-background-color, #000) 100%);
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

/* ==================== 空状态 ==================== */
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 56px 32px;
  gap: 8px;
}

.empty-icon {
  font-size: 48px;
  color: var(--ion-color-medium);
  opacity: 0.5;
  margin-bottom: 4px;
}

.empty-title {
  font-size: 16px;
  font-weight: 600;
  color: var(--ion-text-color);
}

.empty-desc {
  font-size: 14px;
  color: var(--ion-color-medium);
  margin-bottom: 8px;
}

/* ==================== 顶部下拉菜单（IonPopover）==================== */
ion-popover {
  --width: 200px;
}
</style>
