# apps 集合

CloudBase NoSQL 集合，存储用户创建的应用信息。

## 字段定义

| 字段          | 类型       | 必填 | 说明                                         |
| ------------- | ---------- | ---- | -------------------------------------------- |
| `_id`         | `string`   | 自动 | 文档 ID，CloudBase 自动生成                  |
| `_openid`     | `string`   | 自动 | 创建者用户 ID，服务端自动注入                |
| `ownerLogin`  | `string`   | 是   | 所有者用户名，用于展示                       |
| `name`        | `string`   | 是   | 应用名称                                     |
| `slug`        | `string`   | 是   | URL 标识符，全局唯一（唯一索引约束）         |
| `description` | `string`   | 否   | 应用描述                                     |
| `githubRepo`  | `string`   | 否   | GitHub 仓库，格式 `owner/repo`               |
| `websiteUrl`  | `string`   | 否   | 应用网址                                     |
| `backupUrl`   | `string`   | 否   | 备用链接                                     |
| `logo`        | `string`   | 否   | 自定义 Logo 图片 URL（优先于 emoji 展示）    |
| `emoji`       | `string`   | 否   | 应用 emoji 图标（无 logo 时展示，默认 `📱`） |
| `themeColor`  | `string`   | 否   | 主题色，十六进制色值（默认 `#007AFF`）       |
| `category`    | `string`   | 否   | 分类                                         |
| `tags`        | `string[]` | 否   | 标签列表                                     |
| `isPublic`    | `boolean`  | 是   | 是否公开可见                                 |
| `createdAt`   | `number`   | 是   | 创建时间戳（ms）                             |
| `updatedAt`   | `number`   | 是   | 更新时间戳（ms）                             |

## `_openid` 机制

`_openid` 是 CloudBase NoSQL **系统字段**：

- `collection.add()` 时服务端**自动注入**，值为当前登录用户 uid
- 客户端手动传入会被服务端**覆盖**，不要手动传
- 安全规则通过 `auth.uid == doc._openid` 校验文档归属
- 不要创建冗余的 `userId` / `ownerId` 字段存储同样的值

## 索引

| 索引名            | 字段      | 类型 | 说明              |
| ----------------- | --------- | ---- | ----------------- |
| `_id_`            | `_id`     | 默认 | 主键              |
| `_openid_1`       | `_openid` | 升序 | 按创建者查询      |
| `idx_slug_unique` | `slug`    | 唯一 | slug 全局唯一约束 |

## 安全规则

类型：**CUSTOM**

```json
{
  "read": "(doc.isPublic == true && doc.status == 'approved') || auth.uid == doc._openid",
  "create": "auth.uid != null && auth.loginType != 'ANONYMOUS'",
  "update": "auth.uid == doc._openid",
  "delete": "auth.uid == doc._openid"
}
```

| 操作 | 权限                                                      |
| ---- | --------------------------------------------------------- |
| 读取 | 公开且审核通过的应用所有人可读；所有者可读自己的应用      |
| 创建 | 已登录且非匿名用户可创建，`_openid` 由 CloudBase 自动注入 |
| 更新 | 仅创建者可更新                                            |
| 删除 | 仅创建者可删除                                            |

### 安全规则对 `where` 查询的约束

CloudBase 安全规则引擎要求 **`where` 条件必须能让引擎推导出每条结果都满足权限**。
不满足时会返回 `DATABASE_PERMISSION_DENIED`。

**合法查询模式：**

```typescript
// ✅ 查自己的数据 — where 含 _openid
db.collection('apps').where({ _openid: userId })

// ✅ 查公开数据 — where 含 isPublic: true 与 status: 'approved'
db.collection('apps').where({ isPublic: true, status: 'approved' })

// ✅ 组合条件 — 按 slug 查公开应用
db.collection('apps').where({ slug: 'xxx', isPublic: true, status: 'approved' })

// ✅ 组合条件 — 按 slug 查自己的应用
db.collection('apps').where({ slug: 'xxx', _openid: userId })
```

**非法查询模式：**

```typescript
// ❌ 仅按 slug 查询 — 引擎无法判断结果是否有读权限
db.collection('apps').where({ slug: 'xxx' })

// ❌ 按任意非权限字段查询
db.collection('apps').where({ category: 'game' })
```

