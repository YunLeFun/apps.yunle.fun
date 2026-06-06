<script setup lang="ts">
import type { YlfAppInfo } from '~~/packages/types'
import { vOnLongPress } from '@vueuse/components'

const props = defineProps<{
  app: YlfAppInfo
}>()

const emit = defineEmits<{
  longPress: [app: YlfAppInfo, event: PointerEvent | TouchEvent]
}>()

const { openApp } = useOpenApp()

/**
 * 处理点击（统一走 useOpenApp，含会员 / 云币门控）
 */
function handleClick() {
  openApp(props.app)
}

const isLongPressed = ref(false)

function onMouseUp(duration: number, distance: number, isLongPress: boolean) {
  if (!isLongPress) {
    handleClick()
  }
  isLongPressed.value = isLongPress
}

/**
 * 长按回调
 */
function onLongPressCallback(event: PointerEvent | TouchEvent) {
  emit('longPress', props.app, event)
}
</script>

<template>
  <AppIcon
    v-on-long-press.prevent="[onLongPressCallback, { delay: 600, onMouseUp }]"
    :app="app"
  />
</template>
