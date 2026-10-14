<script setup lang="ts">
import { App as CapacitorApp } from '@capacitor/app'
import { Capacitor } from '@capacitor/core'
import { actionSheetController, alertController } from '@ionic/vue'
import {
  bugOutline,
  chatbubbleEllipsesOutline,
  cloudUploadOutline,
  mailOutline,
  shieldCheckmarkOutline,
  starOutline,
  trashOutline,
} from 'ionicons/icons'
import {
  kBlock,
  kBlockTitle,
  kList,
  kListItem,
} from 'konsta/vue'
import { config } from '~/config'
import { YLF_CONTACT } from '~/constants'
import {
  estimateDiagnosticLogBytes,
  selectDiagnosticLogs,
} from '~/utils/diagnostic-logs'

const toast = useToast()
const consoleStore = useConsoleStore()
const userStore = useUserStore()
const route = useRoute()
const { $api } = useNuxtApp()

interface DiagnosticUploadResponse {
  code: 0
  data: {
    expiresAt: number
    logCount: number
    supportCode: string
    uploadId: string
  }
}

type RangePreset = '15m' | '1h' | '24h' | 'custom'

const HOUR_MS = 60 * 60 * 1000
const rangePresets: { label: string, value: Exclude<RangePreset, 'custom'>, duration: number }[] = [
  { label: '15 分钟', value: '15m', duration: 15 * 60 * 1000 },
  { label: '1 小时', value: '1h', duration: HOUR_MS },
  { label: '24 小时', value: '24h', duration: 24 * HOUR_MS },
]
const initialEndTime = Date.now()
const activePreset = ref<RangePreset>('1h')
const startTimeInput = ref(toLocalDatetimeInput(initialEndTime - HOUR_MS))
const endTimeInput = ref(toLocalDatetimeInput(initialEndTime))
const issueDescription = ref('')
const uploading = ref(false)
const appVersion = ref('')
const buildNumber = ref('')

const rangeStart = computed(() => new Date(startTimeInput.value).getTime())
// datetime-local 不保留毫秒；结束时间按所选“秒”的末尾计算，避免漏掉同秒日志。
const rangeEnd = computed(() => new Date(endTimeInput.value).getTime() + 999)
const rangeError = computed(() => {
  if (!Number.isFinite(rangeStart.value) || !Number.isFinite(rangeEnd.value))
    return '请选择完整的开始和结束时间'
  if (rangeStart.value > rangeEnd.value)
    return '开始时间不能晚于结束时间'
  if (rangeEnd.value - rangeStart.value > 24 * HOUR_MS + 999)
    return '单次最多选择 24 小时'
  if (rangeEnd.value > Date.now() + 5 * 60 * 1000)
    return '结束时间不能晚于当前时间'
  return ''
})
const selectedDiagnosticLogs = computed(() =>
  rangeError.value
    ? []
    : selectDiagnosticLogs(consoleStore.diagnosticLogs, rangeStart.value, rangeEnd.value),
)
const selectedLogBytes = computed(() => estimateDiagnosticLogBytes(selectedDiagnosticLogs.value))
const availableRangeText = computed(() => {
  const entries = consoleStore.diagnosticLogs
  const first = entries[0]
  if (!first)
    return '当前还没有本地日志'
  const last = entries.at(-1) || first
  return `本地可用：${formatDateTime(first.timestamp)} 至 ${formatDateTime(last.timestamp)}`
})

onMounted(async () => {
  if (!Capacitor.isNativePlatform())
    return
  try {
    const info = await CapacitorApp.getInfo()
    appVersion.value = info.version
    buildNumber.value = info.build
  }
  catch {
    appVersion.value = ''
    buildNumber.value = ''
  }
})

function applyRangePreset(preset: Exclude<RangePreset, 'custom'>, duration: number) {
  const endTime = Date.now()
  activePreset.value = preset
  startTimeInput.value = toLocalDatetimeInput(endTime - duration)
  endTimeInput.value = toLocalDatetimeInput(endTime)
}

function markCustomRange() {
  activePreset.value = 'custom'
}

