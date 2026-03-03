# 数据库设计

云乐坊使用腾讯 CloudBase NoSQL 数据库，包含以下核心集合：

| 集合                               | 说明         |
| ---------------------------------- | ------------ |
| [`apps`](./apps)                   | 应用信息表   |
| [`featured_apps`](./featured-apps) | 编辑精选推荐 |
| [`user_desktops`](./user-desktops) | 用户桌面配置 |
| [`weekly_charts`](./weekly-charts) | 每周热门排行 |

## 权限模型

CloudBase 安全规则基于 `_openid` 字段实现用户级权限控制：

- `_openid` 由 CloudBase 服务端在 `add()` 时**自动注入**
- 安全规则通过 `auth.uid == doc._openid` 校验文档归属
- 客户端查询必须包含权限推导条件（`_openid` 或 `isPublic: true`）

## 数据流架构

```text
CloudBase NoSQL
       ↓
Composables (useApps / useHomeScreen / useDiscovery)
       ↓
Pinia Store (localStorage 缓存)
       ↓
Vue 组件
```
