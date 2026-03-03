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
  'longPress': []
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

/** 获取当前页应用列表（可拖拽的 model） */
const pageModels = computed(() =>
  props.pages.map(page => [...page]),
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

/** 长按进入编辑 */
function handleLongPress() {
  Haptics.impact({ style: ImpactStyle.Medium }).catch(() => {})
  emit('longPress')
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
      >
        <VueDraggable
          v-model="pageModels[pageIndex]!"
          :disabled="!editMode"
          :animation="200"
          ghost-class="hs-ghost"
          drag-class="hs-drag"
          class="hs-grid"
          @end="onDragEnd"
        >
          <div
            v-for="element in pageModels[pageIndex]"
            :key="element.appId"
            class="hs-grid-item"
            :class="{ 'edit-wobble': editMode }"
            @click="handleAppClick(element)"
            @contextmenu.prevent="handleLongPress"
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
              @pointerdown.prevent
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
}

/* ==================== 编辑模式抖动动画 ==================== */
.edit-wobble {
  animation: wobble 0.3s ease-in-out infinite alternate;
}

.edit-wobble:nth-child(2n) {
  animation-delay: 0.1s;
  animation-direction: alternate-reverse;
}

.edit-wobble:nth-child(3n) {
  animation-delay: 0.15s;
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

/* ==================== 拖拽样式 ==================== */
.hs-ghost {
  opacity: 0.3;
}

.hs-drag {
  opacity: 0.8;
  transform: scale(1.1);
  z-index: 100;
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
