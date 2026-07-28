# 应用提交、审核与发布

## 目标

应用目录采用“稳定应用实体 + 不可变提交版本 + 追加式审核事件”的模型。审核与发布是两次独立动作，客户端不能直接写数据库，也不能自行设置 `status`、`publicationStatus` 或 `isOfficial`。

第一阶段只开放一方应用。第三方的数据结构和状态机已经兼容，但入口由 `APP_THIRD_PARTY_SUBMISSIONS_ENABLED=false` 关闭，界面统一显示“第三方应用入驻敬请期待”。

## 数据模型

### `apps`

稳定实体与当前公开投影。公开目录只能读取同时满足以下条件的记录：

- `isPublic == true`
- `status == 'approved'`
- `publicationStatus == 'published'`

浏览器的 `create/update/delete` 全部关闭。所有者管理也必须经过 Nitro 服务端 API。

### `app_submissions`

每次创建或编辑都新增一个 revision，不覆盖旧版本。核心字段：

- `appId`、`revision`、`kind`
- `submitterUid`、`submitterLogin`
- `reviewStatus`
- `snapshot`
- `ownership`

集合禁止浏览器直接读写。所有者通过服务端鉴权后只能读取自己的提交。

### `app_review_events`

记录提交、归属验证、审核、发布、暂停和下架等动作。事件只追加，不更新、不删除。

### `app_submitters`

一方应用提交 UID allowlist。内部维护者 YunYouJun 使用稳定 CloudBase UID `1978032370372050944`。运行时配置 `APP_FIRST_PARTY_SUBMITTER_UIDS` 仅作为资源迁移期间的服务端兜底。

## 状态轴

状态彼此正交：

- 审核：`pending → in_review → approved / changes_requested / rejected`
- 发布：`unpublished → published → suspended / delisted`
- 访问：`public / login_required / invite_only`
- 阶段：`stable / beta`

审核通过不会自动上架；发布只复制审核通过的 snapshot 到 `apps` 公开投影。编辑已发布应用会创建新提交，旧线上版本保持不变，直到新版本再次审核并发布。

## 一方归属验证

`*.yunle.fun` 只代表一方候选分类，不会仅凭字符串直接授予官方标识。批准前自动检查：

1. 精确 hostname 属于 `yunle.fun`；
2. Cloudflare 账号内存在该 hostname 的精确 DNS 记录；
3. 能按自定义域名、GitHub 仓库或项目名唯一匹配 EdgeOne Pages / Cloudflare Pages 项目；
4. HTTPS 可访问；
5. 最终重定向仍在 `yunle.fun` 范围；
6. 仓库信息与受管部署项目一致（有仓库时）。

全部强制检查通过后，后台可以批准；再次点击发布时才由后台设置 `isOfficial=true`。

## 权限和安全

- 提交者必须已登录、手机号已验证、账号状态为 active，且 UID 命中一方 allowlist。
- API 校验字段、HTTPS URL、slug 唯一性与一方域名范围。
- API 和边缘层应继续配置速率限制；数据库规则不是限流替代品。
- owner 紧急发布必须填写原因，仍不能绕过归属验证，并写入独立审计事件。
- 删除入口执行软下架，保留应用、提交与审核记录。

## 第三方规划

未来开启第三方时沿用相同 submission/review/publication 状态机，仅替换：

- 提交资格策略；
- `dns_txt` / `well_known` / GitHub App 等所有权挑战；
- 开发者资料、协议与联系方式；
- 更严格的隐私、内容安全、滥用处置和复审策略。

不要把第三方开放实现成“允许浏览器直写 apps”，也不要复用 `isOfficial` 表示“审核通过”。

## 运维

1. 在 `admin` 仓库执行 `pnpm provision:app-review -- --apply --confirm-env=<envId>` 创建私有集合与索引。
2. 执行 `pnpm migrate:app-review -- --apply --confirm-env=<envId>` 为历史应用补基线提交并写入一方 allowlist。
3. 在本仓库执行 `bash scripts/cloudbase-rules/apply.sh`，收紧 `apps` 并锁定三个内部集合。
4. 先通过后台创建提交、验证、批准、发布，再验证公开目录。

所有脚本默认 dry-run；生产 apply 必须显式确认环境 ID。
