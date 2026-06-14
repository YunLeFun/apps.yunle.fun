<script setup lang="ts">
import { IonIcon } from '@ionic/vue'
import { checkmarkCircle } from 'ionicons/icons'

defineProps<{
  /** 图标尺寸（相对字号倍数），默认随文字 */
  size?: string
}>()
</script>

<template>
  <IonIcon
    :icon="checkmarkCircle"
    class="verified-badge"
    :style="size ? { fontSize: size } : undefined"
    role="img"
    aria-label="官方认证"
    title="官方认证"
  />
</template>

<style scoped>
.verified-badge {
  color: var(--ion-color-primary);
  font-size: 0.8em;
  vertical-align: -0.06em;
  flex-shrink: 0;
}
</style>
