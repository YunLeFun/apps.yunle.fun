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

### P1

- [ ] **Workshop 应用审核流程**
  - 现状：[app/composables/useAppForm.ts](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/composables/useAppForm.ts) 提交时默认 `isPublic: true`，CloudBase 规则 `isPublic == true || auth.uid == doc._openid` 即所有人可读
  - 用户提交后立即对全平台可见 → 色情/钓鱼/违规外链风险
  - 改造：默认 `isPublic: false`，加 `status: 'pending' | 'approved' | 'rejected'` 字段；后台审核通过才公开
  - 加举报入口（IAPP 必备）
- [ ] **接入错误监控**
  - 选型推荐 Sentry 免费档（5k errors/月）
  - 同时上报：未捕获异常、网络 4xx/5xx、关键链路埋点（登录失败、CloudBase 调用失败）

---

## M3 · 补功能闭环（目标：视产品决策）

> 以下三个功能均处于「文档/UI 承诺但实际未交付」状态，发版前需二选一：要么补完，要么从产品文案中删除。

### P1

- [ ] **底部 Dock 栏**
  - 当前 [app/pages/tabs/home.vue:42](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/pages/tabs/home.vue) `showDock = computed(() => false)`
  - 设置页开关 [app/pages/user/settings.vue:174](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/pages/user/settings.vue) `disabled` + 文案"功能开发中"
  - 产品定位文档 [docs/product/index.md](./product/index.md) 将其列为云居核心特性
- [ ] **扫码手电筒切换**
  - [app/components/scanner/Barcode.vue:94](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/components/scanner/Barcode.vue) TODO
  - 弱光场景必需，体验关键
- [ ] **PC 端微信扫码登录卡片**
  - [app/components/wx/LoginCard.vue:68](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/components/wx/LoginCard.vue) TODO
  - 影响桌面 Web 端登录链路完整性

---

## M4 · 发版 dry-run（目标：2 天）

### P1

- [ ] **CI 补 test job**
  - 当前 [.github/workflows/ci.yml](https://github.com/YunYouJun/apps.yunle.fun/blob/main/.github/workflows/ci.yml) 只跑 lint + typecheck
  - `test/unit/` 下有 7 个套件未在 CI 跑，合入有静默回归风险
  - 补 `pnpm test:unit` job
- [ ] **bump 版本号**
  - [package.json](https://github.com/YunYouJun/apps.yunle.fun/blob/main/package.json) `version: 0.0.1`
  - 用 `pnpm release`（基于 bumpp）打 `1.0.0`
  - Xcode `MARKETING_VERSION` 同步

### P2

- [ ] **核对外链隐私政策 / 服务条款内容覆盖范围**
  - URL 已验证可访问：<https://www.yunle.fun/docs/privacy-policy>、<https://www.yunle.fun/docs/terms-of-service>
  - App Store Connect 接受外链，无需在 App 内单独生成
  - 内容核查清单：
    - 收集的数据类型（手机号、微信 openid/unionid、设备 ID、应用使用日志）
    - 数据存储位置（CloudBase 上海机房，符合数据本地化）
    - 第三方 SDK（CloudBase JS SDK、Capacitor、微信 SDK；GitHub OAuth 仅 Web）
    - 用户权利（注销账号、导出/删除数据、申诉邮箱）
- [ ] **iOS StatusBar 显式配置**
  - [capacitor.config.ts](https://github.com/YunYouJun/apps.yunle.fun/blob/main/capacitor.config.ts) 当前只配了 `Keyboard`，没配 `StatusBar`
  - 某些页面状态栏文字/背景可能撞色
- [ ] **iOS Splash 多套素材**
  - 当前 `ios/App/App/Assets.xcassets/Splash.imageset/` 仅有单张 2732×2732，建议 Light/Dark 分别一套
- [ ] **SEO + 分享卡**
  - [public/robots.txt](https://github.com/YunYouJun/apps.yunle.fun/blob/main/public/robots.txt) 只 `Allow: /`，没 sitemap
  - [nuxt.config.ts](https://github.com/YunYouJun/apps.yunle.fun/blob/main/nuxt.config.ts) `app.head` 缺 Open Graph / Twitter Card → 分享到微信/X 无预览图
- [ ] **ICP 备案 / App Store 中国区备案号**
  - `yunle.fun` 域名在国内提供服务通常需要工信部备案；App Store 中国区 2023-09 起强制要求备案号
- [ ] **README 完善**
  - [README.md](https://github.com/YunYouJun/apps.yunle.fun/blob/main/README.md) 当前 ~10 行命令清单，缺截图、架构图、贡献指南

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

| 日期       | 变更                                                                                                                                          |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-05-21 | 初始版本，基于上架前置盘点产出                                                                                                                |
| 2026-05-22 | SIWA 改为可选 fallback，改用 iOS 端隐藏 GitHub 登录策略；隐私政策已外链可访问，降为 P2 内容核对；新增 P0 Bundle ID 不一致项                   |
| 2026-05-22 | 完成 4 项 P0：Apple ID 回填 6759859441 / capacitor appId 修正 / GitHub iOS 隐藏 / Info.plist 已在前一日完成；M1 仅剩微信合规 1 项依赖外部审核 |
