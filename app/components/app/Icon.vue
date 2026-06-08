<script setup lang="ts">
import type { YlfAppInfo } from '@yunlefun/types'

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

interface Props {
  /** 应用信息 */
  app: YlfAppInfo
  /** 是否显示徽章 */
  showBadge?: boolean
  /** 徽章数字（如果不提供则随机生成） */
  badgeCount?: number | null
  /** 交互样式 */
  interactionStyle?: Record<string, any>
  /** 性能等级 */
  performanceLevel?: 'high' | 'medium' | 'low'

  longPressed?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  showBadge: true,
  badgeCount: null,
  interactionClass: () => ({}),
  interactionStyle: () => ({}),
  performanceLevel: 'high',
  longPressed: false,
})

/**
 * 获取徽章数字
 */
const displayBadge = computed(() => {
  if (!props.showBadge)
    return null
  return props.badgeCount
})

/**
 * 付费 / 会员门控角标：会员专属显示锁，按次付费显示云币标记
 */
const gateMarker = computed<{ text: string, cls: string } | null>(() => {
  if (props.app.requiresMembership)
    return { text: '会员', cls: 'gate-member' }
  if ((props.app.coinCost ?? 0) > 0)
    return { text: `${props.app.coinCost}币`, cls: 'gate-coin' }
  return null
})

/**
 * 是否按下
 */
const isPressed = ref(false)
/**
 * 处理指针按下事件
 */
function handlePointerDown() {
  isPressed.value = true
}
/**
 * 清除 pressed 状态
 */
function clearPressed() {
  isPressed.value = false
}

const appIconClasses = computed(() => {
  return {
    'is-pressed': isPressed.value,
    'is-long-pressed': props.longPressed,
  }
})
</script>

<template>
  <div
    class="app-icon-item"
    :class="appIconClasses"
    :data-performance="performanceLevel"
    @pointerdown="handlePointerDown"
    @pointercancel="clearPressed"
    @pointerup="clearPressed"
    @pointerleave="clearPressed"
    @pointerout="clearPressed"
  >
    <AppIconBox
      :icon="app.logo"
      :emoji="app.emoji"
      :color="app.themeColor"
      :label="app.name"
      :style="interactionStyle"
    >
      <template v-if="displayBadge" #badge>
        <div class="badge">
          {{ displayBadge }}
        </div>
      </template>
    </AppIconBox>

    <!-- 付费 / 会员门控角标 -->
    <span v-if="gateMarker" class="gate-marker" :class="gateMarker.cls">
      {{ gateMarker.text }}
    </span>
  </div>
</template>

<style scoped>
/* ==================== 应用图标项 ==================== */
.app-icon-item {
  cursor: pointer;
  user-select: none;
  -webkit-user-select: none;
  -webkit-tap-highlight-color: transparent;
  position: relative;
  touch-action: manipulation;
  transition: transform 0.15s ease;

  &.is-pressed {
    transform: scale(0.95);

    :deep(.app-icon-box) {
      box-shadow: inset 0 0 64px rgba(0, 0, 0, 0.5);
    }
  }
}

/* 禁用动画模式 */
.app-icon-item.no-animation :deep(.app-icon-box) {
  transition: none !important;
  animation: none !important;
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

/* ==================== 付费 / 会员门控角标 ==================== */
.gate-marker {
  position: absolute;
  top: -4px;
  left: -4px;
  padding: 1px 5px;
  border-radius: 8px;
  font-size: 10px;
  font-weight: 700;
  line-height: 1.4;
  color: #fff;
  border: 1.5px solid white;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
  white-space: nowrap;
}

.dark .gate-marker {
  border-color: #1c1c1e;
}

.gate-marker.gate-coin {
  background: #ff9f0a;
}

.gate-marker.gate-member {
  background: linear-gradient(135deg, #ffb340, #ff8a00);
}

/* ==================== 无障碍优化 ==================== */
@media (prefers-reduced-motion: reduce) {
  .app-icon-item {
    transition: none;
    animation: none;
  }
}
</style>