async function confirmDiagnosticUpload() {
  if (!userStore.isLoggedIn) {
    toast.showInfo('请先登录后上传诊断日志')
    await navigateTo('/login')
    return
  }
  if (rangeError.value) {
    toast.showError(rangeError.value)
    return
  }
  if (!selectedDiagnosticLogs.value.length) {
    toast.showInfo('所选时间内没有可上传的日志')
    return
  }

  const alert = await alertController.create({
    header: '上传诊断日志？',
    message: `将上传 ${selectedDiagnosticLogs.value.length} 条脱敏后的 App 日志（${formatBytes(selectedLogBytes.value)}），服务端保留 7 天。`,
    buttons: [
      { text: '取消', role: 'cancel' },
      { text: '同意并上传', role: 'confirm' },
    ],
  })
  await alert.present()
  const result = await alert.onDidDismiss()
  if (result.role === 'confirm')
    await uploadDiagnosticLogs()
}

async function uploadDiagnosticLogs() {
  uploading.value = true
  try {
    const response = await $api<DiagnosticUploadResponse>('/api/diagnostics/logs', {
      method: 'POST',
      body: {
        startTime: rangeStart.value,
        endTime: rangeEnd.value,
        issueDescription: issueDescription.value,
        logs: selectedDiagnosticLogs.value,
        client: {
          appVersion: appVersion.value,
          buildNumber: buildNumber.value,
          platform: Capacitor.getPlatform(),
          route: route.path,
          timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || '',
          userAgent: navigator.userAgent,
        },
      },
    })
    issueDescription.value = ''
    toast.showSuccess(`日志已上传，编号 ${response.data.supportCode}`)
  }
  catch (error) {
    toast.showError(requestErrorMessage(error, '日志上传失败，请稍后重试'))
  }
  finally {
    uploading.value = false
  }
}

async function confirmClearDiagnosticLogs() {
  const alert = await alertController.create({
    header: '清除本地诊断日志？',
    message: '只会清除本机保存的 App 日志，不影响已经上传的诊断记录。',
    buttons: [
      { text: '取消', role: 'cancel' },
      {
        text: '清除',
        role: 'destructive',
        handler: () => {
          consoleStore.clearLogs()
          toast.showSuccess('本地诊断日志已清除')
        },
      },
    ],
  })
  await alert.present()
}

/**
 * 去 App Store 评分
 */
function goToAppStore() {
  if (Capacitor.isNativePlatform()) {
    window.open(config.appStore.url, '_system')
  }
  else {
    window.open(config.appStore.url, '_blank')
  }
}

/**
 * 生成邮件模板
 */
function buildMailtoUrl(email: string, type: 'business' | 'support') {
  const subject = type === 'business'
    ? encodeURIComponent('【业务合作】来自云乐坊用户')
    : encodeURIComponent('【问题反馈】来自云乐坊用户')

  const body = type === 'business'
    ? encodeURIComponent(
        `您好，\n\n我对贵平台的业务合作感兴趣，以下是我的信息：\n\n`
        + `公司/个人名称：\n`
        + `联系方式：\n`
        + `合作意向：\n\n`
        + `期待您的回复！\n\n`
        + `---\n`
        + `发送自 云乐坊 (yunle.fun)`,
      )
    : encodeURIComponent(
        `您好，\n\n我在使用云乐坊时遇到了以下问题：\n\n`
        + `问题描述：\n`
        + `操作步骤：\n`
        + `期望结果：\n`
        + `实际结果：\n\n`
        + `设备信息：${navigator.userAgent}\n\n`
        + `---\n`
        + `发送自 云乐坊 (yunle.fun)`,
      )

  return `mailto:${email}?subject=${subject}&body=${body}`
}

/**
 * 点击邮箱 → ActionSheet（复制 / 发送）
 */
async function handleEmailClick(email: string, type: 'business' | 'support') {
  const actionSheet = await actionSheetController.create({
    header: email,
    buttons: [
      {
        text: '复制邮箱',
        handler: async () => {
          try {
            await navigator.clipboard.writeText(email)
            toast.showSuccess('邮箱已复制')
          }
          catch {
            toast.showError('复制失败')
          }
        },
      },
      {
        text: '发送邮件',
        handler: () => {
          window.location.href = buildMailtoUrl(email, type)
        },
      },
      { text: '取消', role: 'cancel' },
    ],
  })
  await actionSheet.present()
}

function openWxKf() {
  window.open(YLF_CONTACT.wxKf.url, '_blank')
}

function toLocalDatetimeInput(timestamp: number): string {
  const date = new Date(timestamp)
  const localTime = new Date(timestamp - date.getTimezoneOffset() * 60 * 1000)
  return localTime.toISOString().slice(0, 19)
}

