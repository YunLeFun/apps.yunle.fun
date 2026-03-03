# 云居 - Home Screen

云居是用户的个人桌面，采用类 iOS Home Screen 的设计风格。

## 功能模块

### 1. 主体桌面网格

- 翻页式应用网格，每页 **4×6 = 24** 个应用
- 支持左右滑动翻页，底部页码指示器
- 图标样式与 iOS 桌面保持一致

### 2. 底部 Dock

- 固定 **4 个**常用应用
- 仅展示图标，无应用名称
- 毛玻璃背景效果

### 3. 编辑模式

- **长按**任意图标触发编辑模式
- 触觉反馈（Haptics）
- 图标抖动动画 + 左上角删除按钮
- 支持**拖拽排序**（基于 `vue-draggable-plus`）
- 点击空白区域退出编辑模式

### 4. 最近使用

- 自动记录最近使用过的云应用
- 默认展示 4 个，可展开查看最多 100 个

## 数据同步

```text
用户操作 → homeScreenStore (Pinia + localStorage)
                ↓ 防抖 500ms
        useHomeScreen.syncToCloud()
                ↓
        CloudBase user_desktops 集合
```

- 本地 localStorage 作为缓存层，确保离线可用
- 写入操作 500ms 防抖后异步同步到 CloudBase
- 多设备登录时自动拉取云端最新配置

## 组件结构

| 组件                 | 职责                                   |
| -------------------- | -------------------------------------- |
| `HomeScreenGrid.vue` | 翻页式桌面网格，支持拖拽排序           |
| `HomeScreenDock.vue` | 底部 Dock 常用栏                       |
| `AppIcon.vue`        | 应用图标，编辑模式下增加抖动和删除按钮 |
| `InstallButton.vue`  | 应用安装按钮                           |
