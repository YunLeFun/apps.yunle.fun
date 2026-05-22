# 发布路线图

> 云乐坊 1.0 上架前置工作清单。状态以本文件为准，完成项打勾即可。
>
> 优先级：**P0** = 不修无法上架；**P1** = 修后上架更稳；**P2** = 体验/合规细节。

## 总判定

当前状态：**Web canary（dev.yunle.fun）可用，正式发布 / App Store 上架前仍有硬阻塞**。

预计排期 4 个 milestone，完成 M1 即可启动 TestFlight 内测。

---

## M1 · 补硬阻塞（目标：1 周内进入 TestFlight 内测）

### P0 已完成

- [x] **修正 iOS Info.plist 关键字段**
  - 删除过时的 `armv7`，改为 `arm64`
  - `CFBundleDevelopmentRegion` 由 `en` 改为 `zh-Hans`，并新增 `CFBundleLocalizations`
  - 添加 `ITSAppUsesNonExemptEncryption = false`（声明无加密导出，避免 TestFlight 卡合规）
  - 文件：[ios/App/App/Info.plist](https://github.com/YunYouJun/apps.yunle.fun/blob/main/ios/App/App/Info.plist)
- [x] **修复 workshop 编辑页 typecheck 报错**
  - `app/pages/workshop/[slug]/edit.vue` 缺失 `import { checkmark } from 'ionicons/icons'`
- [x] **修正 `capacitor.config.ts` 的 appId**
  - 改为 `appId: 'fun.yunle.apps'`，与 Xcode `PRODUCT_BUNDLE_IDENTIFIER` 和 AASA `appIDs` 对齐
  - 加注释提醒未来同步规则
- [x] **应用商店 ID 占位符替换**
  - `app/config/index.ts` 中 `appStore.id` 已更新为 `'6759859441'`
  - 同时简化 URL 为 `https://apps.apple.com/app/id${id}`（去掉占位 slug）
- [x] **iOS 端隐藏 GitHub 登录入口**（替代 SIWA 的策略）
  - 在 [app/config/auth.ts](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/config/auth.ts) 用 `Capacitor.isNativePlatform()` 强制原生平台 `github: false`
  - 即使将来把 `baseAuthMethods.github` 改成 `true`，iOS 端仍然隐藏，安全 by default
  - 兜底：如果首次提交被 4.8 拒，再补 SIWA（半天工作量）

### P0 待办

- [ ] **WeChat 登录 iOS 上架合规**
  - 当前微信 `appId = wx925d6e320d64f30a`，需要在腾讯开放平台完成 iOS 应用审核
  - 校验 [public/.well-known/apple-app-site-association](https://github.com/YunYouJun/apps.yunle.fun/blob/main/public/.well-known/apple-app-site-association) 的 `paths` 覆盖 `capacitor.config.ts` 的 `universalLink: 'https://www.yunle.fun/app/'`
  - 注意：[app/config/auth.ts](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/config/auth.ts) 当前 `baseAuthMethods.wechat = false`，腾讯开放平台审核通过后再改为 `true`

---

## M2 · 补安全 / 内容审核（目标：3 天）

### P1 已完成

- [x] **Workshop 应用审核流程**
  - 数据模型新增 `status: 'pending' | 'approved' | 'rejected'`、`rejectedReason`、`reviewedAt`（[app/types/app.ts](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/types/app.ts)）
  - 表单默认 `isPublic: false`，创建强制 `status: 'pending'`，更新会重置为 `pending`（[useAppForm.ts](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/composables/useAppForm.ts) + [useApps.ts](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/composables/useApps.ts)）
  - 公开查询（useApps / useWorkshop / useDiscovery / useAppDetail）全部加 `status: 'approved'` 过滤
  - 我的应用列表显示「审核中 / 已拒绝」状态徽章及拒绝原因
  - 应用详情页加「举报此应用」入口（mailto 模板，自动带应用信息）
- [x] **CloudBase 安全规则文档化**（用户需手动同步到控制台）
  - read: `(doc.isPublic == true && doc.status == 'approved') || auth.uid == doc._openid`
  - write: `auth.uid == doc._openid`
  - 详见 [useApps.ts 头部注释](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/composables/useApps.ts)

### P1 待办

- [x] **CloudBase 安全规则同步**（已通过 MCP 自动应用）
  - 通过 CloudBase MCP 一次性应用到生产环境 `yunlefun-8g7ybcxc7345c490`
  - `apps` / `user_home_screens` 用 CUSTOM 拆分 read/create/update/delete 四元组
  - `featured_apps` / `weekly_charts` 用 READONLY 内置预设（运营在控制台写）
  - 规则源文件版本化存放于 [`scripts/cloudbase-rules/`](https://github.com/YunYouJun/apps.yunle.fun/tree/main/scripts/cloudbase-rules)
  - 一键重放命令：`bash scripts/cloudbase-rules/apply.sh`
  - 详细文档：[`docs/dev/cloudbase-rules.md`](./dev/cloudbase-rules.md)

### P1 已完成

- [x] **接入腾讯云 RUM 错误监控**
  - 安装 `aegis-web-sdk`，AppID `nG8jRFK2e30nRrle5R` 已写入 [`nuxt.config.ts`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/nuxt.config.ts)
  - [`app/plugins/rum.client.ts`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/plugins/rum.client.ts) 用户登录后自动 setConfig({ uin })，便于按用户聚合错误
  - 上报项：JS 异常 + 资源 4xx/5xx + 接口测速 + Web Vitals + SPA pv
  - 验证：发版后到 <https://console.cloud.tencent.com/rum> 看上报数据

---

## M3 · 补功能闭环（目标：视产品决策）

### P1 已完成

- [x] **底部 Dock 栏**
  - 实测发现：组件 ([`HomeScreenDock.vue`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/components/app/HomeScreenDock.vue)) / store (`dockApps`) / 同步链路全部 100% 实现，只是被 `tabs/home.vue:42` 一行 `computed(() => false)` 临时禁用
  - 启用：`showDock = computed(() => settingsStore.dockVisible)`
  - 设置页 [`user/settings.vue`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/pages/user/settings.vue) 解除 disabled，接 `settingsStore.dockVisible` v-model
  - 默认关闭，用户在「设置 → 主屏幕 → 显示 Dock 栏」打开
- [x] **扫码手电筒切换**
  - 新增 [`useTorch.ts`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/composables/useTorch.ts) 通用 composable —— 基于 W3C `MediaStreamTrack.applyConstraints({ torch })` 标准 API，无第三方依赖
  - [`Barcode.vue`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/components/scanner/Barcode.vue) 接入：按钮仅在设备支持时显示（前置摄像头/Firefox 自动隐藏），开关时图标变色
  - 支持矩阵：Chrome/Edge mobile + iOS Safari 17.4+ + Capacitor WebView，其他平台静默降级

### P1 待办

- [ ] **PC 端微信扫码登录卡片**（推迟到 1.x）
  - [`app/components/wx/LoginCard.vue:68`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/components/wx/LoginCard.vue) TODO
  - 用户已确认：可后续再做（手机号/邮箱/密码登录已经覆盖 PC 主链路）

---

## M4 · 发版 dry-run（目标：2 天）

### P1 已完成

- [x] **CI 补 test job**
  - [.github/workflows/ci.yml](https://github.com/YunYouJun/apps.yunle.fun/blob/main/.github/workflows/ci.yml) 增加 `test` job 跑 `pnpm test:unit`
  - 同时升级 actions 到 v4 + pnpm/action-setup v4 + 使用 `--frozen-lockfile`

### P1 待办

- [ ] **bump 版本号**（**发版最后一步**）
  - [package.json](https://github.com/YunYouJun/apps.yunle.fun/blob/main/package.json) `version: 0.0.1`
  - 用 `pnpm release`（基于 bumpp）打 `1.0.0`
  - Xcode `MARKETING_VERSION` 同步

### P2 已完成

- [x] **iOS StatusBar / Splash 显式配置**
  - [capacitor.config.ts](https://github.com/YunYouJun/apps.yunle.fun/blob/main/capacitor.config.ts) 添加 `StatusBar`（style: DEFAULT, overlaysWebView: true）和 `SplashScreen` 配置
- [x] **SEO + 分享卡**
  - [nuxt.config.ts](https://github.com/YunYouJun/apps.yunle.fun/blob/main/nuxt.config.ts) `app.head` 补 Open Graph + Twitter Card + theme-color
  - [public/robots.txt](https://github.com/YunYouJun/apps.yunle.fun/blob/main/public/robots.txt) 加 sitemap 引用 + Disallow 私有路由
  - [public/sitemap.xml](https://github.com/YunYouJun/apps.yunle.fun/blob/main/public/sitemap.xml) 新增基础站点地图（三大 Tab + 静态页）
  - **TODO**：放一张 1200×630 的 `public/og-image.png` 分享封面（设计交付物）
- [x] **README 完善**
  - 加徽章、架构图、命令表、目录结构说明、贡献流程

### P2 待办

- [ ] **核对外链隐私政策 / 服务条款内容覆盖范围**
  - URL 已验证可访问：<https://www.yunle.fun/docs/privacy-policy>、<https://www.yunle.fun/docs/terms-of-service>
  - App Store Connect 接受外链，无需在 App 内单独生成
  - **完整核对清单见 [`docs/dev/privacy-checklist.md`](./dev/privacy-checklist.md)**
  - 已用 `open` 帮用户在浏览器打开两个页面，需要用户人工核对清单逐项打勾
- [ ] **iOS Splash 多套素材**
  - 当前 `ios/App/App/Assets.xcassets/Splash.imageset/` 仅有单张 2732×2732，建议 Light/Dark 分别一套
- [ ] **ICP 备案 / App Store 中国区备案号**
  - `yunle.fun` 域名在国内提供服务通常需要工信部备案；App Store 中国区 2023-09 起强制要求备案号
- [ ] **设计交付：`public/og-image.png`**
  - 1200×630px，社交分享/微信预览用

---

## 已完成的发布前准备（参考）

> 这些不是 roadmap 项，仅记录已经满足的基线，避免重复盘点。

- 构建产物 2.55 MB / 637 KB gzip，合理
- Ionic 三 Tab 路由结构稳定
- 暗黑模式/主题色全部走 CSS 变量（2026-05 完成清理：硬编码颜色 196 → 61，剩余均为反白文字/阴影/品牌色等合理保留）
- 微信 / 手机号 / GitHub 登录链路存在
- iOS Universal Link 与 URL Scheme 已配置
- 应用发现 / 工坊 / 详情页骨架完整
- 单元测试 7 个套件覆盖核心 store / composable
- `pnpm build` 正常出包

---

## 维护说明

- 路线图变更时**先改本文件**，再去对应文件改代码
- 完成一项就把 `- [ ]` 改成 `- [x]`，并在 PR 描述里引用本文件锚点
- 新增 P0/P1 项需要先在文末"变更记录"加一行
- 当前未规划但讨论过的想法（多端同步策略、应用评分、应用付费）暂不列入，等 1.0 上线后再开 1.1 路线图

### 变更记录

| 日期       | 变更                                                                                                                                                                                                    |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-05-21 | 初始版本，基于上架前置盘点产出                                                                                                                                                                          |
| 2026-05-22 | SIWA 改为可选 fallback，改用 iOS 端隐藏 GitHub 登录策略；隐私政策已外链可访问，降为 P2 内容核对；新增 P0 Bundle ID 不一致项                                                                             |
| 2026-05-22 | 完成 4 项 P0：Apple ID 回填 6759859441 / capacitor appId 修正 / GitHub iOS 隐藏 / Info.plist 已在前一日完成；M1 仅剩微信合规 1 项依赖外部审核                                                           |
| 2026-05-22 | 完成 M2 Workshop 审核流程 + M4 CI/StatusBar/SEO/README；M2 仅剩错误监控（等 Sentry DSN）+ CloudBase 规则手动同步；M3 三项功能闭环和「bump 版本号」是发版前最后一组待办                                  |
| 2026-05-22 | 完成 M3 Dock 启用（发现是死代码 1 行修复）+ 扫码手电筒（新增 useTorch composable）；错误监控选型改为腾讯云 RUM（docs/dev/rum.md + plugin scaffold），等用户拿 AppID；M3 PC 端微信扫码登录确认延后到 1.x |
