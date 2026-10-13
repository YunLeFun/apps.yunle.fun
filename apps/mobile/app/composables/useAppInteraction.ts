/**
 * useAppInteraction - 应用交互反馈 Composable
 *
 * @description
 * 提供优化的应用图标点击交互反馈，包括视觉反馈、触觉反馈和性能优化
 *
 * @features
 * - 快速响应（<100ms）
 * - 视觉反馈（缩放、颜色变化）
 * - 触觉反馈（振动）
 * - 性能优化（requestAnimationFrame）
 * - 设备适配（检测性能和偏好设置）
 *
 * @example
 * ```ts
 * const { handleTouchStart, handleTouchEnd, isPressed } = useAppInteraction({
 *   onTap: (app) => console.log('Tapped:', app.name),
 *   enableHaptic: true,
 * })
 * ```
 */

import type { YlfAppInfo } from '@yunlefun/types'
import type { Ref } from 'vue'
import { Haptics } from '@capacitor/haptics'

export interface AppInteractionOptions {
  /** 点击回调 */
  onTap?: (app: YlfAppInfo) => void
  /** 长按回调 */
  onLongPress?: (app: YlfAppInfo, event: PointerEvent | TouchEvent) => void
  /** 是否启用触觉反馈 */
  enableHaptic?: boolean
  /** 是否启用视觉反馈 */
  enableVisualFeedback?: boolean
  /** 点击响应延迟（ms），默认 0 */
  tapDelay?: number
  /** 长按触发时间（ms），默认 500 */
  longPressDelay?: number
}

export interface AppInteractionState {
  /** 当前按下的应用 ID */
  pressedAppId: Ref<string | null>
  /** 是否正在长按 */
  isLongPressing: Ref<boolean>
  /** 是否支持触觉反馈 */
  supportsHaptic: Ref<boolean>
  /** 是否启用动画（根据用户偏好） */
  enableAnimation: Ref<boolean>
  /** 设备性能等级 */
  performanceLevel: Ref<'high' | 'medium' | 'low'>
}

/**
 * 检测设备是否支持触觉反馈
 */
function checkHapticSupport(): boolean {
  if (typeof window === 'undefined')
    return false
  return 'vibrate' in navigator
}

/**
 * 检测用户是否偏好减少动画
 */
