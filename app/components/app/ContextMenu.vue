<script setup lang="ts">
/**
 * AppContextMenu - iOS 风格应用上下文菜单
 *
 * 长按应用图标时显示的操作菜单，模拟 iOS 主屏幕长按效果：
 * - 毛玻璃背景圆角卡片
 * - 文字标签 + 右侧图标（iOS SF Symbols 布局）
 * - 文字使用系统色（黑/白），危险操作用红色
 * - 分隔线贯穿整行
 */

import type { YlfAppInfo } from '~~/packages/types'

interface Props {
  visible: boolean
  position: { x: number, y: number }
  app?: YlfAppInfo | null
}

const props = defineProps<Props>()
const emit = defineEmits<{
  editHomeScreen: []
  share: []
  remove: []
  close: []
}>()

const MENU_WIDTH = 250
const MENU_HEIGHT = 164
const MARGIN = 12

const menuRef = ref<HTMLElement | null>(null)

/** 计算菜单位置，居中于手指位置上方 */
const menuStyle = computed(() => {
  const { x, y } = props.position
  const vw = typeof window !== 'undefined' ? window.innerWidth : 375
  const vh = typeof window !== 'undefined' ? window.innerHeight : 812

  // 菜单出现在长按点上方，水平居中于手指
  const left = Math.min(Math.max(x - MENU_WIDTH / 2, MARGIN), vw - MENU_WIDTH - MARGIN)
  const top = Math.min(Math.max(y - MENU_HEIGHT - 20, MARGIN), vh - MENU_HEIGHT - MARGIN)

  return {
    left: `${left}px`,
    top: `${top}px`,
    width: `${MENU_WIDTH}px`,
  }
})

function handleAction(action: 'editHomeScreen' | 'share' | 'remove') {
  if (action === 'editHomeScreen')
    emit('editHomeScreen')
  else if (action === 'share')
    emit('share')
  else
    emit('remove')
}

function onOverlayClick() {
  emit('close')
}
</script>

<template>
  <Teleport to="body">
    <Transition name="ctx-menu">
      <div
        v-if="visible"
        class="ctx-overlay"
        @click.self="onOverlayClick"
        @contextmenu.prevent
      >
        <div
          ref="menuRef"
          class="ctx-menu"
          :style="menuStyle"
        >
          <!-- 编辑主屏幕 -->
          <button class="ctx-item" @click="handleAction('editHomeScreen')">
            <span class="ctx-label">编辑主屏幕</span>
            <svg class="ctx-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M3 7v4a1 1 0 001 1h3m10-5v4a1 1 0 01-1 1h-3" />
              <rect x="5" y="3" width="14" height="14" rx="2" />
              <path d="M3 17h18M3 21h18" />
            </svg>
          </button>

          <div class="ctx-divider" />

          <!-- 分享 App -->
          <button class="ctx-item" @click="handleAction('share')">
            <span class="ctx-label">分享 App</span>
            <svg class="ctx-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M4 12v8a2 2 0 002 2h12a2 2 0 002-2v-8" />
              <polyline points="16 6 12 2 8 6" />
              <line x1="12" y1="2" x2="12" y2="15" />
            </svg>
          </button>

          <div class="ctx-divider" />

          <!-- 移除 App -->
          <button class="ctx-item ctx-item--danger" @click="handleAction('remove')">
            <span class="ctx-label">移除 App</span>
            <svg class="ctx-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <polyline points="3 6 5 6 21 6" />
              <path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a2 2 0 012-2h4a2 2 0 012 2v2" />
              <line x1="10" y1="11" x2="10" y2="17" />
              <line x1="14" y1="11" x2="14" y2="17" />
            </svg>
          </button>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.ctx-overlay {
  position: fixed;
  inset: 0;
  z-index: 99999;
  background: rgba(0, 0, 0, 0.2);
  backdrop-filter: blur(4px);
  -webkit-backdrop-filter: blur(4px);
}

.ctx-menu {
  position: fixed;
  background: rgba(255, 255, 255, 0.85);
  backdrop-filter: blur(40px) saturate(180%);
  -webkit-backdrop-filter: blur(40px) saturate(180%);
  border-radius: 14px;
  box-shadow:
    0 8px 32px rgba(0, 0, 0, 0.18),
    0 0 0 0.33px rgba(0, 0, 0, 0.06);
  overflow: hidden;
}

.dark .ctx-menu {
  background: rgba(44, 44, 46, 0.85);
  box-shadow:
    0 8px 32px rgba(0, 0, 0, 0.55),
    0 0 0 0.33px rgba(255, 255, 255, 0.08);
}

/* ==================== 菜单项 ==================== */
.ctx-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  width: 100%;
  padding: 12px 16px;
  border: none;
  background: transparent;
  cursor: pointer;
  font-size: 17px;
  line-height: 22px;
  letter-spacing: -0.4px;
  color: #000;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.1s ease;
}

.dark .ctx-item {
  color: #fff;
}

.ctx-item:active {
  background: rgba(0, 0, 0, 0.08);
}

.dark .ctx-item:active {
  background: rgba(255, 255, 255, 0.12);
}

.ctx-item--danger {
  color: #ff3b30;
}

.dark .ctx-item--danger {
  color: #ff453a;
}

.ctx-label {
  flex: 1;
  text-align: left;
}

.ctx-icon {
  width: 20px;
  height: 20px;
  flex-shrink: 0;
  opacity: 0.55;
}

.ctx-item--danger .ctx-icon {
  opacity: 1;
  color: #ff3b30;
}

.dark .ctx-item--danger .ctx-icon {
  color: #ff453a;
}

/* ==================== 分隔线 ==================== */
.ctx-divider {
  height: 0.33px;
  background: rgba(60, 60, 67, 0.29);
  margin: 0;
}

.dark .ctx-divider {
  background: rgba(84, 84, 88, 0.65);
}

/* ==================== 动画 ==================== */
.ctx-menu-enter-active {
  transition:
    opacity 0.2s ease,
    transform 0.2s cubic-bezier(0.2, 0.9, 0.3, 1.2);
}

.ctx-menu-leave-active {
  transition:
    opacity 0.15s ease,
    transform 0.15s ease;
}

.ctx-menu-enter-from {
  opacity: 0;
}

.ctx-menu-enter-from .ctx-menu {
  transform: scale(0.85);
  opacity: 0;
}

.ctx-menu-leave-to {
  opacity: 0;
}

.ctx-menu-leave-to .ctx-menu {
  transform: scale(0.95);
  opacity: 0;
}

@media (prefers-reduced-motion: reduce) {
  .ctx-menu-enter-active,
  .ctx-menu-leave-active {
    transition: none;
  }
}
</style>
