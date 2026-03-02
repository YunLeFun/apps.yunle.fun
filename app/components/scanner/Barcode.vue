<script setup lang="ts">
import { IonButton, IonIcon } from '@ionic/vue'
import { closeOutline, flashlightOutline } from 'ionicons/icons'

const props = defineProps<{
  isVisible: boolean
  showFlashlight?: boolean
}>()

const emit = defineEmits<{
  cancel: []
  result: [content: string]
}>()

const flashlightOn = ref(false)
const flashlightOffOutline = flashlightOutline
const videoRef = ref<HTMLVideoElement | null>(null)
const { startScan: startWebScan, stopScan: stopWebScan, isSupported } = useWebBarcodeScan()

// 监听可见性变化
watch(() => props.isVisible, async (visible) => {
  if (visible && videoRef.value && isSupported()) {
    try {
      await startWebScan(videoRef.value)
    }
    catch (error) {
      console.error('启动 Web 扫码失败:', error)
      emit('cancel')
    }
  }
  else if (!visible) {
    stopWebScan()
  }
})

function handleCancel() {
  stopWebScan()
  emit('cancel')
}

function toggleFlashlight() {
  flashlightOn.value = !flashlightOn.value
  // TODO: 实现手电筒切换
}

// 组件卸载时清理
onUnmounted(() => {
  stopWebScan()
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
        playsinline
      />

      <!-- 扫描框 -->
      <div class="scan-area">
        <div class="scan-frame">
          <div class="corner corner-tl" />
          <div class="corner corner-tr" />
          <div class="corner corner-bl" />
          <div class="corner corner-br" />
          <div class="scan-line" />
        </div>
      </div>

      <!-- 提示文字 -->
      <div class="scan-tips">
        <p>将二维码/条形码放入框内</p>
        <p>即可自动扫描</p>
      </div>

      <!-- 底部操作栏 -->
      <div class="scan-actions">
        <IonButton fill="clear" color="light" @click="handleCancel">
          <IonIcon slot="icon-only" :icon="closeOutline" />
        </IonButton>
        <IonButton v-if="showFlashlight" fill="clear" color="light" @click="toggleFlashlight">
          <IonIcon slot="icon-only" :icon="flashlightOn ? flashlightOutline : flashlightOffOutline" />
        </IonButton>
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
  padding: 60px 20px 40px;
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
  border: 2px solid rgba(255, 255, 255, 0.3);

  .corner {
    position: absolute;
    width: 20px;
    height: 20px;
    border-color: #fff;
    border-style: solid;

    &.corner-tl {
      top: -2px;
      left: -2px;
      border-width: 3px 0 0 3px;
    }

    &.corner-tr {
      top: -2px;
      right: -2px;
      border-width: 3px 3px 0 0;
    }

    &.corner-bl {
      bottom: -2px;
      left: -2px;
      border-width: 0 0 3px 3px;
    }

    &.corner-br {
      bottom: -2px;
      right: -2px;
      border-width: 0 3px 3px 0;
    }
  }

  .scan-line {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 2px;
    background: linear-gradient(90deg, transparent, #00ff00, transparent);
    animation: scan 2s linear infinite;
  }
}

@keyframes scan {
  0% {
    top: 0;
  }
  50% {
    top: 100%;
  }
  100% {
    top: 0;
  }
}

.scan-tips {
  margin-top: 40px;
  text-align: center;
  color: #fff;

  p {
    margin: 8px 0;
    font-size: 14px;
    opacity: 0.8;
  }
}

.scan-actions {
  display: flex;
  gap: 40px;
  align-items: center;
  justify-content: center;
  padding: 20px 0;

  ion-button {
    --padding-start: 16px;
    --padding-end: 16px;
    font-size: 28px;
  }
}
</style>
