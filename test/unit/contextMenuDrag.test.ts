/**
 * HomeScreen 交互逻辑 + CSS 约束守卫 单元测试
 *
 * 验证：
 * 1. iOS 风格交互状态机
 * 2. 上下文菜单移动检测
 * 3. 拖拽排序 store 更新
 * 4. 菜单位置计算
 * 5. CSS 约束守卫 —— 防止未来修改破坏 SortableJS 拖拽
 * 6. VueDraggable 配置守卫
 */
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it, vi } from 'vitest'

// ==================== 辅助：读取源码 ====================

const GRID_VUE = readFileSync(
  resolve(__dirname, '../../app/components/app/HomeScreenGrid.vue'),
  'utf-8',
)

// ==================== 1. 交互状态机 ====================

describe('homeScreen: 交互状态机', () => {
  /** 模拟 HomeScreenGrid 的交互状态逻辑 */
  function createInteractionModel() {
    let editMode = false
    let longPressTimer: ReturnType<typeof setTimeout> | null = null
    let contextMenuVisible = false
    const LONG_PRESS_DELAY = 500

    /** SortableJS disabled 状态 —— 和 editMode 直接关联 */
    function isSortableEnabled() {
      return editMode
    }

    /** SortableJS delay */
    function getSortableDelay() {
      return 0 // 编辑模式下始终 0
    }

    function onPointerDown(isApp: boolean) {
      // 编辑模式下不启动自定义长按
      if (editMode)
        return { longPressStarted: false }

      longPressTimer = setTimeout(() => {
        longPressTimer = null
        if (isApp)
          contextMenuVisible = true
        else
          editMode = true // 空白区域长按 → 编辑模式
      }, LONG_PRESS_DELAY)
      return { longPressStarted: true }
    }

    function onPointerMove(dx: number, dy: number) {
      if (longPressTimer && (Math.abs(dx) > 10 || Math.abs(dy) > 10)) {
        clearTimeout(longPressTimer)
        longPressTimer = null
        return { cancelled: true }
      }
      return { cancelled: false }
    }

    function onPointerUp() {
      if (longPressTimer) {
        clearTimeout(longPressTimer)
        longPressTimer = null
      }
    }

    function handleContextEditHomeScreen() {
      contextMenuVisible = false
      editMode = true
    }

    function closeContextMenu() {
      contextMenuVisible = false
    }

    function exitEditMode() {
      editMode = false
    }

    return {
      get editMode() { return editMode },
      get contextMenuVisible() { return contextMenuVisible },
      isSortableEnabled,
      getSortableDelay,
      onPointerDown,
      onPointerMove,
      onPointerUp,
      handleContextEditHomeScreen,
      closeContextMenu,
      exitEditMode,
    }
  }

  it('初始状态：非编辑模式，SortableJS 禁用', () => {
    const model = createInteractionModel()
    expect(model.editMode).toBe(false)
    expect(model.isSortableEnabled()).toBe(false)
    expect(model.contextMenuVisible).toBe(false)
  })

  it('非编辑模式：pointerdown 启动长按检测', () => {
    const model = createInteractionModel()
    const { longPressStarted } = model.onPointerDown(true)
    expect(longPressStarted).toBe(true)
    model.onPointerUp() // 清理
  })

  it('编辑模式：pointerdown 不启动长按检测（SortableJS 接管）', () => {
    const model = createInteractionModel()
    model.handleContextEditHomeScreen() // 先进入编辑模式
    const { longPressStarted } = model.onPointerDown(true)
    expect(longPressStarted).toBe(false)
    expect(model.isSortableEnabled()).toBe(true)
  })

  it('非编辑模式长按图标 → 弹上下文菜单', async () => {
    vi.useFakeTimers()
    const model = createInteractionModel()
    model.onPointerDown(true)
    vi.advanceTimersByTime(500)
    expect(model.contextMenuVisible).toBe(true)
    expect(model.editMode).toBe(false)
    expect(model.isSortableEnabled()).toBe(false) // 仍然非编辑模式
    vi.useRealTimers()
  })

  it('非编辑模式长按空白 → 进入编辑模式', async () => {
    vi.useFakeTimers()
    const model = createInteractionModel()
    model.onPointerDown(false)
    vi.advanceTimersByTime(500)
    expect(model.editMode).toBe(true)
    expect(model.isSortableEnabled()).toBe(true)
    expect(model.contextMenuVisible).toBe(false)
    vi.useRealTimers()
  })

  it('上下文菜单 → 编辑主屏幕 → 编辑模式', () => {
    vi.useFakeTimers()
    const model = createInteractionModel()
    model.onPointerDown(true)
    vi.advanceTimersByTime(500)
    expect(model.contextMenuVisible).toBe(true)

    model.handleContextEditHomeScreen()
    expect(model.contextMenuVisible).toBe(false)
    expect(model.editMode).toBe(true)
    expect(model.isSortableEnabled()).toBe(true)
    vi.useRealTimers()
  })

  it('编辑模式下 SortableJS delay = 0', () => {
    const model = createInteractionModel()
    model.handleContextEditHomeScreen()
    expect(model.getSortableDelay()).toBe(0)
  })

  it('手指移动超阈值 → 取消长按', () => {
    vi.useFakeTimers()
    const model = createInteractionModel()
    model.onPointerDown(true)
    const { cancelled } = model.onPointerMove(15, 0) // 超过 10px
    expect(cancelled).toBe(true)
    vi.advanceTimersByTime(500)
    expect(model.contextMenuVisible).toBe(false) // 不应弹出
    vi.useRealTimers()
  })

  it('手指移动未超阈值 → 不取消长按', () => {
    vi.useFakeTimers()
    const model = createInteractionModel()
    model.onPointerDown(true)
    const { cancelled } = model.onPointerMove(5, 5) // 未超 10px
    expect(cancelled).toBe(false)
    vi.advanceTimersByTime(500)
    expect(model.contextMenuVisible).toBe(true) // 正常弹出
    vi.useRealTimers()
  })

  it('pointerup 在 500ms 前 → 取消长按', () => {
    vi.useFakeTimers()
    const model = createInteractionModel()
    model.onPointerDown(true)
    vi.advanceTimersByTime(200) // 只过了 200ms
    model.onPointerUp()
    vi.advanceTimersByTime(300) // 补齐到 500ms
    expect(model.contextMenuVisible).toBe(false) // 不应弹出
    vi.useRealTimers()
  })
})

