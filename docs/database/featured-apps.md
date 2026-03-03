# featured_apps 集合

CloudBase NoSQL 集合，存储编辑精选推荐应用数据。

## 字段定义

| 字段         | 类型      | 必填 | 说明                                                |
| ------------ | --------- | ---- | --------------------------------------------------- |
| `_id`        | `string`  | 自动 | 文档 ID                                             |
| `_openid`    | `string`  | 自动 | 运营者用户 ID                                       |
| `appId`      | `string`  | 是   | 关联的应用 ID（`apps._id` 或静态应用 `slug`）       |
| `appSource`  | `string`  | 是   | 应用来源：`static` / `cloudbase`                    |
| `type`       | `string`  | 是   | 推荐类型：`daily`（每日推荐）/ `editor`（编辑精选） |
| `title`      | `string`  | 否   | 推荐标题（覆盖应用原名称）                          |
| `subtitle`   | `string`  | 否   | 副标题（如「编辑精选」）                            |
| `tagline`    | `string`  | 否   | 标语                                                |
| `coverColor` | `string`  | 否   | 推荐卡片背景色                                      |
| `sortOrder`  | `number`  | 是   | 排序序号                                            |
| `startDate`  | `number`  | 是   | 推荐生效时间戳（ms）                                |
| `endDate`    | `number`  | 是   | 推荐失效时间戳（ms）                                |
| `isActive`   | `boolean` | 是   | 是否激活                                            |
| `createdAt`  | `number`  | 是   | 创建时间戳                                          |
| `updatedAt`  | `number`  | 是   | 更新时间戳                                          |

## 索引

| 索引名            | 字段                     | 类型 | 说明               |
| ----------------- | ------------------------ | ---- | ------------------ |
| `_id_`            | `_id`                    | 默认 | 主键               |
| `idx_active_sort` | `isActive` + `sortOrder` | 复合 | 查询激活推荐并排序 |
| `idx_type_date`   | `type` + `startDate`     | 复合 | 按类型和时间查询   |

## 安全规则

类型：**CUSTOM**

```json
{
  "read": "auth.uid != null",
  "write": "auth.uid == doc._openid"
}
```

所有登录用户可读，仅创建者（运营管理员）可写。

## 查询模式

### 获取当前有效的每日推荐

```typescript
const now = Date.now()
db.collection('featured_apps')
  .where({
    isActive: true,
    type: 'daily',
    startDate: _.lte(now),
    endDate: _.gte(now),
  })
  .orderBy('sortOrder', 'asc')
  .limit(5)
  .get()
```

### 获取编辑精选

```typescript
db.collection('featured_apps')
  .where({
    isActive: true,
    type: 'editor',
  })
  .orderBy('sortOrder', 'asc')
  .limit(10)
  .get()
```

## Fallback 策略

CloudBase 无数据时，回退到静态 `FEATURED_APP` 常量（`app/constants/apps/index.ts`）。
