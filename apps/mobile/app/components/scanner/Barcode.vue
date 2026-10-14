<script setup lang="ts">
import { Capacitor } from '@capacitor/core'
import { Haptics, ImpactStyle } from '@capacitor/haptics'
import { IonButton, IonIcon, IonSpinner } from '@ionic/vue'
import { closeOutline, flashlightOutline, imagesOutline, refreshOutline, videocamOffOutline } from 'ionicons/icons'

const props = defineProps<{
  isVisible: boolean
  showFlashlight?: boolean
  /** 是否显示底部取消按钮（页面级使用时头部已有返回，应传 false；overlay 场景保留默认 true） */
  showClose?: boolean
}>()

const emit = defineEmits<{
  cancel: []
  result: [content: string]
  pickAlbum: []
}>()

const videoRef = shallowRef<HTMLVideoElement | null>(null)
const { startScan: startWebScan, stopScan: stopWebScan, isSupported, stream } = useWebBarcodeScan()
const { startScan: startNativeScan } = useBarcodeScan()

// 手电筒：基于 W3C MediaStreamTrack.applyConstraints({ torch })
// 仅当 stream 就绪且设备支持时按钮才会渲染（前置摄像头/不兼容设备自动隐藏）
const {
  isSupported: torchSupported,
  enabled: torchOn,
  toggle: toggleTorch,
  check: checkTorch,
} = useTorch(stream)

type ScanStatus = 'idle' | 'starting' | 'scanning' | 'error'
const status = ref<ScanStatus>('idle')
const errorMessage = ref('')
const errorHint = ref('')

let scanAnimationId: number | null = null
let resultEmitted = false

/** 启动相机 + 二维码检测，失败时进入错误状态（而非静默退出页面） */
async function startCamera() {
  if (Capacitor.isNativePlatform()) {
    await startNativeCamera()
    return
  }

  const video = videoRef.value
  if (!video)
    return

  if (!isSupported()) {
    status.value = 'error'
    errorMessage.value = '当前环境不支持调用相机'
    errorHint.value = '可以点击下方按钮从相册选择二维码图片'
    return
  }

  status.value = 'starting'
  try {
    await startWebScan(video)
    // video play 之后再检测一次 torch 能力（启动时 stream 尚未 play）
    await nextTick()
    checkTorch()
    status.value = 'scanning'
    startQrDetection()
  }
  catch (error: any) {
    // useWebBarcodeScan.startScan 内部已输出错误日志，这里只负责映射错误文案
    status.value = 'error'
    if (error?.name === 'NotAllowedError' || error?.name === 'SecurityError') {
      errorMessage.value = '相机权限未开启'
      errorHint.value = '请在系统设置中允许「云乐坊」访问相机后重试'
    }
    else if (error?.name === 'NotFoundError' || error?.name === 'OverconstrainedError') {
      errorMessage.value = '未检测到可用的摄像头'
      errorHint.value = '可以点击下方按钮从相册选择二维码图片'
    }
    else {
      errorMessage.value = '相机启动失败'
      errorHint.value = '请重试，或从相册选择二维码图片'
    }
  }
}

async function startNativeCamera() {
  status.value = 'starting'
  try {
    const result = await startNativeScan()
    if (result?.ScanResult) {
      handleDetected(result.ScanResult)
      return
    }

    handleCancel()
  }
  catch (error: any) {
    status.value = 'error'
    const message = String(error?.message || error).toLowerCase()
    if (message.includes('permission') || message.includes('denied') || message.includes('not allowed')) {
      errorMessage.value = '相机权限未开启'
      errorHint.value = '请在系统设置中允许「云乐坊」访问相机后重试'
    }
    else {
      errorMessage.value = '相机启动失败'
      errorHint.value = '请重试，或从相册选择二维码图片'
    }
  }
}

function stopCamera() {
  stopQrDetection()
  stopWebScan()
  status.value = 'idle'
}

onMounted(() => {
  // isVisible 常为静态 true（如 /scan 页），watch 不会触发，必须在挂载时主动启动
  if (props.isVisible)
    startCamera()
})

// 支持外部动态切换显隐（弹层式用法）
watch(() => props.isVisible, (visible) => {
  if (visible)
    startCamera()
  else
    stopCamera()
})

/**
 * 从视频帧中持续检测二维码
 * 性能：降采样到 ~640px + willReadFrequently + 限频 ~10fps，避免整帧高分辨率解码卡顿
 */
