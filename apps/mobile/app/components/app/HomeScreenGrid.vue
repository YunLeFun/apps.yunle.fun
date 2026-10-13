<script setup lang="ts">
/**
 * HomeScreenGrid - 主屏应用网格（纵向滚动）
 *
 * 交互模型（对齐 iOS 原生行为）：
 * - 非编辑模式：长按 500ms 图标 → 弹出上下文菜单；长按空白区域 → 进入编辑模式
 * - 编辑模式：SortableJS 启用（delay=0），触摸图标立即可拖拽排序
 * - 整个应用列表随外层内容区纵向滚动（不再横向翻页）
 */
import type { YlfAppInfo } from '@yunlefun/types'
import type { UseDraggableReturn } from 'vue-draggable-plus'
import type { InstalledApp } from '~/types/homeScreen'
import { Haptics, ImpactStyle } from '@capacitor/haptics'
import { VueDraggable } from 'vue-draggable-plus'

interface Props {
  /** 已安装应用列表（单一纵向列表，可拖拽排序） */
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
  open: [app: YlfAppInfo, installed: InstalledApp]
  remove: [installed: InstalledApp]
  longPress: [app: InstalledApp | null, position: { x: number, y: number }, iconRect: DOMRect | null]
}>()

const homeScreenStore = useHomeScreenStore()
const { getApp, ensureLoaded } = useAppCatalog()

/** 解析应用完整信息（集合优先，内置兜底） */
function resolveApp(installed: InstalledApp): YlfAppInfo | null {
  return getApp(installed.appId) ?? null
}

onMounted(() => {
  ensureLoaded()
})

/** 可拖拽的扁平 model —— 必须是可写 ref，computed 只读会导致拖拽写入被丢弃 */
const gridModel = ref<InstalledApp[]>([])

watch(
  () => props.apps,
  (apps) => {
    gridModel.value = apps.map(app => ({ ...app }))
  },
  { immediate: true, deep: true },
)

/**
 * Sortable 手动初始化（:immediate="false" + start($el)）。
 *
 * HMR 全量重载时 VueDraggable 内部模板 ref 可能丢失 owner
 * （Vue warn: "Missing ref owner context. ref cannot be used on hoisted vnodes"），
 * 库的自动初始化会报 "Root element not found" 且 Sortable 静默未创建、拖拽失效。
 * vnode.el 的赋值不受该问题影响，因此挂载后取实例 $el 显式传给 start()，
 * 完全绕开库内部的模板 ref。
 */
type DraggableInstance = UseDraggableReturn & { $el?: unknown }

const draggableRef = ref<DraggableInstance | null>(null)
let sortableStarted = false

function setDraggableRef(instance: unknown) {
  draggableRef.value = instance as DraggableInstance | null
}

async function initSortable() {
  await nextTick()
  const draggable = draggableRef.value
  if (!draggable || sortableStarted)
    return
  if (draggable.$el instanceof HTMLElement) {
    draggable.start(draggable.$el)
    sortableStarted = true
  }
}

onMounted(initSortable)

/** 拖拽开始 */
function onDragStart() {
  Haptics.impact({ style: ImpactStyle.Medium }).catch(() => {})
}

/** 拖拽结束时更新 */
function onDragEnd() {
  homeScreenStore.updateInstalledApps([...gridModel.value])
  homeScreenStore.markPendingChanges()
  Haptics.impact({ style: ImpactStyle.Light }).catch(() => {})
}

/** 处理应用点击 */
function handleAppClick(installed: InstalledApp) {
  if (props.editMode)
    return
  const app = resolveApp(installed)
  if (app) {
    emit('open', app, installed)
  }
}

/** 长按进入编辑（兼容 iOS 真机） */
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

function handleLongPress(app: InstalledApp | null, x: number, y: number) {
  Haptics.impact({ style: ImpactStyle.Medium }).catch(() => {})
  const iconRect = longPressElement?.getBoundingClientRect() ?? null
  emit('longPress', app, { x, y }, iconRect)
}

function onPointerDown(e: PointerEvent, app: InstalledApp | null = null) {
  // 编辑模式下让事件冒泡给 SortableJS 处理拖拽
  if (props.editMode)
    return

  // 非编辑模式：图标上的 pointerdown 阻止冒泡到空白区域，
  // 避免同时触发空白区域的长按检测
  if (app)
    e.stopPropagation()

  startX = e.clientX
  startY = e.clientY
  longPressApp = app
  longPressElement = (e.currentTarget as HTMLElement) || null
  clearLongPressTimer()
  longPressTimer = setTimeout(() => {
    longPressTimer = null
    handleLongPress(longPressApp, startX, startY)
  }, LONG_PRESS_DELAY)
}

