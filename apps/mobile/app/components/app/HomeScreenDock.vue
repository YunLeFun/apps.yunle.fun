<script setup lang="ts">
/**
 * HomeScreenDock - Home Screen 底部常用栏
 * 基于 LayoutDock 改造，从路由导航改为应用 Dock
 * 固定 4 个常用应用，仅显示图标不显示名称
 */
import type { YlfAppInfo } from '@yunlefun/types'
import type { UseDraggableReturn } from 'vue-draggable-plus'
import type { InstalledApp } from '~/types/homeScreen'
import { Haptics, ImpactStyle } from '@capacitor/haptics'
import { kGlass } from 'konsta/vue'
import { VueDraggable } from 'vue-draggable-plus'

interface Props {
  /** Dock 应用列表 */
  apps: InstalledApp[]
  /** 是否编辑模式 */
  editMode?: boolean
  /** 上下文菜单预览时需要隐藏的应用 ID */
  hiddenAppId?: string
}

const props = withDefaults(defineProps<Props>(), {
  editMode: false,
})

const emit = defineEmits<{
  'update:apps': [apps: InstalledApp[]]
  'open': [app: YlfAppInfo, installed: InstalledApp]
  'remove': [installed: InstalledApp]
  'longPress': [app: InstalledApp, position: { x: number, y: number }, iconRect: DOMRect]
}>()

const { getApp, ensureLoaded } = useAppCatalog()

/** 解析应用信息（集合优先，内置兜底） */
function resolveApp(installed: InstalledApp): YlfAppInfo | null {
  return getApp(installed.appId) ?? null
}

onMounted(() => {
  ensureLoaded()
})

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

const homeScreenStore = useHomeScreenStore()

/**
 * Sortable 手动初始化（:immediate="false" + start($el)），
 * 原因同 HomeScreenGrid：HMR 全量重载时 VueDraggable 内部模板 ref
 * 可能丢失 owner，自动初始化会报 "Root element not found" 且拖拽静默失效。
 */
type DraggableInstance = UseDraggableReturn & { $el?: unknown }

const draggableRef = ref<DraggableInstance | null>(null)

onMounted(async () => {
  await nextTick()
  const draggable = draggableRef.value
  if (draggable && draggable.$el instanceof HTMLElement)
    draggable.start(draggable.$el)
})

function onDragStart() {
  if (!props.editMode) {
    homeScreenStore.enterEditMode()
  }
  Haptics.impact({ style: ImpactStyle.Medium }).catch(() => {})
}

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
let longPressElement: HTMLElement | null = null

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
  longPressElement = (e.currentTarget as HTMLElement) || null
  clearLongPressTimer()
  longPressTimer = setTimeout(() => {
    longPressTimer = null
    Haptics.impact({ style: ImpactStyle.Medium }).catch(() => {})
    const iconRect = longPressElement!.getBoundingClientRect()
    emit('longPress', longPressApp!, { x: startX, y: startY }, iconRect)
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
    <k-glass class="dock-container" :highlight="false">
      <VueDraggable
        ref="draggableRef"
        v-model="dockApps"
        :immediate="false"
        :disabled="!editMode"
        :animation="300"
        :delay="editMode ? 0 : 500"
        :delay-on-touch-only="!editMode"
        :force-fallback="true"
        :fallback-tolerance="3"
        ghost-class="dock-ghost"
        chosen-class="dock-chosen"
        drag-class="dock-drag"
        class="dock-items"
        @start="onDragStart"
        @end="onDragEnd"
      >
        <div
          v-for="element in dockApps"
          :key="element.appId"
          class="dock-item"
          :class="{ 'edit-wobble': editMode, 'dock-hidden': element.appId === hiddenAppId }"
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

          <AppIconBox
            v-if="resolveApp(element)"
            :icon="resolveApp(element)!.logo"
            :icon-assets="resolveApp(element)!.iconAssets"
            :emoji="resolveApp(element)!.emoji"
            :color="resolveApp(element)!.themeColor"
          />
          <AppIconBox v-else placeholder />
        </div>
      </VueDraggable>
    </k-glass>
  </div>
</template>

<style scoped>
.hs-dock {
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  display: flex;
  justify-content: center;
  /* 与 Grid 的 padding 左右对齐 */
  padding: 8px 20px 16px;
  z-index: 100;
  pointer-events: none;
}

.dock-container {
  pointer-events: auto;
  border-radius: var(--ylf-radius-dock);
  padding: 8px 12px;
  width: 100%;
  max-width: calc(var(--ylf-content-max-width) - 40px);
}

.dock-items {
  --app-icon-size: 64px;
  --app-icon-radius: 16px;
  --app-emoji-size: 32px;

  display: flex;
  /* 与 Grid 的 gap 一致 */
  gap: 20px;
  justify-content: center;
  align-items: center;
  min-height: 64px;
}

.dock-item {
  position: relative;
  cursor: pointer;
  transition: transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.dock-item:active {
  transform: scale(0.85);
}

/* ==================== 编辑抖动（iOS 仿真） ==================== */
.edit-wobble {
  animation: wobble 0.115s ease-in-out infinite alternate;
}

.edit-wobble:nth-child(2n) {
  animation-delay: -0.04s;
  animation-direction: alternate-reverse;
}

.edit-wobble:nth-child(3n) {
  animation-delay: -0.07s;
}

@keyframes wobble {
  0% {
    transform: rotate(-1.2deg);
  }
  100% {
    transform: rotate(1.2deg);
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
  color: #fff;
  font-size: 16px;
  font-weight: 600;
  line-height: 1;
}

.dock-ghost {
  opacity: 0;
}

/* 上下文菜单浮动预览时隐藏原始图标（保留占位） */
.dock-hidden {
  visibility: hidden;
}

.dock-chosen {
  animation: none !important;
  transform: scale(1.15);
  z-index: 100;
  filter: drop-shadow(0 10px 30px rgba(0, 0, 0, 0.3));
}

.dock-drag {
  opacity: 1;
  transform: scale(1.15);
  z-index: 100;
  filter: drop-shadow(0 10px 30px rgba(0, 0, 0, 0.3));
}

/* ==================== 响应式 ==================== */
@media (max-width: 480px) {
  .hs-dock {
    padding: 8px 16px 16px;
  }

  .dock-items {
    --app-icon-size: 60px;
    --app-icon-radius: 14px;
    --app-emoji-size: 28px;

    gap: 16px;
    min-height: 60px;
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
