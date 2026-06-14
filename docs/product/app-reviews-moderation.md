# 评分评论审核、敏感词与举报机制（v2 修订版）

> 本计划是对上一版 codex 计划的修订完善，补齐了原计划缺失的：服务端鉴权方案、审核接口收敛（不公开 /api/moderation/check）、TMS 失败策略、iOS baseURL 预留、限流防滥用、读路径收敛。可直接交给 codex 执行。

## Context

详情页 `app/pages/app/[id].vue` 的「评分与评论」UI 已完整存在（323-399 行），但数据是硬编码假数据（54-63 行）；`YlfAppInfo.rating` 目前是运营预设伪指标。本计划落地真实的评分评论系统：评论/举报文本统一接入腾讯云文本内容安全（TMS），**服务端审核后写入**——`Pass` 公开、`Review` 待审、`Block` 拒绝。敏感词库在腾讯云控制台维护（官方不支持 API 管理自定义屏蔽词），代码只读 BizType 环境变量。

**关键架构事实**（执行前必读）：
- Nuxt 4 `ssr: false` SPA，但生产部署为 Node server（腾讯云 SCF 容器，[deploy.config.ts](deploy.config.ts)），`server/api/*` 路由生产可用。
- 客户端认证：CloudBase v2 auth，accessToken 为 JWT（claims 含 `sub`/`exp`），[app/plugins/api.ts](app/plugins/api.ts) 的 `$api` 自动带 `Authorization: Bearer`，**401 时自动刷新 token 重试**——服务端必须返回真实 HTTP 401 才能触发此机制。
- **server/ 目前没有任何鉴权代码**，这是本计划新增的基础设施。
- 客户端验 token 先例：[useCloudbaseAuthCore.ts](app/composables/auth/useCloudbaseAuthCore.ts) 148-206 行调 `https://{envId}.api.tcloudbasegateway.com/auth/v1/user/me`。
- 安全规则源文件在 `scripts/cloudbase-rules/*.json`，用 `bash scripts/cloudbase-rules/apply.sh`（mcporter + CloudBase MCP）应用，格式参照 `apps.json`。
- 应用提交是客户端直写 apps 集合（status='pending' 人工审核），**本期不动、不加预检接口**（已确认），moderation util 留注释扩展点即可。
- 类型定义放本仓库 `app/types/review.ts`（已确认，不进 @yunlefun/types）。
- Capacitor iOS 壳本期不完整支持，但要预留 `apiBaseUrl` runtime config。

## 设计决策（已定，勿改）

| 决策点 | 结论 |
|---|---|
| 审核接口 | **内部 server util**，不暴露公开 `/api/moderation/check`（防止被白嫖 TMS 付费配额） |
| TMS 失败/超时 | fail-safe：`suggestion='Review'` 落 pending，不放行不丢数据，记 error |
| Block 的评论 | 写入 `rejected` 状态返回 200（保留证据、用户可改后重提覆盖），不抛错 |
| 举报 reason 文本 | 仅审核标记不拦截（举报是安全信号，不对外展示，Block 拦截只会丢信号） |
| appKey | 用 `apps.slug` |
| 一人一应用一条评论 | API 层 upsert + 控制台唯一索引 `(appKey, uid)` 双保险；编辑已发布评论重新审核 |
| 读路径 | 写全走 server API；读：`app_reviews` 规则允许客户端读 published + 本人，但前端统一走 `GET /api/reviews`（规则只是兜底） |
| 限流 | DB 查询判断（SCF 无状态，不用内存/Redis）：评论/举报每用户 60s 冷却；举报 (uid,targetType,targetId) 永久去重 |
| 运行时凭证 | 独立 CAM 子账号（仅 TMS + TCB 权限），变量名 `NUXT_TENCENT_API_SECRET_ID/KEY`，**不复用**部署密钥 `TENCENT_CLOUD_SECRET_ID/KEY` |
| 聚合 | 均分/分布由 GET 现算（小数据量），集合注释预留聚合优化 |

---

## 阶段 1：服务端基础设施

### 1.1 依赖与配置

- `package.json` **dependencies**（非 dev，Nitro 要打包进 .output）：`@cloudbase/node-sdk`、`tencentcloud-sdk-nodejs-tms`。
- [nuxt.config.ts](nuxt.config.ts) runtimeConfig 新增：

```ts
runtimeConfig: {
  tencentApiSecretId: '',   // NUXT_TENCENT_API_SECRET_ID
  tencentApiSecretKey: '',  // NUXT_TENCENT_API_SECRET_KEY
  tmsBizType: '',           // NUXT_TMS_BIZ_TYPE（可为空=默认策略）
  public: {
    // ...现有不动
    apiBaseUrl: '',         // NUXT_PUBLIC_API_BASE_URL，Capacitor 壳预留
  },
}
```

