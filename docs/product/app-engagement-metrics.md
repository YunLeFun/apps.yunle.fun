# 应用互动指标设计：收藏 / 访问 / 有用 / 投币

> 状态：设计稿（2026-06-13）。收藏量为 Phase 1，投币为待决策方案。
> 原则延续应用详情改版定下的「**真实或不展示**」——所有计数由服务端真实维护，无数据则显示 0 / 隐藏，不再出现写死的运营数字（已移除的「下载量/大小」即此原因）。

## 1. 术语决策（先回答「叫什么最合适」）

| 动作 | 现有实现 | 语义 | 公开计数命名 |
|------|----------|------|--------------|
| **获取** | `useHomeScreen.installApp` → 加入「我的主屏」（CloudBase `user_home_screens`，按用户一份、云同步） | 个人**留存 / 收藏** | **收藏量**（"X 人收藏 / 在用"） |
| **打开** | `useOpenApp` / 内置浏览器 | **参与度**（用一次≠留存） | **访问量**（打开次数） |
| 下载量 | —（已删） | 网站无此概念 | 不用 |

**结论**：
- 「获取」本质就是收藏（把网站加进我的主屏 = 把它留下来）。所以**获取的聚合数 = 收藏量**，动作按钮仍叫「获取」（App Store 习惯），对外计数叫「收藏」。
- 「访问量」是另一个维度（打开次数），与收藏互补，需要单独的打开埋点。
- 二者都比旧的假「下载量」更真实、更难刷。

## 2. B 站「三连」取舍

