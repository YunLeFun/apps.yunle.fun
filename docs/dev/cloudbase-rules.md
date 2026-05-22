# CloudBase 安全规则配置手册

> 上线前必须在 CloudBase 控制台同步以下规则。代码侧的 where 条件依赖这些规则的可推导性，规则不对会导致查询直接被拒。

## 一键操作步骤

1. 打开 <https://console.cloud.tencent.com/tcb/database>（已用 `open` 帮你打开）
2. 选择环境：`yunlefun-8g7ybcxc7345c490`（从 `nuxt.config.ts` 的 `tcbEnvId` 推断）
3. 左侧选「数据库」→ 上方切换到 NoSQL 数据库
4. 依次对每个集合点「权限设置」→ 选「自定义安全规则」→ 粘贴下面对应的 JSON

---

## `apps` 集合（用户提交的云应用）

```json
{
  "read": "(doc.isPublic == true && doc.status == 'approved') || auth.uid == doc._openid",
  "write": "auth.uid == doc._openid"
}
```

**含义**：

- 任何人都能读「公开且审核通过」的应用
- 只有作者本人能读 / 写自己的应用（包括未公开 / 待审核 / 被拒的）
- 任何人都不能写别人的应用

**验证**：

- 未登录用户访问 `/tabs/apps` → 只看到 `status='approved'` 的
- 登录后访问 `/workshop` → 看到自己所有应用（含 pending/rejected）
- 篡改 `_openid` 写别人的应用 → 失败

---

## `user_home_screens` 集合（云居桌面配置）

```json
{
  "read": "auth.uid == doc._openid",
  "write": "auth.uid == doc._openid"
}
```

**含义**：纯私有，仅本人可读写。

---

## `featured_apps` 集合（编辑推荐 / 今日推荐）

```json
{
  "read": true,
  "write": false
}
```

**含义**：所有人可读，**任何用户都不能写**（仅运营在控制台手动添加）。

---

## `weekly_charts` 集合（每周热门排行）

```json
{
  "read": true,
  "write": false
}
```

同 `featured_apps`：所有人可读，仅运营写。

---

## 验证清单

配置完成后请用浏览器+无痕窗口跑一遍：

- [ ] 未登录打开 <https://www.yunle.fun/tabs/apps> 能看到 `featured` 卡片和应用列表
- [ ] 创建新账号，进 `/workshop/new` 提交一个应用 → 立刻打开 `/tabs/apps` 看不到（因 status=pending）
- [ ] 在 CloudBase 控制台手动把这个文档的 `status` 改为 `approved` → 刷新 `/tabs/apps` 能看到
- [ ] 切换到另一个账号，尝试用 `db.collection('apps').doc(刚才的 _id).update(...)` → 应被拒（write 校验 \_openid 不匹配）

## 后台审核工作流（暂未上 UI）

当前没有内置的 admin 审核后台，运营审核流程：

1. 用户提交 → 数据库自动 `status: 'pending'`
2. 运营每日打开 CloudBase 控制台 → `apps` 集合 → 筛选 `status == 'pending'`
3. 人工查 `name` / `description` / `websiteUrl` 是否合规
4. 通过：编辑文档把 `status` 改为 `'approved'`、`reviewedAt: Date.now()`
5. 拒绝：把 `status` 改为 `'rejected'`、填 `rejectedReason`，用户下次进工坊会看到红色拒绝原因

> 1.x 版本可考虑做一个 `/developer/admin` 审核后台页面，需要在 CloudBase 加管理员 role 标记。