function checkReducedMotion(): boolean {
  if (typeof window === 'undefined')
    return false
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

/**
 * 检测设备性能等级
 */
function detectPerformanceLevel(): 'high' | 'medium' | 'low' {
  if (typeof window === 'undefined')
    return 'medium'

  // 基于硬件并发数和内存判断
  const cores = navigator.hardwareConcurrency || 4
  const memory = (navigator as any).deviceMemory || 4

  if (cores >= 8 && memory >= 8)
    return 'high'
  if (cores >= 4 && memory >= 4)
    return 'medium'
  return 'low'
}

/**
 * 触发触觉反馈
 */
function triggerHaptic(pattern: number = 10) {
  if (checkHapticSupport()) {
    try {
      Haptics.vibrate({ duration: pattern })
    }
    catch (error) {
      console.warn('Haptic feedback failed:', error)
    }
  }
}

/**
 * 应用交互反馈 Hook
 */
export function useAppInteraction(options: AppInteractionOptions = {}) {
  const {
    onTap,
    onLongPress,
    enableHaptic = true,
    enableVisualFeedback = true,
    tapDelay = 0,
    longPressDelay = 500,
  } = options

  // 状态管理
  const pressedAppId = ref<string | null>(null)
  const isLongPressing = ref(false)
  const supportsHaptic = ref(checkHapticSupport())
  const enableAnimation = ref(!checkReducedMotion())
  const performanceLevel = ref(detectPerformanceLevel())

  // 长按定时器
  let longPressTimer: ReturnType<typeof setTimeout> | null = null
  let tapTimer: ReturnType<typeof setTimeout> | null = null
  let animationFrameId: number | null = null

  // 触摸起始时间（用于性能监控）
  let touchStartTime = 0

  /**
   * 处理触摸开始
   */
  function handleTouchStart(app: YlfAppInfo, event: PointerEvent | TouchEvent) {
    touchStartTime = performance.now()

    // 使用 RAF 优化性能
    if (animationFrameId)
      cancelAnimationFrame(animationFrameId)

    animationFrameId = requestAnimationFrame(() => {
      // 设置按下状态
      pressedAppId.value = app.id

      // 触发轻微触觉反馈
      if (enableHaptic && supportsHaptic.value) {
        triggerHaptic(10) // 10ms 轻微振动
      }

      // 启动长按检测
      longPressTimer = setTimeout(() => {
        isLongPressing.value = true

        // 长按触觉反馈（稍强）
        if (enableHaptic && supportsHaptic.value) {
          triggerHaptic(30) // 30ms 中等振动
        }

        // 触发长按回调
        if (onLongPress) {
          onLongPress(app, event)
        }
      }, longPressDelay)
    })
  }

  /**
   * 处理触摸结束
   */
  function handleTouchEnd(app: YlfAppInfo) {
    const touchEndTime = performance.now()
    const duration = touchEndTime - touchStartTime

    // 清理定时器
    if (longPressTimer) {
      clearTimeout(longPressTimer)
      longPressTimer = null
    }

    // 如果不是长按，触发点击
    if (!isLongPressing.value) {
      // 根据性能等级调整延迟
      const actualDelay = performanceLevel.value === 'low' ? Math.max(tapDelay, 50) : tapDelay

      tapTimer = setTimeout(() => {
        if (onTap) {
          onTap(app)
        }

        // 性能监控：如果响应时间超过 100ms，发出警告
        if (duration > 100) {
          console.warn(`Slow interaction detected: ${duration.toFixed(2)}ms`)
        }
      }, actualDelay)
    }

    // 延迟重置状态，保持视觉反馈
    setTimeout(() => {
      pressedAppId.value = null
      isLongPressing.value = false
    }, enableAnimation.value ? 150 : 0)
  }

  /**
   * 处理触摸取消
   */
  function handleTouchCancel() {
    if (longPressTimer) {
      clearTimeout(longPressTimer)
      longPressTimer = null
    }
    if (tapTimer) {
      clearTimeout(tapTimer)
      tapTimer = null
    }
    if (animationFrameId) {
      cancelAnimationFrame(animationFrameId)
      animationFrameId = null
    }

    pressedAppId.value = null
    isLongPressing.value = false
  }

  /**
   * 检查应用是否被按下
   */
  function isAppPressed(appId: string): boolean {
    return pressedAppId.value === appId
  }

  /**
   * 获取应用的交互样式类
   */
  function getInteractionClass(appId: string): Record<string, boolean> {
    return {
      'is-pressed': isAppPressed(appId),
      'is-long-pressing': isLongPressing.value && isAppPressed(appId),
      'no-animation': !enableAnimation.value,
    }
  }

  /**
   * 获取应用的交互样式
   */
  function getInteractionStyle(appId: string): Record<string, string> {
    if (!enableVisualFeedback || !isAppPressed(appId))
      return {}

    // 根据性能等级调整动画
    const scale = isLongPressing.value ? '0.92' : '0.95'
    const transition = performanceLevel.value === 'high'
      ? 'transform 0.1s cubic-bezier(0.4, 0, 0.2, 1)'
      : 'transform 0.15s ease-out'

    return {
      transform: `scale(${scale})`,
      transition: enableAnimation.value ? transition : 'none',
    }
  }

  // 监听用户偏好变化
  if (typeof window !== 'undefined') {
    const mediaQuery = window.matchMedia('(prefers-reduced-motion: reduce)')
    const handleChange = (e: MediaQueryListEvent) => {
      enableAnimation.value = !e.matches
    }

    if (mediaQuery.addEventListener) {
      mediaQuery.addEventListener('change', handleChange)
    }

    // 清理
    onUnmounted(() => {
      if (mediaQuery.removeEventListener) {
        mediaQuery.removeEventListener('change', handleChange)
      }
      handleTouchCancel()
    })
  }

  return {
    // 状态
    pressedAppId: readonly(pressedAppId),
    isLongPressing: readonly(isLongPressing),
    supportsHaptic: readonly(supportsHaptic),
    enableAnimation: readonly(enableAnimation),
    performanceLevel: readonly(performanceLevel),

    // 方法
    handleTouchStart,
    handleTouchEnd,
    handleTouchCancel,
    isAppPressed,
    getInteractionClass,
    getInteractionStyle,
    triggerHaptic,
  }
}

/**
 * 预设的触觉反馈模式
 */
export const HapticPatterns = {
  /** 轻触 */
  light: 10,
  /** 中等 */
  medium: 30,
  /** 重击 */
  heavy: 50,
  /** 成功 */
  success: [10, 50, 10],
  /** 警告 */
  warning: [30, 100, 30],
  /** 错误 */
  error: [50, 100, 50, 100, 50],
} as const
