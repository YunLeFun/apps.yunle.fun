<script setup lang="ts">
import { describeRemoteResource, reportClientEvent } from '~/utils/client-telemetry'

defineOptions({
  inheritAttrs: false,
})

const props = withDefaults(defineProps<{
  src?: string | null
  alt?: string
  telemetrySurface?: string
}>(), {
  alt: '',
  telemetrySurface: 'user.avatar',
})

const emit = defineEmits<{
  error: [event: Event]
  load: [event: Event]
}>()

const failed = ref(false)
const { resolvedSrc, resolutionError } = useAvatarUrl(() => props.src)

watch(() => props.src, () => {
  failed.value = false
})

watch(resolvedSrc, () => {
  failed.value = false
})

watch(resolutionError, (error) => {
  if (!error)
    return

  reportClientEvent('ui.avatar.signing_failed', {
    surface: props.telemetrySurface,
    stage: 'sign',
    ...describeRemoteResource(props.src),
    error: error.message,
  })
})

function handleLoad(event: Event) {
  failed.value = false
  emit('load', event)
}

function handleError(event: Event) {
  failed.value = true
  reportClientEvent('ui.avatar.load_failed', {
    surface: props.telemetrySurface,
    stage: 'load',
    ...describeRemoteResource(resolvedSrc.value || props.src),
  })
  emit('error', event)
}
</script>

<template>
  <img
    v-if="resolvedSrc && !failed"
    v-bind="$attrs"
    :src="resolvedSrc"
    :alt="alt"
    @error="handleError"
    @load="handleLoad"
  >
  <slot
    v-else
    name="fallback"
    :failed="failed"
    :loading="!resolvedSrc && !!src"
  />
</template>
