# user_home_screens 集合

CloudBase NoSQL 集合，存储用户的 Home Screen 配置（已安装应用、排序、Dock）。

每个用户对应**一条文档**，Home Screen 是用户个性化配置，读写粒度天然为整体。

## 字段定义

| 字段            | 类型             | 必填 | 说明                          |
| --------------- | ---------------- | ---- | ----------------------------- |
| `_id`           | `string`         | 自动 | 文档 ID，CloudBase 自动生成   |
| `_openid`       | `string`         | 自动 | 用户 ID，服务端自动注入       |
| `installedApps` | `InstalledApp[]` | 是   | 主屏已安装应用列表（有序）    |
| `dockApps`      | `InstalledApp[]` | 是   | Dock 常用应用（最多 4 个）    |
| `recentApps`    | `RecentApp[]`    | 是   | 最近使用的应用（最多 100 个） |
| `createdAt`     | `number`         | 是   | 创建时间戳（ms）              |
| `updatedAt`     | `number`         | 是   | 更新时间戳（ms）              |

### InstalledApp 子结构

| 字段    | 类型     | 说明                          |
| ------- | -------- | ----------------------------- |
| `appId` | `string` | 应用 ID（统一使用 slug 标识） |

> 排序由数组索引隐式表达，无需 `sortOrder` 字段。

### RecentApp 子结构

| 字段     | 类型     | 说明                 |
| -------- | -------- | -------------------- |
| `appId`  | `string` | 应用 ID              |
| `usedAt` | `number` | 最近使用时间戳（ms） |

## 索引

| 索引名      | 字段      | 类型 | 说明       |
| ----------- | --------- | ---- | ---------- |
| `_id_`      | `_id`     | 默认 | 主键       |
| `_openid_1` | `_openid` | 唯一 | 每用户一条 |

## 安全规则

类型：**CUSTOM**

```json
{
  "read": "doc._openid == auth.openid || doc._openid == auth.uid",
  "write": "doc._openid == auth.openid || doc._openid == auth.uid"
}
```

仅用户本人可读写自己的 Home Screen 配置。

> **跨平台兼容**（CloudBase 官方推荐写法）：
>
> - `auth.openid`：微信登录方式的 openid
> - `auth.uid`：非微信登录方式（用户名、手机、邮箱等）的 user_id（Auth v2 JWT `sub`）
> - 安全规则需同时匹配两者以兼容不同登录方式
>
> **`_openid` 注入规则**：CloudBase `add()` 时服务端自动注入。
> 代码中也手动传入 `_openid: uid`，确保与 `auth.uid` 一致。

## 查询模式

### 获取用户 Home Screen

```typescript
db.collection('user_home_screens')
  .where({ _openid: userId })
  .limit(1)
  .get()
```

### 创建/更新 Home Screen

```typescript
// 首次创建（_openid 自动注入）
db.collection('user_home_screens').add({
  installedApps: [],
  dockApps: [],
  recentApps: [],
  createdAt: Date.now(),
  updatedAt: Date.now(),
})

// 更新（乐观更新：先改本地，再同步到 CloudBase）
db.collection('user_home_screens').doc(docId).update({
  installedApps,
  dockApps,
  updatedAt: Date.now(),
})
```

## 同步策略

1. **启动加载**：先从 localStorage 读取缓存快速渲染，后台异步拉取 CloudBase 最新数据
2. **乐观更新**：拖拽/安装/卸载时先更新本地 store + localStorage，异步写入 CloudBase
3. **防抖写入**：排序变更采用 500ms 防抖，避免频繁写入
4. **冲突处理**：以 `updatedAt` 较新的数据为准

## 类型定义

文件：`app/types/homeScreen.ts`

```typescript
interface InstalledApp {
  appId: string
  sortOrder: number
}

interface RecentApp {
  appId: string
  usedAt: number
}

interface HomeScreenConfig {
  installedApps: InstalledApp[]
  dockApps: InstalledApp[]
  recentApps: RecentApp[]
  updatedAt: number
}

interface UserHomeScreenRecord {
  _id: string
  _openid: string
  installedApps: InstalledApp[]
  dockApps: InstalledApp[]
  recentApps: RecentApp[]
  createdAt: number
  updatedAt: number
}
```
