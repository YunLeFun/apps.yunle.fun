# user_home_screens 集合

CloudBase NoSQL 集合，存储用户的 Home Screen 配置（已安装应用、排序、Dock）。

产品模型期望每个用户一份 Home Screen，读写粒度为整体。**2026-10-16 线上结构核实：`_openid_1` 为普通索引，历史上可能存在同一用户的多份文档；不能把一用户一文档当作数据库保证。** 原生入口的读取、冲突及历史保留方式见[同步契约](../dev/ios-home-sync.md)。

## 字段定义

| 字段            | 类型             | 必填 | 说明                                       |
| --------------- | ---------------- | ---- | ------------------------------------------ |
| `_id`           | `string`         | 是   | 旧 SDK 自动生成；原生服务端使用固定派生 ID |
| `_openid`       | `string`         | 是   | 旧 SDK 自动注入；原生服务端从验证身份填写  |
| `installedApps` | `InstalledApp[]` | 是   | 主屏已安装应用列表（有序）                 |
| `dockApps`      | `InstalledApp[]` | 是   | Dock 常用应用（最多 4 个）                 |
| `recentApps`    | `RecentApp[]`    | 是   | 最近使用的应用（最多 100 个）              |
| `createdAt`     | `number`         | 是   | 创建时间戳（ms）                           |
| `updatedAt`     | `number`         | 是   | 更新时间戳（ms）                           |

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

| 索引名      | 字段      | 类型 | 说明                       |
| ----------- | --------- | ---- | -------------------------- |
| `_id_`      | `_id`     | 默认 | 主键                       |
| `_openid_1` | `_openid` | 普通 | 支持按用户查询，不保证唯一 |

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
> **`_openid` 注入规则**：旧 Web SDK `add()` 由 CloudBase 自动注入，当前客户端不手工覆盖。新 Nitro 管理员 SDK 不依赖客户端安全规则，必须由已验证的服务端身份填写 `_openid`，不能采用请求正文中的 UID。

## 旧 Web SDK 查询模式

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

## 旧 Web SDK 同步策略

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
