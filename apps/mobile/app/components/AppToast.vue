<script setup lang="ts">
import {
  alertCircle,
  checkmarkCircle,
  closeCircle,
  informationCircle,
} from 'ionicons/icons'
import { kButton, kToast } from 'konsta/vue'

const { opened, message, type, copyText, close } = useToast()
const copyState = ref<'idle' | 'copied' | 'failed'>('idle')

watch([opened, message], () => {
  copyState.value = 'idle'
})

async function copyError() {
  if (!copyText.value)
    return
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(copyText.value)
    }
    else {
      const textarea = document.createElement('textarea')
      textarea.value = copyText.value
      textarea.style.position = 'fixed'
      textarea.style.opacity = '0'
      document.body.appendChild(textarea)
      textarea.select()
      let copied = false
      try {
        copied = document.execCommand('copy')
      }
      finally {
        textarea.remove()
      }
      if (!copied)
        throw new Error('copy failed')
    }
    copyState.value = 'copied'
  }
  catch {
    copyState.value = 'failed'
  }
}

const copyLabel = computed(() => {
  if (copyState.value === 'copied')
    return '已复制'
  if (copyState.value === 'failed')
    return '复制失败'
  return '复制'
})

const icon = computed(() => {
  switch (type.value) {
    case 'success': return checkmarkCircle
    case 'error': return closeCircle
    case 'warning': return alertCircle
    case 'info': return informationCircle
    default: return informationCircle
  }
})

const iconColor = computed(() => {
  switch (type.value) {
    case 'success': return 'text-green-500'
    case 'error': return 'text-red-500'
    case 'warning': return 'text-orange-500'
    case 'info': return 'text-blue-500'
    default: return 'text-blue-500'
  }
})
</script>

<template>
  <k-toast
    class="app-toast app-toast--top"
    position="center"
    :opened="opened"
    role="status"
    aria-live="polite"
  >
    <div class="flex items-center gap-2 shrink">
      <IonIcon :icon="icon" :class="iconColor" class="text-lg shrink-0" />
      <span class="text-sm">{{ message }}</span>
    </div>
    <template #button>
      <div class="flex items-center">
        <k-button
          v-if="type === 'error' && copyText"
          clear
          rounded
          inline
          class="text-xs!"
          aria-label="复制错误信息"
          @click="copyError"
        >
          {{ copyLabel }}
        </k-button>
        <k-button clear rounded inline class="text-xs!" @click="close">
          关闭
        </k-button>
      </div>
    </template>
  </k-toast>
</template>

<style scoped>
.app-toast--top {
  top: calc(var(--ion-safe-area-top, env(safe-area-inset-top, 0px)) + 12px) !important;
  bottom: auto !important;
}

.app-toast--top.translate-y-full {
  --tw-translate-y: -100% !important;
  translate: 0 -100% !important;
}
</style>
