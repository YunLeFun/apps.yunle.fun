# CloudBase 安全规则配置手册

> **状态：✅ 已通过 CloudBase MCP 自动应用到生产环境 `yunlefun-8g7ybcxc7345c490`（2026-05-22）**
>
> 后续维护无需手动到控制台，用 MCP 一次性修改即可（命令在文末）。

## 自动应用方式（推荐）

前提：项目根 `config/mcporter.json` 已配置 CloudBase MCP。

```bash
# 检查 MCP 健康
npx mcporter list | grep cloudbase

# 登录 + 选环境
npx mcporter call cloudbase auth action=set_env envId=yunlefun-8g7ybcxc7345c490

# 应用某个集合的规则（示例：apps 集合）
npx mcporter call cloudbase managePermissions --args "$(cat scripts/cloudbase-rules/apps.json)"

# 校验
npx mcporter call cloudbase queryPermissions \
  action=getResourcePermission resourceType=noSqlDatabase resourceId=apps
```

规则源文件存放在 `scripts/cloudbase-rules/*.json`（见 [`scripts/cloudbase-rules/`](https://github.com/YunYouJun/apps.yunle.fun/tree/main/scripts/cloudbase-rules)），改了重新跑 `managePermissions` 即可。

## 当前生效的规则（已部署）

### `apps`（用户提交的云应用）—— `CUSTOM`

```json
{
  "read": "(doc.isPublic == true && doc.status == 'approved') || auth.uid == doc._openid",
  "create": "auth.uid != null && auth.loginType != 'ANONYMOUS'",
  "update": "auth.uid == doc._openid",
  "delete": "auth.uid == doc._openid"
}
```

**含义**：

- 任何登录态（含匿名）可读「公开且审核通过」的应用
- 所有者可读 / 改 / 删自己的应用（不论 status / isPublic）
- 任何已登录的非匿名用户可创建新应用（默认 `status='pending'`，`_openid` 服务端注入）
- 任何用户不能改/删别人的应用

### `user_home_screens`（云居桌面配置）—— `CUSTOM`

```json
{
  "read": "auth.uid == doc._openid",
  "create": "auth.uid != null && auth.loginType != 'ANONYMOUS'",
  "update": "auth.uid == doc._openid",
  "delete": "auth.uid == doc._openid"
}
```

**含义**：纯私有，仅本人可读写。匿名用户不能创建（避免脏数据）。

### `featured_apps`（编辑推荐 / 今日推荐）—— `READONLY`

内置预设：所有人可读，**任何用户都不能写**（仅运营在控制台手动添加）。

### `weekly_charts`（每周热门排行）—— `READONLY`

同 `featured_apps`。

## 为什么拆 `write` 成 `create/update/delete`？

CloudBase MCP 在更新规则时给的告警：

> ⚠️ `create` 规则验证写入数据（request.data），此时文档尚不存在，`doc.*` 不可用。

所以早期的 `"write": "auth.uid == doc._openid"` 写法在 `create` 路径上等价于"永远拒绝"（doc.\_openid 是 undefined）。拆分后：

- `create` 只校验登录态（`_openid` 服务端注入）
- `update` / `delete` 才能用 `doc._openid` 校验所有权

## 验证清单

配置完成后请用浏览器+无痕窗口跑一遍：

- [ ] 未登录打开 <https://www.yunle.fun/tabs/apps> 能看到 `featured` 卡片和应用列表
- [ ] 创建新账号，进 `/workshop/new` 提交一个应用 → 立刻打开 `/tabs/apps` 看不到（因 status=pending）
- [ ] 在 CloudBase 控制台手动把这个文档的 `status` 改为 `approved` → 刷新 `/tabs/apps` 能看到
- [ ] 切换到另一个账号，尝试 `db.collection('apps').doc(刚才的 _id).update(...)` → 应被拒（\_openid 不匹配）

## 后台审核工作流（暂未上 UI）

当前没有内置的 admin 审核后台，运营审核流程：

1. 用户提交 → 数据库自动 `status: 'pending'`
2. 运营每日打开 CloudBase 控制台 → `apps` 集合 → 筛选 `status == 'pending'`
3. 人工查 `name` / `description` / `websiteUrl` 是否合规
4. 通过：编辑文档把 `status` 改为 `'approved'`、`reviewedAt: Date.now()`
5. 拒绝：把 `status` 改为 `'rejected'`、填 `rejectedReason`

> 1.x 版本可考虑做一个 `/developer/admin` 审核后台页面，需要在 CloudBase 加管理员 role 标记。

## 控制台直达

- 数据库：<https://tcb.cloud.tencent.com/dev?envId=yunlefun-8g7ybcxc7345c490#/db/doc>
- `apps` 集合：<https://tcb.cloud.tencent.com/dev?envId=yunlefun-8g7ybcxc7345c490#/db/doc/collection/apps>

## 应用上架审核资源

`apps` 只允许客户端读取 `isPublic=true && status='approved' && publicationStatus='published'` 的公开投影，客户端写入全部关闭。

`app_submissions`、`app_review_events`、`app_submitters` 均为服务端专用集合，浏览器读写全部关闭。完整流程与迁移方式见 [应用提交、审核与发布](../product/app-submission-review.md)。