async function startQrDetection() {
  const jsQR = (await import('jsqr')).default
  const canvas = document.createElement('canvas')
  const ctx = canvas.getContext('2d', { willReadFrequently: true })
  if (!ctx)
    return

  const MAX_DIMENSION = 640
  const DETECT_INTERVAL = 100
  let lastDetect = 0

  function tick(now: number) {
    const video = videoRef.value
    if (!video || video.readyState < video.HAVE_ENOUGH_DATA) {
      scanAnimationId = requestAnimationFrame(tick)
      return
    }

    if (now - lastDetect < DETECT_INTERVAL) {
      scanAnimationId = requestAnimationFrame(tick)
      return
    }
    lastDetect = now

    const scale = Math.min(1, MAX_DIMENSION / Math.max(video.videoWidth, video.videoHeight))
    canvas.width = Math.round(video.videoWidth * scale)
    canvas.height = Math.round(video.videoHeight * scale)
    ctx!.drawImage(video, 0, 0, canvas.width, canvas.height)
    const imageData = ctx!.getImageData(0, 0, canvas.width, canvas.height)
    const result = jsQR(imageData.data, imageData.width, imageData.height)

    if (result?.data) {
      handleDetected(result.data)
      return
    }

    scanAnimationId = requestAnimationFrame(tick)
  }

  scanAnimationId = requestAnimationFrame(tick)
}

function handleDetected(content: string) {
  if (resultEmitted)
    return
  resultEmitted = true
  Haptics.impact({ style: ImpactStyle.Medium }).catch(() => {})
  stopCamera()
  emit('result', content)
}

function stopQrDetection() {
  if (scanAnimationId !== null) {
    cancelAnimationFrame(scanAnimationId)
    scanAnimationId = null
  }
}

function handleCancel() {
  stopCamera()
  emit('cancel')
}

function handlePickAlbum() {
  emit('pickAlbum')
}

async function toggleFlashlight() {
  await toggleTorch()
}

// 组件卸载时清理
onUnmounted(() => {
  stopCamera()
})
</script>

<template>
  <div v-if="isVisible" class="scanner-overlay">
    <div class="scanner-container">
      <!-- Web 端视频预览 -->
      <video
        ref="videoRef"
        class="scanner-video"
        autoplay
        muted
        playsinline
      />

      <!-- 相机错误 / 不可用状态 -->
      <div v-if="status === 'error'" class="scan-error">
        <IonIcon :icon="videocamOffOutline" class="scan-error-icon" />
        <p class="scan-error-title">
          {{ errorMessage }}
        </p>
        <p class="scan-error-hint">
          {{ errorHint }}
        </p>
        <div class="scan-error-actions">
          <!-- 页面背景固定纯黑，颜色硬编码白色系（语义色 light 会随暗色模式反转成深灰导致不可读）；
               主操作 solid、次操作 outline，区分层级 -->
          <IonButton size="small" class="scan-btn-primary" @click="startCamera">
            <IonIcon slot="start" :icon="refreshOutline" />
            重试
          </IonButton>
          <IonButton fill="outline" size="small" class="scan-btn-secondary" @click="handlePickAlbum">
            <IonIcon slot="start" :icon="imagesOutline" />
            从相册选择
          </IonButton>
        </div>
      </div>

      <!-- 扫描框 -->
      <div v-else class="scan-area">
        <div class="scan-frame">
          <div class="corner corner-tl" />
          <div class="corner corner-tr" />
          <div class="corner corner-bl" />
          <div class="corner corner-br" />
          <div v-if="status === 'scanning'" class="scan-line" />
          <div v-if="status === 'starting'" class="scan-loading">
            <IonSpinner name="crescent" />
            <span>正在启动相机…</span>
          </div>
        </div>
      </div>

      <!-- 提示文字 -->
      <div v-if="status !== 'error'" class="scan-tips">
        <p>将二维码/条形码放入框内</p>
        <p>即可自动扫描</p>
      </div>
      <div v-else class="scan-tips" />

      <!-- 底部操作栏：错误态下相册入口已在错误面板中，避免重复展示 -->
      <div class="scan-actions">
        <div v-if="status !== 'error'" class="scan-action-item">
          <IonButton fill="clear" @click="handlePickAlbum">
            <IonIcon slot="icon-only" :icon="imagesOutline" />
          </IonButton>
          <span class="scan-action-label">相册</span>
        </div>
        <div v-if="showClose ?? true" class="scan-action-item">
          <IonButton fill="clear" @click="handleCancel">
            <IonIcon slot="icon-only" :icon="closeOutline" />
          </IonButton>
          <span class="scan-action-label">取消</span>
        </div>
        <div v-if="status === 'scanning' && (showFlashlight ?? true) && torchSupported" class="scan-action-item">
          <IonButton
            fill="clear"
            class="scan-torch-btn"
            :class="{ 'torch-on': torchOn }"
            :aria-label="torchOn ? '关闭手电筒' : '打开手电筒'"
            @click="toggleFlashlight"
          >
            <IonIcon slot="icon-only" :icon="flashlightOutline" />
          </IonButton>
          <span class="scan-action-label">{{ torchOn ? '关灯' : '照明' }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
.scanner-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: #000;
  z-index: 9999;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
}

