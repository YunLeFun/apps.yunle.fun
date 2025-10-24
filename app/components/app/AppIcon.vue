<script setup lang="ts">
/**
 * AppIcon - 应用图标组件
 *
 * @description
 * 单个应用图标的展示组件，支持点击和长按交互、徽章显示、交互反馈
 *
 * @example
 * ```vue
 * <AppIcon
 *   :app="app"
 *   :show-badge="true"
 *   :badge-count="5"
 *   :interaction-class="'is-pressed'"
 *   :interaction-style="{ transform: 'scale(0.95)' }"
 *   @pointerdown="handlePointerDown"
 *   @pointerup="handlePointerUp"
 * />
 * ```
 */

import type { YlfAppInfo } from '~~/packages/types'

interface Props {
  /** 应用信息 */
  app: YlfAppInfo
  /** 是否显示徽章 */
  showBadge?: boolean
  /** 徽章数字（如果不提供则随机生成） */
  badgeCount?: number | null
  /** 交互状态类名（支持字符串或对象） */
  interactionClass?: string | Record<string, boolean>
  /** 交互样式 */
  interactionStyle?: Record<string, any>
  /** 性能等级 */
  performanceLevel?: 'high' | 'medium' | 'low'
}

const props = withDefaults(defineProps<Props>(), {
  showBadge: true,
  badgeCount: null,
  interactionClass: () => ({}),
  interactionStyle: () => ({}),
  performanceLevel: 'high',
})

/**
 * 获取徽章数字
 * 如果提供了 badgeCount 则使用，否则随机生成
 */
const displayBadge = computed(() => {
  if (!props.showBadge)
    return null
  if (props.badgeCount !== null)
    return props.badgeCount
  // 随机生成徽章（30% 概率显示）
  return Math.random() > 0.7 ? Math.floor(Math.random() * 99) + 1 : null
})
</script>

<template>
  <div
    class="app-icon-item"
    :class="interactionClass"
    :data-performance="performanceLevel"
  >
    <div
      class="app-icon-box"
      :style="{
        backgroundColor: app.color,
        ...interactionStyle,
      }"
    >
      <div class="app-emoji">
        {{ app.icon }}
      </div>
      <!-- 红点通知 -->
      <div
        v-if="displayBadge"
        class="badge"
      >
        {{ displayBadge }}
      </div>
    </div>
    <div class="app-label">
      {{ app.name }}
    </div>
  </div>
</template>

<style scoped>
/* ==================== 应用图标项 ==================== */
.app-icon-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  user-select: none;
  -webkit-user-select: none;
  -webkit-tap-highlight-color: transparent;
  position: relative;
  touch-action: manipulation;
  /* 移除默认 transition，由 JS 控制 */
}

/* 按下状态 - 快速响应 */
.app-icon-item.is-pressed .app-icon-box {
  /* 由 JS 动态设置 transform */
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
}

.dark .app-icon-item.is-pressed .app-icon-box {
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.4);
}

/* 长按状态 - 更强的视觉反馈 */
.app-icon-item.is-long-pressing .app-icon-box {
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.25);
  animation: pulse 0.5s ease-in-out;
}

.dark .app-icon-item.is-long-pressing .app-icon-box {
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.5);
}

/* 脉冲动画 */
@keyframes pulse {
  0%,
  100% {
    filter: brightness(1);
  }
  50% {
    filter: brightness(1.1);
  }
}

/* 禁用动画模式 */
.app-icon-item.no-animation .app-icon-box {
  transition: none !important;
  animation: none !important;
}

.app-icon-box {
  width: 64px;
  height: 64px;
  border-radius: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  position: relative;
  box-shadow: 0 3px 10px rgba(0, 0, 0, 0.12);
  /* 使用 will-change 优化性能 */
  will-change: transform, box-shadow;
  /* 启用硬件加速 */
  transform: translateZ(0);
  backface-visibility: hidden;
  -webkit-backface-visibility: hidden;
}

.dark .app-icon-box {
  box-shadow: 0 3px 10px rgba(0, 0, 0, 0.35);
}

/* 性能优化：低性能设备使用简化样式 */
.app-icon-item[data-performance='low'] .app-icon-box {
  will-change: auto;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.1);
}

.app-icon-item[data-performance='low'].is-pressed .app-icon-box {
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.08);
}

.app-icon-box::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: 16px;
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.08);
  pointer-events: none;
}

.app-emoji {
  font-size: 32px;
  line-height: 1;
  display: flex;
  align-items: center;
  justify-content: center;
}

/* 红点通知 */
.badge {
  position: absolute;
  top: -4px;
  right: -4px;
  background: #ff3b30;
  color: white;
  border-radius: 50%;
  width: 24px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 11px;
  font-weight: 700;
  border: 2px solid white;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
}

.dark .badge {
  border-color: #1c1c1e;
}

.app-label {
  font-size: 12px;
  font-weight: 500;
  color: #000;
  text-align: center;
  line-height: 1.3;
  max-width: 64px;
  overflow: hidden;
  text-overflow: ellipsis;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  white-space: normal;
}

.dark .app-label {
  color: #fff;
}

/* ==================== 响应式设计 ==================== */
@media (max-width: 480px) {
  .app-icon-box {
    width: 60px;
    height: 60px;
    border-radius: 14px;
  }

  .app-emoji {
    font-size: 28px;
  }

  .app-label {
    font-size: 11px;
    max-width: 60px;
  }
}

@media (min-width: 768px) {
  .app-icon-box {
    width: 72px;
    height: 72px;
    border-radius: 18px;
  }

  .app-emoji {
    font-size: 36px;
  }

  .app-label {
    font-size: 13px;
    max-width: 72px;
  }
}

@media (min-width: 1024px) {
  .app-icon-box {
    width: 80px;
    height: 80px;
    border-radius: 20px;
  }

  .app-emoji {
    font-size: 40px;
  }

  .app-label {
    font-size: 14px;
    max-width: 80px;
  }
}

/* ==================== 无障碍优化 ==================== */
@media (prefers-reduced-motion: reduce) {
  .app-icon-item {
    transition: none;
    animation: none;
  }
}
</style>
