# Home Screen 拖拽排序

## 架构概述

Home Screen 的拖拽排序基于 [SortableJS](https://sortablejs.github.io/Sortable/)（通过 `vue-draggable-plus` 封装），对齐 iOS SpringBoard 的交互模型。

### 交互状态机

```
┌─────────────────┐     长按图标 500ms      ┌───────────────────┐
│   非编辑模式     │ ──────────────────────→ │   上下文菜单       │
│                 │     长按空白 500ms       │                   │
│ SortableJS OFF  │ ───────┐                │  · 编辑主屏幕      │
│ 自定义长按 ON    │        │                │  · 分享 App        │
└─────────────────┘        │                │  · 移除 App        │
        ↑                  │                └───────────────────┘
        │                  │                    │ 点击"编辑"    │ 手指移动 >10px
        │ 点击"完成"      ↓                    ↓               ↓
        │            ┌─────────────────┐ ←──────────────────────
        └─────────── │   编辑模式       │
                     │                 │
                     │ SortableJS ON   │  触摸图标 → 立即拖拽
                     │ 自定义长按 OFF   │  SortableJS 内置让位动画
                     │ 图标抖动         │
                     └─────────────────┘
```

### 关键设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 拖拽引擎 | SortableJS（vue-draggable-plus） | 成熟库，内置 FLIP 让位动画、触屏优化、性能优化 |
| 拖拽模式 | `force-fallback: true` + `fallback-on-body: true` | fallback 模式创建 clone 跟随手指；挂到 body 避免被 `overflow: hidden` 裁剪 |
| 编辑/非编辑切换 | SortableJS `:disabled="!editMode"` | 非编辑模式下 SortableJS 完全不干预事件流 |
| 长按检测 | 自定义 `setTimeout` 500ms | 非编辑模式下使用，与 SortableJS 互斥，避免事件竞争 |

## ⚠️ 关键约束（踩坑记录）

### 1. 拖拽 clone 的 CSS **禁止设置 `transform`**

```css
/* ❌ 错误：CSS transform 会覆盖 SortableJS 的位移计算 */
.hs-drag {
  transform: scale(1.15);
}

/* ✅ 正确：让 SortableJS 完全控制 transform */
.hs-drag {
  filter: drop-shadow(0 10px 30px rgba(0, 0, 0, 0.3));
  z-index: 100000 !important;
}
```

**原理**：SortableJS fallback 模式通过 `element.style.transform = matrix(...)` 控制 clone 跟随手指。CSS 类中的 `transform` 值会与 inline style 竞争，导致位移分量被重置为 0。

### 2. 拖拽样式必须是**全局样式**（非 scoped）

```vue
<!-- ❌ scoped 样式无法匹配 body 上的 clone -->
<style scoped>
.hs-drag { ... }
</style>

<!-- ✅ 全局样式匹配 fallbackOnBody 的 clone -->
<style>
.hs-drag { ... }
</style>
```

**原理**：`fallback-on-body` 将 clone 挂到 `document.body`，不在组件 DOM 树内，Vue scoped 的 `data-v-xxx` 属性选择器不会匹配。

### 3. 编辑模式下**禁止滚动容器滚动**

```css
.hs-scroll-container.no-scroll {
  overflow-x: hidden;
  scroll-snap-type: none;
}
```

**原理**：`overflow-x: auto` + `scroll-snap-type: x mandatory` 的滚动容器会把横向拖拽手势判定为"翻页滚动"，吞掉 `pointermove` 事件，SortableJS 收不到手指移动。

### 4. 编辑模式下 grid item **不注册自定义 pointer 事件**

```vue
<!-- 动态绑定：编辑模式下让 SortableJS 完全接管 -->
<div v-on="editMode ? {} : { pointerdown, pointermove, ... }">
```

**原理**：自定义 pointer 事件处理器可能干扰 SortableJS 的事件链（pointer capture、preventDefault 等）。

### 5. grid item **不设 `touch-action: none`**

**原理**：`touch-action: none` 在某些浏览器上会导致 pointer 事件序列被提前取消，SortableJS 的 fallback 模式依赖完整的 pointer 事件流。

### 6. 上下文菜单浮动图标隐藏原始图标用 `visibility: hidden`

```css
.hs-hidden { visibility: hidden; }  /* ✅ 保留占位空间 */
/* display: none 会导致布局跳动 */
```

## 文件清单

| 文件 | 职责 |
|------|------|
| `app/components/app/HomeScreenGrid.vue` | Grid 网格 + SortableJS 拖拽 + 长按检测 |
| `app/components/app/HomeScreenDock.vue` | Dock 常用栏 + 拖拽排序 |
| `app/components/app/ContextMenu.vue` | 上下文菜单（纯 UI，不含拖拽逻辑） |
| `app/pages/tabs/home.vue` | 页面编排，连接 Grid/Dock/ContextMenu |
| `app/stores/homeScreen.ts` | Home Screen 状态（editMode、installedApps、dockApps） |
| `test/unit/contextMenuDrag.test.ts` | 交互状态机和 CSS 约束的单元测试 |
