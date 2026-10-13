<script setup lang="ts">
import type { CatalogEntry } from '../../shared/desktop'
import { computed, shallowRef, watch } from 'vue'
import { appIconUrl } from '../../shared/app-icons'
import { appIconColor } from '../utils/app-presentation'

const props = defineProps<{ app: Readonly<CatalogEntry> }>()
const imageElement = shallowRef<HTMLImageElement | null>(null)
const source = computed(() => appIconUrl(props.app.slug))
const failedSource = shallowRef('')
const showImage = computed(() => Boolean(source.value) && failedSource.value !== source.value)
const iconStyle = computed(() => showImage.value ? undefined : { backgroundColor: appIconColor(props.app.slug) })
watch(source, () => {
  failedSource.value = ''
}, { flush: 'sync' })

function onImageError(event: Event) {
  const image = imageElement.value
  if (image && event.currentTarget === image && event.target === image && image.getAttribute('src') === source.value)
    failedSource.value = source.value
}
</script>

<template>
  <span class="app-icon" :style="iconStyle" aria-hidden="true">
    <img
      v-if="showImage"
      :key="source"
      ref="imageElement"
      :src="source"
      alt=""
      aria-hidden="true"
      referrerpolicy="no-referrer"
      draggable="false"
      decoding="async"
      loading="lazy"
      width="56"
      height="56"
      @error="onImageError"
    >
    <template v-else>
      {{ app.emoji }}
    </template>
  </span>
</template>

<style scoped>
.app-icon {
  display: inline-flex;
  width: 56px;
  height: 56px;
  flex: 0 0 56px;
  align-items: center;
  justify-content: center;
  border-radius: 12px;
  overflow: hidden;
  font-size: 31px;
  line-height: 1;
}

.app-icon img {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}
</style>
