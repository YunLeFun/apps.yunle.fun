<script setup lang="ts">
import { DEFAULT_EMOJI } from '~/types/app'

const props = defineProps<{
  emoji: string
  themeColor: string
  logo: string
}>()
</script>

<template>
  <div class="flex flex-col items-center pb-4 pt-2">
    <div
      class="app-icon-preview"
      :style="{ backgroundColor: props.themeColor }"
    >
      <img
        v-if="props.logo"
        :src="props.logo"
        alt="logo"
        class="h-full w-full rounded-[22px] object-cover"
      >
      <span v-else class="text-5xl leading-none">{{ props.emoji || DEFAULT_EMOJI }}</span>
    </div>
    <p class="mt-2 text-center text-xs text---ion-color-medium">
      应用图标预览
    </p>
  </div>
</template>

<style scoped>
.app-icon-preview {
  width: 96px;
  height: 96px;
  border-radius: 22px;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.12);
  position: relative;
  overflow: hidden;
}

.app-icon-preview::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: 22px;
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.08);
  pointer-events: none;
}
</style>