## 查询模式

### 查自己的所有应用

```typescript
db.collection('apps')
  .where({ _openid: userId })
  .orderBy('updatedAt', 'desc')
  .get()
```

### 删除自己的应用

删除时同时带上 `_id` 与 `_openid`，让安全规则可以从查询条件推导出文档归属。

```typescript
db.collection('apps')
  .where({ _id: appId, _openid: userId })
  .remove()
```

### 按 slug 查应用

需要分两步：先查自己的（含私有），再查公开的。

```typescript
// 1. 先查自己的
const { data } = await db.collection('apps')
  .where({ slug, _openid: userId })
  .limit(1)
  .get()
if (data.length > 0)
  return data[0]

// 2. 再查公开的
const { data: pub } = await db.collection('apps')
  .where({ slug, isPublic: true, status: 'approved' })
  .limit(1)
  .get()
return pub[0] || null
```

### 检查 slug 是否被占用

客户端只能查到本人数据 + 公开数据，**无法检测其他用户的私有 slug**。
但 `idx_slug_unique` 唯一索引会在创建时保证全局唯一，重复则 `add()` 报错。

```typescript
// 客户端预检（不能覆盖他人私有数据）
const pub = await db.collection('apps')
  .where({ slug, isPublic: true, status: 'approved' })
  .limit(1)
  .get()
const my = await db.collection('apps')
  .where({ slug, _openid: userId })
  .limit(1)
  .get()

// 最终由唯一索引兜底
```

### 创建应用

```typescript
// _openid 由服务端自动注入，不要手动传
await db.collection('apps').add({
  ownerLogin: 'username',
  name: 'My App',
  slug: 'my-app',
  logo: '', // 自定义 Logo URL（可选）
  emoji: '🚀', // emoji 图标（默认 📱）
  themeColor: '#007AFF', // 主题色（默认 #007AFF）
  isPublic: true,
  createdAt: Date.now(),
  updatedAt: Date.now(),
})
```

## 公开应用查询模式（工坊页面）

### 按分类查询公开应用

```typescript
db.collection('apps')
  .where({ isPublic: true, status: 'approved', category: '工具' })
  .orderBy('updatedAt', 'desc')
  .skip(offset)
  .limit(20)
  .get()
```

### 搜索公开应用

```typescript
db.collection('apps')
  .where({
    isPublic: true,
    status: 'approved',
    name: db.RegExp({ regexp: keyword, options: 'i' }),
  })
  .limit(20)
  .get()
```

### 查询所有公开应用（分页）

```typescript
db.collection('apps')
  .where({ isPublic: true, status: 'approved' })
  .orderBy('updatedAt', 'desc')
  .skip(offset)
  .limit(20)
  .get()
```

### 根据多个 ID 批量查询

```typescript
db.collection('apps')
  .where({
    _id: _.in(appIds),
    isPublic: true,
    status: 'approved',
  })
  .get()
```

## 类型定义

文件：`app/types/app.ts`

```typescript
interface AppRecord {
  _id: string
  _openid: string
  ownerLogin: string
  name: string
  slug: string
  description?: string
  githubRepo?: string
  websiteUrl?: string
  backupUrl?: string
  logo?: string
  emoji?: string
  themeColor?: string
  category?: string
  tags?: string[]
  isPublic: boolean
  createdAt: number
  updatedAt: number
}
```

## 图标展示规则

优先级：`logo` > `emoji` > 默认 emoji `📱`

```text
有 logo URL → 展示 logo 图片（圆角矩形裁剪）
无 logo → 展示 emoji 字符
无 emoji → 展示默认 📱
```

背景色使用 `themeColor`，未设置时默认 `#007AFF`（iOS 蓝）。

### 预设主题色

```text
#007AFF  iOS 蓝
#34C759  iOS 绿
#FF9500  iOS 橙
#FF3B30  iOS 红
#AF52DE  iOS 紫
#FF2D55  iOS 粉
#5856D6  iOS 靛蓝
#00C7BE  iOS 青
#FFD60A  iOS 黄
#8E8E93  iOS 灰
```
