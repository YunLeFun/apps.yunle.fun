<script setup lang="ts">
/**
 * AppContextMenu - iOS 风格应用上下文菜单
 *
 * 长按应用图标时：
 * - 被长按的应用图标浮于遮罩之上（带缩放动画 + 抖动）
 * - 菜单卡片出现在浮动图标旁
 * - 手指移动超阈值 → 关闭菜单并进入编辑模式（由 SortableJS 接管拖拽排序）
 */

import type { YlfAppInfo } from '~~/packages/types'

interface Props {
  visible: boolean
  position: { x: number, y: number }
  app?: YlfAppInfo | null
  /** 长按图标的原始位置和尺寸 */
  iconRect?: { x: number, y: number, width: number, height: number } | null
}

const props = defineProps<Props>()
const emit = defineEmits<{
  editHomeScreen: []
  share: []
  remove: []
  close: []
}>()

const MENU_WIDTH = 250
const MARGIN = 12
const ICON_MENU_GAP = 8
/** 长按后移动超此阈值 → 关闭菜单进入编辑模式 */
const DRAG_TO_EDIT_THRESHOLD = 10

// ---------- 长按后移动检测：超阈值即关闭菜单进入编辑模式 ----------

let moveBaseX = 0
let moveBaseY = 0
let isTracking = false

function onGlobalPointerMove(e: PointerEvent) {
  if (!isTracking)
    return
  const dx = e.clientX - moveBaseX
  const dy = e.clientY - moveBaseY
  if (Math.abs(dx) > DRAG_TO_EDIT_THRESHOLD || Math.abs(dy) > DRAG_TO_EDIT_THRESHOLD) {
    cleanup()
    emit('editHomeScreen')
  }
}

function onGlobalPointerUp() {
  // 松手 → 停止追踪，菜单保持显示
  isTracking = false
  document.removeEventListener('pointermove', onGlobalPointerMove)
  document.removeEventListener('pointerup', onGlobalPointerUp)
}

function cleanup() {
  isTracking = false
  document.removeEventListener('pointermove', onGlobalPointerMove)
  document.removeEventListener('pointerup', onGlobalPointerUp)
}

watch(() => props.visible, (v) => {
  if (v && props.iconRect) {
    moveBaseX = props.position.x
    moveBaseY = props.position.y
    isTracking = true
    document.addEventListener('pointermove', onGlobalPointerMove)
    document.addEventListener('pointerup', onGlobalPointerUp)
  }
  else {
    cleanup()
  }
})

onUnmounted(cleanup)

// ---------- 浮动图标和菜单位置 ----------

const floatingIconStyle = computed(() => {
  if (!props.iconRect)
    return null
  const { x, y, width, height } = props.iconRect
  return {
    position: 'fixed' as const,
    left: `${x}px`,
    top: `${y}px`,
    width: `${width}px`,
    height: `${height}px`,
    zIndex: 100001,
  }
})

