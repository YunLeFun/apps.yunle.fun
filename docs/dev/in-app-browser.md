# 沉浸式内嵌浏览器

iOS / Android 的自定义网页容器共用 `app/host-runtime/index.ts` 定义的
`HostRuntime` 协议，Web 层入口见 `app/composables/useBrowser.ts` 的
`openInAppBrowser()`。iOS 适配器使用 `WKWebView`（`ios/App/App/WebViewController.swift`），
Android 适配器使用平台 `WebView`（`android/app/src/main/java/fun/yunle/apps/HostWebViewActivity.kt`）。

> 面向第三方页面开发者的 JSAPI 使用文档见 [JSAPI 接入（window.ylf）](/guide/jsapi)，
> 本文记录容器内部实现与维护流程。

## 展示形态（displayMode）

用户在设置「网页浏览器样式」中二选一（`app/stores/settings.ts` 的 `InAppBrowserMode`）：
**标题栏**（默认，走自定义容器）或 **手机内置**（SFSafariViewController）。
沉浸形态不再作为用户全局选项，仅由官方应用经目录声明 `YlfAppInfo.displayMode = 'immersive'`
启用（见下文「形态决策优先级」）：

- **标题栏 `titlebar`**（默认）：顶部固定导航栏（safe-area + 44pt），
  **自动套用应用主题色** `appInfo.themeColor` 为底色、按亮度自动选黑/白前景与状态栏样式
  （无合法主题色时回退 `systemBackground` + 发丝线）；**左上角「最小化（压后台）」键**
  （`chevron.down`，常驻）+ 页内返回键（随历史出现，紧跟其右）、中间应用标题
  （`customTitle` 优先，缺省回退页面 `<title>` 并随导航更新）、**右侧单个「更多」菜单按钮**
  （点开展开面板，「结束」收口其中；不可拖动、不随滚动隐藏），网页从栏下开始、底部仍铺满；
- **沉浸 `immersive`**（官方应用声明专属）：网页全屏平铺（顶达屏幕最顶、底达屏幕最底），
  右上角悬浮胶囊（更多 | 关闭，可拖动、随滚动隐藏），可后退时左上角悬浮返回键；
- **手机内置 `system`**：iOS 使用 SFSafariViewController，Android 使用 Custom Tabs，
  样式与生命周期由系统组件控制。

形态在 `viewDidLoad` 定型；设置变更后再打开同一应用时，
iOS 插件层判定 `displayMode` 不一致则放弃恢复暂停会话、走新建；Android 首版只维护
当前原生 Activity，会话结束后释放 WebView，并固定保留标题栏退出锚，不开放沉浸形态。

### 形态决策优先级

打开自定义容器时按以下优先级计算初始形态（`openInAppBrowser`）：

1. 用户全局设置为「手机内置 `system`」→ 一律 SFSafariViewController，
   用户明确退出自定义容器，下面各层不生效；
2. 应用目录声明 `YlfAppInfo.displayMode`（宿主侧钩子，经审核背书）；
3. 用户全局设置（未声明应用的默认）。

第 2 层目前**仅在 apps 侧把链路接通**（`openInAppBrowser(url, { displayMode })`
透传 + 单测），`YlfAppInfo.displayMode` 经 `app/types/yunlefun-types.d.ts` 增补占位；
是否真正启用「平台为应用强制形态」取决于产品需要——届时再发 `@yunlefun/types`
包字段 + admin 表单 + 重跑 `gen:apps-snapshot`。目录里没有应用声明时，此层透明跳过。

### 运行时调整：只支持「请求更沉浸」

标题栏 / 沉浸的初始形态确定后，页面**只能单向请求收起标题栏**
（`hideTitleBar` → `setTitleBarVisible`），不提供切到标题栏模式的 JSAPI。
理由：标题栏里的应用名 +「更多」菜单按钮是宿主的信任锚，「显示」由宿主与用户掌控，
页面只能「降级到沉浸姿态」这一个安全方向。

- 仅标题栏模式生效；沉浸模式 no-op 但照常 resolve（`setTitleBarVisible` 内 guard）；
- 收起后：webView 顶锚从「栏底」切到「屏顶」、进度条移到 safe-area 顶、
  最小化 / 返回 / 「更多」按钮转悬浮材质（统一走 `applyBarButtonStyles`），左上角最小化键与
  右上角菜单均固定保留作退出锚点（最小化压后台、「更多」内「结束」彻底释放；故
  **不重置每文档、会话内持久**，不会把用户困住）；
- 先同步 `layoutIfNeeded()` 定版面再做淡出动画，确保页面在 `hideTitleBar()`
  resolve 后立刻 `getEnv()` 能读到最终的 `capsuleRect` / `safeAreaInsets`；
- `getEnv().titleBarVisible` 反映当前状态（沉浸模式恒 `false`）。

未来如需用户 per-app 覆盖初始形态（“在此应用中始终用 XX”），插入优先级第 1、2 层之间。

## 视觉规范

