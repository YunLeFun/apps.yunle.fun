<script setup lang="ts">
/**
 * HomeScreenGrid - iOS 风格 Home Screen 网格
 * 基于现有 AppGrid 扩展，支持翻页、拖拽排序、编辑模式
 */
import type { YlfAppInfo } from '~~/packages/types'
import type { InstalledApp } from '~/types/homeScreen'
import { Haptics, ImpactStyle } from '@capacitor/haptics'
import { VueDraggable } from 'vue-draggable-plus'
import { ALL_APPS } from '~/constants/apps'

interface Props {
  /** 分页后的应用列表 */
  pages: InstalledApp[][]
  /** 是否编辑模式 */
  editMode?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  editMode: false,
})

const emit = defineEmits<{
  'update:pages': [pages: InstalledApp[][]]
  'open': [app: YlfAppInfo, installed: InstalledApp]
  'remove': [installed: InstalledApp]
  'longPress': [app: InstalledApp | null, position: { x: number, y: number }, iconRect: DOMRect | null]
}>()

const homeScreenStore = useHomeScreenStore()
const currentPage = computed({
  get: () => homeScreenStore.currentPage,
  set: (v) => { homeScreenStore.currentPage = v },
})

/** 解析应用完整信息 */
function resolveApp(installed: InstalledApp): YlfAppInfo | null {
  return ALL_APPS.find(a => a.id === installed.appId || a.slug === installed.appId) || null
}

/** 可拖拽的 model —— 必须是可写 ref，computed 只读会导致拖拽写入被丢弃 */
const pageModels = ref<InstalledApp[][]>([])

watch(
  () => props.pages,
  (pages) => {
    pageModels.value = pages.map(page => [...page])
  },
  { immediate: true, deep: true },
)

/** 拖拽结束时更新 */
function onDragEnd() {
  const flatApps = pageModels.value.flat()
  homeScreenStore.updateInstalledApps(flatApps)
  homeScreenStore.markPendingChanges()

  // 拖拽触觉反馈
  Haptics.impact({ style: ImpactStyle.Light }).catch(() => {})
}

/** 处理翻页滚动 */
const scrollContainer = ref<HTMLElement | null>(null)

function scrollToPage(index: number) {
  if (!scrollContainer.value)
    return
  const width = scrollContainer.value.clientWidth
  scrollContainer.value.scrollTo({ left: width * index, behavior: 'smooth' })
  currentPage.value = index
}

function onScroll() {
  if (!scrollContainer.value)
    return
  const width = scrollContainer.value.clientWidth
  const scrollLeft = scrollContainer.value.scrollLeft
  const page = Math.round(scrollLeft / width)
  if (page !== currentPage.value) {
    currentPage.value = page
  }
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
  // 编辑模式下让事件继续冒泡，SortableJS 需要捕获来发起拖拽
  if (props.editMode)
    return

  // 非编辑模式：应用图标上的 pointerdown 需要阻止冒泡到 .hs-page，
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
</script>

<template>
  <div class="hs-grid-wrapper">
    <!-- 翻页容器 -->
    <div
      ref="scrollContainer"
      class="hs-scroll-container"
      @scroll.passive="onScroll"
    >
      <div
        v-for="(page, pageIndex) in pages"
        :key="pageIndex"
        class="hs-page"
        @pointerdown="onPointerDown($event, null)"
        @pointermove="onPointerMove"
        @pointerup="onPointerUp"
        @pointercancel="onPointerCancel"
      >
        <VueDraggable
          v-model="pageModels[pageIndex]!"
          :disabled="!editMode"
          :animation="250"
          :delay="0"
          :delay-on-touch-only="false"
          :force-fallback="true"
          :fallback-tolerance="3"
          ghost-class="hs-ghost"
          drag-class="hs-drag"
          chosen-class="hs-chosen"
          class="hs-grid"
          @end="onDragEnd"
        >
          <div
            v-for="element in pageModels[pageIndex]"
            :key="element.appId"
            class="hs-grid-item"
            :class="{ 'edit-wobble': editMode }"
            @click="handleAppClick(element)"
            @pointerdown="onPointerDown($event, element)"
            @pointermove="onPointerMove"
            @pointerup="onPointerUp"
            @pointercancel="onPointerCancel"
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
    </div>

    <!-- 页码指示器 -->
    <div v-if="pages.length > 1" class="page-dots">
      <button
        v-for="(_, i) in pages"
        :key="i"
        class="page-dot"
        :class="{ active: i === currentPage }"
        @click="scrollToPage(i)"
      />
    </div>
  </div>
</template>

<style scoped>
.hs-grid-wrapper {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.hs-scroll-container {
  flex: 1;
  display: flex;
  overflow-x: auto;
  scroll-snap-type: x mandatory;
  scrollbar-width: none;
  -webkit-overflow-scrolling: touch;
}

.hs-scroll-container::-webkit-scrollbar {
  display: none;
}

.hs-page {
  flex: 0 0 100%;
  scroll-snap-align: start;
  min-height: 0;
}

.hs-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 20px;
  padding: 12px 20px;
  min-height: 100%;
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
  touch-action: none;
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
  color: white;
  font-size: 16px;
  font-weight: 600;
  line-height: 1;
}

/* ==================== 拖拽样式（iOS 风格） ==================== */
.hs-ghost {
  opacity: 0;
}

.hs-chosen {
  animation: none !important;
  transform: scale(1.1);
  z-index: 100;
  filter: drop-shadow(0 8px 20px rgba(0, 0, 0, 0.25));
  transition: transform 0.2s cubic-bezier(0.2, 0, 0.2, 1);
}

.hs-drag {
  opacity: 1;
  transform: scale(1.1);
  z-index: 100;
  filter: drop-shadow(0 8px 20px rgba(0, 0, 0, 0.25));
}

/* ==================== 页码指示器 ==================== */
.page-dots {
  display: flex;
  justify-content: center;
  gap: 8px;
  padding: 8px 0;
}

.page-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.2);
  border: none;
  padding: 0;
  cursor: pointer;
  transition: all 0.2s ease;
}

.dark .page-dot {
  background: rgba(255, 255, 255, 0.2);
}

.page-dot.active {
  background: rgba(0, 0, 0, 0.6);
  transform: scale(1.3);
}

.dark .page-dot.active {
  background: rgba(255, 255, 255, 0.8);
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