function formatDateTime(timestamp: number): string {
  return new Intl.DateTimeFormat('zh-CN', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(timestamp)
}

function formatBytes(bytes: number): string {
  if (bytes < 1024)
    return `${bytes} B`
  return `${(bytes / 1024).toFixed(1)} KB`
}

function requestErrorMessage(error: unknown, fallback: string): string {
  if (isRecord(error)) {
    const data = error.data
    if (isRecord(data)) {
      const message = data.statusMessage || data.message
      if (typeof message === 'string' && message)
        return message
    }
    const message = error.statusMessage || error.message
    if (typeof message === 'string' && message)
      return message
  }
  return error instanceof Error && error.message ? error.message : fallback
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="我" />
        </IonButtons>
        <IonTitle>反馈</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <IonHeader collapse="condense">
        <IonToolbar>
          <IonTitle size="large">
            反馈
          </IonTitle>
        </IonToolbar>
      </IonHeader>

      <k-block-title>诊断日志</k-block-title>
      <k-block strong inset class="diagnostic-block">
        <div class="diagnostic-heading">
          <span class="ios-icon-box ios-icon-orange">
            <IonIcon :icon="bugOutline" />
          </span>
          <div>
            <h2>上传特定时间内的 App 日志</h2>
            <p>仅采集云乐坊自身日志，不读取系统或其他 App 日志。</p>
          </div>
        </div>

        <div class="diagnostic-presets" aria-label="快速选择日志时间范围">
          <button
            v-for="preset in rangePresets"
            :key="preset.value"
            type="button"
            class="diagnostic-preset"
            :class="{ 'diagnostic-preset-active': activePreset === preset.value }"
            @click="applyRangePreset(preset.value, preset.duration)"
          >
            {{ preset.label }}
          </button>
        </div>

        <div class="diagnostic-range">
          <label>
            <span>开始时间</span>
            <input
              v-model="startTimeInput"
              type="datetime-local"
              step="1"
              :max="endTimeInput"
              @change="markCustomRange"
            >
          </label>
          <label>
            <span>结束时间</span>
            <input
              v-model="endTimeInput"
              type="datetime-local"
              step="1"
              :min="startTimeInput"
              :max="toLocalDatetimeInput(Date.now())"
              @change="markCustomRange"
            >
          </label>
        </div>

        <p v-if="rangeError" class="diagnostic-error">
          {{ rangeError }}
        </p>
        <p v-else class="diagnostic-available">
          {{ availableRangeText }}
        </p>

        <div class="diagnostic-summary">
          <IonIcon :icon="shieldCheckmarkOutline" />
          <div>
            <strong>{{ selectedDiagnosticLogs.length }} 条 · {{ formatBytes(selectedLogBytes) }}</strong>
            <p>凭证、签名 URL、手机号和邮箱会在本机及服务端各脱敏一次。</p>
          </div>
        </div>

        <IonTextarea
          v-model="issueDescription"
          class="diagnostic-description"
          label="问题描述（可选）"
          label-placement="stacked"
          fill="outline"
          :maxlength="500"
          :counter="true"
          :auto-grow="true"
          placeholder="例如：10:25 点击“获取私有应用”后提示云同步失败"
        />

        <p class="diagnostic-consent">
          点击上传即表示你同意提交所选日志、账号标识和 App/设备基本信息。诊断记录仅支持人员可见，7 天后清理。
        </p>

        <IonButton
          expand="block"
          :disabled="uploading || !!rangeError || selectedDiagnosticLogs.length === 0"
          @click="confirmDiagnosticUpload"
        >
          <IonSpinner v-if="uploading" slot="start" name="crescent" />
          <IonIcon v-else slot="start" :icon="cloudUploadOutline" />
          {{ userStore.isLoggedIn ? (uploading ? '上传中…' : '确认并上传') : '登录后上传' }}
        </IonButton>

        <IonButton
          fill="clear"
          color="danger"
          size="small"
          class="diagnostic-clear"
          :disabled="consoleStore.diagnosticLogs.length === 0"
          @click="confirmClearDiagnosticLogs"
        >
          <IonIcon slot="start" :icon="trashOutline" />
          清除本地日志
        </IonButton>
      </k-block>

      <!-- 反馈 -->
      <k-block-title>联系我们</k-block-title>
      <k-list strong inset>
        <k-list-item
          link
          :title="YLF_CONTACT.support.label"
          :after="YLF_CONTACT.support.email"
          @click="handleEmailClick(YLF_CONTACT.support.email, 'support')"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-orange">
              <IonIcon :icon="chatbubbleEllipsesOutline" />
            </span>
          </template>
        </k-list-item>

        <k-list-item
          link
          :title="YLF_CONTACT.business.label"
          :after="YLF_CONTACT.business.email"
          @click="handleEmailClick(YLF_CONTACT.business.email, 'business')"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="mailOutline" />
            </span>
          </template>
        </k-list-item>

        <k-list-item
          link
          :title="YLF_CONTACT.wxKf.label"
          after="微信"
          @click="openWxKf"
        >
          <template #media>
            <span class="ios-icon-box" style="background-color: #07c160">
              <Icon name="ri:customer-service-2-line" class="text-white" size="18px" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 支持我们 -->
      <k-block-title>支持我们</k-block-title>
      <k-list strong inset>
        <k-list-item
          link
          title="去评分"
          after="App Store"
          @click="goToAppStore"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-yellow">
              <IonIcon :icon="starOutline" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 社交媒体 -->
      <AppSocialMediaList />

      <!-- 底部说明 -->
      <k-block class="mt-8">
        <p class="text-center text-xs ios-secondary-text">
          我们会尽快回复您的反馈，感谢您的支持！
        </p>
      </k-block>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.diagnostic-block {
  margin-top: 0;
}

.diagnostic-heading {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  gap: 12px;
  align-items: start;
}

.diagnostic-heading h2 {
  margin: 1px 0 3px;
  color: var(--ion-text-color, #1c1c1e);
  font-size: 16px;
  font-weight: 650;
}

.diagnostic-heading p,
.diagnostic-summary p,
.diagnostic-consent {
  margin: 0;
  color: var(--ion-color-medium, #6d6d72);
  font-size: 12px;
  line-height: 1.45;
}

.diagnostic-presets {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 7px;
  margin-top: 16px;
}

.diagnostic-preset {
  min-height: 34px;
  border: 1px solid rgba(var(--ion-color-primary-rgb, 0, 122, 255), 0.28);
  border-radius: 9px;
  background: rgba(var(--ion-color-primary-rgb, 0, 122, 255), 0.07);
  color: var(--ion-color-primary, #007aff);
  font-size: 13px;
  font-weight: 550;
}

.diagnostic-preset-active {
  border-color: var(--ion-color-primary, #007aff);
  background: var(--ion-color-primary, #007aff);
  color: #fff;
}

.diagnostic-range {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  gap: 10px;
  margin-top: 12px;
}

.diagnostic-range label {
  display: grid;
  gap: 5px;
  color: var(--ion-color-medium, #6d6d72);
  font-size: 11px;
}

.diagnostic-range input {
  box-sizing: border-box;
  min-width: 0;
  width: 100%;
  min-height: 38px;
  padding: 8px;
  border: 1px solid var(--ion-color-step-250, #c7c7cc);
  border-radius: 9px;
  outline: none;
  background: var(--ion-item-background, #fff);
  color: var(--ion-text-color, #1c1c1e);
  font: inherit;
  font-size: 12px;
}

.diagnostic-range input:focus {
  border-color: var(--ion-color-primary, #007aff);
  box-shadow: 0 0 0 2px rgba(var(--ion-color-primary-rgb, 0, 122, 255), 0.12);
}

.diagnostic-available,
.diagnostic-error {
  margin: 8px 0 0;
  font-size: 11px;
  line-height: 1.35;
}

.diagnostic-available {
  color: var(--ion-color-medium, #6d6d72);
}

.diagnostic-error {
  color: var(--ion-color-danger, #ff3b30);
}

.diagnostic-summary {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  gap: 10px;
  align-items: start;
  margin: 14px 0;
  padding: 11px;
  border-left: 3px solid var(--ion-color-primary, #007aff);
  border-radius: 4px 10px 10px 4px;
  background: rgba(var(--ion-color-primary-rgb, 0, 122, 255), 0.07);
}

.diagnostic-summary > ion-icon {
  margin-top: 1px;
  color: var(--ion-color-primary, #007aff);
  font-size: 20px;
}

.diagnostic-summary strong {
  display: block;
  margin-bottom: 2px;
  color: var(--ion-text-color, #1c1c1e);
  font-size: 13px;
}

.diagnostic-description {
  --padding-start: 11px;
  --padding-end: 11px;
  margin-top: 2px;
}

.diagnostic-consent {
  margin: 10px 2px 12px;
}

.diagnostic-clear {
  display: block;
  margin: 5px auto -5px;
}

@media (max-width: 370px) {
  .diagnostic-range {
    grid-template-columns: 1fr;
  }
}
</style>
