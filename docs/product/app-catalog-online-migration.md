# 应用目录在线化迁移方案

> 状态：草案，待评审
> 目标：把当前**手维护的静态应用目录**（`ALL_APPS`）改造为**以 CloudBase `apps` 集合为唯一事实源**，同时保留离线 / 首屏能力。
> 关联：[[discovery]]、[[workshop]]、admin「寻乐运营」模块、`apps` 集合（[database/apps](../database/apps.md)）。

## 1. 背景与问题

发现页的「编辑精选 / 本周热门」已经在线化（`featured_apps` / `weekly_charts`，由 admin 运营平台维护）。但运营平台挑选应用时只能从 `apps` 集合取——而 38 个第一方应用目前**硬编码在前端 `app/constants/apps/index.ts` 的 `ALL_APPS` 里，并不在集合中**，导致：

- 运营平台**选不到第一方应用**（精选/热门只能选社区提交的应用）。
- 改一个应用（名称、链接、下线）要**改代码 + 发版**。
- 同一份目录维护在两处（静态 + 集合），`resolveApp` 还**静态优先**，admin 即使把某应用写进集合也**无法覆盖**第一方那份。

## 2. 核心决策：线上为准 + 内置兜底（**不走纯线上**）

**结论：事实源迁到集合，但保留一份「构建时生成的内置快照」作为离线/首屏兜底，而不是删掉静态裸奔。**

理由（为什么不纯线上）：

1. 本项目是 **Capacitor 原生 App（iOS/Android + 微信）**，`apps` 集合目前**无任何本地缓存层**。纯线上 = 每次冷启动应用网格/桌面都要等网络，弱网/离线直接空白。
2. **首屏与离线**：静态目录编译时打包，秒开且离线可用；Home Screen 的 Dock/Grid 直接依赖目录解析 `appId`，安装的应用必须随时可解析。
3. 38 个**全是第一方、低频变动**，真正高频的是推荐/精选/热门——那部分已在线上。核心目录的「在线化」收益主要在**统一管理**，不在「实时性」。

因此方向是把静态从「手维护的真源」降级为「自动生成的离线缓存」，把集合升级为「唯一真源」。

## 3. 现状盘点

### 3.1 两个数据源

| 数据源                                | 位置                            | 性质       | 现状                                                                               |
| ------------------------------------- | ------------------------------- | ---------- | ---------------------------------------------------------------------------------- |
| 静态 `ALL_APPS`（38）/ `FEATURED_APP` | `app/constants/apps/index.ts`   | 编译时打包 | 手维护，第一方                                                                     |
| `apps` 集合                           | CloudBase NoSQL                 | 运行时拉取 | 用户经 `workshop/new` 提交，`status: pending→approved`，**当前无种子、无审核后台** |
| 内置系统应用                          | `app/constants/apps/builtin.ts` | 编译时打包 | 外壳应用（设置等），**应保持静态**                                                 |
| `homeApps`（18）                      | `app/constants/apps/data.ts`    | 编译时打包 | 首页演示数据，与目录无关，**另行清理**                                             |

### 3.2 Schema 差异（迁移的关键）

静态 `YlfAppInfo` 与集合 `AppRecord` 字段并不一致，迁移必须做映射：

| 静态 `YlfAppInfo`                             | 集合 `AppRecord`                                                           | 处理                                                                |
| --------------------------------------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `id`                                          | `_id`（自动）                                                              | 不迁；改以 `slug` 为业务主键                                        |
| `slug`                                        | `slug`（唯一索引）                                                         | 直接映射，作幂等键                                                  |
| `name` / `description` / `emoji` / `category` | 同名                                                                       | 直接映射                                                            |
| `color`                                       | `themeColor`                                                               | **重命名映射**                                                      |
| `url`                                         | `websiteUrl`                                                               | **重命名映射**                                                      |
| `icon`                                        | `logo`                                                                     | **重命名映射**                                                      |
| `rating` / `downloads` / `size` / `age`       | —（集合无）                                                                | **展示用「伪指标」**，见 §10 待确认：扩展集合存它 or 借机清除       |
| `subtitle` / `tagline`                        | —（集合无）                                                                | 仅 `FEATURED_APP` 用；精选覆盖已由 `featured_apps` 承担，应用级可丢 |
| —                                             | `ownerLogin` / `isPublic` / `status` / `tags` / `githubRepo` / `backupUrl` | 迁入时补默认值                                                      |

