# apps — 应用身份与目录投影

应用身份规则见 [应用标识、所属空间与市场短名](../product/app-identifiers.md)。本页替代旧版“显示名称和 slug 全局唯一、浏览器直写 apps”的设计。

| 字段                           | 用途                                                   |
| ------------------------------ | ------------------------------------------------------ |
| `_id`                          | 不可变 appId，关联 revision、权限及业务数据            |
| `ownerUid`                     | 稳定所有者 UID，由服务端认证确定                       |
| `ownerLogin` / `ownerLoginKey` | 用户地址中的登录名及小写检索键                         |
| `slug`                         | 所有者命名空间内唯一的 URL 标识                        |
| `name` / `nameKey`             | 可重复显示名称及搜索归一化键                           |
| `audience`                     | `public` / `workshop` / `owner`                        |
| `publicationStatus`            | `published` / `unpublished` / `suspended` / `delisted` |
| `currentRevisionId`            | 所有者当前版本                                         |
| `publishedSubmissionId`        | 当前发布版本兼容指针                                   |
| `activeSubmissionId`           | 当前审核提交兼容指针                                   |
| `identityVersion`              | 命名空间策略版本；新记录为 2                           |
| `legacyTipKey`                 | 仅历史应用保留原投币账本键，不向公开目录下发           |

`description`、`websiteUrl`、隐私/支持链接、图标、分类、标签、截图、评分、访问方式和发布阶段继续按现有 AppRecord 与 revision 快照维护。

## 唯一性

- `apps` 建立 `ownerUid + slug` 唯一索引。
- `nameKey` 不唯一。旧 `idx_name_key_unique` 与单字段 `slug` 唯一索引由迁移脚本在回填后移除。
- `app_identifiers` 是 ADMINONLY 集合，以确定性文档 ID 登记所属空间 slug 与市场短名。读已有归属与写入占名必须与应用 / listing 写入处于同一事务。
- `public_market_listings` 以 appId 关联应用，`shortName` 保存已取得的市场短名。投稿时原子占名，管理员上架、恢复及紧急发布必须验证短名。
- 下架、暂停和私有化不删除身份或释放短名。

## 读取与写入

浏览器经应用平台 Nitro API 读取白名单投影，不直接访问身份登记表，不直接写 `apps`。

- `/api/apps/public`：只返回已上架、当前仍公开、已发布的应用，使用获批 revision。
- `/api/apps/public/:key`：按 appId 或市场短名读取，不按全局 namespace slug 猜测目标。
- `/api/markets/personal/:login`：所属用户的公开分享，使用当前 revision，不要求市场上架。
- `/api/apps/mine` 与管理接口：验证当前用户身份，按 ownerUid 授权。
- 所属空间地址 `/u/:owner/apps/:slug` 在官网展示；市场短地址 `/apps/:shortName` 独立。

公开目录响应使用 `Cache-Control: no-store`，避免转私有后继续从共享缓存返回旧数据。发布切换还需清理此前已有 CDN 缓存。

创建和修改通过 submission 服务生成 revision；投稿云乐坊单独取得市场短名并进入审核。公开分享不自动进入市场。

## 迁移

使用 admin 仓库 `scripts/migrate-app-identifiers.ts`，默认 dry-run。具体顺序、冲突处理、账本兼容和回滚限制见 [迁移说明](../product/app-identifiers.md#旧数据与发布顺序)。新策略上线后不得重新运行旧版名称全局唯一迁移。
