<script setup lang="ts">
/**
 * AppIconBox - 应用图标盒子（纯展示）
 *
 * @description
 * 纯展示组件，渲染 icon-box + emoji/图片 + label。
 * 被 AppIcon（带交互）和 HomeScreenGrid 占位复用。
 */

interface Props {
  /** 图标图片 URL（路径或 http 开头）；非图片值会被忽略，回退到 emoji */
  icon?: string
  /** Emoji 字符 */
  emoji?: string
  /** 背景色 */
  color?: string
  /** 标签文字 */
  label?: string
  /** 是否为占位模式（灰色背景） */
  placeholder?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  icon: '',
  emoji: '📱',
  color: '',
  label: '',
  placeholder: false,
})

/** 仅当 icon 是图片路径（/ 或 http 开头）时才作为图片渲染，否则回退 emoji */
const isImageIcon = computed(() => props.icon.startsWith('/') || props.icon.startsWith('http'))

const iconBoxClasses = computed(() => ({
  'has-color': Boolean(props.color) && !props.placeholder,
  'has-image': isImageIcon.value,
  'is-placeholder': props.placeholder,
}))

const iconBoxStyle = computed(() => props.color
  ? { '--app-icon-color': props.color }
  : undefined)
</script>

<template>
  <div class="app-icon-box-wrap">
    <div
      class="app-icon-box"
      :class="iconBoxClasses"
      :style="iconBoxStyle"
    >
      <slot name="icon">
        <img v-if="isImageIcon" :src="icon" alt="应用图标" class="app-icon-img">
        <span v-else class="app-emoji">{{ icon || emoji }}</span>
      </slot>
      <slot name="badge" />
    </div>
    <div v-if="label" class="app-label">
      {{ label }}
    </div>
    <slot name="label" />
  </div>
</template>

<style scoped>
.app-icon-box-wrap {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  -webkit-user-select: none;
  user-select: none;
  -webkit-touch-callout: none;
}

.app-icon-box {
  width: var(--app-icon-size);
  height: var(--app-icon-size);
  border-radius: var(--app-icon-radius);
  display: flex;
  align-items: center;
  justify-content: center;
  position: relative;
  overflow: hidden;
  isolation: isolate;
  background: linear-gradient(145deg, rgba(255, 255, 255, 0.72), rgba(255, 255, 255, 0.28)), var(--ylf-fill-secondary);
  box-shadow:
    0 14px 24px rgba(0, 0, 0, 0.14),
    0 3px 8px rgba(0, 0, 0, 0.1),
    inset 0 1px 0 rgba(255, 255, 255, 0.48);
  backdrop-filter: blur(18px) saturate(170%);
  -webkit-backdrop-filter: blur(18px) saturate(170%);
  will-change: transform, box-shadow;
  transform: translateZ(0);
  backface-visibility: hidden;
  -webkit-backface-visibility: hidden;
}

.app-icon-box.has-color {
  background: var(--app-icon-color);
  background:
    radial-gradient(circle at 28% 18%, rgba(255, 255, 255, 0.52), transparent 34%),
    linear-gradient(
      145deg,
      color-mix(in srgb, var(--app-icon-color) 74%, white 26%) 0%,
      color-mix(in srgb, var(--app-icon-color) 88%, black 12%) 58%,
      color-mix(in srgb, var(--app-icon-color) 72%, black 28%) 100%
    );
}

.app-icon-box::before {
  content: '';
  position: absolute;
  inset: 1px;
  z-index: 1;
  border-radius: calc(var(--app-icon-radius) - 1px);
  background:
    linear-gradient(145deg, rgba(255, 255, 255, 0.62), transparent 42%),
    linear-gradient(335deg, rgba(255, 255, 255, 0.18), transparent 45%);
  opacity: 0.78;
  pointer-events: none;
  mix-blend-mode: screen;
}

.dark .app-icon-box {
  background: linear-gradient(145deg, rgba(255, 255, 255, 0.16), rgba(255, 255, 255, 0.05)), var(--ylf-fill-secondary);
  box-shadow:
    0 16px 28px rgba(0, 0, 0, 0.42),
    0 3px 9px rgba(0, 0, 0, 0.28),
    inset 0 1px 0 rgba(255, 255, 255, 0.18);
}

.dark .app-icon-box.has-color {
  background: var(--app-icon-color);
  background:
    radial-gradient(circle at 30% 18%, rgba(255, 255, 255, 0.36), transparent 34%),
    linear-gradient(
      145deg,
      color-mix(in srgb, var(--app-icon-color) 68%, white 32%) 0%,
      color-mix(in srgb, var(--app-icon-color) 78%, black 22%) 62%,
      color-mix(in srgb, var(--app-icon-color) 58%, black 42%) 100%
    );
}

.app-icon-box::after {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 3;
  border-radius: var(--app-icon-radius);
  box-shadow:
    inset 0 0 0 0.5px rgba(255, 255, 255, 0.34),
    inset 0 -18px 26px rgba(0, 0, 0, 0.12),
    inset 0 0 24px rgba(255, 255, 255, 0.08);
  pointer-events: none;
}

/* 占位模式 */
.app-icon-box.is-placeholder {
  background: linear-gradient(145deg, rgba(255, 255, 255, 0.18), rgba(255, 255, 255, 0.04)), var(--ylf-fill-secondary);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.12),
    inset 0 0 0 0.5px rgba(255, 255, 255, 0.1);
}

.app-icon-img {
  position: relative;
  z-index: 2;
  width: 100%;
  height: 100%;
  border-radius: var(--app-icon-radius);
  object-fit: cover;
}

.app-emoji {
  position: relative;
  z-index: 2;
  font-size: var(--app-emoji-size);
  line-height: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  filter: drop-shadow(0 1px 0 rgba(255, 255, 255, 0.18)) drop-shadow(0 5px 8px rgba(0, 0, 0, 0.24));
  -webkit-user-select: none;
  user-select: none;
  -webkit-touch-callout: none;
}

.app-icon-box.has-image::before,
.app-icon-box.has-image::after {
  opacity: 0.32;
}

.app-icon-box :slotted(.badge) {
  z-index: 4;
}

.app-label {
  font-size: var(--app-label-size);
  font-weight: 500;
  color: var(--ion-text-color);
  text-align: center;
  line-height: 1.3;
  max-width: var(--app-icon-size);
  overflow: hidden;
  text-overflow: ellipsis;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  white-space: normal;
  -webkit-user-select: none;
  user-select: none;
}

.is-placeholder + .app-label {
  color: var(--ion-color-medium);
  white-space: nowrap;
  display: block;
  -webkit-line-clamp: unset;
  line-clamp: unset;
}
</style>