集合读规则：`doc.isPublic == true || auth.uid == doc._openid`；发现页/工坊查询额外带 `status: 'approved'` 过滤。种子数据统一 `isPublic: true, status: 'approved'`。

### 3.3 `ALL_APPS` / `FEATURED_APP` 引用点（8 处，迁移需逐一改造）

| 文件                                | 用途                                          |
| ----------------------------------- | --------------------------------------------- |
| `composables/useDiscovery.ts`       | 发现页推荐 + 周榜（静态兜底）                 |
| `composables/useWorkshop.ts`        | 工坊列表（静态优先 + 集合去重追加）           |
| `composables/useAppDetail.ts`       | 详情页（静态优先查找）                        |
| `components/app/HomeScreenDock.vue` | 桌面 Dock                                     |
| `components/app/HomeScreenGrid.vue` | 桌面网格                                      |
| `pages/recent.vue`                  | 最近使用                                      |
| `pages/tabs/home.vue`               | 首页（+ `homeApps` 演示）                     |
| `constants/apps/index.ts`           | `getAppById` / `getAppsByCategory` 等工具函数 |

### 3.4 当前解析优先级（需翻转）

`resolveApp` / `useAppDetail` 均**静态优先 → 集合兜底**。在线化后应翻转为**集合（含本地缓存）优先 → 内置快照兜底**，否则 admin 对第一方应用的编辑永远不生效。

## 4. 目标架构

```
┌─────────────────────────────────────────────┐
│  CloudBase apps 集合   ← 唯一事实源            │  全量目录(第一方 + 社区), admin 审核/CRUD
└───────────────┬─────────────────────────────┘
                │ 运行时拉取 approved+public
┌───────────────▼─────────────────────────────┐
│  localStorage 缓存     ← 冷启动 / 弱网兜底     │  上次成功拉取的目录快照 + 时间戳
└───────────────┬─────────────────────────────┘
                │ 缓存缺失时
┌───────────────▼─────────────────────────────┐
│  内置快照(构建时生成)  ← 离线 / 首屏           │  prebuild 从集合生成, 取代手维护 ALL_APPS
└─────────────────────────────────────────────┘
```

数据流（`useAppCatalog` 统一出口）：

1. 启动即用「内置快照」渲染首屏（0 延迟、离线可用）。
2. 命中 localStorage 缓存则用缓存覆盖（更新）。
3. 后台异步拉取集合 → 成功则刷新 UI + 写回 localStorage；失败静默降级。

## 5. Schema 统一方案（命名对齐，已定）

**决策：以 `apps` 集合命名为规范源（canonical），把 `YlfAppInfo` 向它对齐**——因为集合将成为唯一事实源，且其命名本身是更好的通用实践。对齐后转换层近乎直通。

> 改动面已评估：`@yunlefun/types` 是 monorepo 内部包（`ylf/packages/types/`），**仅 apps.yunle.fun 依赖**，对齐波及约 40 个文件、全在 apps.yunle.fun，**不影响 www/admin/api 等其他仓库**。

字段重命名（旧 → 新规范名）：

| 旧 `YlfAppInfo` | 新规范名     | 说明                                                        |
| --------------- | ------------ | ----------------------------------------------------------- |
| `color`         | `themeColor` | 语义明确，避免与文字色混淆，默认 `#007AFF`                  |
| `url`           | `websiteUrl` | 与 `backupUrl` 区分                                         |
| `icon`          | `logo`       | 品牌图 URL，与 `emoji` 并列；展示优先级 `logo > emoji > 📱` |
| `id`            | （弱化）     | 业务主键统一用 `slug`；`_id` 仅作文档主键                   |

