<script setup lang="ts">
import {
  alertController,
} from '@ionic/vue'
import consola from 'consola'
import {
  bugOutline,
  checkmarkCircle,
  codeSlashOutline,
  copyOutline,
  globeOutline,
  informationCircleOutline,
  logOutOutline,
  terminalOutline,
  trashOutline,
} from 'ionicons/icons'
import {
  kBlockTitle,
  kList,
  kListItem,
} from 'konsta/vue'

const developerStore = useDeveloperStore()
const consoleStore = useConsoleStore()
const appStore = useAppStore()
const { showSuccess, showError } = useToast()
const { confirmExitDevMode } = useDeveloperMode()
const { active: vConsoleActive, toggle: toggleVConsole } = useVConsole()
const runtimeConfig = useRuntimeConfig()

const appVersion = '0.0.1'

// 应用 / Nuxt 信息
const appInfo = computed(() => [
  { label: '版本号', value: appVersion },
  { label: 'Nuxt SSR', value: 'false (CSR)' },
  { label: '运行环境', value: import.meta.dev ? '开发' : '生产' },
])

// CloudBase 信息
const tcbEnvId = computed(() => runtimeConfig.public.tcbEnvId || '未配置')
const tcbRegion = computed(() => runtimeConfig.public.cloudbaseRegion || '未配置')

async function copyEnvId() {
  try {
    await navigator.clipboard.writeText(tcbEnvId.value)
    showSuccess('环境 ID 已复制')
  }
  catch {
    showError('复制失败')
  }
}

// API 环境选项
const apiEnvironments = [
  { label: '生产环境', value: 'production' as const, url: 'https://api.yunle.fun' },
  { label: '开发环境', value: 'development' as const, url: 'http://localhost:8001' },
]

function selectApiEnv(env: 'production' | 'development') {
  developerStore.setApiEnvironment(env)
  showSuccess(`已切换到${env === 'production' ? '生产' : '开发'}环境`)
  consola.info(`[Developer] API 环境切换为: ${env}`)
}

async function confirmClearCache() {
  const alert = await alertController.create({
    header: '清除缓存',
    message: '将清除所有本地缓存数据（包括主题设置、最近使用记录等），确定要继续吗？',
    buttons: [
      {
        text: '取消',
        role: 'cancel',
      },
      {
        text: '清除',
        role: 'destructive',
        handler: () => {
          try {
            appStore.clearRecentApps()
            localStorage.clear()
            showSuccess('缓存已清除，部分设置将在刷新后重置')
            consola.info('[Developer] 本地缓存已清除')
          }
          catch (e) {
            showError('清除缓存失败')
            consola.error('[Developer] 清除缓存失败:', e)
          }
        },
      },
    ],
  })

  await alert.present()
}

async function confirmClearLogs() {
  const alert = await alertController.create({
    header: '清除日志',
    message: '确定要清除所有日志记录吗？',
    buttons: [
      {
        text: '取消',
        role: 'cancel',
      },
      {
        text: '清除',
        role: 'destructive',
        handler: () => {
          consoleStore.clearLogs()
          // eslint-disable-next-line no-console
          console.clear()
          showSuccess('日志已清除')
          consola.info('[Developer] 控制台日志已清除')
        },
      },
    ],
  })

  await alert.present()
}

// 控制台日志计数
const logCount = computed(() => consoleStore.logs.length)
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="我" />
        </IonButtons>
        <IonTitle>开发者选项</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <IonHeader collapse="condense">
        <IonToolbar>
          <IonTitle size="large">
            开发者选项
          </IonTitle>
        </IonToolbar>
      </IonHeader>

      <!-- 应用信息 -->
      <k-block-title>应用信息</k-block-title>
      <k-list strong inset>
        <k-list-item
          v-for="item in appInfo"
          :key="item.label"
          :title="item.label"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-gray">
              <IonIcon :icon="informationCircleOutline" />
            </span>
          </template>
          <template #after>
            <span class="max-w-48 truncate text-right">{{ item.value }}</span>
          </template>
        </k-list-item>
      </k-list>

      <!-- CloudBase -->
      <k-block-title>CloudBase</k-block-title>
      <k-list strong inset>
        <k-list-item
          link
          title="环境 ID"
          title-wrap-class="flex-nowrap"
          @click="copyEnvId"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="copyOutline" />
            </span>
          </template>
          <template #after>
            <span class="max-w-40 truncate text-right text-xs font-mono">{{ tcbEnvId }}</span>
          </template>
        </k-list-item>

        <k-list-item title="区域">
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="globeOutline" />
            </span>
          </template>
          <template #after>
            <span class="max-w-48 truncate text-right">{{ tcbRegion }}</span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 调试工具 -->
      <k-block-title>调试工具</k-block-title>
      <k-list strong inset>
        <k-list-item
          link
          title="控制台"
          footer="实时查看应用日志"
          inner-class="k-list-item-vcenter"
          @click="navigateTo('/developer/console')"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-green">
              <IonIcon :icon="terminalOutline" />
            </span>
          </template>
          <template v-if="logCount > 0" #after>
            <span class="ios-badge ios-badge-center text-xs">{{ logCount }}</span>
          </template>
        </k-list-item>

        <k-list-item
          link
          title="vConsole"
          footer="网络请求、存储、元素检查"
          inner-class="k-list-item-vcenter"
          @click="toggleVConsole()"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-teal">
              <IonIcon :icon="codeSlashOutline" />
            </span>
          </template>
          <template #after>
            <span
              class="text-xs font-medium"
              :class="vConsoleActive ? 'text-green-500' : 'ios-secondary-text'"
            >
              {{ vConsoleActive ? '已开启' : '已关闭' }}
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 环境配置 -->
      <k-block-title>环境配置</k-block-title>
      <k-list strong inset>
        <k-list-item
          v-for="env in apiEnvironments"
          :key="env.value"
          :title="env.label"
          :footer="env.url"
          inner-class="k-list-item-vcenter"
          @click="selectApiEnv(env.value)"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="globeOutline" />
            </span>
          </template>
          <template #after>
            <IonIcon
              v-if="developerStore.apiEnvironment === env.value"
              :icon="checkmarkCircle"
              class="text-xl"
              color="primary"
            />
          </template>
        </k-list-item>
      </k-list>

      <!-- 数据管理 -->
      <k-block-title>数据管理</k-block-title>
      <k-list strong inset>
        <k-list-item
          link
          title="清除缓存"
          footer="清除 localStorage 和应用数据"
          inner-class="k-list-item-vcenter"
          @click="confirmClearCache"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-orange">
              <IonIcon :icon="trashOutline" />
            </span>
          </template>
        </k-list-item>

        <k-list-item
          link
          title="清除日志"
          footer="清除控制台日志"
          inner-class="k-list-item-vcenter"
          @click="confirmClearLogs"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-gray">
              <IonIcon :icon="bugOutline" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 退出开发者模式 -->
      <k-list strong inset class="mt-8">
        <k-list-item
          link
          title="退出开发者模式"
          class="k-list-item-destructive"
          @click="confirmExitDevMode"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-red">
              <IonIcon :icon="logOutOutline" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <div class="h-8" />
    </IonContent>
  </IonPage>
</template>
