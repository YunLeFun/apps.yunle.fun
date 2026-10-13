<script setup lang="ts">
import type { AppIconStyle, InAppBrowserMode, ThemeMode } from '~/stores/settings'
import { Capacitor } from '@capacitor/core'
import {
  IonAlert,
} from '@ionic/vue'
import {
  appsOutline,
  chevronBackOutline,
  cloudDoneOutline,
  cloudOutline,
  ellipsisHorizontalOutline,
  layersOutline,
  moonOutline,
  openOutline,
  phonePortraitOutline,
  serverOutline,
  shareOutline,
  sunnyOutline,
  syncOutline,
  trashOutline,
} from 'ionicons/icons'
import {
  kBlock,
  kBlockTitle,
  kList,
  kListItem,
  kSegmented,
  kSegmentedButton,
  kToggle,
} from 'konsta/vue'
import { APP_ICON_STYLE_OPTIONS, SESSION_LIMIT_OPTIONS } from '~/stores/settings'

const settingsStore = useSettingsStore()
const homeScreenStore = useHomeScreenStore()
const userStore = useUserStore()
const { isMember } = useCoin()

const selectedTheme = ref<ThemeMode>(settingsStore.themeMode)
const selectedAppIconStyle = ref<AppIconStyle>(settingsStore.appIconStyle)

function selectTheme(value: ThemeMode) {
  selectedTheme.value = value
  settingsStore.applyTheme(value)
}

function selectAppIconStyle(value: AppIconStyle) {
  selectedAppIconStyle.value = value
  settingsStore.setAppIconStyle(value)
}

const isIOS = import.meta.client && Capacitor.getPlatform() === 'ios'

const selectedBrowserMode = ref<InAppBrowserMode>(settingsStore.inAppBrowserMode)

function selectBrowserMode(value: InAppBrowserMode) {
  selectedBrowserMode.value = value
  settingsStore.inAppBrowserMode = value
}

const showSessionLimitAlert = shallowRef(false)
const sessionLimitLabel = computed(() => {
  if (!isMember.value)
    return '自动（最高 5 个）'
  const preference = settingsStore.sessionLimitPreference
  return preference === 'auto' ? '自动（推荐）' : `${preference} 个`
})
const sessionLimitInputs = computed(() => SESSION_LIMIT_OPTIONS.map(option => ({
  type: 'radio' as const,
  label: option.label,
  value: option.value,
  checked: settingsStore.sessionLimitPreference === option.value,
})))

function openSessionLimitSettings() {
  if (!isMember.value) {
    navigateTo('/membership')
    return
  }
  showSessionLimitAlert.value = true
}

function applySessionLimitPreference(value: unknown) {
  const preference = value === 'auto' ? value : Number(value)
  const option = SESSION_LIMIT_OPTIONS.find(item => item.value === preference)
  if (option)
    settingsStore.setSessionLimitPreference(option.value)
}

const sessionLimitAlertButtons = [
  { text: '取消', role: 'cancel' },
  { text: '完成', handler: applySessionLimitPreference },
]

onMounted(() => {
  settingsStore.initTheme()
  refreshStorageInfo()
})

// ==================== 存储空间 ====================

const storageUsed = ref('计算中...')
const storageKeys = ref(0)

function refreshStorageInfo() {
  const { used, keys } = settingsStore.getLocalStorageUsage()
  storageKeys.value = keys
  storageUsed.value = formatBytes(used)
}

