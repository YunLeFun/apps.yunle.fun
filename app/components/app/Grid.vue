<script setup lang="ts">
/**
 * AppGrid - 应用网格组件
 *
 * @description
 * 展示应用图标网格，支持点击打开和长按显示菜单
 * 包含优化的交互反馈系统
 *
 * @example
 * ```vue
 * <AppGrid
 *   :apps="apps"
 *   :enable-haptic="true"
 *   @click="handleClick"
 *   @long-press="handleLongPress"
 * />
 * ```
 */

import type { YlfAppInfo } from '~~/packages/types'

interface Props {
  /** 应用列表 */
  apps: YlfAppInfo[]
  /** 是否显示徽章（随机） */
  showBadge?: boolean
  /** 是否启用触觉反馈 */
  enableHaptic?: boolean
  /** 是否启用视觉反馈 */
  enableVisualFeedback?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  showBadge: true,
  enableHaptic: true,
  enableVisualFeedback: true,
})

const emit = defineEmits<{
  /** 点击应用事件 */
  click: [app: YlfAppInfo]
  /** 长按应用事件 */
  longPress: [app: YlfAppInfo, event: PointerEvent | TouchEvent]
}>()

// 使用交互反馈系统
const {
  getInteractionClass,
  getInteractionStyle,
  performanceLevel,
} = useAppInteraction({
  onTap: (app: YlfAppInfo) => emit('click', app),
  onLongPress: (app: YlfAppInfo, event: PointerEvent | TouchEvent) => emit('longPress', app, event),
  enableHaptic: props.enableHaptic,
  enableVisualFeedback: props.enableVisualFeedback,
})

const showActionSheet = ref(false)

/**
 * 处理长按
 * 转发事件到父组件
 */
function handleLongPress(app: YlfAppInfo, event: PointerEvent | TouchEvent) {
  showActionSheet.value = true
  emit('longPress', app, event)
}
</script>

<template>
  <div class="apps-grid" :data-performance="performanceLevel">
    <slot name="pre" />
    <AppItem
      v-for="app in apps"
      :key="app.id"
      :app="app"
      :show-badge="showBadge"
      :interaction-class="getInteractionClass(app.id)"
      :interaction-style="getInteractionStyle(app.id)"
      :performance-level="performanceLevel"
      @long-press="(app, event) => handleLongPress(app, event)"
    />
    <slot name="post" />
  </div>

  <AppActionSheet :is-open="showActionSheet" @did-dismiss="showActionSheet = false" />
</template>

<style scoped>
/* ==================== 应用网格 ==================== */
.apps-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 20px;
  padding: 20px 20px 120px 20px;
  max-width: 100%;
}

/* ==================== 响应式设计 ==================== */
@media (max-width: 480px) {
  .apps-grid {
    grid-template-columns: repeat(4, 1fr);
    gap: 16px;
    padding: 16px 16px 110px 16px;
  }
}

@media (min-width: 768px) {
  .apps-grid {
    grid-template-columns: repeat(5, 1fr);
    gap: 24px;
    padding: 24px 24px 120px 24px;
  }
}

@media (min-width: 1024px) {
  .apps-grid {
    grid-template-columns: repeat(6, 1fr);
    gap: 28px;
    padding: 28px 32px 130px 32px;
  }
}
</style>
