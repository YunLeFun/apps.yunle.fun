# 工坊 - Workshop

> 2026-10-28 新方向：工坊承接寻乐原有推荐、榜单和 AI 找应用，统一应用发现与获取。[改造计划](./native-game-discovery.md)已启动实施，下文仍记录改造前的目录设计。

工坊是云应用商店，用户可以在这里浏览、搜索和安装云应用。开发者也可以在这里发布自己的作品。

## 功能模块

### 1. 分类标签栏

- `IonSegment` 横向滚动标签
- 支持多种应用分类

### 2. 搜索功能

- 搜索栏位于页面顶部
- 输入防抖 **300ms**
- 从 CloudBase 正则匹配搜索应用名称和描述

### 3. 应用列表

- 列表式展示应用信息（图标、名称、描述、安装按钮）
- 无限滚动分页加载，每次 **20** 条
- 按更新时间倒序排列

### 4. 安装交互

- 「获取」按钮点击后安装到云居桌面
- 已安装的应用显示「打开」按钮

## 数据查询

### 按分类浏览

```typescript
db.collection('apps')
  .where({ isPublic: true, category: selectedCategory })
  .orderBy('updatedAt', 'desc')
  .skip(offset)
  .limit(20)
  .get()
```

### 搜索应用

```typescript
db.collection('apps')
  .where({
    isPublic: true,
    name: db.RegExp({ regexp: keyword, options: 'i' }),
  })
  .limit(20)
  .get()
```

## 开发者功能

开发者可以在「我的」页面中管理自己发布的云应用：

- 创建新应用（名称、slug、图标、网址、分类等）
- 编辑已有应用信息
- 设置应用公开/私有
- 查看应用统计
