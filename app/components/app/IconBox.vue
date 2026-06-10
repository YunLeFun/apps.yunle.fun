<script setup lang="ts">
import type { AppIconStyle } from '~/stores/settings'

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
  /** 可选覆盖图标风格；默认读取外观设置 */
  styleMode?: AppIconStyle
}

const props = withDefaults(defineProps<Props>(), {
  icon: '',
  emoji: '📱',
  color: '',
  label: '',
  placeholder: false,
  styleMode: undefined,
})

const settingsStore = useSettingsStore()

/** 仅当 icon 是图片路径（/ 或 http 开头）时才作为图片渲染，否则回退 emoji */
const isImageIcon = computed(() => props.icon.startsWith('/') || props.icon.startsWith('http'))
const currentStyleMode = computed(() => props.styleMode ?? settingsStore.appIconStyle)

const iconBoxClasses = computed(() => ({
  'has-color': Boolean(props.color) && !props.placeholder,
  'has-image': isImageIcon.value,
  'is-placeholder': props.placeholder,
  [`style-${currentStyleMode.value}`]: true,
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
  background: var(--ylf-fill-secondary);
  transition:
    background 0.18s ease,
    box-shadow 0.18s ease,
    filter 0.18s ease;
  will-change: transform, box-shadow;
  transform: translateZ(0);
  backface-visibility: hidden;
  -webkit-backface-visibility: hidden;
}

.app-icon-box.style-liquid-glass {
  background:
    linear-gradient(160deg, rgba(255, 255, 255, 0.42), rgba(255, 255, 255, 0.14) 62%), var(--ylf-fill-secondary);
  box-shadow:
    0 10px 22px rgba(0, 0, 0, 0.12),
    0 2px 6px rgba(0, 0, 0, 0.08),
    inset 0 1px 0 rgba(255, 255, 255, 0.4);
  backdrop-filter: blur(18px) saturate(160%);
  -webkit-backdrop-filter: blur(18px) saturate(160%);
}

.app-icon-box.style-liquid-glass.has-color {
  background: var(--app-icon-color);
  background:
    radial-gradient(130% 90% at 25% -12%, rgba(255, 255, 255, 0.3), transparent 52%),
    linear-gradient(
      160deg,
      color-mix(in srgb, var(--app-icon-color) 88%, white 12%) 0%,
      var(--app-icon-color) 52%,
      color-mix(in srgb, var(--app-icon-color) 80%, black 20%) 100%
    );
}

.app-icon-box.style-liquid-glass::before {
  content: '';
  position: absolute;
  inset: 1px;
  z-index: 1;
  border-radius: calc(var(--app-icon-radius) - 1px);
  background:
    linear-gradient(168deg, rgba(255, 255, 255, 0.26) 0%, rgba(255, 255, 255, 0.05) 38%, transparent 58%),
    radial-gradient(90% 56% at 50% 118%, rgba(255, 255, 255, 0.14), transparent 64%);
  pointer-events: none;
}

.dark .app-icon-box.style-liquid-glass {
  background:
    linear-gradient(160deg, rgba(255, 255, 255, 0.12), rgba(255, 255, 255, 0.03) 62%), var(--ylf-fill-secondary);
  box-shadow:
    0 12px 24px rgba(0, 0, 0, 0.4),
    0 2px 8px rgba(0, 0, 0, 0.26),
    inset 0 1px 0 rgba(255, 255, 255, 0.16);
}

.dark .app-icon-box.style-liquid-glass.has-color {
  background: var(--app-icon-color);
  background:
    radial-gradient(130% 90% at 25% -12%, rgba(255, 255, 255, 0.18), transparent 52%),
    linear-gradient(
      160deg,
      color-mix(in srgb, var(--app-icon-color) 84%, white 16%) 0%,
      color-mix(in srgb, var(--app-icon-color) 92%, black 8%) 55%,
      color-mix(in srgb, var(--app-icon-color) 66%, black 34%) 100%
    );
}

.dark .app-icon-box.style-liquid-glass::before {
  background:
    linear-gradient(168deg, rgba(255, 255, 255, 0.14) 0%, rgba(255, 255, 255, 0.03) 38%, transparent 58%),
    radial-gradient(90% 56% at 50% 118%, rgba(255, 255, 255, 0.08), transparent 64%);
}

.app-icon-box.style-liquid-glass::after {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 3;
  border-radius: var(--app-icon-radius);
  box-shadow:
    inset 0 0 0 0.5px rgba(255, 255, 255, 0.28),
    inset 0 1.5px 1px rgba(255, 255, 255, 0.32),
    inset 0 -1px 1px rgba(255, 255, 255, 0.1),
    inset 0 -10px 16px rgba(0, 0, 0, 0.08);
  pointer-events: none;
}

.app-icon-box.style-flat-color {
  background: var(--ylf-fill-secondary);
  box-shadow:
    0 3px 10px rgba(0, 0, 0, 0.12),
    inset 0 0 0 0.5px rgba(0, 0, 0, 0.08);
}

.app-icon-box.style-flat-color.has-color {
  background: var(--app-icon-color);
}

.app-icon-box.style-flat-color.has-image {
  background: transparent;
}

.dark .app-icon-box.style-flat-color {
  box-shadow:
    0 3px 10px rgba(0, 0, 0, 0.35),
    inset 0 0 0 0.5px rgba(255, 255, 255, 0.1);
}

.dark .app-icon-box.style-flat-color.has-color {
  background: color-mix(in srgb, var(--app-icon-color) 88%, black 12%);
}

/* 占位模式 */
.app-icon-box.is-placeholder {
  background: var(--ylf-fill-secondary);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.12),
    inset 0 0 0 0.5px rgba(255, 255, 255, 0.1);
}

.app-icon-box.style-liquid-glass.is-placeholder {
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
  filter: drop-shadow(0 2px 4px rgba(0, 0, 0, 0.2));
  -webkit-user-select: none;
  user-select: none;
  -webkit-touch-callout: none;
}

.app-icon-box.style-flat-color .app-emoji {
  filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.18));
}

.app-icon-box.style-liquid-glass.has-image::before,
.app-icon-box.style-liquid-glass.has-image::after {
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