规范字段全集（前端 `YlfAppInfo` 与集合 `AppRecord` 一致）：
`slug`(业务主键) · `name` · `description` · `emoji` · `themeColor` · `logo` · `websiteUrl` · `backupUrl` · `category` · `tags` · `githubRepo` · `rating?` · `downloads?` · `size?` · `age?`（展示用，保留作未来扩展）；
持久化专属：`_id` · `_openid` · `ownerLogin` · `isPublic` · `status` · `rejectedReason?` · `reviewedAt?` · `createdAt` · `updatedAt`。

对齐后保留一个 `recordToAppInfo(record)` 薄封装：仅做 `logo>emoji>📱`、`themeColor` 默认值等兜底，不再改字段名。

## 6. 分阶段实施

### Phase 0 — Schema 命名对齐 ✅ 已完成

按 §5 把 `YlfAppInfo` 字段对齐集合：`color→themeColor`、`url→websiteUrl`、`icon→logo`（`id` 暂保留，slug 收敛留后续）。落地情况：

- `ylf/packages/types/src/app.ts` 重命名字段 + bump `0.0.1→0.0.2`；修复 `release.yml` 的 tag glob（`*@*` 不匹配 scoped tag，补 `*/*@*`）；经 OIDC 发布 **@yunlefun/types@0.0.2** 到 npm（PR ylf#4、tag `@yunlefun/types@0.0.2`）。
- apps.yunle.fun 依赖 bump 到 `^0.0.2`，21 个源码文件改完旧字段引用，常量数据 key 同步重命名；`pnpm typecheck`（忽略遗留 `src/`）与 `pnpm lint` 均通过。
- 避坑：`AppCategory.icon`（分类图标）、`[id].vue` 的 screenshot `.color`、`constants/links.ts` 的链接对象均与 `YlfAppInfo` 无关，保持不动。

### Phase 1 — 灌数据迁移脚本（低风险，半天）✅ 可立即做

目的：把 38 个第一方应用写入 `apps` 集合，**立刻解决运营平台选不到第一方应用的缺口**，且是后两步前提。

- 脚本位置：`scripts/migrate-builtin-apps.ts`（Node + `@cloudbase/node-sdk`，admin 凭据，与 admin 钱包同 env）。
- **幂等**：按 `slug` 先查后写（存在则 `update`，不存在则 `add`），避免唯一索引 `idx_slug_unique` 撞错、可重复执行。
- 写入字段：`name/slug/description/emoji/category` + `themeColor(=color)/websiteUrl(=url)/logo(=icon)`，统一 `isPublic:true, status:'approved', ownerLogin:'YunYouJun', tags:[]`，`createdAt/updatedAt=now`。
- `_openid` 归属见 §10。
- 验收：admin「寻乐运营」精选/热门下拉能搜到全部 38 个应用。

### Phase 2 — admin「应用管理」模块（中等）

目的：做出「线上为准」的控制台（集合现在没人管）。仿 admin 钱包/运营模块结构：

- `server/api/apps/{list,upsert,delete,review}.post.ts`（管理端 SDK 直接读写，写接口 `requireUserSession`）。
- `app/pages/apps/index.vue`：列表（按 status 过滤）+ 审核 pending（approve/reject + `rejectedReason`/`reviewedAt`）+ CRUD。
- 菜单挂到「寻乐运营」或「业务运维」下。

### Phase 3 — 前端在线化（较大，核心）

- 新增 `composables/useAppCatalog.ts`：统一目录出口，实现 §4 三层数据流 + localStorage 缓存（带 TTL/版本）。
- 新增构建时快照生成 `scripts/gen-app-snapshot.ts`：查集合 approved+public → 生成 `app/constants/apps/generated.ts`；接入 `prebuild`（CI 联网能力见 §10）。
- **翻转解析优先级**：`resolveApp`/`useAppDetail` 改为缓存/集合优先、内置快照兜底。
- 改造 §3.3 的 8 个引用点：从 `import { ALL_APPS }` 改为 `useAppCatalog()`；`getAppById/getAppsByCategory` 基于目录数据重写。
- `FEATURED_APP` 兜底改为「快照里第一个」或保留一个常量兜底。

### Phase 4 — 清理与回归

