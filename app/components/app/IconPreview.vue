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
    <AppIconBox
      class="app-icon-preview"
      :icon="props.logo"
      :emoji="props.emoji || DEFAULT_EMOJI"
      :color="props.themeColor"
    />
    <p class="mt-2 text-center text-xs text---ion-color-medium">
      应用图标预览
    </p>
  </div>
</template>

<style scoped>
.app-icon-preview {
  --app-icon-size: 96px;
  --app-icon-radius: 22px;
  --app-emoji-size: 48px;
}
</style>
