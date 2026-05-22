import type { YlfAppInfo } from '~~/packages/types'
import { Haptics, ImpactStyle } from '@capacitor/haptics'

export type DropZoneType = 'add' | 'delete' | null

interface DragPosition {
  x: number
  y: number
}

/** 底部 drop zone 区域高度（px） */
const DROP_ZONE_HEIGHT = 100

interface UseRecentDragOptions {
  /** 拖放完成回调 */
  onDrop?: (zone: 'add' | 'delete', app: YlfAppInfo) => void
}

/**
 * 最近使用区域的长按拖拽逻辑
 *
 * 长按后拖动应用图标到底部操作栏，松手执行「添加到我的」或「删除」操作。
 */
export function useRecentDrag(options: UseRecentDragOptions = {}) {
  /** 是否正在拖拽 */
  const isDragging = ref(false)
  /** 拖拽中的应用 */
  const dragApp = ref<YlfAppInfo | null>(null)
  /** 拖拽手指位置 */
  const dragPosition = ref<DragPosition>({ x: 0, y: 0 })
  /** 当前高亮的 drop zone */
  const activeDropZone = ref<DropZoneType>(null)

  /** 上一次 drop zone 状态，用于触发切换时的 haptic */
  let lastDropZone: DropZoneType = null

  /**
   * 从 pointer/touch 事件中提取坐标
   */
  function getEventPosition(event: PointerEvent | TouchEvent): DragPosition {
    if ('touches' in event && event.touches.length > 0) {
      const touch = event.touches[0]!
      return { x: touch.clientX, y: touch.clientY }
    }
    if ('clientX' in event) {
      return { x: event.clientX, y: event.clientY }
    }
    return { x: 0, y: 0 }
  }

  /**
   * 根据坐标判断 drop zone
   */
  function detectDropZone(pos: DragPosition): DropZoneType {
    const windowHeight = window.innerHeight
    const windowWidth = window.innerWidth

    // 距离底部 DROP_ZONE_HEIGHT 内才算进入 drop zone
    if (pos.y < windowHeight - DROP_ZONE_HEIGHT) {
      return null
    }

    // 左半区 → add，右半区 → delete
    return pos.x < windowWidth / 2 ? 'add' : 'delete'
  }

  /**
   * 长按触发后开始拖拽
   */
  function startDrag(app: YlfAppInfo, event: PointerEvent | TouchEvent) {
    const pos = getEventPosition(event)
    dragApp.value = app
    dragPosition.value = pos
    activeDropZone.value = null
    lastDropZone = null
    isDragging.value = true

    Haptics.impact({ style: ImpactStyle.Medium }).catch(() => {})

    // 拖拽期间禁用浏览器右键菜单（长按在桌面浏览器会触发 contextmenu）
    document.addEventListener('contextmenu', preventContextMenu, { capture: true })

    // 注册全局事件监听
    document.addEventListener('pointermove', onDragMove, { passive: false })
    document.addEventListener('pointerup', onDragEnd)
    document.addEventListener('pointercancel', onDragCancel)
    document.addEventListener('touchmove', onTouchMove, { passive: false })
    document.addEventListener('touchend', onTouchEnd)
    document.addEventListener('touchcancel', onDragCancel)
  }

  function onTouchMove(event: TouchEvent) {
    event.preventDefault()
    updateDragPosition(event)
  }

  function onTouchEnd() {
    endDrag()
  }

  function onDragMove(event: PointerEvent) {
    event.preventDefault()
    updateDragPosition(event)
  }

  function onDragEnd() {
    endDrag()
  }

  function onDragCancel() {
    cancelDrag()
  }

  /** 阻止右键菜单 */
  function preventContextMenu(event: Event) {
    event.preventDefault()
  }

  /**
   * 更新拖拽位置并检测 drop zone
   */
  function updateDragPosition(event: PointerEvent | TouchEvent) {
    if (!isDragging.value)
      return

    const pos = getEventPosition(event)
    dragPosition.value = pos

    const zone = detectDropZone(pos)
    activeDropZone.value = zone

    // drop zone 切换时触发 haptic
    if (zone !== lastDropZone) {
      if (zone !== null) {
        Haptics.impact({ style: ImpactStyle.Light }).catch(() => {})
      }
      lastDropZone = zone
    }
  }

  /**
   * 松手：根据 drop zone 执行操作
   */
  function endDrag() {
    const zone = activeDropZone.value
    const app = dragApp.value

    if (zone && app && options.onDrop) {
      Haptics.impact({ style: ImpactStyle.Medium }).catch(() => {})
      options.onDrop(zone, app)
    }

    cleanup()
  }

  /**
   * 取消拖拽
   */
  function cancelDrag() {
    cleanup()
  }

  /**
   * 清理所有状态和事件监听
   */
  function cleanup() {
    isDragging.value = false
    dragApp.value = null
    activeDropZone.value = null
    lastDropZone = null

    document.removeEventListener('contextmenu', preventContextMenu, { capture: true })
    document.removeEventListener('pointermove', onDragMove)
    document.removeEventListener('pointerup', onDragEnd)
    document.removeEventListener('pointercancel', onDragCancel)
    document.removeEventListener('touchmove', onTouchMove)
    document.removeEventListener('touchend', onTouchEnd)
    document.removeEventListener('touchcancel', onDragCancel)
  }

  // 组件卸载时清理
  onUnmounted(() => {
    if (isDragging.value) {
      cleanup()
    }
  })

  return {
    isDragging: readonly(isDragging),
    dragApp: readonly(dragApp),
    dragPosition: readonly(dragPosition),
    activeDropZone: readonly(activeDropZone),
    startDrag,
    cancelDrag,
  }
}
