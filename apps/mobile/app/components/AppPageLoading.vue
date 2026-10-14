<script setup lang="ts">
import { IonSpinner } from '@ionic/vue'

withDefaults(defineProps<{
  label?: string
}>(), {
  label: '页面加载中',
})
</script>

<template>
  <div
    class="app-page-loading"
    role="status"
    aria-live="polite"
    :aria-label="label"
  >
    <IonSpinner name="crescent" aria-hidden="true" />
  </div>
</template>

<style scoped>
.app-page-loading {
  box-sizing: border-box;
  inline-size: 100%;
  min-block-size: 60vh;
  padding: 72px 24px 32px;
  display: grid;
  place-items: center;
  color: var(--ion-color-medium);
}
</style>