- **胶囊 / 悬浮返回键**（沉浸模式 + 标题栏收起态）：统一暗色半透明材质
  （`black @ 45%` 背景、白色图标、`white @ 25%` 描边），不随系统浅色/深色模式变化，
  保证在任意网页配色上可读。
- **标题栏配色**（仅标题栏模式）：顶栏自动套用应用主题色（`appInfo.themeColor`），
  经 `UIColor.isLight` 按亮度选黑/白前景（标题 / 返回键 / 菜单按钮 / 发丝线）并同步状态栏
  明暗（`darkContent` / `lightContent`）；无合法主题色时回退 `systemBackground` + `.separator`。
- **标题栏浮层按钮（最小化 / 返回 / 更多）**：栏内为素色（前景色着色、无背景，统一走
  `styleBarButton`），沉浸模式或 `hideTitleBar` 收起后转悬浮暗色圆钮；「更多」展开面板
  （`AppInfoSheetController`）含分享 / 复制 / Safari / 刷新 / 详情与「结束」（彻底释放）。

## iOS 生命周期：最小化（压后台）/ 结束

标题栏左上角是**最小化**而非关闭，配合容器既有的「暂停保活」机制做小程序式压后台：

- **最小化**（左上角 `chevron.down` → `minimizeTapped` → `onMinimize`）：dismiss 容器但
  插件层**不释放** `presentedVC`，仅 `notifyListeners("browserFinished")` 通知前台已收起；
  重新打开同一应用经 `isSameSession`（按 appId/URL 匹配）命中后直接恢复页面状态（滚动位置、表单、登录态都在）。
- **结束**（「更多」→「结束」→ `closeTapped` → `onClose`）：置 `presentedVC = nil` 彻底释放，
  下次打开全新开始。
- 打开**另一个**应用时，`open()` 判定非同会话 → 释放旧的挂起会话再新建，**同一时刻仅挂起一个**，
  不会堆积 WKWebView。
- 「查看详情与评价」跳站内页同样走暂停保活（`onDetail`），从详情页再次打开即恢复。
- 沉浸模式（官方应用专属）暂不提供最小化：胶囊关闭键 = 结束（释放），与现状一致。
- **打开瞬间防白闪**：WKWebView 默认 `isOpaque`，首帧内容绘制前会铺一层不透明白底；
  容器中已改为 `isOpaque = false` 并以 `systemBackground` 兜底
  （含 `scrollView` 与 `underPageBackgroundColor`），避免暗色模式下开屏白闪。
  注意：完全不声明背景色的网页会透出系统背景色（暗色模式下为黑色），
  接入的应用页面应自行声明 `background-color`。

## JSAPI 架构

传输层只有一条 `invoke(method, params) → Promise` 通道：

- iOS 基于 `WKScriptMessageHandlerWithReply`，原生 `replyHandler(result, error)`
  直接驱动页面 Promise 的 resolve/reject；Android 基于 AndroidX WebKit
  `WebViewCompat.addWebMessageListener` / `JavaScriptReplyProxy`，每条消息携带
  不可由页面伪造的 `sourceOrigin` 与 `isMainFrame`；
- 注入脚本（`setupJSBridge`）只定义 `invoke` 与薄糖衣方法，长期稳定；
- 方法登记在 `jsapiRegistry`（方法名 → 权限级别），鉴权由分发层统一执行，
  方法实现（`handleJSAPI` 的 case）不关心权限；
- 两端分发层均再次校验主 frame，iframe 调用一律 reject；Android 禁止退回
  `addJavascriptInterface`，因为它不能为每条调用提供同等级的来源证明；
- handler 经 `WeakScriptMessageHandler` 弱引用代理注册，
  打破 `WKUserContentController` 强持有导致的循环引用，`deinit` 时移除。

## 鉴权模型

方法分 `open`（无害 UI 控制，全部页面可用）与 `trusted`（敏感能力）两级。

**授信判定**（`isTrustedOrigin`，每条消息独立评估，文档内导航后自动按新源重新判定）：

1. 来源由平台 WebKit 提供：iOS 使用 `WKSecurityOrigin`，Android 使用
   `WebMessageListener.sourceOrigin`；页面脚本无法伪造（勿用 `webView.url` 替代）；
2. 协议必须是 `https`（`localhost` / `127.0.0.1` 本机调试地址除外）；
3. host 命中授信域或其子域。授信域 = 内置第一方域（`firstPartyHosts`，
   现为 `yunle.fun`、`yunyoujun.cn`）∪ 宿主打开浏览器时传入的 `trustedHosts`。

信任决策留在宿主 JS 层（应用目录所在处），原生只负责执行。
宿主按会话追加授信域，**仅对人工核验过的第三方应用传入**：

```ts
await openInAppBrowser(app.url, {
  app: appInfo,
  // 该应用经过核验，其自有域名可使用敏感 JSAPI
  trustedHosts: ['example.com'], // 可注册域即可，子域自动匹配
})
```

恢复暂停会话时插件层会同步刷新 `trustedHosts`，避免设置变更后沿用旧授信。

### 身份边界