- [app/plugins/api.ts](app/plugins/api.ts)：`$fetch.create({ baseURL: config.public.apiBaseUrl || undefined, ... })`，401 重试逻辑不动。

### 1.2 `server/utils/cloudbase-admin.ts` — node-sdk 单例

模块级缓存 `cloudbase.init({ env: config.public.tcbEnvId, secretId, secretKey })`，导出 `useCloudbaseAdmin()` 返回 `{ app, db }`。

### 1.3 `server/utils/cloudbase-auth.ts` — 服务端鉴权（本计划核心新增）

方式：**远程 `/auth/v1/user/me` 验证 + 进程内缓存 + 本地 exp 预检**（不做本地 JWT 签名校验——CloudBase v2 无官方 JWKS 文档保障）。

```ts
export interface ServerAuthUser { uid: string, name?: string, picture?: string }
export async function requireCloudbaseUser(event: H3Event): Promise<ServerAuthUser>  // 无效抛 createError 401
export async function tryGetCloudbaseUser(event: H3Event): Promise<ServerAuthUser | null>  // GET 用，不抛错
```

实现要点：
1. 取 `Authorization: Bearer <token>`，无则 401（message '请先登录'）。
2. 本地 base64url 解码 JWT payload 查 `exp`，过期直接 401（零网络；客户端 `$api` 收到 401 自动刷新重试，新 token 自然绕过缓存）。
3. 进程内 `Map<sha256(token), { user, expiresAt }>` 缓存，TTL = `min(exp - now, 5min)`，上限 500 条简单淘汰。
4. 未命中 → `fetch('https://${tcbEnvId}.api.tcloudbasegateway.com/auth/v1/user/me', { headers: { Authorization }, signal: AbortSignal.timeout(5000) })`，非 2xx → 401；`uid = profile.sub`，字段映射参照 useCloudbaseAuthCore.ts 的 `mapCloudbaseUser`。

### 1.4 `server/utils/moderation.ts` — TMS 封装（内部 util，不开公开接口）

```ts
export type ModerationSuggestion = 'Pass' | 'Review' | 'Block'
export interface ModerationResult {
  suggestion: ModerationSuggestion
  label?: string, subLabel?: string, keywords?: string[], requestId?: string
  error?: string   // TMS 失败时填充，suggestion 固定 'Review'
}
// 拼接：parts.filter(Boolean).join('\n')，防御性截断 9500 字符
export function buildModerationContent(parts: (string | undefined)[]): string
// new TmsClient({ region: 'ap-guangzhou', reqTimeout 5s })；Content base64；BizType 从 config；DataId；User: { UserId }
export async function moderateText(opts: { content, userId, dataId, scene: string }): Promise<ModerationResult>
// 写 moderation_tasks，自身 try/catch 吞错（日志失败不影响主流程）
export async function logModerationTask(db, task): Promise<void>
```

失败策略：TMS 抛错/超时/响应异常 → `{ suggestion: 'Review', error }`。文件内注释标注扩展点：「应用提交预检后续可加 /api/apps/precheck 复用本 util」。

---

## 阶段 2：评论集合与 API

### 2.1 `app_reviews` schema（`app/types/review.ts` 定义，server 相对导入）

```ts
interface ReviewRecord {
  _id: string
  appKey: string          // apps.slug
  appId: string           // apps 文档 _id 冗余
  uid: string
  authorName: string      // 昵称快照
  authorAvatar?: string
  rating: number          // 1-5 整数
  title?: string          // ≤100 字符
  content: string         // 1-1000 字符
  status: 'published' | 'pending' | 'rejected'
  rejectedReason?: string // Block 时写 Label/SubLabel
  moderation?: { suggestion: string, label?: string, requestId?: string }
  createdAt: number, updatedAt: number, publishedAt?: number
}
```

### 2.2 `scripts/cloudbase-rules/app_reviews.json`

```json
{
  "read": "doc.status == 'published' || auth.uid == doc.uid",
  "create": false, "update": false, "delete": false
}
```

（包装成 apps.json 同款 `updateResourcePermission` 格式；admin node-sdk 不受规则约束，这就是「只能走 server 写」的机制。）

### 2.3 `server/utils/reviews.ts` — 纯逻辑（可单测）

- `validateReviewInput(body)` → 400；rating ∈ 1..5 整数、content 1-1000、title ≤100
- `mapSuggestionToStatus(s)`：Pass→published、Review→pending、Block→rejected
- `computeReviewSummary(ratings)` → `{ average(1 位小数, 空时 0), count, distribution }`
- `checkCooldown(db, collection, uid, 60_000)` → 命中抛 429

