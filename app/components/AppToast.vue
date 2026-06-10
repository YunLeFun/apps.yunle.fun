<script setup lang="ts">
import {
  alertCircle,
  checkmarkCircle,
  closeCircle,
  informationCircle,
} from 'ionicons/icons'
import { kButton, kToast } from 'konsta/vue'

const { opened, message, type, close } = useToast()

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
      <k-button clear rounded inline class="text-xs!" @click="close">
        关闭
      </k-button>
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