| 机制 | 取舍 | 理由 |
|------|------|------|
| 收藏 | ✅ Phase 1 | 直接复用「获取/主屏」，只差把聚合数露出来，性价比最高 |
| 投币 | ✅ 但需先决策（见 §6） | 复用现有**云币**经济做打赏；但涉及开发者收款/防刷/**iOS 合规**，是支付+激励设计，非单纯指标 |
| 点赞 | ⚠️ 不给 app 独立点赞 | 与 5 星**评分**重叠，会变成两套打分信号。降级为评论的「有用 👍」 |
| 访问量 | ◻️ Phase 2（可选） | 另一维度的热度/趋势信号，需打开埋点 + 去重 |

## 3. 架构总览（四者共用）

```
客户端（只读计数） ── GET ──▶ apps 文档携带 favoritesCount / viewsCount / rating(聚合)
       │
       └── 写操作 ── POST ──▶ Nitro 服务端 (server/api/**)
                                 │ useCloudbaseAdmin()  ← admin SDK，绕过 owner-only 规则
                                 │ 校验登录态 (server/utils/cloudbase-auth)
                                 │ 限频 (复用 checkCooldown 模式)
                                 ▼
                      去规范化计数写回 apps / reviews 文档 + 明细集合去重
```

- **计数去规范化**到主文档：`apps.favoritesCount` / `apps.viewsCount`（评分聚合 `apps.rating`/`ratingCount` 见已立的待办——评论增删时回写）。列表/详情读主文档即可，无需逐应用拉明细。
- **明细集合**用于去重 + 回显「我是否已操作」：`app_favorites`(uid+appKey 唯一)、`review_helpful`(uid+reviewId 唯一)、`coin_votes`(投币流水)。
- **所有写计数走服务端 admin**：apps 集合更新规则是 owner-only，普通用户无法直接 +1；统一经 Nitro 路由用 `useCloudbaseAdmin()` 写。客户端只读。
- 读路径：计数字段随 `useAppCatalog.fetchFromCloud` / `useAppDetail` 进入 `YlfAppInfo`；`isFavorited` / `helpfulByMe` 经轻量 GET 或随列表返回。

## 4. Phase 1 — 收藏量（推荐先做）

**数据模型**
- `apps.favoritesCount: number`（去规范化计数，列表/详情展示）
- 集合 `app_favorites`：`{ uid, appKey, createdAt }`，`uid+appKey` 唯一（去重 + 回显 isFavorited）

**触发：复用「获取」，不新增按钮**
- `useHomeScreen.installApp(appId)` → 额外 `POST /api/apps/:key/favorite { on: true }`
- `useHomeScreen.uninstallApp(appId)` → `POST /api/apps/:key/favorite { on: false }`
- 服务端幂等：`on:true` 时 upsert `app_favorites`，**仅当新建**才 `db.command.inc(1)` favoritesCount；`on:false` 时删除明细并 `inc(-1)`（下限 0）。重复调用不重复计数。

**端点**
- `server/api/apps/[key]/favorite.post.ts`：校验登录 → toggle 明细 → inc/dec apps.favoritesCount → 返回 `{ favoritesCount, favorited }`
- 计数随 app 文档下发，无需额外 GET

**展示**
- 详情页统计条加一格「收藏」（`X` 人收藏），与「评分 / 年龄 / 开发者」并列
- 列表项副信息可加「♥ X」（可选）
- `recordToAppInfo` + admin 快照透传 `favoritesCount`

**实现文件清单**
- `server/api/apps/[key]/favorite.post.ts`（新）
- `app/composables/useHomeScreen.ts`（install/uninstall 调端点）
- `app/pages/app/[id].vue`（统计条加「收藏」格）
- `app/utils/appRecord.ts` + `app/types/app.ts`（favoritesCount 透传）
- `admin/scripts/gen-app-snapshot.ts`（快照透传）
- CloudBase：建 `app_favorites` 集合 + 安全规则（写经服务端 admin；如允许客户端直写则 `create/delete: auth.uid == doc.uid`）

**反作弊**：必须登录；`uid+appKey` 唯一天然防重复刷；卸载 -1 不低于 0；对账脚本按明细重算 count。

## 5. Phase 2 — 访问量（可选）

- 模型：`apps.viewsCount: number`
- 触发：打开应用时（`useOpenApp.doOpen` / `recordRecentUse`）`POST /api/apps/:key/view`（navigator.sendBeacon 优先）
- **去重/防刷**：同一 uid（或设备）+ appKey 在窗口期（如 30 min）只计一次——明细 `app_views{uid,appKey,lastAt}` 或服务端按最近时间窗判定；匿名用户按设备指纹粗去重或不计
- 展示：统计条「访问」格（可选）；主要作**热门/趋势排序**信号
- 注意：高频写入，考虑节流/批量；可只在 native 容器打开时计

## 6. Phase 4 — 投币（设计方案，**需你拍板后再实现**）

**目标**：复用云币让用户给「应用/开发者」打赏，形成热度 + 创作者激励。

**现状缺口**：`useCoin` 只有 `deduct`（扣费），**没有 credit / 分账给开发者**的路径。投币要新增「入账」。

**数据模型（草案）**
- `apps.coinsCount: number`（累计投币，热度展示）
- 集合 `coin_votes`：`{ uid, appKey, amount, bizId, createdAt }`（流水 + 幂等键）
- 开发者收益：`developer_earnings { ownerLogin, balance }`，或在账户表加 `earnings`

**流程**：`deduct(uid, amount, bizId=tip:{appKey}:{uid}:{ts})` → credit 开发者 earnings → `inc apps.coinsCount`（服务端事务/幂等）

**必须先决策的 5 点**
1. **投币给谁**：开发者个人？平台抽成比例？
2. **投币换什么**：纯荣誉/热度？解锁内容？排行加权？（换内容会触发下面的合规问题）
3. **上限/冷却**：每人每应用每日上限，防刷。
4. **开发者提现**：earnings 能否提现/兑换？涉及实名/合规。
5. **⚠️ iOS 合规（高风险）**：用云币给「数字内容/应用」打赏，Apple 很可能判定为**应用内购买数字内容**，必须走 IAP 并被抽成；绕过 IAP 用自有币打赏数字内容是审核红线。参考会员/IAP 的支付通道裁决经验（见仓库 `docs/product/` 与会员接入记录）。

**建议**：投币列为 v2，先在 **Web / Android** 验证形态与防刷，**iOS 端合规评估通过后**再开；或限定「打赏=纯荣誉、不解锁任何内容、不可提现」以尽量规避 IAP 红线（仍需法务/审核确认）。

## 7. 评论「有用」（替代独立点赞）

- 模型：`reviews.helpfulCount`；集合 `review_helpful { uid, reviewId }`（唯一）
- 端点：`server/api/reviews/[id]/helpful.post.ts`（toggle，admin inc/dec + 去重）
- 展示：`AppReviewItem` 加「有用 👍 N」按钮（已赞高亮）；评论列表返回 `helpfulByMe`
- 排序：评论可按 `helpfulCount` 优先
- 类型：`ReviewPublic` 加 `helpfulCount`；`ReviewListResponse` 加 `helpfulIds`（我赞过的）

## 8. 一致性与运维

- 计数与明细可能漂移（并发/失败）：提供 admin 对账脚本，按明细集合重算各 `*Count`。
- 新增的 apps 计数字段需在 CloudBase 控制台补字段；写入保持 owner-only，由服务端 admin 绕过。
- 计数字段一并纳入 `@yunlefun/types` 的 `YlfAppInfo`（与 downloads/size 移除、screenshots/developer 新增同批发包）。

## 9. 分期落地

| Phase | 内容 | 依赖 |
|-------|------|------|
| 1 | 收藏量（复用获取） | CloudBase 集合 + 服务端路由 |
| 2 | 访问量（埋点 + 去重） | 同上 |
| 3 | 评论「有用」 | 复用 reviews 服务端 |
| 4 | 投币 | §6 五点决策 + iOS 合规评估 |

## 10. 待拍板

- [ ] 「收藏 == 获取」（同一动作，不新增独立收藏按钮）确认？（建议：是）
- [ ] 访问量是否只在 native 计、匿名用户是否计入？
- [ ] 投币 §6 的 5 点，尤其 iOS 合规口径。