纯函数从 `h3` 显式 import `createError`，保证 unit node 环境可跑。

### 2.4 API（错误约定：成功 `{ code: 0, data }`；错误一律 `createError` 真实 HTTP 状态码——400/401/403/404/409/429/500。**禁止「200 + code: 400」混合模式**，否则客户端 401 重试失效）

**`server/api/reviews/index.get.ts`**（公开，tryGetCloudbaseUser）

```
GET /api/reviews?appKey=cook
→ { code: 0, data: {
    summary: { average, count, distribution },
    reviews: [...published, orderBy updatedAt desc, limit 50],   // 仅公开字段
    myReview: ReviewRecord | null    // 登录时返回本人那条（含 pending/rejected + rejectedReason）
}}
```

summary 现算：`where({ appKey, status: 'published' }).limit(1000).field({ rating: true })` 后内存计算。

**`server/api/reviews/index.post.ts`**（requireCloudbaseUser，upsert）

流程：validate → admin db 查 `apps where({ slug: appKey, isPublic: true, status: 'approved' })` 不存在 404 → checkCooldown 429 → `moderateText(buildModerationContent([title, content]), uid, dataId)` + logModerationTask → 查 `where({ appKey, uid })` 有则 update（状态按新审核结果重置）无则 add → 返回 `{ code: 0, data: { status, message?, review } }`（pending: '已提交，审核通过后展示'；rejected: '内容涉嫌违规，未能发布'）。

**`server/api/reviews/[id].delete.ts`**（requireCloudbaseUser）：doc.uid 不匹配 403；成功 `{ code: 0 }`。

---

## 阶段 3：举报集合与 API

### 3.1 `app_reports` schema

```ts
interface ReportRecord {
  _id: string
  uid: string
  targetType: 'app' | 'review'
  targetId: string        // app→slug，review→评论 _id
  appKey?: string         // review 举报时冗余
  reason: 'illegal' | 'porn' | 'abuse' | 'spam' | 'privacy' | 'other'
  detail?: string         // ≤500 字符
  reasonModeration?: { suggestion: string, label?: string }  // 仅标记
  status: 'open' | 'resolved' | 'dismissed'
  createdAt: number, updatedAt: number
}
```

### 3.2 规则：`app_reports.json`、`moderation_tasks.json` 全部 read/create/update/delete `false`（纯服务端集合）。`scripts/cloudbase-rules/apply.sh` 的集合列表追加三个新集合。

`moderation_tasks` 字段：`scene, targetId, uid, contentLength, suggestion, label, subLabel, keywords, requestId, error, durationMs, createdAt`。

### 3.3 `server/api/reports/index.post.ts`（requireCloudbaseUser）

流程：校验枚举/长度 → 目标存在性（app→apps where slug；review→app_reviews doc）404 → 去重 `where({ uid, targetType, targetId })` 已有 409 '你已举报过该内容' → checkCooldown 429 → detail 非空时 moderateText（scene 'report'，**结果只写 reasonModeration 不拦截**）→ 落库 `{ code: 0, data: { id } }`。

---

## 阶段 4：前端

### 4.1 `app/types/review.ts`

`ReviewStatus`、`ReviewRecord`、`ReviewPublic`、`ReviewSummary`、`ReportReason` 枚举 + label 映射（垃圾营销/色情低俗/违法违规/人身攻击/隐私泄露/其他）、API 响应类型。

### 4.2 `app/composables/useAppReviews.ts`

state：`summary / reviews / myReview / loading / error`。方法：`load()`（`$api` GET，未登录也能拿公开数据）、`submitReview({ rating, title, content })`（按返回 status 用现有 useToast 提示，然后 load）、`deleteMyReview()`、`submitReport({ targetType, targetId, reason, detail })`（409/429 转友好文案）。未登录提交时引导 `/login`（userStore.isLoggedIn）。

### 4.3 组件（`app/components/app/`，自动注册）

- `ReviewSection.vue`：评分汇总（真实 average + distribution 条）+ 评论列表 + 写评论按钮 + 本人评论置顶（pending 显「审核中」徽标，rejected 显原因 + 编辑入口）。样式搬 [id].vue 323-399 行现有 scoped class。
- `ReviewForm.vue`：IonModal sheet；星级点选 + title input + content textarea（1000 字数计数）+ 提交；编辑模式预填 myReview。
- `ReviewItem.vue`：单条评论（头像/星/标题/内容/相对时间）+ 举报入口。
- `ReportSheet.vue`：举报理由 actionSheet → 可选 detail → submitReport。

