<script setup lang="ts">
import type { AppIconAssetsDraft } from '~/utils/appIconAssets'
import { DEFAULT_EMOJI } from '~/types/app'
import { compactAppIconAssets } from '~/utils/appIconAssets'

const props = defineProps<{
  emoji: string
  themeColor: string
  logo: string
  iconAssets: AppIconAssetsDraft
}>()

const compactAssets = computed(() => compactAppIconAssets(props.iconAssets))
</script>

<template>
  <section class="icon-preview" aria-label="应用图标亮暗模式预览">
    <div class="preview-item preview-light">
      <AppIconBox
        class="app-icon-preview"
        :icon="props.logo"
        :icon-assets="compactAssets"
        :emoji="props.emoji || DEFAULT_EMOJI"
        :color="props.themeColor"
        appearance="light"
      />
      <span>浅色</span>
    </div>
    <div class="preview-item preview-dark">
      <AppIconBox
        class="app-icon-preview"
        :icon="props.logo"
        :icon-assets="compactAssets"
        :emoji="props.emoji || DEFAULT_EMOJI"
        :color="props.themeColor"
        appearance="dark"
      />
      <span>深色</span>
    </div>
  </section>
</template>

<style scoped>
.icon-preview {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 132px));
  justify-content: center;
  gap: 12px;
  padding: 8px 0 18px;
}

.preview-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  padding: 18px 12px 10px;
  border: 1px solid rgba(120, 120, 128, 0.18);
  border-radius: 18px;
  font-size: 12px;
}

.preview-light {
  color: #3a3a3c;
  background: #f2f2f7;
}

.preview-dark {
  color: #e5e5ea;
  background: #1c1c1e;
}

.app-icon-preview {
  --app-icon-size: 88px;
  --app-icon-radius: 19px;
  --app-emoji-size: 44px;
}
</style>