.scanner-video {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
  z-index: 1;
}

.scanner-container {
  position: relative;
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: space-between;
  // 顶部预留 toolbar 高度 + 刘海安全区，避免内容顶到固定头部下方
  padding: calc(56px + var(--ion-safe-area-top, 0px)) 20px calc(24px + var(--ion-safe-area-bottom, 0px));
  z-index: 2;
  overflow: hidden;
}

// 取景 UI 必须显式抬升到 video（z-index: 1）之上，否则被相机画面覆盖
.scan-area,
.scan-tips,
.scan-actions,
.scan-error {
  position: relative;
  z-index: 2;
}

.scan-area {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
}

.scan-frame {
  position: relative;
  width: 260px;
  height: 260px;
  border-radius: 2px;
  // 镂空遮罩：扫描框外蒙上半透明黑，聚焦取景区域
  box-shadow: 0 0 0 200vmax rgba(0, 0, 0, 0.45);

  .corner {
    position: absolute;
    width: 22px;
    height: 22px;
    border-color: var(--ion-color-primary, #3880ff);
    border-style: solid;

    &.corner-tl {
      top: -2px;
      left: -2px;
      border-width: 4px 0 0 4px;
      border-top-left-radius: 6px;
    }

    &.corner-tr {
      top: -2px;
      right: -2px;
      border-width: 4px 4px 0 0;
      border-top-right-radius: 6px;
    }

    &.corner-bl {
      bottom: -2px;
      left: -2px;
      border-width: 0 0 4px 4px;
      border-bottom-left-radius: 6px;
    }

    &.corner-br {
      bottom: -2px;
      right: -2px;
      border-width: 0 4px 4px 0;
      border-bottom-right-radius: 6px;
    }
  }

  .scan-line {
    position: absolute;
    top: 0;
    left: 8px;
    right: 8px;
    height: 2px;
    background: linear-gradient(90deg, transparent, var(--ion-color-primary, #3880ff), transparent);
    box-shadow: 0 0 8px var(--ion-color-primary, #3880ff);
    animation: scan 2s ease-in-out infinite;
  }

  .scan-loading {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    color: rgba(255, 255, 255, 0.85);
    font-size: 13px;

    ion-spinner {
      color: #fff;
    }
  }
}

@keyframes scan {
  0% {
    top: 8px;
    opacity: 1;
  }
  50% {
    top: calc(100% - 10px);
    opacity: 0.6;
  }
  100% {
    top: 8px;
    opacity: 1;
  }
}

.scan-tips {
  margin-top: 32px;
  min-height: 44px;
  text-align: center;
  color: #fff;

  p {
    margin: 6px 0;
    font-size: 14px;
    opacity: 0.8;
  }
}

// ==================== 错误状态 ====================
.scan-error {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 0 32px;
  text-align: center;
  color: #fff;
}

.scan-error-icon {
  font-size: 56px;
  opacity: 0.6;
  margin-bottom: 8px;
}

.scan-error-title {
  margin: 0;
  font-size: 17px;
  font-weight: 600;
}

.scan-error-hint {
  margin: 0;
  font-size: 14px;
  opacity: 0.7;
  line-height: 1.5;
}

.scan-error-actions {
  display: flex;
  gap: 12px;
  margin-top: 16px;

  // 固定黑底上的按钮配色（不随系统深浅模式变化）
  .scan-btn-primary::part(native) {
    background: #fff;
    color: #111;
  }

  .scan-btn-secondary::part(native) {
    background: transparent;
    border-color: rgba(255, 255, 255, 0.55);
    color: #fff;
  }
}

// ==================== 底部操作栏 ====================
.scan-actions {
  display: flex;
  gap: 40px;
  align-items: flex-start;
  justify-content: center;
  padding: 16px 0 0;
}

.scan-action-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2px;

  // 所有操作按钮统一尺寸与图标大小，保持视觉一致
  ion-button {
    --padding-start: 14px;
    --padding-end: 14px;
    --border-radius: 50%;
    width: 52px;
    height: 52px;
    font-size: 24px;
    margin: 0;
  }

  // clear 按钮的 --background 会被 shadow 内部样式覆盖，用 ::part 直接指定；
  // 固定黑底，图标颜色硬编码白色（语义色会随暗色模式反转）
  ion-button::part(native) {
    background: rgba(255, 255, 255, 0.12);
    color: #fff;
  }

  .scan-torch-btn.torch-on::part(native) {
    color: var(--ion-color-warning, #ffc409);
  }
}

.scan-action-label {
  font-size: 12px;
  color: rgba(255, 255, 255, 0.75);
}
</style>
