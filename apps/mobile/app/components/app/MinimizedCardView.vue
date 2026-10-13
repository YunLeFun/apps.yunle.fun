<script setup lang="ts">
import type { PreviewWindowSize } from '~/stores/settings'
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'

withDefaults(defineProps<{
  size?: PreviewWindowSize
  name: string
  previewImage?: string
  logo?: string
  emoji?: string
  pending?: boolean
}>(), { pending: false, size: 'medium' })
const emit = defineEmits<{ resume: [], end: [] }>()
const region = ref<HTMLElement>()
const card = ref<HTMLElement>()
const x = ref(0)
const y = ref(0)
const ready = ref(false)
const dragging = ref(false)
let side: 'left' | 'right' = 'right'
let gesture: { id: number, x: number, y: number, left: number, top: number } | undefined
let suppressClick = false
let observer: ResizeObserver | undefined
const position = computed(() => ({ transform: `translate3d(${x.value}px, ${y.value}px, 0)`, visibility: ready.value ? 'visible' as const : 'hidden' as const }))

function bounds() {
  return {
    width: Math.max(0, (region.value?.clientWidth ?? 0) - (card.value?.offsetWidth ?? 0)),
    height: Math.max(0, (region.value?.clientHeight ?? 0) - (card.value?.offsetHeight ?? 0)),
  }
}
function constrain(snap = false) {
  const { width, height } = bounds()
  x.value = snap ? (side === 'right' ? width : 0) : Math.max(0, Math.min(width, x.value))
  y.value = Math.max(0, Math.min(height, y.value))
}
function start(event: PointerEvent) {
  if (!event.isPrimary || event.button !== 0)
    return
  suppressClick = false
  gesture = { id: event.pointerId, x: event.clientX, y: event.clientY, left: x.value, top: y.value }
}
function move(event: PointerEvent) {
  if (!gesture || event.pointerId !== gesture.id)
    return
  const dx = event.clientX - gesture.x
  const dy = event.clientY - gesture.y
  if (!dragging.value && Math.hypot(dx, dy) < 8)
    return
  dragging.value = true
  suppressClick = true
  card.value?.setPointerCapture(event.pointerId)
  x.value = gesture.left + dx
  y.value = gesture.top + dy
  constrain()
}
function finish(event: PointerEvent) {
  if (!gesture || event.pointerId !== gesture.id)
    return
  if (dragging.value) {
    side = x.value + (card.value?.offsetWidth ?? 0) / 2 > (region.value?.clientWidth ?? 0) / 2 ? 'right' : 'left'
    constrain(true)
  }
  gesture = undefined
  dragging.value = false
  if (card.value?.hasPointerCapture(event.pointerId))
    card.value.releasePointerCapture(event.pointerId)
}
function activate(_event: MouseEvent, action: 'resume' | 'end') {
  // Touch-generated clicks can also have detail=0 in WKWebView.
  // Keyboard input explicitly clears this guard in keydown.
  if (suppressClick) {
    suppressClick = false
    return
  }
  if (action === 'resume')
    emit('resume')
  else
    emit('end')
}
onMounted(async () => {
  await nextTick()
  y.value = 16
  constrain(true)
  ready.value = true
  observer = new ResizeObserver(() => constrain(true))
  if (region.value)
    observer.observe(region.value)
  if (card.value)
    observer.observe(card.value)
})
onBeforeUnmount(() => observer?.disconnect())
</script>

<template>
  <div ref="region" class="minimized-region">
    <aside
      ref="card"
      class="minimized-card"
      :class="{ 'is-dragging': dragging }"
      :data-size="size"
      :style="position"
      aria-label="已收起的应用"
      :aria-busy="pending"
      @pointerdown="start"
      @pointermove="move"
      @pointerup="finish"
      @pointercancel="finish"
      @lostpointercapture="finish"
      @keydown="suppressClick = false"
    >
      <button class="restore" type="button" :disabled="pending" :aria-label="`恢复${name}`" @click="activate($event, 'resume')">
        <span class="page-preview">
          <img v-if="previewImage" :src="previewImage" :alt="`${name}收起时的网页预览`" draggable="false">
          <span v-else class="preview-fallback">
            <span aria-hidden="true">{{ emoji || '🌐' }}</span>
            <span>暂无法预览</span>
          </span>
        </span>
        <span class="caption">
          <img v-if="logo" :src="logo" class="app-icon" alt="" draggable="false">
          <span v-else class="app-icon emoji" aria-hidden="true">{{ emoji || '🌐' }}</span>
          <span class="name" :title="name">{{ name }}</span>
        </span>
      </button>
      <button class="end" type="button" :disabled="pending" :aria-label="`结束${name}`" @click="activate($event, 'end')">
        <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" /></svg>
      </button>
    </aside>
  </div>
