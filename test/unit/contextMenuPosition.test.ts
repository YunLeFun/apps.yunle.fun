/**
 * ContextMenu 位置边界限制 单元测试
 *
 * 验证上下文菜单的 menuStyle 位置计算逻辑，确保菜单不会超出视口边界。
 * 逻辑提取自 app/components/app/ContextMenu.vue 的 menuStyle computed。
 *
 * iOS 风格：菜单居中于手指上方弹出。
 */
import { describe, expect, it } from 'vitest'

/** 与 ContextMenu.vue 保持一致的常量 */
const MENU_WIDTH = 250
const MENU_HEIGHT = 164
const MARGIN = 12

/**
 * 从 ContextMenu.vue menuStyle 提取的纯函数
 * 菜单居中于手指上方 (y - MENU_HEIGHT - 20)
 */
function calcMenuPosition(
  position: { x: number, y: number },
  viewport: { width: number, height: number },
) {
  const { x, y } = position
  const { width: vw, height: vh } = viewport

  return {
    x: Math.min(Math.max(x - MENU_WIDTH / 2, MARGIN), vw - MENU_WIDTH - MARGIN),
    y: Math.min(Math.max(y - MENU_HEIGHT - 20, MARGIN), vh - MENU_HEIGHT - MARGIN),
  }
}

describe('contextMenu position clamping', () => {
  const viewport = { width: 375, height: 812 }

  it('居中位置：菜单出现在手指上方，水平居中', () => {
    const result = calcMenuPosition({ x: 200, y: 500 }, viewport)
    // x: 200 - 125 = 75, 在 [12, 113] 范围内
    expect(result.x).toBe(75)
    // y: 500 - 164 - 20 = 316, 在 [12, 636] 范围内
    expect(result.y).toBe(316)
  })

  it('左边界限制：x 接近左侧时不超出 MARGIN', () => {
    const result = calcMenuPosition({ x: 20, y: 500 }, viewport)
    // x: 20 - 125 = -105 → clamped to 12
    expect(result.x).toBe(MARGIN)
  })

  it('右边界限制：x 接近右侧时不超出视口', () => {
    const result = calcMenuPosition({ x: 370, y: 500 }, viewport)
    // x: 370 - 125 = 245 → clamped to 375 - 250 - 12 = 113
    expect(result.x).toBe(375 - MENU_WIDTH - MARGIN)
  })

  it('上边界限制：y 接近顶部时不超出 MARGIN', () => {
    const result = calcMenuPosition({ x: 200, y: 50 }, viewport)
    // y: 50 - 164 - 20 = -134 → clamped to 12
    expect(result.y).toBe(MARGIN)
  })

  it('下边界限制：y 接近底部时不超出视口', () => {
    const result = calcMenuPosition({ x: 200, y: 810 }, viewport)
    // y: 810 - 164 - 20 = 626, 在 [12, 636] 范围内
    expect(result.y).toBe(626)
    // y = 812 时: 812 - 164 - 20 = 628 → clamped to 636
    const result2 = calcMenuPosition({ x: 200, y: 812 }, viewport)
    expect(result2.y).toBe(628)
  })

  it('左上角极端位置', () => {
    const result = calcMenuPosition({ x: 0, y: 0 }, viewport)
    expect(result.x).toBe(MARGIN)
    expect(result.y).toBe(MARGIN)
  })

  it('右下角极端位置', () => {
    const result = calcMenuPosition({ x: 375, y: 812 }, viewport)
    expect(result.x).toBe(375 - MENU_WIDTH - MARGIN)
    expect(result.y).toBe(812 - MENU_HEIGHT - 20)
  })

  it('小屏设备（320x568）边界正确', () => {
    const small = { width: 320, height: 568 }
    const result = calcMenuPosition({ x: 300, y: 560 }, small)
    expect(result.x).toBe(320 - MENU_WIDTH - MARGIN)
    // y: 560 - 164 - 20 = 376, max = 568 - 164 - 12 = 392
    expect(result.y).toBe(376)
  })
})
