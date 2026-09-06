# 应用标识、所属空间与市场短名

采纳 GitHub #25 的命名空间建议，参考 npm 的 scoped / unscoped 分层，但增加“正式上架公共市场必须有唯一短名”的产品约束。npm 的公开 scoped 包本身并不要求另取 unscoped 名称，参见 [npm scope 与可见性文档](https://docs.npmjs.com/package-scope-access-level-and-visibility/)。

| 字段 / 地址                        | 规则                                                       |
| ---------------------------------- | ---------------------------------------------------------- |
| `apps._id`（appId）                | 不可变身份；数据、权限和新投币账本按 ID 关联               |
| `ownerUid + slug`                  | 所属空间内唯一，跨用户可以同名                             |
| `/u/:owner/apps/:slug`             | 所属空间地址，公开分享可访问，私有应用不向匿名用户返回数据 |
| `public_market_listings.shortName` | 市场全局唯一，统一小写，系统名称保留                       |
| `/apps/:shortName`                 | 已上架市场应用的短地址；下架或转私有后不返回应用           |
| `name`                             | 显示名称可以重复，通过作者区分                             |

私有、工坊共享、公开分享是受众状态；市场上架是独立分发状态。公开分享不等于上架，不必占用市场短名。投稿时选择短名，默认建议所属空间 slug。短名已占用时返回 409，用户另选短名，不必重命名应用。

短名与所属空间标识由服务端在写入应用 / listing 的同一事务内登记到 `app_identifiers`。同一应用重试幂等，不同应用不能覆盖已有登记。下架、暂停、转私有均不删除登记；市场短名暂不开放改名或自动释放，避免链接被接管。

官网市场卡片优先链接市场短地址；个人分享保留所属空间地址。创建和编辑统一前往 `apps.yunle.fun/workshop`，避免官网旧表单绕过应用平台的服务端约束。公共接口每次检查当前受众与 listing 状态，响应禁止缓存；不以“知道 URL”作为访问权限。

## 旧数据与发布顺序

涉及 `apps.yunle.fun`、`admin`、官网及 `account-api` 云函数，需要配套发布：

1. 备份 `apps`、`public_market_listings` 及索引配置。
2. 用 admin 的 `scripts/ensure-app-review-resources.mjs` 准备 `app_identifiers`，权限为 ADMINONLY，浏览器禁止读写。
3. 在 admin 执行 `node --env-file=.env --import tsx scripts/migrate-app-identifiers.ts`。默认只读 dry-run，检查所有者、同空间冲突、旧短名冲突和保留名称；有冲突则停止，不自动替用户改名。
4. 审查计划后，先执行 `--apply --backfill-only --confirm-env=<完整环境 ID>`，仅回填、不切换索引。新版应用平台与 admin 的写入接口在 `app_identifiers/migration_v2.ready` 未开启时返回 503。新版配套部署完成、旧实例请求排空后，再执行 `--apply --activate --confirm-env=<完整环境 ID>` 完成最终回填、索引切换并恢复写入。脚本分页回填：所属空间登记、旧 listing 短名、`ownerLoginKey`、旧投币账本键；建立 `ownerUid + slug` 唯一索引后，再删除实际存在的单字段全局 `slug` / `nameKey` 唯一索引。保留普通搜索索引。
5. 配套发布应用平台、管理后台、官网和 `account-api`，清理旧 CDN 公共响应缓存，再恢复写入。不得在新旧写入服务并存时提前移除旧索引。
6. 用两个测试用户验证相同 slug 可以创建、同一用户重复 slug 被拒；同一市场短名只能归属一个应用；验证下架保留占名、转私有后短地址与所属空间匿名请求均不可见。

旧市场 listing（包括暂停和下架）保留原 slug 为短名；现有 appId 和所属空间 slug 不变。老投币流水不改写，通过 `legacyTipKey` 让 ID 入口与旧 slug 入口共用原账本及每日限额。新应用按 appId 记账；歧义旧 slug 不允许投币。

当前变更是代码和迁移工具，不能仅凭本地测试宣称生产迁移完成。#25 应在配套发布和线上验收后关闭。

## 本地验收记录（2026-09-06）

- 应用平台：526 项测试、类型检查及构建通过。
- 管理后台：624 项测试、类型检查及构建通过。
- 官网：1,192 项测试、类型检查及构建通过，14 个 EdgeOne 客户端入口检查通过。
- Chromium：1280 / 390 像素下以接口夹具验证市场短地址、所属空间地址、错误所有者隔离；应用平台创建入口可加载。
- 尚未验证：生产数据库回填、真实 CloudBase 并发占名、认证后的实际投稿和线上发布。可通过已登录的 `tcb secrets get --json` 会话在内存中注入临时凭据（SDK 使用 sessionToken，manager 使用 token），无需把密钥写进仓库。