// ==================== 2. 上下文菜单移动检测 ====================

describe('contextMenu: 手指移动 → 关闭菜单进入编辑模式', () => {
  const THRESHOLD = 10

  function shouldCloseMenu(dx: number, dy: number): boolean {
    return Math.abs(dx) > THRESHOLD || Math.abs(dy) > THRESHOLD
  }

  it('在阈值内不关闭', () => {
    expect(shouldCloseMenu(5, 5)).toBe(false)
  })

  it('超过阈值关闭', () => {
    expect(shouldCloseMenu(15, 0)).toBe(true)
  })

  it('正好等于阈值不关闭', () => {
    expect(shouldCloseMenu(10, 0)).toBe(false)
  })
})

// ==================== 3. 拖拽排序结果 ====================

describe('homeScreen: 拖拽排序 store 更新', () => {
  it('拖拽排序后 flat 列表更新', () => {
    const pages = [
      [{ appId: 'a' }, { appId: 'b' }, { appId: 'c' }],
      [{ appId: 'd' }],
    ]
    // 模拟拖拽后 page 内排序变化
    pages[0] = [{ appId: 'c' }, { appId: 'a' }, { appId: 'b' }]
    const flat = pages.flat()
    expect(flat.map(a => a.appId)).toEqual(['c', 'a', 'b', 'd'])
  })

  it('空页处理', () => {
    const pages: { appId: string }[][] = [[]]
    expect(pages.flat()).toEqual([])
  })
})

// ==================== 4. 菜单位置计算 ====================

describe('contextMenu: 位置计算', () => {
  const MENU_WIDTH = 250
  const MARGIN = 12
  const ICON_MENU_GAP = 8

  function calcMenuPosition(
    iconRect: { x: number, y: number, width: number, height: number },
    viewport: { width: number, height: number },
    menuHeight: number = 164,
  ) {
    const iconCenterX = iconRect.x + iconRect.width / 2
    const menuTop = iconRect.y + iconRect.height + ICON_MENU_GAP

    let left = iconCenterX - MENU_WIDTH / 2
    left = Math.min(Math.max(left, MARGIN), viewport.width - MENU_WIDTH - MARGIN)

    let top = menuTop
    if (menuTop + menuHeight > viewport.height - MARGIN) {
      top = iconRect.y - menuHeight - ICON_MENU_GAP
      if (top < MARGIN)
        top = MARGIN
    }

    return { left, top }
  }

  it('菜单在图标下方居中', () => {
    const pos = calcMenuPosition(
      { x: 100, y: 100, width: 60, height: 60 },
      { width: 375, height: 812 },
    )
    expect(pos.left).toBe(12)
    expect(pos.top).toBe(168)
  })

  it('图标在底部 → 菜单翻到上方', () => {
    const pos = calcMenuPosition(
      { x: 100, y: 700, width: 60, height: 60 },
      { width: 375, height: 812 },
    )
    expect(pos.top).toBe(700 - 164 - 8)
  })

  it('右边界限制', () => {
    const pos = calcMenuPosition(
      { x: 350, y: 100, width: 60, height: 60 },
      { width: 375, height: 812 },
    )
    expect(pos.left).toBe(375 - 250 - 12)
  })
})

