<script setup lang="ts">
import type { LogLevel } from '~/stores/console'
import { actionSheetController, IonContent } from '@ionic/vue'
import {
  closeOutline,
  funnelOutline,
  pauseOutline,
  playOutline,
  shareOutline,
  trashOutline,
} from 'ionicons/icons'

const consoleStore = useConsoleStore()
const toast = useToast()

// 过滤
const activeFilter = ref<LogLevel | 'all'>('all')

const filteredLogs = computed(() => {
  if (activeFilter.value === 'all')
    return consoleStore.logs
  return consoleStore.logs.filter(l => l.level === activeFilter.value)
})

// 自动滚动到底部
const contentRef = ref<InstanceType<typeof IonContent> | null>(null)

watch(() => consoleStore.logs.length, () => {
  nextTick(() => {
    contentRef.value?.$el?.scrollToBottom?.(150)
  })
})

// 进入页面时自动开始采集
onMounted(() => {
  consoleStore.startCapture()
})

// 日志等级样式
const levelStyles: Record<LogLevel, { color: string, bg: string, label: string }> = {
  log: { color: 'text-gray-600 dark:text-gray-300', bg: '', label: 'LOG' },
  info: { color: 'text-blue-600 dark:text-blue-400', bg: 'bg-blue-50 dark:bg-blue-900/20', label: 'INF' },
  warn: { color: 'text-yellow-700 dark:text-yellow-400', bg: 'bg-yellow-50 dark:bg-yellow-900/20', label: 'WRN' },
  error: { color: 'text-red-600 dark:text-red-400', bg: 'bg-red-50 dark:bg-red-900/20', label: 'ERR' },
  debug: { color: 'text-purple-600 dark:text-purple-400', bg: '', label: 'DBG' },
}

function formatTime(ts: number) {
  const d = new Date(ts)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}:${String(d.getSeconds()).padStart(2, '0')}.${String(d.getMilliseconds()).padStart(3, '0')}`
}

// 过滤选择
async function showFilter() {
  const filters: { label: string, value: LogLevel | 'all' }[] = [
    { label: '全部', value: 'all' },
    { label: 'Log', value: 'log' },
    { label: 'Info', value: 'info' },
    { label: 'Warn', value: 'warn' },
    { label: 'Error', value: 'error' },
    { label: 'Debug', value: 'debug' },
  ]

  const actionSheet = await actionSheetController.create({
    header: '筛选日志等级',
    buttons: [
      ...filters.map(f => ({
        text: `${f.label}${activeFilter.value === f.value ? ' ✓' : ''}`,
        handler: () => { activeFilter.value = f.value },
      })),
      { text: '取消', role: 'cancel' as const },
    ],
  })
  await actionSheet.present()
}

// 导出日志
async function exportLogs() {
  const text = filteredLogs.value.map(l =>
    `[${formatTime(l.timestamp)}] [${l.level.toUpperCase()}] ${l.plain}`,
  ).join('\n')

  if (!text) {
    toast.showInfo('暂无日志')
    return
  }

  try {
    await navigator.clipboard.writeText(text)
    toast.showSuccess(`已复制 ${filteredLogs.value.length} 条日志`)
  }
  catch {
    toast.showError('复制失败')
  }
}

function handleClear() {
  consoleStore.clearLogs()
  toast.showSuccess('日志已清除')
}

function toggleCapture() {
  if (consoleStore.capturing) {
    consoleStore.stopCapture()
    toast.showInfo('已暂停采集')
  }
  else {
    consoleStore.startCapture()
    toast.showSuccess('已开始采集')
  }
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/developer" text="开发者" />
        </IonButtons>
        <IonTitle>控制台</IonTitle>
        <IonButtons slot="end">
          <IonButton @click="toggleCapture">
            <IonIcon slot="icon-only" :icon="consoleStore.capturing ? pauseOutline : playOutline" />
          </IonButton>
          <IonButton @click="showFilter">
            <IonIcon slot="icon-only" :icon="funnelOutline" />
          </IonButton>
          <IonButton @click="exportLogs">
            <IonIcon slot="icon-only" :icon="shareOutline" />
          </IonButton>
          <IonButton color="danger" @click="handleClear">
            <IonIcon slot="icon-only" :icon="trashOutline" />
          </IonButton>
        </IonButtons>
      </IonToolbar>

      <!-- 状态栏 -->
      <IonToolbar>
        <div class="flex items-center gap-3 px-4 py-1 text-xs">
          <span class="flex items-center gap-1">
            <span
              class="inline-block h-2 w-2 rounded-full"
              :class="consoleStore.capturing ? 'bg-green-500' : 'bg-gray-400'"
            />
            {{ consoleStore.capturing ? '采集中' : '已暂停' }}
          </span>
          <span class="ios-secondary-text">
            {{ filteredLogs.length }} 条{{ activeFilter !== 'all' ? ` (${activeFilter})` : '' }}
          </span>
        </div>
      </IonToolbar>
    </IonHeader>

    <IonContent ref="contentRef" :fullscreen="true" class="console-content">
      <!-- 空状态 -->
      <div v-if="filteredLogs.length === 0" class="flex flex-col items-center justify-center pt-20 text-center">
        <IonIcon :icon="closeOutline" class="mb-2 text-4xl ios-secondary-text" />
        <p class="text-sm ios-secondary-text">
          暂无日志
        </p>
        <p class="mt-1 text-xs ios-secondary-text">
          {{ consoleStore.capturing ? '等待日志输出…' : '点击右上角 ▶ 开始采集' }}
        </p>
      </div>

      <!-- 日志列表 -->
      <div v-else class="console-list">
        <div
          v-for="entry in filteredLogs"
          :key="entry.id"
          class="console-entry"
          :class="levelStyles[entry.level].bg"
        >
          <div class="console-entry-header">
            <span
              class="console-level-badge"
              :class="levelStyles[entry.level].color"
            >
              {{ levelStyles[entry.level].label }}
            </span>
            <span class="console-time">{{ formatTime(entry.timestamp) }}</span>
          </div>
          <pre
            class="console-entry-body"
            :class="levelStyles[entry.level].color"
          ><template v-for="(seg, i) in entry.segments" :key="i"><span v-if="seg.style" :style="seg.style">{{ seg.text }}</span><template v-else>{{ seg.text }}</template></template></pre>
        </div>
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.console-content {
  --background: var(--ion-background-color, #f2f2f6);
  font-family: 'SF Mono', 'Menlo', 'Monaco', 'Consolas', monospace;
}

.console-list {
  padding: 4px 0;
}

.console-entry {
  padding: 6px 12px;
  border-bottom: 0.5px solid var(--ion-item-border-color, rgba(0, 0, 0, 0.08));
}

.console-entry-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 2px;
}

.console-level-badge {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.5px;
}

.console-time {
  font-size: 10px;
  color: var(--ion-color-medium, #8e8e93);
}

.console-entry-body {
  margin: 0;
  font-size: 12px;
  line-height: 1.4;
  white-space: pre-wrap;
  word-break: break-all;
}
</style>