function formatBytes(bytes: number): string {
  if (bytes === 0)
    return '0 B'
  if (bytes < 1024)
    return `${bytes} B`
  if (bytes < 1024 * 1024)
    return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

// 清除缓存确认
const showClearAlert = ref(false)

function handleClearStorage() {
  showClearAlert.value = true
}

function confirmClearStorage() {
  settingsStore.clearLocalStorage()
  refreshStorageInfo()
  showClearAlert.value = false
}

// ==================== 云同步 ====================

const syncStatusText = computed(() => {
  if (!settingsStore.cloudSyncEnabled)
    return '已关闭'
  if (homeScreenStore.isSyncing)
    return '同步中...'
  if (homeScreenStore.lastSyncAt > 0) {
    return `上次同步：${formatSyncTime(homeScreenStore.lastSyncAt)}`
  }
  return '尚未同步'
})

function formatSyncTime(timestamp: number): string {
  const now = Date.now()
  const diff = now - timestamp
  if (diff < 60000)
    return '刚刚'
  if (diff < 3600000)
    return `${Math.floor(diff / 60000)} 分钟前`
  if (diff < 86400000)
    return `${Math.floor(diff / 3600000)} 小时前`
  const date = new Date(timestamp)
  return `${date.getMonth() + 1}/${date.getDate()} ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`
}

const { syncToCloud } = useHomeScreen()

async function handleManualSync() {
  if (homeScreenStore.isSyncing)
    return
  await syncToCloud()
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="我" />
        </IonButtons>
        <IonTitle>设置</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <IonHeader collapse="condense">
        <IonToolbar>
          <IonTitle size="large">
            设置
          </IonTitle>
        </IonToolbar>
      </IonHeader>

      <!-- 外观 -->
      <k-block-title>外观</k-block-title>
      <k-block strong inset class="theme-block">
        <k-segmented strong class="theme-segment">
          <k-segmented-button
            :active="selectedTheme === 'system'"
            @click="selectTheme('system')"
          >
            <div class="flex flex-col items-center gap-1 py-2">
              <IonIcon :icon="phonePortraitOutline" class="text-lg" />
              <span class="text-xs">自动</span>
            </div>
          </k-segmented-button>
          <k-segmented-button
            :active="selectedTheme === 'light'"
            @click="selectTheme('light')"
          >
            <div class="flex flex-col items-center gap-1 py-2">
              <IonIcon :icon="sunnyOutline" class="text-lg" />
              <span class="text-xs">浅色</span>
            </div>
          </k-segmented-button>
          <k-segmented-button
            :active="selectedTheme === 'dark'"
            @click="selectTheme('dark')"
          >
            <div class="flex flex-col items-center gap-1 py-2">
              <IonIcon :icon="moonOutline" class="text-lg" />
              <span class="text-xs">深色</span>
            </div>
          </k-segmented-button>
        </k-segmented>
        <p class="text-xs text-center mt-3 opacity-50">
          「自动」将跟随系统外观设置
        </p>
      </k-block>

      <k-block strong inset class="theme-block">
        <k-segmented strong class="theme-segment">
          <k-segmented-button
            v-for="option in APP_ICON_STYLE_OPTIONS"
            :key="option.value"
            :active="selectedAppIconStyle === option.value"
            @click="selectAppIconStyle(option.value)"
          >
            <div class="flex flex-col items-center gap-1.5 py-2">
              <AppIconBox
                class="icon-style-preview"
                emoji="🎨"
                color="#007AFF"
                :style-mode="option.value"
              />
              <span class="text-xs">{{ option.label }}</span>
            </div>
          </k-segmented-button>
        </k-segmented>
        <p class="text-xs text-center mt-3 opacity-50">
          应用图标外观，全站统一生效
        </p>
      </k-block>

      <!-- 网页浏览器（仅 iOS） -->
      <k-block v-if="isIOS" strong inset class="theme-block">
        <k-segmented strong class="theme-segment">
          <k-segmented-button
            :active="selectedBrowserMode === 'titlebar'"
            @click="selectBrowserMode('titlebar')"
          >
            <div class="flex flex-col items-center gap-1.5 py-2">
              <div class="bmp-card">
                <div class="bmp-bar bmp-bar--themed">
                  <IonIcon :icon="chevronBackOutline" class="bmp-icon bmp-icon--on-theme" />
                  <span class="bmp-title bmp-title--on-theme">今天来做菜</span>
                  <IonIcon :icon="ellipsisHorizontalOutline" class="bmp-icon bmp-icon--on-theme" />
                </div>
                <div class="bmp-lines">
                  <div class="bmp-line" />
                  <div class="bmp-line bmp-line--s" />
                </div>
              </div>
              <span class="text-xs">标题栏模式</span>
            </div>
          </k-segmented-button>
          <k-segmented-button
            :active="selectedBrowserMode === 'system'"
            @click="selectBrowserMode('system')"
          >
            <div class="flex flex-col items-center gap-1.5 py-2">
              <div class="bmp-card">
                <div class="bmp-bar bmp-bar--safari">
                  <span class="bmp-done">完成</span>
                  <span class="bmp-url">cook.yunyoujun.cn</span>
                  <IonIcon :icon="shareOutline" class="bmp-icon bmp-icon--blue" />
                </div>
                <div class="bmp-lines">
                  <div class="bmp-line" />
                  <div class="bmp-line bmp-line--s" />
                </div>
              </div>
              <span class="text-xs">手机内置</span>
            </div>
          </k-segmented-button>
        </k-segmented>
        <p class="text-xs text-center mt-3 opacity-50">
          网页浏览器样式 · 沉浸模式由官方应用自动启用
        </p>
      </k-block>

      <!-- 外链打开方式（仅沉浸/标题栏模式生效） -->
      <k-list v-if="isIOS && selectedBrowserMode !== 'system'" strong inset>
        <k-list-item
          title="外链跳出 App 打开"
          footer="在 App 内浏览器打开其他网站的链接时，跳出到手机默认浏览器；关闭后在 App 内以系统浏览器视图打开"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-orange">
              <IonIcon :icon="openOutline" />
            </span>
          </template>
          <template #after>
            <k-toggle
              :checked="settingsStore.externalLinkMode === 'default-browser'"
              @change="settingsStore.externalLinkMode
                = settingsStore.externalLinkMode === 'default-browser' ? 'safari-view' : 'default-browser'"
            />
          </template>
        </k-list-item>
      </k-list>

      <!-- Background session policy only affects the native iOS container. -->
      <k-block-title v-if="isIOS">
        后台运行
      </k-block-title>
      <k-list v-if="isIOS" strong inset>
        <k-list-item
          link
          title="后台应用数量"
          :after="sessionLimitLabel"
          :footer="isMember
            ? '手动设置最多 7 个；设备内存紧张时仍会自动回收较早使用的应用'
            : '自动适配设备，最高 5 个；会员可手动设置最多 7 个'"
          @click="openSessionLimitSettings"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="layersOutline" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 主屏幕 -->
      <k-block-title>主屏幕</k-block-title>
      <k-list strong inset>
        <k-list-item
          title="显示 Dock 栏"
          footer="底部固定常用应用栏，长按可拖入/移除"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-purple">
              <IonIcon :icon="appsOutline" />
            </span>
          </template>
          <template #after>
            <k-toggle
              :checked="settingsStore.dockVisible"
              @change="settingsStore.dockVisible = !settingsStore.dockVisible"
            />
          </template>
        </k-list-item>
      </k-list>

      <!-- 云同步 -->
      <k-block-title>云同步</k-block-title>
      <k-list strong inset>
        <k-list-item
          title="云同步"
          :footer="userStore.isLoggedIn ? syncStatusText : '登录后可开启云同步'"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="cloudOutline" />
            </span>
          </template>
          <template #after>
            <k-toggle
              :checked="settingsStore.cloudSyncEnabled && userStore.isLoggedIn"
              :disabled="!userStore.isLoggedIn"
              @change="settingsStore.cloudSyncEnabled = !settingsStore.cloudSyncEnabled"
            />
          </template>
        </k-list-item>

        <k-list-item
          v-if="settingsStore.cloudSyncEnabled && userStore.isLoggedIn"
          title="自动同步"
          footer="本地变更自动同步到云端"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-green">
              <IonIcon :icon="syncOutline" />
            </span>
          </template>
          <template #after>
            <k-toggle
              :checked="settingsStore.cloudAutoSync"
              @change="settingsStore.cloudAutoSync = !settingsStore.cloudAutoSync"
            />
          </template>
        </k-list-item>

        <k-list-item
          v-if="settingsStore.cloudSyncEnabled && userStore.isLoggedIn"
          link
          title="立即同步"
          @click="handleManualSync"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-teal">
              <IonIcon :icon="cloudDoneOutline" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 存储空间 -->
      <k-block-title>存储空间</k-block-title>
      <k-list strong inset>
        <k-list-item
          title="本地缓存"
          :after="storageUsed"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-gray">
              <IonIcon :icon="serverOutline" />
            </span>
          </template>
        </k-list-item>

        <k-list-item
          link
          title="清除本地缓存"
          class="k-list-item-destructive"
          @click="handleClearStorage"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-red">
              <IonIcon :icon="trashOutline" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 清除缓存确认弹窗 -->
      <IonAlert
        :is-open="showSessionLimitAlert"
        css-class="session-limit-alert"
        header="后台应用数量"
        message="数量越多，占用的内存越高。发生内存警告时会优先回收较早使用的后台应用。"
        :inputs="sessionLimitInputs"
        :buttons="sessionLimitAlertButtons"
        @did-dismiss="showSessionLimitAlert = false"
      />

      <IonAlert
        :is-open="showClearAlert"
        header="清除本地缓存"
        message="将清除所有本地缓存数据（包括主题设置、已安装应用、最近使用等），不会影响账号数据。确定要清除吗？"
        :buttons="[
          { text: '取消', role: 'cancel', handler: () => { showClearAlert = false } },
          { text: '清除', role: 'destructive', handler: confirmClearStorage },
        ]"
        @did-dismiss="showClearAlert = false"
      />
    </IonContent>
  </IonPage>
</template>

<style scoped>
.theme-block :deep(.k-block-content-wrap) {
  padding-left: 0 !important;
  padding-right: 0 !important;
}

/* 图标风格选项的迷你预览 */
.icon-style-preview {
  --app-icon-size: 32px;
  --app-icon-radius: 9px;
  --app-emoji-size: 16px;
}

.theme-segment :deep(button) {
  height: auto !important;
  overflow: visible !important;
}

/* 浏览器模式迷你预览（内嵌在 segmented button 中） */
.bmp-card {
  position: relative;
  display: flex;
  flex-direction: column;
  width: 88px;
  height: 42px;
  border-radius: 8px;
  border: 0.5px solid rgba(0, 0, 0, 0.12);
  overflow: hidden;
}

.bmp-bar {
  display: flex;
  align-items: center;
  gap: 3px;
  padding: 5px 6px 4px;
  border-bottom: 0.5px solid rgba(0, 0, 0, 0.08);
}

.bmp-bar--safari {
  justify-content: space-between;
}

.bmp-icon {
  font-size: 10px;
  flex-shrink: 0;
  color: var(--ion-color-medium, #888);
}

.bmp-icon--blue {
  color: var(--ion-color-primary, #007aff);
}

.bmp-title {
  flex: 1;
  text-align: center;
  font-size: 8px;
  font-weight: 500;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.bmp-done {
  font-size: 8px;
  color: var(--ion-color-primary, #007aff);
  white-space: nowrap;
}

.bmp-url {
  flex: 1;
  margin: 0 3px;
  background: rgba(0, 0, 0, 0.06);
  border-radius: 3px;
  padding: 1px 4px;
  font-size: 7px;
  color: var(--ion-color-medium, #888);
  text-align: center;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* 标题栏模式：顶栏自动套用应用主题色（预览用主色示意），文字/图标转白 */
.bmp-bar--themed {
  background: var(--ion-color-primary, #007aff);
  border-bottom-color: rgba(255, 255, 255, 0.18);
}

.bmp-icon--on-theme {
  color: rgba(255, 255, 255, 0.95);
}

.bmp-title--on-theme {
  color: #fff;
}

.bmp-lines {
  flex: 1;
  padding: 5px 6px;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 3px;
}

.bmp-line {
  height: 4px;
  border-radius: 2px;
  background: rgba(0, 0, 0, 0.08);
}

.bmp-line--s {
  width: 55%;
}

@media (prefers-color-scheme: dark) {
  .bmp-card {
    border-color: rgba(255, 255, 255, 0.12);
  }

  .bmp-bar {
    border-color: rgba(255, 255, 255, 0.08);
  }

  .bmp-url {
    background: rgba(255, 255, 255, 0.1);
  }

  .bmp-line {
    background: rgba(255, 255, 255, 0.1);
  }
}

/* Dark mode: segmented selected state — subtle highlight + white text (native iOS feel) */
:global(.dark) .theme-segment :deep(.k-segmented-strong-button-active) {
  color: white;
}

:global(.dark) .theme-block :deep(.k-segmented > span:last-child) {
  background: rgba(255, 255, 255, 0.2) !important;
}

:global(.session-limit-alert .alert-radio-group) {
  max-height: 360px;
}
</style>
