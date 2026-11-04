<script setup lang="ts">
import { Capacitor } from '@capacitor/core'

const props = defineProps<{ appKey: string, websiteUrl?: string }>()
const emit = defineEmits<{ online: [] }>()
const isBrowser = shallowRef(false)
onMounted(() => {
  isBrowser.value = !Capacitor.isNativePlatform()
})

// A tap is intentional; never probe installation or redirect on a timer.
const nativeUrl = computed(() => /^[\w-]{1,256}$/.test(props.appKey)
  ? `yunlefun://app/${encodeURIComponent(props.appKey)}`
  : undefined)
const hasWebsite = computed(() => {
  try {
    const url = new URL(props.websiteUrl || '')
    return ['https:', 'http:'].includes(url.protocol) && !url.username && !url.password
  }
  catch { return false }
})
</script>

<template>
  <section v-if="isBrowser" class="share-landing" aria-label="选择体验方式">
    <div class="share-landing-copy">
      <strong>在你喜欢的地方，打开快乐。</strong>
      <span>已安装云乐坊？可在 App 中查看。也可以直接体验在线版。</span>
    </div>
    <div class="share-landing-actions">
      <a v-if="nativeUrl" :href="nativeUrl" class="share-landing-native">在云乐坊打开</a>
      <button v-if="hasWebsite" type="button" class="share-landing-online" @click="emit('online')">
        体验在线版 ↗
      </button>
    </div>
  </section>
</template>

<style scoped>
.share-landing {
  --share-ink: var(--ion-text-color, #111827);
  --share-paper: var(--ion-background-color, #fff);
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin: 24px 0;
  padding: 20px;
  border: 1px solid color-mix(in srgb, var(--share-ink) 15%, var(--share-paper));
  border-radius: 24px;
  background: color-mix(in srgb, var(--share-paper) 94%, var(--share-ink));
  color: var(--share-ink);
}
.share-landing-copy {
  display: grid;
  gap: 6px;
}
.share-landing-copy strong {
  font-size: 15px;
}
.share-landing-copy span {
  font-size: 13px;
  color: var(--ion-color-medium);
}
.share-landing-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  align-items: center;
}
.share-landing-native,
.share-landing-online {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-height: 44px;
  padding: 10px 18px;
  border-radius: 999px;
  font: inherit;
  font-size: 14px;
  font-weight: 600;
  text-decoration: none;
  cursor: pointer;
}
.share-landing-native {
  background: var(--share-ink);
  color: var(--share-paper);
}
.share-landing-online {
  background: transparent;
  color: var(--share-ink);
  border: 1px solid color-mix(in srgb, var(--share-ink) 25%, var(--share-paper));
}
</style>