function onPointerMove(e: PointerEvent) {
  if (!longPressTimer)
    return
  const dx = e.clientX - startX
  const dy = e.clientY - startY
  // 手指移动超过阈值则取消长按
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

/**
 * Touch 事件兜底：iOS 滚动容器内 pointerdown 可能被 pointercancel 取消，
 * 用 touchstart/touchmove/touchend/touchcancel 作为空白区域长按的可靠兜底。
 */
let touchLongPressTimer: ReturnType<typeof setTimeout> | null = null
let touchStartX = 0
let touchStartY = 0

function clearTouchLongPressTimer() {
  if (touchLongPressTimer) {
    clearTimeout(touchLongPressTimer)
    touchLongPressTimer = null
  }
}

function onBlankTouchStart(e: TouchEvent) {
  if (props.editMode)
    return
  // 只在空白区域触发（事件直接落在容器上，不是从子图标冒泡）
  if (e.target !== e.currentTarget)
    return

  const touch = e.touches[0]!
  touchStartX = touch.clientX
  touchStartY = touch.clientY
  clearTouchLongPressTimer()
  touchLongPressTimer = setTimeout(() => {
    touchLongPressTimer = null
    handleLongPress(null, touchStartX, touchStartY)
  }, LONG_PRESS_DELAY)
}

function onBlankTouchMove(e: TouchEvent) {
  if (!touchLongPressTimer)
    return
  const touch = e.touches[0]!
  const dx = touch.clientX - touchStartX
  const dy = touch.clientY - touchStartY
  if (Math.abs(dx) > LONG_PRESS_MOVE_THRESHOLD || Math.abs(dy) > LONG_PRESS_MOVE_THRESHOLD) {
    clearTouchLongPressTimer()
  }
}

function onBlankTouchEnd() {
  clearTouchLongPressTimer()
}

function onBlankTouchCancel() {
  clearTouchLongPressTimer()
}
</script>

<template>
  <!-- 纵向滚动容器：长按空白区域进入编辑模式 -->
  <div
    class="hs-grid-wrapper"
    @pointerdown="onPointerDown($event, null)"
    @pointermove="onPointerMove"
    @pointerup="onPointerUp"
    @pointercancel="onPointerCancel"
    @touchstart="onBlankTouchStart"
    @touchmove="onBlankTouchMove"
    @touchend="onBlankTouchEnd"
    @touchcancel="onBlankTouchCancel"
  >
    <VueDraggable
      :ref="setDraggableRef"
      v-model="gridModel"
      :immediate="false"
      :disabled="!editMode"
      :animation="300"
      :delay="0"
      :force-fallback="true"
      :fallback-on-body="true"
      :fallback-tolerance="3"
      ghost-class="hs-ghost"
      drag-class="hs-drag"
      chosen-class="hs-chosen"
      class="hs-grid"
      @start="onDragStart"
      @end="onDragEnd"
    >
      <div
        v-for="element in gridModel"
        :key="element.appId"
        class="hs-grid-item"
        :class="{
          'edit-wobble': editMode,
          'hs-hidden': element.appId === hiddenAppId,
        }"
        @click="handleAppClick(element)"
        v-on="editMode ? {} : {
          pointerdown: (e: PointerEvent) => onPointerDown(e, element),
          pointermove: onPointerMove,
          pointerup: onPointerUp,
          pointercancel: onPointerCancel,
        }"
        @contextmenu.prevent
      >
        <!-- 删除按钮（编辑模式） -->
        <button
          v-if="editMode"
          class="delete-badge"
          @click.stop="emit('remove', element)"
        >
          <span class="delete-icon">−</span>
        </button>

        <!-- 复用 AppIcon -->
        <AppIcon
          v-if="resolveApp(element)"
          :app="resolveApp(element)!"
          :show-badge="false"
        />
        <!-- 未解析的应用占位 -->
        <AppIconBox
          v-else
          placeholder
          :label="element.appId"
        />
      </div>
    </VueDraggable>
  </div>
</template>

<style scoped>
.hs-grid-wrapper {
  /* 至少撑满内容区，保证图标下方留有可长按进入编辑模式的空白 */
  min-height: 100%;
}

.hs-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 20px;
  padding: 12px 20px;
  align-content: start;
}

.hs-grid-item {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  -webkit-touch-callout: none;
  -webkit-user-select: none;
  user-select: none;
}

/* 上下文菜单浮动预览时隐藏原始图标（保留占位） */
.hs-hidden {
  visibility: hidden;
}

/* ==================== 编辑模式抖动动画（iOS 仿真） ==================== */
/*
 * iOS 真实参数：约 0.115s 半周期，±1.2deg 旋转角度
 * 通过 nth-child 错开相位，模拟"随机感"
 */
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

.edit-wobble:nth-child(5n) {
  animation-delay: -0.02s;
  animation-direction: alternate-reverse;
}

.edit-wobble:nth-child(7n) {
  animation-delay: -0.09s;
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

/* ==================== 拖拽样式（iOS 风格） ==================== */
/* ghost 在原容器内，scoped 生效 */
.hs-ghost {
  opacity: 0;
}

/* ==================== 响应式 ==================== */
@media (max-width: 480px) {
  .hs-grid {
    gap: 16px;
    padding: 12px 16px;
  }
}

@media (prefers-reduced-motion: reduce) {
  .edit-wobble {
    animation: none;
  }
}
</style>

<!-- 拖拽 clone 挂在 body 上（fallbackOnBody），需要全局样式 -->
<style>
/* 选中状态（pointerdown 选中、拖拽前） */
.hs-chosen {
  animation: none !important;
  z-index: 100;
  filter: drop-shadow(0 10px 30px rgba(0, 0, 0, 0.3));
}

/*
 * 拖拽中的 clone（fallbackOnBody 挂在 body 上）
 * 重要：不设 transform，SortableJS 通过 inline style transform: matrix()
 * 控制 clone 跟随手指。CSS transform 会覆盖 SortableJS 的位移计算。
 */
.hs-drag {
  opacity: 1 !important;
  z-index: 100000 !important;
  filter: drop-shadow(0 10px 30px rgba(0, 0, 0, 0.3));
}
</style>
