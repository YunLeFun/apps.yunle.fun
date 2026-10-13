<script setup lang="ts">
import type { CatalogEntry } from '../../shared/desktop'
import { appIconColor } from '../utils/app-presentation'

const props = defineProps<{ app: Readonly<CatalogEntry> }>()
const iconStyle = computed(() => ({ backgroundColor: appIconColor(props.app.slug) }))
</script>

<template>
  <span class="app-icon" :style="iconStyle" aria-hidden="true">
    {{ app.emoji }}
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
  border: 1px solid rgb(255 255 255 / 12%);
  box-shadow: 0 1px 2px rgb(0 0 0 / 8%);
  font-size: 31px;
  line-height: 1;
}
</style>
