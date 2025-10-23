/**
 * 长按交互 Composable（基于 VueUse）
 * 用于列表项的点击和长按事件处理
 *
 * @see https://vueuse.org/core/onLongPress/
 */

import type { MaybeElementRef } from '@vueuse/core'
import { onLongPress } from '@vueuse/core'

export interface LongPressOptions {
  /** 长按触发延迟（毫秒）@default 500 */
  delay?: number
  /** 移动容差（像素）@default 10 */
  distanceThreshold?: number
}

export interface LongPressHandlers<T = any> {
  /** 点击回调 */
  onClick?: (item: T, event: PointerEvent) => void
  /** 长按回调 */
  onLongPress?: (item: T, event: PointerEvent) => void
  /** 长按开始回调（用于视觉反馈） */
  onLongPressStart?: (item: T) => void
  /** 长按取消回调 */
  onLongPressCancel?: (item: T) => void
}

/**
 * 列表项长按处理
 * @example
 * const { longPressingId, handlePointerDown, handlePointerUp } = useLongPress({
 *   onClick: (item) => console.log('clicked', item),
 *   onLongPress: (item) => console.log('long pressed', item),
 * })
 */
export function useLongPress<T = any>(
  handlers: LongPressHandlers<T>,
  options: LongPressOptions = {},
) {
  const { delay = 500, distanceThreshold = 10 } = options

  // 状态
  const longPressingId = ref<string | null>(null)
  let currentItem: T | null = null
  let isLongPressed = false
  let cleanup: (() => void) | null = null

  // 重置状态
  function reset() {
    cleanup?.()
    cleanup = null
    longPressingId.value = null
    currentItem = null
    isLongPressed = false
  }

  // 按下
  function handlePointerDown(item: T, event: PointerEvent, id?: string) {
    if (event.button !== 0)
      return

    reset()

    currentItem = item
    if (id)
      longPressingId.value = id

    handlers.onLongPressStart?.(item)

    // 使用 VueUse 的 onLongPress
    const { stop } = onLongPress(
      event.target as MaybeElementRef,
      (e) => {
        isLongPressed = true
        // 触觉反馈
        window.navigator.vibrate?.(50)
        handlers.onLongPress?.(item, e as PointerEvent)
      },
      { delay, distanceThreshold },
    )

    cleanup = stop
  }

  // 移动（VueUse 自动处理，保留接口兼容）
  function handlePointerMove(_event: PointerEvent) {}

  // 抬起
  function handlePointerUp(event: PointerEvent) {
    if (isLongPressed) {
      reset()
      return
    }

    if (currentItem) {
      handlers.onClick?.(currentItem, event)
    }

    reset()
  }

  // 取消
  function handlePointerCancel() {
    if (currentItem && !isLongPressed) {
      handlers.onLongPressCancel?.(currentItem)
    }
    reset()
  }

  onUnmounted(reset)

  return {
    longPressingId: readonly(longPressingId),
    handlePointerDown,
    handlePointerMove,
    handlePointerUp,
    handlePointerCancel,
  }
}