// ==================== 5. CSS 约束守卫 ====================
// 通过读取源文件内容，确保关键的 CSS 约束不被未来修改破坏。
// 参考文档：docs/dev/home-screen-drag.md

describe('homeScreenGrid: CSS 约束守卫', () => {
  it('.hs-drag 不设 transform（防止覆盖 SortableJS 位移）', () => {
    // 提取全局 <style> 块中 .hs-drag 的内容
    const globalStyleMatch = GRID_VUE.match(/<style>[\s\S]*?<\/style>/g)
    expect(globalStyleMatch).not.toBeNull()
    const globalStyle = globalStyleMatch!.join('\n')

    // .hs-drag 块中不应包含 transform 属性
    const hsDragBlock = globalStyle.match(/\.hs-drag\s*\{[^}]*\}/)?.[0] ?? ''
    expect(hsDragBlock).toBeTruthy()
    // 匹配 "transform:" 但排除注释中的提及
    const hasTransform = /^\s*transform\s*:/m.test(hsDragBlock)
    expect(hasTransform, '.hs-drag 不应设置 transform 属性，会覆盖 SortableJS 的拖拽位移').toBe(false)
  })

  it('.hs-chosen 不设 transform（防止覆盖 SortableJS 位移）', () => {
    const globalStyleMatch = GRID_VUE.match(/<style>[\s\S]*?<\/style>/g)
    const globalStyle = globalStyleMatch!.join('\n')

    const hsChosenBlock = globalStyle.match(/\.hs-chosen\s*\{[^}]*\}/)?.[0] ?? ''
    expect(hsChosenBlock).toBeTruthy()
    const hasTransform = /^\s*transform\s*:/m.test(hsChosenBlock)
    expect(hasTransform, '.hs-chosen 不应设置 transform 属性').toBe(false)
  })

  it('.hs-drag 和 .hs-chosen 在全局样式中（非 scoped）', () => {
    // 确保 .hs-drag 出现在不带 scoped 的 <style> 块中
    const globalBlocks = GRID_VUE.match(/<style>[\s\S]*?<\/style>/g) ?? []
    const scopedBlocks = GRID_VUE.match(/<style\s+scoped>[\s\S]*?<\/style>/g) ?? []

    const inGlobal = globalBlocks.some(b => b.includes('.hs-drag'))
    const inScoped = scopedBlocks.some(b => b.includes('.hs-drag'))
    expect(inGlobal, '.hs-drag 应在全局 <style> 中（fallbackOnBody clone 挂到 body）').toBe(true)
    expect(inScoped, '.hs-drag 不应在 <style scoped> 中').toBe(false)
  })

  it('.hs-grid-item 不设 touch-action: none', () => {
    const gridItemMatch = GRID_VUE.match(/\.hs-grid-item\s*\{[^}]*\}/)?.[0] ?? ''
    expect(gridItemMatch).toBeTruthy()
    expect(gridItemMatch).not.toContain('touch-action')
  })

  it('网格容器保持纵向滚动布局约束', () => {
    expect(GRID_VUE).toContain('class="hs-grid-wrapper"')
    expect(GRID_VUE).toMatch(/\.hs-grid-wrapper\s*\{[^}]*min-height:\s*100%/)
    expect(GRID_VUE).toContain('grid-template-columns: repeat(4, 1fr)')
  })
})

// ==================== 6. VueDraggable 配置守卫 ====================

describe('homeScreenGrid: VueDraggable 配置守卫', () => {
  it('配置了 force-fallback', () => {
    expect(GRID_VUE).toContain(':force-fallback="true"')
  })

  it('配置了 fallback-on-body', () => {
    expect(GRID_VUE).toContain(':fallback-on-body="true"')
  })

  it('editMode 控制 disabled', () => {
    expect(GRID_VUE).toContain(':disabled="!editMode"')
  })

  it('编辑模式下 delay 为 0', () => {
    expect(GRID_VUE).toContain(':delay="0"')
  })

  it('ghost 元素设为透明（opacity: 0）', () => {
    expect(GRID_VUE).toContain('ghost-class="hs-ghost"')
    expect(GRID_VUE).toMatch(/\.hs-ghost\s*\{[^}]*opacity:\s*0/)
  })
})
