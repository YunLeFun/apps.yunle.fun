# weekly_charts 集合

CloudBase NoSQL 集合，存储每周热门应用排行数据。

## 字段定义

| 字段        | 类型     | 必填 | 说明                                          |
| ----------- | -------- | ---- | --------------------------------------------- |
| `_id`       | `string` | 自动 | 文档 ID                                       |
| `_openid`   | `string` | 自动 | 运营者用户 ID                                 |
| `appId`     | `string` | 是   | 关联的应用 ID（`apps._id` 或静态应用 `slug`） |
| `appSource` | `string` | 是   | 应用来源：`static` / `cloudbase`              |
| `weekStart` | `number` | 是   | 周起始日期时间戳（当周周一 00:00 UTC+8）      |
| `rank`      | `number` | 是   | 排名（1-10）                                  |
| `score`     | `number` | 否   | 热度分数（用于排序依据）                      |
| `createdAt` | `number` | 是   | 创建时间戳                                    |
| `updatedAt` | `number` | 是   | 更新时间戳                                    |

## 索引

| 索引名          | 字段                 | 类型 | 说明           |
| --------------- | -------------------- | ---- | -------------- |
| `_id_`          | `_id`                | 默认 | 主键           |
| `idx_week_rank` | `weekStart` + `rank` | 复合 | 按周查询并排序 |

## 安全规则

类型：**CUSTOM**

```json
{
  "read": "auth.uid != null",
  "write": "auth.uid == doc._openid"
}
```

所有登录用户可读，仅运营管理员可写。

## 查询模式

### 获取当周热门

```typescript
// 计算当周周一 00:00 时间戳
function getWeekStart(): number {
  const now = new Date()
  const day = now.getDay()
  const diff = now.getDate() - day + (day === 0 ? -6 : 1)
  const monday = new Date(now.setDate(diff))
  monday.setHours(0, 0, 0, 0)
  return monday.getTime()
}

db.collection('weekly_charts')
  .where({ weekStart: getWeekStart() })
  .orderBy('rank', 'asc')
  .limit(10)
  .get()
```

## Fallback 策略

CloudBase 无数据时，回退到 `WeeklyChart.vue` 内的静态硬编码数据。
