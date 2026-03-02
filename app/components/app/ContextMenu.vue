<script setup lang="ts">
/**
 * AppContextMenu - 应用上下文菜单组件
 *
 * @description
 * 长按应用图标时显示的操作菜单，支持自定义菜单项和位置
 *
 * @example
 * ```vue
 * <AppContextMenu
 *   :visible="showMenu"
 *   :position="{ x: 100, y: 200 }"
 *   :app-name="selectedApp?.name"
 *   @open="handleOpen"
 *   @edit="handleEdit"
 *   @share="handleShare"
 *   @remove="handleRemove"
 *   @close="handleClose"
 * />
 * ```
 */

import type { YlfAppInfo } from '~~/packages/types'

interface Props {
  /** 是否显示菜单 */
  visible: boolean
  /** 菜单位置 */
  position: { x: number, y: number }
  /** 当前选中的应用（可选，用于显示应用名称） */
  app?: YlfAppInfo | null
}

defineProps<Props>()
const emit = defineEmits(['open', 'edit', 'share', 'remove', 'close'])

/**
 * 处理菜单项点击
 */
function handleAction(action: 'open' | 'edit' | 'share' | 'remove') {
  emit(action)
}

/**
 * 关闭菜单
 */
function handleClose() {
  emit('close')
}
</script>

<template>
  <Transition name="context-menu-fade">
    <div
      v-if="visible"
      class="context-menu-overlay"
      @click="handleClose"
      @touchstart.prevent
      @touchend="handleClose"
    >
      <div
        class="context-menu"
        :style="{
          left: `${position.x}px`,
          top: `${position.y}px`,
        }"
        @click.stop
        @touchend.stop
      >
        <div class="context-menu-item" @click="handleAction('open')">
          <span class="menu-icon">📱</span>
          <span>打开</span>
        </div>
        <div class="context-menu-item" @click="handleAction('edit')">
          <span class="menu-icon">✏️</span>
          <span>编辑</span>
        </div>
        <div class="context-menu-item" @click="handleAction('share')">
          <span class="menu-icon">📤</span>
          <span>分享</span>
        </div>
        <div class="context-menu-item danger" @click="handleAction('remove')">
          <span class="menu-icon">🗑️</span>
          <span>移除</span>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
/* ==================== 长按菜单 ==================== */
.context-menu-overlay {
  position: fixed;
  inset: 0;
  z-index: 1000;
  background: rgba(0, 0, 0, 0.3);
  backdrop-filter: blur(2px);
  -webkit-backdrop-filter: blur(2px);
}

.context-menu {
  position: fixed;
  background: rgba(255, 255, 255, 0.98);
  backdrop-filter: blur(30px) saturate(180%);
  -webkit-backdrop-filter: blur(30px) saturate(180%);
  border-radius: 16px;
  box-shadow:
    0 10px 40px rgba(0, 0, 0, 0.15),
    0 0 0 0.5px rgba(0, 0, 0, 0.05);
  overflow: hidden;
  min-width: 160px;
  z-index: 1001;
  transform-origin: center;
}

.dark .context-menu {
  background: rgba(28, 28, 30, 0.98);
  box-shadow:
    0 10px 40px rgba(0, 0, 0, 0.5),
    0 0 0 0.5px rgba(255, 255, 255, 0.1);
}

.context-menu-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 14px 20px;
  font-size: 16px;
  color: #007aff;
  cursor: pointer;
  transition: background 0.15s ease;
  position: relative;
}

.dark .context-menu-item {
  color: #0a84ff;
}

.context-menu-item .menu-icon {
  font-size: 18px;
  width: 24px;
  text-align: center;
}

.context-menu-item:active {
  background: rgba(0, 0, 0, 0.05);
}

.dark .context-menu-item:active {
  background: rgba(255, 255, 255, 0.08);
}

.context-menu-item.danger {
  color: #ff3b30;
}

.dark .context-menu-item.danger {
  color: #ff453a;
}

.context-menu-item.cancel {
  color: #8e8e93;
  font-weight: 600;
  justify-content: center;
}

.dark .context-menu-item.cancel {
  color: #98989d;
}

.context-menu-divider {
  height: 1px;
  background: rgba(0, 0, 0, 0.1);
  margin: 4px 0;
}

.dark .context-menu-divider {
  background: rgba(255, 255, 255, 0.1);
}

/* 菜单动画 */
.context-menu-fade-enter-active {
  transition: all 0.2s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.context-menu-fade-leave-active {
  transition: all 0.15s ease-out;
}

.context-menu-fade-enter-from {
  opacity: 0;
}

.context-menu-fade-enter-from .context-menu {
  opacity: 0;
  transform: scale(0.8);
}

.context-menu-fade-leave-to {
  opacity: 0;
}

.context-menu-fade-leave-to .context-menu {
  opacity: 0;
  transform: scale(0.95);
}

/* ==================== 无障碍优化 ==================== */
@media (prefers-reduced-motion: reduce) {
  .context-menu-fade-enter-active,
  .context-menu-fade-leave-active {
    transition: none;
  }
}
</style>
