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
  /**
   * 尺寸预设：
   * - grid：跟随全局响应式 CSS 变量（主屏幕网格，默认）
   * - list：48px，紧凑列表（工坊）
   * - md：64px，常规列表/卡片（排行榜、应用列表）
   * - xl：120px，详情页大图标
   */
  size?: 'grid' | 'list' | 'md' | 'xl'
}

const props = withDefaults(defineProps<Props>(), {
  icon: '',
  emoji: '📱',
  color: '',
  label: '',
  placeholder: false,
  styleMode: undefined,
  size: 'grid',
})

const settingsStore = useSettingsStore()

/** 仅当 icon 是图片路径（/ 或 http 开头）时才作为图片渲染，否则回退 emoji */
const imageLoadFailed = ref(false)
const isImageUrl = computed(() => props.icon.startsWith('/') || props.icon.startsWith('http'))
const isImageIcon = computed(() => isImageUrl.value && !imageLoadFailed.value)
const fallbackIcon = computed(() => isImageUrl.value ? props.emoji : props.icon || props.emoji)
const currentStyleMode = computed(() => props.styleMode ?? settingsStore.appIconStyle)

watch(() => props.icon, () => {
  imageLoadFailed.value = false
})

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
  <div class="app-icon-box-wrap" :class="size !== 'grid' ? `size-${size}` : undefined">
    <div
      class="app-icon-box"
      :class="iconBoxClasses"
      :style="iconBoxStyle"
    >
      <slot name="icon">
        <img
          v-if="isImageIcon"
          :src="icon"
          alt="应用图标"
          class="app-icon-img"
          @error="imageLoadFailed = true"
        >
        <span v-else class="app-emoji">{{ fallbackIcon }}</span>
      </slot>
      <slot name="badge" />
    </div>
    <div v-if="label" class="app-label" :title="label">
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

/* ==================== 尺寸预设 ==================== */
.app-icon-box-wrap.size-list {
  --app-icon-size: 48px;
  --app-icon-radius: 12px;
  --app-emoji-size: 24px;
}

.app-icon-box-wrap.size-md {
  --app-icon-size: 64px;
  --app-icon-radius: 14px;
  --app-emoji-size: 32px;
}

.app-icon-box-wrap.size-xl {
  --app-icon-size: 120px;
  --app-icon-radius: 27px;
  --app-emoji-size: 64px;
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

/* ==================== 渐变立体风格 ==================== */
.app-icon-box.style-gradient {
  background: linear-gradient(135deg, rgba(255, 255, 255, 0.14), rgba(0, 0, 0, 0.1)), var(--ylf-fill-secondary);
  box-shadow:
    0 2px 8px rgba(0, 0, 0, 0.1),
    inset 0 0 0 0.5px rgba(0, 0, 0, 0.08);
}

.app-icon-box.style-gradient.has-color {
  background: var(--app-icon-color);
  background: linear-gradient(
    135deg,
    color-mix(in srgb, var(--app-icon-color) 95%, white 5%) 0%,
    color-mix(in srgb, var(--app-icon-color) 70%, black 30%) 100%
  );
}

.app-icon-box.style-gradient.has-image {
  background: transparent;
}

.dark .app-icon-box.style-gradient {
  box-shadow:
    0 2px 8px rgba(0, 0, 0, 0.4),
    inset 0 0 0 0.5px rgba(255, 255, 255, 0.1);
}

/* ==================== 极简描边风格 ==================== */
.app-icon-box.style-minimal {
  background: var(--ion-background-color, #fff);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--ion-text-color, #000) 14%, transparent);
}

.app-icon-box.style-minimal.has-color {
  background: color-mix(in srgb, var(--app-icon-color) 10%, var(--ion-background-color, #fff));
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--app-icon-color) 45%, transparent);
}

.app-icon-box.style-minimal.has-image {
  background: transparent;
  box-shadow: inset 0 0 0 0.5px color-mix(in srgb, var(--ion-text-color, #000) 12%, transparent);
}

.app-icon-box.style-minimal .app-emoji {
  filter: none;
}

.dark .app-icon-box.style-minimal.has-color {
  background: color-mix(in srgb, var(--app-icon-color) 18%, var(--ion-background-color, #000));
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--app-icon-color) 55%, transparent);
}

/* ==================== 小尺寸阴影降级 ====================
   列表等小尺寸场景下淡化液态玻璃的厚重阴影并禁用模糊（视觉 + 性能），
   置于深色规则之后以保证两种模式下同时生效 */
.size-list .app-icon-box.style-liquid-glass,
.size-md .app-icon-box.style-liquid-glass {
  box-shadow:
    0 2px 6px rgba(0, 0, 0, 0.1),
    inset 0 1px 0 rgba(255, 255, 255, 0.35);
  backdrop-filter: none;
  -webkit-backdrop-filter: none;
}

.size-list .app-icon-box.style-liquid-glass::after,
.size-md .app-icon-box.style-liquid-glass::after {
  box-shadow:
    inset 0 0 0 0.5px rgba(255, 255, 255, 0.28),
    inset 0 1px 1px rgba(255, 255, 255, 0.32),
    inset 0 -4px 8px rgba(0, 0, 0, 0.06);
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
  /* 应用名称单行展示，超出省略号（与 iOS 启动台一致，不换行） */
  max-width: var(--app-icon-size);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  -webkit-user-select: none;
  user-select: none;
}

.is-placeholder + .app-label {
  color: var(--ion-color-medium);
}
</style>
