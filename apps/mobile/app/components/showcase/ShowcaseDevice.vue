<script setup lang="ts">
/**
 * ShowcaseDevice - 展示页的 iPhone 外框
 *
 * 纯 CSS 绘制机身、灵动岛与屏幕圆角；多张截图叠放，按 active 交叉淡入。
 */

interface Shot {
  src: string
  alt: string
}

const props = withDefaults(defineProps<{
  shots: Shot[]
  active?: number
  /** 首屏截图立即加载，其余延迟 */
  eager?: boolean
}>(), {
  active: 0,
  eager: false,
})
</script>

<template>
  <div class="device" role="img" :aria-label="props.shots[props.active]?.alt">
    <div class="device-screen">
      <img
        v-for="(shot, index) in props.shots"
        :key="shot.src"
        class="device-shot"
        :class="{ 'is-active': index === props.active }"
        :src="shot.src"
        alt=""
        width="1206"
        height="2622"
        :loading="props.eager && index === 0 ? 'eager' : 'lazy'"
        decoding="async"
      >
      <span class="device-island" aria-hidden="true" />
    </div>
  </div>
</template>

<style scoped>
.device {
  --bezel: clamp(7px, 2.6%, 12px);
  position: relative;
  width: 100%;
  aspect-ratio: 1206 / 2622;
  padding: var(--bezel);
  border-radius: 15% / 7%;
  background: linear-gradient(145deg, #3a3a3c 0%, #1c1c1e 45%, #2c2c2e 100%);
  box-shadow:
    inset 0 0 0 1.5px rgb(255 255 255 / 0.14),
    inset 0 0 0 3px #0b0b0c,
    0 40px 80px -20px rgb(0 0 0 / 0.65),
    0 0 0 1px rgb(0 0 0 / 0.6);
}

.device-screen {
  position: relative;
  width: 100%;
  height: 100%;
  overflow: hidden;
  border-radius: 13% / 6%;
  background: #000;
}

.device-shot {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
  opacity: 0;
  transform: scale(1.04);
  filter: blur(6px);
  transition:
    opacity 0.6s cubic-bezier(0.22, 1, 0.36, 1),
    transform 0.8s cubic-bezier(0.22, 1, 0.36, 1),
    filter 0.6s cubic-bezier(0.22, 1, 0.36, 1);
}

.device-shot.is-active {
  opacity: 1;
  transform: none;
  filter: none;
}

.device-island {
  position: absolute;
  top: 1.6%;
  left: 50%;
  width: 31%;
  height: 3.4%;
  border-radius: 999px;
  background: #000;
  transform: translateX(-50%);
}

@media (prefers-reduced-motion: reduce) {
  .device-shot {
    transform: none;
    filter: none;
    transition: opacity 0.3s linear;
  }
}
</style>