### 4.4 `app/pages/app/[id].vue` 改造

- 删 54-63 行假 reviews 数据。
- 323-399 行评分评论 section 替换为 `<AppReviewSection :app-key="appData.slug || appData.id" />`；无评论显示空态「成为第一个评论的人」；`summary.count > 0` 时头部评分用真实均分，否则回落运营预设 `rating`。
- 115-139 行 `openMoreMenu` 的 mailto 举报换成 ReportSheet（未登录跳登录 + toast）。

---

## 阶段 5：测试

unit project（node 环境，沿用 [test/unit/useApps.test.ts](test/unit/useApps.test.ts) 的 `createMockDb` 链式 mock + `vi.stubGlobal` 风格）：

| 文件 | 覆盖 | mock |
|---|---|---|
| `test/unit/moderation.test.ts` | 拼接/截断/base64；Pass/Review/Block 解析；TMS 抛错/超时→'Review'+error | `vi.mock('tencentcloud-sdk-nodejs-tms')` |
| `test/unit/server-reviews.test.ts` | validate 边界（rating 0/6/小数、content 空/超长）；状态映射；summary（空/单条/分布/小数位）；cooldown | createMockDb 同款 |
| `test/unit/cloudbase-auth.test.ts` | Bearer 解析、exp 过期本地 401、缓存命中零请求、/user/me 4xx→401 | `vi.stubGlobal('fetch')` + 手造 base64url JWT |
| `test/unit/useAppReviews.test.ts` | load 映射、submitReview 各 status 分支、409/429 文案 | stub useNuxtApp().$api + useUserStore |

handler 保持薄壳不直接测。静态检查：`pnpm typecheck`、`pnpm lint`、`pnpm test:unit`。

---

## 需要用户手动操作（代码外，codex 应在交付说明中列出）

1. 腾讯云开通**文本内容安全 TMS**；按需在控制台建自定义词库 + BizType 策略（BizType 可先留空用默认）。
2. 建 **CAM 子账号**（仅编程访问），授权 TMS + TCB（可收紧到集合粒度），生成 SecretId/Key。
3. SCF 函数（yunle-fun）环境变量：`NUXT_TENCENT_API_SECRET_ID`、`NUXT_TENCENT_API_SECRET_KEY`、`NUXT_TMS_BIZ_TYPE`；本地 `.env` 同步（`.env.example` 也更新）。
4. CloudBase 控制台建集合：`app_reviews`、`app_reports`、`moderation_tasks`。
5. 建索引：`app_reviews` 唯一 `(appKey, uid)` + 普通 `(appKey, status)`；`app_reports` 唯一 `(uid, targetType, targetId)`。
6. 应用规则：`bash scripts/cloudbase-rules/apply.sh`。
7. **核对 uid 一致性**：用真实 token 调一次 `/auth/v1/user/me`，确认 `sub` == 现有 apps 文档 `_openid`（鉴权体系的关键假设，实现前验证）。
8. 运营流程：控制台筛 `app_reviews.status=='pending'`、`app_reports.status=='open'` 人工处理（同现有 apps 审核习惯）。

## 验证（集成）

- `http://localhost:8001/app/<slug>`：未登录可看公开评论与均分；登录后提交正常评论 → published 立即可见；命中词库/违规文本 → pending（「审核中」徽标）或 rejected（显示原因可编辑重提）；二次提交覆盖原评论；60s 内连发 → 429 提示。
- 举报：登录后对 app/评论举报成功，重复举报 → 409。
- js-sdk 控制台手测：直写三个新集合全部被规则拒绝；未登录直读 app_reviews 只见 published。
- `pnpm typecheck && pnpm lint && pnpm test:unit` 全绿。

## 范围外（明确不做）

- 应用提交/编辑的 TMS 预检（人工审核兜底，moderation.ts 留扩展点注释）。
- Capacitor iOS 原生壳完整支持（仅预留 `apiBaseUrl`，CORS 与原生联调另开任务）。
- 评论分页（limit 50 + 预留 query 参数）、聚合计数冷写回、admin 审核后台 UI、图片审核。
- @yunlefun/types 迁移（类型先放本仓库 app/types/review.ts）。

> 后续进展（2026-06）：上表「admin 审核后台 UI」已在 `ylf/admin` 仓库落地（评论审核 + 举报处理双 Tab，举报列表会 join 回显被举报内容快照——评论正文/评分/状态/作者、应用名称/图标）；本仓库已补充用户侧「我的举报」反馈页（`/user/reports` + `GET /api/reports`，经管理端 SDK 鉴权代理，仅下发对举报人安全的字段，不含机审/处理人/处理备注）。两者独立于本方案的初始交付范围。