内嵌浏览器不转移宿主会话。原生容器的 CloudBase access token 与 refresh token
不进入 WebView 配置或 JSAPI。第一方页面可以调用 `window.ylf.authorize()` 请求
绑定来源、client、nonce 与 PKCE 的短时单次 SSO code；宿主以自身登录态向统一
身份服务签发后，页面仍须在自己的 Origin/BFF 完成 code 交换和 HttpOnly session
建立。该能力只开放给统一 SSO Registry 中精确注册的第一方客户端，client id、Origin、
redirect URI、scope、nonce 与 PKCE 必须全部匹配。

`HostRuntime` 统一支持两种交互，页面不按 iOS / Android 分支：

- `prompt: 'consent'`：iOS Sheet 与 Android Material Bottom Sheet 使用统一信息结构，显示注册表
  应用图标、认证域名、当前云乐坊账号、scope 对应权限与可信注册表配置的业务提示；用户可明确选择「以当前账号登录」、取消或「其他账号」。页面不能自定义
  权限或消耗文案；当前账号路径直接由宿主签发一次性 code；
- `prompt: 'select_account'`：跳过当前账号弹窗，直接进入系统级认证会话。iOS 使用
  `ASWebAuthenticationSession`，Android 使用 Custom Tabs；登录凭据和 Provider Cookie
  始终留在系统认证组件，不进入自定义 WebView。

系统认证会话在原请求的 HTTPS redirect URI 之外增加一个仅用于传输结果的
`yunlefun://auth/sso` 原生回调。回调以 256-bit state 绑定发起会话，原生端再精确校验
issuer、redirect URI、nonce 和一次性 code；回调中禁止出现 access token、refresh token、
ticket 或 session。Provider 仍按原注册 HTTPS redirect URI 绑定和签发 code，Consumer 仍在
自己的 Origin/BFF 兑换，因此原生回调不是新的 OAuth redirect URI，也不能绕过 Registry。

Android 的 WebMessage listener 只注册初始页面的精确 Origin，不使用 `*`；跨 Origin 导航后
不会复用旧桥接会话。Release 构建仅允许 HTTPS，Debug 只额外允许 loopback HTTP。

## 胶囊交互状态

胶囊可见性由两个独立状态合成（`applyOverlayVisibility`），**仅沉浸模式生效**：

- `overlayHidden`：滚动方向感知（下滑隐藏、回滑/近顶恢复），同时作用于悬浮返回键；
- `capsuleHiddenByPage`：页面经 JSAPI 主动隐藏，仅作用于胶囊，
  每次主文档导航（`didCommit`）重置，防止页面把用户「困」在浏览器里。

标题栏模式下顶栏（含右上角「更多」菜单按钮）固定显示：滚动感知不注册，
页面调用 `setCapsuleVisible` 静默忽略（`setCapsuleHiddenByPage` 直接 return），
`getEnv().capsuleVisible` 恒为 `true`；标题栏显示时 `capsuleRect`（标题栏模式即菜单按钮的矩形，
字段名沿用以兼容旧页面）经 `webView.frame.minY` 换算到页面视口坐标后 y 为负，避让逻辑自然判定无重叠。

标题栏可由页面经 `hideTitleBar` 收起（`titleBarVisible` 状态，会话内持久），
收起后容器退化为沉浸姿态：webView 顶锚切到屏顶、最小化 / 返回 / 菜单按钮转悬浮材质，
左上角最小化键与右上角菜单固定保留为退出锚点（最小化压后台、菜单内「结束」释放），
`capsuleRect.y` 随 `webView.frame.minY` 归零转正，页面据此重新避让。
注意：收起态下仍**不启用滚动隐藏 / 拖动**
（那是沉浸模式初始形态的便利项），菜单按钮固定可预期，便于已适配页面做精确避让。
详见上文「运行时调整」。

## 新增 JSAPI 方法指南

1. `WebViewController.swift` 的 `jsapiRegistry` 登记方法名与权限级别；
2. `handleJSAPI` 加 `case`，经 `reply(result, errorMessage)` 应答
   （result 须为 JSON 可序列化值）；
3. 如需糖衣，在 `setupJSBridge` 注入脚本中追加一行包装（可选，页面也可直接 `invoke`）；
4. 更新 [JSAPI 接入](/guide/jsapi) 的 API 参考表；
   若属破坏性变更，递增注入脚本中的 `version`。

## 扩展约定

- **原生 → 页面事件**：用标准 `CustomEvent` 下发（`evaluateJavaScript` 派发
  `window.dispatchEvent(new CustomEvent('ylf:xxx', { detail }))`），
  页面用 `addEventListener('ylf:xxx')` 监听，无需在注入脚本里维护回调注册表。
- **更高敏感度能力**（手机号、钱包、支付等）：host 白名单只是准入门槛，
  此类能力还应回传宿主 JS 层做用户级确认（弹窗授权），
  参考微信 JS-SDK config 签名 + 用户授权双层模式。当前 `profile`
  仅通过一次性授权码静默兑换最小账号信息。
- **跨端**：新增能力先修改 `HostRuntime` / `window.ylf` 统一协议，再分别落到 Swift 与
  Kotlin 适配器；页面代码不按平台分支，只通过 `canIUse` 做能力探测。