const menuStyle = computed(() => {
  const vw = typeof window !== 'undefined' ? window.innerWidth : 375
  const vh = typeof window !== 'undefined' ? window.innerHeight : 812

  if (props.iconRect) {
    const { x, y, width, height } = props.iconRect
    const iconCenterX = x + width / 2
    const menuTop = y + height + ICON_MENU_GAP

    let left = iconCenterX - MENU_WIDTH / 2
    left = Math.min(Math.max(left, MARGIN), vw - MENU_WIDTH - MARGIN)

    const menuEl = document.querySelector('.ctx-menu') as HTMLElement | null
    const menuHeight = menuEl?.offsetHeight ?? 164
    let top = menuTop
    if (menuTop + menuHeight > vh - MARGIN) {
      top = y - menuHeight - ICON_MENU_GAP
      if (top < MARGIN)
        top = MARGIN
    }

    return {
      left: `${left}px`,
      top: `${top}px`,
      width: `${MENU_WIDTH}px`,
    }
  }

  const { x, y } = props.position
  const left = Math.min(Math.max(x - MENU_WIDTH / 2, MARGIN), vw - MENU_WIDTH - MARGIN)
  const top = Math.min(Math.max(y + 10, MARGIN), vh - 164 - MARGIN)
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
        <!-- 浮动的应用图标预览 -->
        <div
          v-if="app && floatingIconStyle"
          class="ctx-floating-icon"
          :style="floatingIconStyle"
          @contextmenu.prevent
        >
          <AppIconBox
            :icon="app.icon"
            :emoji="app.emoji"
            :color="app.color"
            :label="app.name"
          />
        </div>

        <!-- 菜单卡片 -->
        <div
          class="ctx-menu"
          :style="menuStyle"
        >
          <button class="ctx-item" @click="handleAction('editHomeScreen')">
            <span class="ctx-label">编辑主屏幕</span>
            <svg class="ctx-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M3 7v4a1 1 0 001 1h3m10-5v4a1 1 0 01-1 1h-3" />
              <rect x="5" y="3" width="14" height="14" rx="2" />
              <path d="M3 17h18M3 21h18" />
            </svg>
          </button>

          <div class="ctx-divider" />

          <button class="ctx-item" @click="handleAction('share')">
            <span class="ctx-label">分享 App</span>
            <svg class="ctx-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M4 12v8a2 2 0 002 2h12a2 2 0 002-2v-8" />
              <polyline points="16 6 12 2 8 6" />
              <line x1="12" y1="2" x2="12" y2="15" />
            </svg>
          </button>

          <div class="ctx-divider" />

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
  background: transparent;
  backdrop-filter: none;
  -webkit-backdrop-filter: none;
}

/* ==================== 浮动图标 ==================== */
.ctx-floating-icon {
  z-index: 100001;
  animation: ctx-wobble 0.115s ease-in-out infinite alternate;
  filter: drop-shadow(0 8px 24px rgba(0, 0, 0, 0.25));
  -webkit-user-select: none;
  user-select: none;
  -webkit-touch-callout: none;
  touch-action: none;
}

@keyframes ctx-wobble {
  0% {
    transform: rotate(-1.2deg) scale(1.05);
  }
  100% {
    transform: rotate(1.2deg) scale(1.05);
  }
}

/* ==================== 菜单卡片 ==================== */
.ctx-menu {
  position: fixed;
  background: var(--ion-item-background);
  backdrop-filter: blur(40px) saturate(180%);
  -webkit-backdrop-filter: blur(40px) saturate(180%);
  border-radius: 14px;
  box-shadow:
    0 8px 32px rgba(0, 0, 0, 0.18),
    0 0 0 0.33px rgba(0, 0, 0, 0.06);
  overflow: hidden;
  z-index: 100000;
}

.dark .ctx-menu {
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
  color: var(--ion-text-color);
  -webkit-tap-highlight-color: transparent;
  transition: background 0.1s ease;
}

.ctx-item:active {
  background: var(--ylf-fill-quaternary);
}

.ctx-item--danger {
  color: var(--ion-color-danger);
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
  color: var(--ion-color-danger);
}

/* ==================== 分隔线 ==================== */
.ctx-divider {
  height: 0.33px;
  background: var(--ylf-separator);
  margin: 0;
}

/* ==================== 进入/离开动画 ==================== */
.ctx-menu-enter-active {
  transition: opacity 0.2s ease;
}

.ctx-menu-enter-active .ctx-menu {
  transition:
    opacity 0.2s ease,
    transform 0.25s cubic-bezier(0.2, 0.8, 0.2, 1.1);
}

.ctx-menu-enter-active .ctx-floating-icon {
  transition:
    opacity 0.15s ease,
    transform 0.25s cubic-bezier(0.2, 0.8, 0.2, 1.1);
}

.ctx-menu-leave-active {
  transition: opacity 0.15s ease;
}

.ctx-menu-leave-active .ctx-menu,
.ctx-menu-leave-active .ctx-floating-icon {
  transition:
    opacity 0.15s ease,
    transform 0.15s ease;
}

.ctx-menu-enter-from {
  opacity: 0;
}

.ctx-menu-enter-from .ctx-menu {
  opacity: 0;
  transform: scale(0.85);
}

.ctx-menu-enter-from .ctx-floating-icon {
  opacity: 0;
  transform: scale(0.7);
}

.ctx-menu-leave-to {
  opacity: 0;
}

.ctx-menu-leave-to .ctx-menu {
  opacity: 0;
  transform: scale(0.95);
}

.ctx-menu-leave-to .ctx-floating-icon {
  opacity: 0;
  transform: scale(0.9);
}

@media (prefers-reduced-motion: reduce) {
  .ctx-menu-enter-active,
  .ctx-menu-leave-active,
  .ctx-menu-enter-active .ctx-menu,
  .ctx-menu-leave-active .ctx-menu,
  .ctx-menu-enter-active .ctx-floating-icon,
  .ctx-menu-leave-active .ctx-floating-icon {
    transition: none;
  }

  .ctx-floating-icon {
    animation: none;
  }
}
</style>
