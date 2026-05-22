<script setup lang="ts">
/**
 * AppIconBox - 应用图标盒子（纯展示）
 *
 * @description
 * 纯展示组件，渲染 icon-box + emoji/图片 + label。
 * 被 AppIcon（带交互）和 HomeScreenGrid 占位复用。
 */

interface Props {
  /** 图标图片 URL */
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

withDefaults(defineProps<Props>(), {
  icon: '',
  emoji: '📱',
  color: '',
  label: '',
  placeholder: false,
})
</script>

<template>
  <div class="app-icon-box-wrap">
    <div
      class="app-icon-box"
      :class="{ 'is-placeholder': placeholder }"
      :style="color ? { backgroundColor: color } : undefined"
    >
      <slot name="icon">
        <img v-if="icon" :src="icon" alt="应用图标" class="app-icon-img">
        <span v-else class="app-emoji">{{ emoji }}</span>
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
  box-shadow: 0 3px 10px rgba(0, 0, 0, 0.12);
  will-change: transform, box-shadow;
  transform: translateZ(0);
  backface-visibility: hidden;
  -webkit-backface-visibility: hidden;
}

.dark .app-icon-box {
  box-shadow: 0 3px 10px rgba(0, 0, 0, 0.35);
}

.app-icon-box::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: var(--app-icon-radius);
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.08);
  pointer-events: none;
}

/* 占位模式 */
.app-icon-box.is-placeholder {
  background: var(--ylf-fill-secondary);
  box-shadow: none;
}

.app-icon-img {
  width: 100%;
  height: 100%;
  border-radius: var(--app-icon-radius);
  object-fit: cover;
}

.app-emoji {
  font-size: var(--app-emoji-size);
  line-height: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  -webkit-user-select: none;
  user-select: none;
  -webkit-touch-callout: none;
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