</template>

<style scoped>
.minimized-region {
  position: fixed;
  inset: calc(env(safe-area-inset-top, 0px) + 64px) calc(env(safe-area-inset-right, 0px) + 12px)
    calc(env(safe-area-inset-bottom, 0px) + 84px) calc(env(safe-area-inset-left, 0px) + 12px);
  pointer-events: none;
  z-index: 100;
}
.minimized-card {
  box-sizing: border-box;
  position: absolute;
  top: 0;
  left: 0;
  display: flex;
  --preview-height: 196px;
  --caption-background: #fff;
  --caption-color: #242426;
  --caption-divider: rgb(0 0 0 / 6%);
  width: 168px;
  max-width: 100%;
  border: 1px solid var(--ylf-separator, rgba(120, 120, 128, 0.22));
  border-radius: 14px;
  background: var(--ion-background-color, #fff);
  color: var(--ion-text-color, #171717);
  box-shadow:
    0 8px 24px rgb(0 0 0 / 14%),
    0 2px 6px rgb(0 0 0 / 6%);
  pointer-events: auto;
  touch-action: none;
  user-select: none;
  transition: transform 180ms ease;
  overflow: hidden;
}
.minimized-card[data-size='mini'] {
  width: 136px;
  --preview-height: 152px;
}
.minimized-card[data-size='large'] {
  width: 216px;
  --preview-height: 288px;
}
.minimized-card.is-dragging {
  transition: none;
  cursor: grabbing;
}
button {
  border: 0;
  background: transparent;
  color: inherit;
  cursor: pointer;
  font: inherit;
}
button:focus-visible {
  outline: 2px solid var(--ion-color-primary, #007aff);
  outline-offset: -3px;
  border-radius: 16px;
}
button:active {
  background: var(--ylf-fill-secondary, rgba(120, 120, 128, 0.12));
}
button:disabled {
  opacity: 0.6;
}
.restore {
  display: flex;
  align-items: center;
  flex-direction: column;
  min-width: 0;
  width: 100%;
  padding: 0;
  text-align: start;
  min-height: 48px;
}
.page-preview {
  display: block;
  width: 100%;
  height: min(var(--preview-height), 45dvh);
  overflow: hidden;
  background: var(--ion-background-color, #fff);
}
.page-preview > img {
  width: 100%;
  height: 100%;
  display: block;
  object-fit: cover;
  object-position: top;
  pointer-events: none;
}
.caption {
  position: relative;
  background: var(--caption-background);
  color: var(--caption-color);
  width: 100%;
  box-sizing: border-box;
  height: 28px;
  padding: 6px 8px;
  display: flex;
  gap: 6px;
  align-items: center;
}
.caption::before {
  content: '';
  position: absolute;
  inset: 0 0 auto;
  height: 1px;
  background: var(--caption-divider);
  transform: scaleY(0.5);
  transform-origin: top;
  pointer-events: none;
}
:global(.dark .minimized-card) {
  --caption-background: #1c1c1e;
  --caption-color: #ebebef;
  --caption-divider: rgb(255 255 255 / 8%);
}
.preview-fallback {
  display: flex;
  height: 100%;
  align-items: center;
  justify-content: center;
  flex-direction: column;
  gap: 12px;
  color: var(--ion-color-medium, #737373);
  font-size: 13px;
}
.preview-fallback > :first-child {
  font-size: 40px;
}
.app-icon {
  width: 16px;
  height: 16px;
  border-radius: 4px;
  flex-shrink: 0;
  object-fit: cover;
}
.emoji {
  display: grid;
  place-items: center;
  font-size: 14px;
  background: transparent;
}
.name {
  min-width: 0;
  font-size: 12px;
  line-height: 16px;
  font-weight: 500;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.end {
  position: absolute;
  top: 0;
  right: 0;
  border-radius: 50%;
  background: transparent;
  color: white;
  flex-shrink: 0;
  display: grid;
  place-items: center;
  width: 44px;
  height: 44px;
}
.end::before {
  content: '';
  position: absolute;
  inset: 10px;
  border-radius: 50%;
  background: rgb(0 0 0 / 55%);
}
.end svg {
  position: relative;
}
.end:active {
  background: transparent;
}
.end:active::before {
  background: rgb(0 0 0 / 75%);
}
@media (prefers-reduced-motion: reduce) {
  .minimized-card {
    transition: none;
  }
}
</style>
