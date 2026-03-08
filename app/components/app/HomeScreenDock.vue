<script setup lang="ts">
/**
 * HomeScreenDock - Home Screen 底部常用栏
 * 基于 LayoutDock 改造，从路由导航改为应用 Dock
 * 固定 4 个常用应用，仅显示图标不显示名称
 */
import type { YlfAppInfo } from '~~/packages/types'
import type { InstalledApp } from '~/types/homeScreen'
import { Haptics, ImpactStyle } from '@capacitor/haptics'
import { VueDraggable } from 'vue-draggable-plus'
import { ALL_APPS } from '~/constants/apps'

interface Props {
  /** Dock 应用列表 */
  apps: InstalledApp[]
  /** 是否编辑模式 */
  editMode?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  editMode: false,
})

const emit = defineEmits<{
  'update:apps': [apps: InstalledApp[]]
  'open': [app: YlfAppInfo, installed: InstalledApp]
  'remove': [installed: InstalledApp]
  'longPress': [app: InstalledApp, position: { x: number, y: number }]
}>()

/** 解析应用信息 */
function resolveApp(installed: InstalledApp): YlfAppInfo | null {
  return ALL_APPS.find(a => a.id === installed.appId || a.slug === installed.appId) || null
}

function handleClick(installed: InstalledApp) {
  if (props.editMode)
    return
  const app = resolveApp(installed)
  if (app) {
    emit('open', app, installed)
  }
}

const dockApps = computed({
  get: () => [...props.apps],
  set: (v) => { emit('update:apps', v) },
})

function onDragEnd() {
  Haptics.impact({ style: ImpactStyle.Light }).catch(() => {})
  emit('update:apps', dockApps.value)
}

/** 长按检测 */
const LONG_PRESS_DELAY = 500
const LONG_PRESS_MOVE_THRESHOLD = 10

let longPressTimer: ReturnType<typeof setTimeout> | null = null
let startX = 0
let startY = 0
let longPressApp: InstalledApp | null = null

function clearLongPressTimer() {
  if (longPressTimer) {
    clearTimeout(longPressTimer)
    longPressTimer = null
  }
}

function onPointerDown(e: PointerEvent, app: InstalledApp) {
  if (props.editMode)
    return
  startX = e.clientX
  startY = e.clientY
  longPressApp = app
  clearLongPressTimer()
  longPressTimer = setTimeout(() => {
    longPressTimer = null
    Haptics.impact({ style: ImpactStyle.Medium }).catch(() => {})
    emit('longPress', longPressApp!, { x: startX, y: startY })
  }, LONG_PRESS_DELAY)
}

function onPointerMove(e: PointerEvent) {
  if (!longPressTimer)
    return
  const dx = e.clientX - startX
  const dy = e.clientY - startY
  if (Math.abs(dx) > LONG_PRESS_MOVE_THRESHOLD || Math.abs(dy) > LONG_PRESS_MOVE_THRESHOLD) {
    clearLongPressTimer()
  }
}

function onPointerUp() {
  clearLongPressTimer()
}

function onPointerCancel() {
  clearLongPressTimer()
}
</script>

<template>
  <div class="hs-dock">
    <div class="dock-container">
      <VueDraggable
        v-model="dockApps"
        :disabled="!editMode"
        :animation="200"
        ghost-class="dock-ghost"
        class="dock-items"
        @end="onDragEnd"
      >
        <div
          v-for="element in dockApps"
          :key="element.appId"
          class="dock-item"
          :class="{ 'edit-wobble': editMode }"
          @click="handleClick(element)"
          @pointerdown="onPointerDown($event, element)"
          @pointermove="onPointerMove"
          @pointerup="onPointerUp"
          @pointercancel="onPointerCancel"
          @contextmenu.prevent
        >
          <!-- 删除按钮 -->
          <button
            v-if="editMode"
            class="delete-badge"
            @click.stop="emit('remove', element)"
          >
            <span class="delete-icon">−</span>
          </button>

          <div
            v-if="resolveApp(element)"
            class="dock-icon"
            :style="{ backgroundColor: resolveApp(element)!.color }"
          >
            <div v-if="resolveApp(element)!.icon" class="dock-img">
              <img :src="resolveApp(element)!.icon" alt="">
            </div>
            <span v-else class="dock-emoji">{{ resolveApp(element)!.emoji }}</span>
          </div>
          <div v-else class="dock-icon placeholder-dock">
            <span class="dock-emoji">📱</span>
          </div>
        </div>
      </VueDraggable>
    </div>
  </div>
</template>

<style scoped>
.hs-dock {
  position: relative;
  display: flex;
  justify-content: center;
  padding: 8px 16px 16px;
}

.dock-container {
  background: rgba(255, 255, 255, 0.7);
  backdrop-filter: blur(30px) saturate(180%);
  -webkit-backdrop-filter: blur(30px) saturate(180%);
  border-radius: 20px;
  padding: 8px 16px;
  box-shadow:
    0 8px 32px rgba(0, 0, 0, 0.12),
    0 0 0 0.5px rgba(0, 0, 0, 0.05);
}

.dark .dock-container {
  background: rgba(28, 28, 30, 0.7);
  box-shadow:
    0 8px 32px rgba(0, 0, 0, 0.4),
    0 0 0 0.5px rgba(255, 255, 255, 0.1);
}

.dock-items {
  display: flex;
  gap: 20px;
}

.dock-item {
  position: relative;
  cursor: pointer;
  transition: transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.dock-item:active {
  transform: scale(0.85);
}

.dock-icon {
  width: 64px;
  height: 64px;
  border-radius: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 3px 10px rgba(0, 0, 0, 0.12);
  position: relative;
  overflow: hidden;
}

.dock-icon::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: 16px;
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.08);
  pointer-events: none;
}

.dark .dock-icon {
  box-shadow: 0 3px 10px rgba(0, 0, 0, 0.35);
}

.dock-emoji {
  font-size: 32px;
  line-height: 1;
  filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.2));
}

.dock-img img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.placeholder-dock {
  background: #e5e5ea;
}

.dark .placeholder-dock {
  background: #3a3a3c;
}

/* ==================== 编辑抖动 ==================== */
.edit-wobble {
  animation: wobble 0.3s ease-in-out infinite alternate;
}

@keyframes wobble {
  0% {
    transform: rotate(-1deg);
  }
  100% {
    transform: rotate(1deg);
  }
}

/* ==================== 删除按钮 ==================== */
.delete-badge {
  position: absolute;
  top: -6px;
  left: -2px;
  width: 22px;
  height: 22px;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.45);
  border: none;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 10;
  cursor: pointer;
  padding: 0;
}

.delete-icon {
  color: white;
  font-size: 16px;
  font-weight: 600;
  line-height: 1;
}

.dock-ghost {
  opacity: 0.3;
}

/* ==================== 响应式 ==================== */
@media (max-width: 480px) {
  .dock-items {
    gap: 16px;
  }

  .dock-icon {
    width: 60px;
    height: 60px;
    border-radius: 14px;
  }

  .dock-emoji {
    font-size: 28px;
  }
}

@media (hover: hover) {
  .dock-item:hover {
    transform: translateY(-4px) scale(1.05);
  }

  .dock-item:active {
    transform: translateY(-2px) scale(0.95);
  }
}

@media (prefers-reduced-motion: reduce) {
  .edit-wobble,
  .dock-item {
    animation: none;
    transition: none;
  }
}
</style>