- `ALL_APPS` 由「手维护」退化为「生成快照」；删除手维护数组。
- `builtin.ts`（系统外壳应用）**保持静态**，明确与目录分离。
- `data.ts` 的 `homeApps` 演示数据按需清理。
- 回归重点：**离线启动**、**弱网首屏**、桌面已安装应用解析、工坊搜索/分类、详情页直达、深链。

## 7. 风险与回滚

| 风险                        | 缓解                                          |
| --------------------------- | --------------------------------------------- |
| 离线/弱网白屏               | 三层兜底；快照随包发布；缓存 TTL              |
| 集合数据被误删/误改影响线上 | Phase 2 加操作鉴权 + 审计；保留快照可随时回退 |
| `slug` 撞唯一索引           | 迁移脚本幂等 upsert                           |
| 伪指标字段丢失致 UI 异常    | §10 先定方案；映射函数对缺失字段给默认值      |
| 优先级翻转引入回归          | Phase 3 单独灰度；先翻发现页，再桌面/工坊     |

回滚：Phase 1/2 纯增量，不影响线上；Phase 3 若异常，恢复 `resolveApp` 静态优先 + 保留 `ALL_APPS` 即回到现状。

## 8. 验收清单

- [ ] 38 个第一方应用进入集合，运营平台可选
- [ ] admin 可审核 pending、可 CRUD 集合
- [ ] 飞行模式冷启动应用网格/桌面正常
- [ ] 弱网首屏无明显空窗（先快照后刷新）
- [ ] admin 编辑第一方应用，前端生效（验证优先级已翻转）
- [ ] 工坊搜索/分类、详情直达、深链全部正常

## 9. 工作量与建议节奏

| 阶段               | 量级    | 依赖                                |
| ------------------ | ------- | ----------------------------------- |
| Phase 0 命名对齐   | ~1-2 天 | 无（建议先做）                      |
| Phase 1 灌数据     | ~0.5 天 | 建议在 Phase 0 后                   |
| Phase 2 应用管理   | ~2-3 天 | Phase 1                             |
| Phase 3 前端在线化 | ~3-5 天 | Phase 0、Phase 1（与 Phase 2 并行） |
| Phase 4 清理回归   | ~1-2 天 | Phase 3                             |

建议节奏：**Phase 0 命名对齐 → Phase 1 灌数据**（两步都低风险、收益即时），再视需要推进 2/3。在 admin 审核后台（Phase 2）就绪前，不要急于让前端「只读集合」，以免把稳定盘押在无人管理的数据上。

## 10. 决策记录（Decisions）

1. ✅ **伪指标 `rating/downloads/size/age`**：**挪进集合作可选展示字段保留**，未来再扩展这些功能（无损迁移）。
2. ✅ **第一方应用 `_openid` 归属**：**设为 YunYouJun 真实 uid**，之后可在 workshop 自助编辑。
   - ⏳ 待提供：该 CloudBase auth uid 的实际值（获取方式见下「待办」）。
3. ✅ **Schema 命名**：**对齐到集合规范名**（`color→themeColor`、`url→websiteUrl`、`icon→logo`，主键收敛 `slug`），见 §5 / Phase 0。

仍待确认（次要）：

4. **快照生成时机**：`prebuild` 联网从集合实时生成（要求 CI 能访问 CloudBase 凭据），还是提交一份静态快照、定期手动/定时刷新？
5. **`category`**：维持中文名（`整活`/`工具`…）还是改用 `APP_CATEGORIES.id`？现状中文名，倾向保持以减少改动。
6. **迁移脚本归属仓库**：放 `apps.yunle.fun/scripts`（贴近源数据）还是 admin（已有管理端凭据）？

### 待办：提供第一方应用所属 uid

Phase 1 需要把 38 个应用的 `_openid` 设为你的真实 CloudBase uid。获取方式（任一）：

- CloudBase 控制台 → 环境 `yunlefun-8g7ybcxc7345c490` → 身份认证/用户管理，找到你的账号 uid；
- 若你已在 workshop 提交过应用：该文档的 `_openid` 即是；
- 登录 apps.yunle.fun 后从登录态/接口里读当前 uid。
