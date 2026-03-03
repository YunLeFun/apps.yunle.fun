<script setup lang="ts">
import type { ThemeMode } from '~/stores/settings'
import {
  IonAlert,
} from '@ionic/vue'
import {
  cloudDoneOutline,
  cloudOutline,
  moonOutline,
  phonePortraitOutline,
  serverOutline,
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

const settingsStore = useSettingsStore()
const homeScreenStore = useHomeScreenStore()
const userStore = useUserStore()

const selectedTheme = ref<ThemeMode>(settingsStore.themeMode)

function selectTheme(value: ThemeMode) {
  selectedTheme.value = value
  settingsStore.applyTheme(value)
}

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

.theme-segment :deep(button) {
  height: auto !important;
  overflow: visible !important;
}
</style>
