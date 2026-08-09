# 原生应用授权面板设计规范

## 目的

授权面板是云乐坊 App 的可信系统界面，用于回答四个问题：哪个应用正在申请登录、将使用哪个
云乐坊账号、应用会获得哪些信息、当前操作是否产生费用。面板由宿主原生代码渲染，不允许内嵌
网页提供名称、图标、域名、权限或费用文案。

首版服务第一方单账号、单 scope 登录。后续增加长期授权、多 scope 或第三方应用时，应沿用本文
的信息顺序和数据来源，而不是在页面中另建授权弹窗。

## 视觉方向

- **风格**：Brutally minimal，克制、可信、信息优先。
- **品牌主色**：`#B3261E`，用于可信连接标识和主要操作。
- **浅暖背景**：`#FFF8F6`；暗色模式由平台动态色适配。
- **主要文字**：`#1D1B20`；次要文字：`#625B71`；分隔色：`#E7E0DC`。
- **字体**：iOS 使用 San Francisco 与 Dynamic Type；Android 使用 Material Typography 与系统
  字号缩放。授权界面不加载远程字体。
- **图标**：只使用 SF Symbols、Android 系统/Material 图标和注册表中的 HTTPS 应用图标；禁止
  使用页面传入的 emoji 作为可信应用标识。

## 信息结构

从上到下固定为：

1. Sheet 拖动指示器。
2. 身份连接：应用图标与名称 → “云乐坊认证” → 当前账号头像与昵称。
3. 标题“登录到 {应用名}”及精确注册域名。
4. 权限区：“将向 {应用名} 提供”及 scope 映射出的可读权限。
5. 可选业务提示，例如“登录本身不会消耗云币；生成春联时会另行提示消耗”。
6. 安全说明：“不会共享你的密码或云乐坊长期登录凭证”。
7. 操作区：主要操作“以「{账号名}」登录”、次要操作“使用其他账号”、取消。

长账号名在可视按钮中截断，但辅助功能标签保留完整名称。正文必须支持 Dynamic Type、系统字体
缩放和多行显示；内容超出屏幕时正文可滚动，操作区保持可达。

## 跨平台一致性

| 语义       | iOS                             | Android                          |
| ---------- | ------------------------------- | -------------------------------- |
| 容器       | `UISheetPresentationController` | Material `BottomSheetDialog`     |
| 关闭       | 下拉、取消按钮                  | 下滑、返回键、取消按钮           |
| 主操作     | Filled button                   | Filled button                    |
| 切换账号   | Tinted/secondary button         | Outlined/secondary button        |
| 字体与间距 | Apple HIG / Dynamic Type        | Material Components / font scale |

两端可以按平台调整圆角、动效、安全区和返回手势，但信息顺序、文案、选择结果与辅助功能语义必须
一致。所有关闭路径统一返回 `choice: 'cancel'`；切换账号返回 `choice: 'other'`；确认返回
`choice: 'current'`。

## 可信数据协议

`HostRuntime.confirmAuthorization` 的展示字段只由宿主身份代理提供：

- `applicationName`、`applicationOrigin`、`applicationIconUrl`：来自精确 SSO 注册表。
- `permissionDescription`：由已验证 scope 在宿主中映射。
- `authorizationNotice`：来自注册表的可选业务策略。
- `accountName`、`accountAvatarUrl`：来自宿主已验证的当前会话。

内嵌页面仍只能提交 `clientId`、`redirectUri`、scope、nonce、PKCE challenge 和 prompt。展示数据
不得从页面请求中透传。

### 远程图片安全边界

应用图标与账号头像加载失败时必须保留文字占位，不得阻断授权。两端统一执行以下限制：

- 只接受 HTTPS，禁止跟随重定向，只允许常见栅格图片 MIME；
- 响应体最多 2 MB，已声明的 `Content-Length` 超限时立即拒绝，流式读取再次执行硬上限；
- 源图单边最多 8192 px、总像素最多 16,777,216；先读元数据，不得直接完整解码；
- 最终只生成最长边 256 px 的缩略图，避免压缩体积很小但解码内存巨大的图片；
- 不向页面暴露下载错误、缓存路径或底层图片对象。

## 状态与错误

- `ready`：展示全部可信信息并允许选择。
- `submitting`：后续若授权码签发并入 Sheet，主要按钮进入加载且禁止重复提交。
- `error`：保留面板和账号上下文，展示可重试错误；不得暴露 token 或底层异常详情。
- `dismissed`：所有手势、返回键和取消操作只结算一次，统一视为拒绝。

当前协议在用户选择后关闭 Sheet，再由宿主签发一次性 code；因此首版实现 `ready` 与
`dismissed`，并通过 `authorizationPromptActive` 防止重复面板。

授权请求进入原生交互后使用 5 分钟用户决策时限；用户作出选择后重新启动 30 秒 broker/网络
时限。不能让最初的 30 秒网络超时在用户阅读面板期间继续倒计时，也不能无限期保留请求。

### 宿主未登录回跳

当宿主没有有效 CloudBase 会话或受限测试会话时，不得立即向页面返回失败，也不得销毁发起请求的
WebView：

1. 原生层以 `requestId` 定位并暂停原请求，将页面会话保活在后台；
2. Apps Web 层只在 `sessionStorage` 保存受格式与长度限制的 `requestId`，进入本地 `/login`；
3. 登录页默认展示普通登录，公共测试身份仅作为明确的手动入口，不能影响生产用户；
4. 登录成功调用 `resumeAuthorizationAfterLogin`，恢复原 WebView 并重新投递同一请求；
5. 用户返回或离开登录页调用 `cancelAuthorizationLogin`，恢复原 WebView 并以
   `HOST_AUTH_DENIED` 结束原 Promise；
6. 任一步骤过期或 App 进程被回收时失败关闭，不签码、不自动重试凭据，也不在 URL 中携带账号或
   challenge。

登录页的交互状态必须保持一致：

- 顶栏标题使用“登录并继续”或“注册并继续”，返回操作显示为“取消”；
- 上下文提示固定说明“返回后仍需在原生面板确认；登录本身不会自动授权”，避免用户误以为提交
  登录表单等于授权；
- 恢复原应用期间显示“登录成功，正在返回原应用”，锁定表单并阻止重复返回或提交；
- 恢复失败时保留原 `requestId` 和已登录状态，提供“重试返回原应用”，用户仍可取消本次授权；
- 公共测试身份入口只在存在待处理原生授权时展示，并使用折叠式次要入口，不与普通登录方式竞争。

Android 主 Activity 使用 `singleTop` 配合 `FLAG_ACTIVITY_REORDER_TO_FRONT`，避免回到登录页时清除
上层 `HostWebViewActivity`；iOS 继续使用会话池保活并重新 present 同一个 `WebViewController`。

## 授权生命周期与可观测性

当前版本不保存长期 grant：每次 `prompt: 'consent'` 都由用户确认，因此暂不需要“已授权应用”撤销
页面。未来若保存长期授权，必须同时上线授权时间、scope、设备/客户端、撤销入口和策略版本，
不能只增加“记住授权”开关。

宿主通过既有 Tencent RUM 上报以下脱敏事件：

| 阶段           | 事件                                                                                       |
| -------------- | ------------------------------------------------------------------------------------------ |
| 收到并校验请求 | `auth.native_sso.requested`、`auth.native_sso.validated`                                   |
| 展示与选择     | `auth.native_sso.prompted`、`auth.native_sso.consent_decided`                              |
| 签码与交付     | `auth.native_sso.code_issued`、`auth.native_sso.completed`                                 |
| 系统账号/失败  | `auth.native_sso.handed_off`、`auth.native_sso.failed`、`auth.native_sso.delivery_expired` |

事件只包含 `requestId`、client/app、阶段、结果、耗时、平台和 App 版本。客户端与 Provider 使用
nonce 的 SHA-256 前 16 个十六进制字符作为匿名 `flow` 关联值；严禁记录原始 nonce、PKCE、code、
ticket、token、Cookie、完整 URL 或账号凭据。

## 上线前验收

自动验证：

```bash
pnpm lint
pnpm typecheck
pnpm test:unit
pnpm build
xcodebuild -workspace ios/App/App.xcworkspace -scheme App \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
(cd android && ./gradlew testDebugUnitTest assembleDebug)
```

真机至少覆盖以下场景，并在 RUM 中按 `flow` 核对事件闭环：

1. 当前账号同意：AI 春联完成登录，页面显示宿主账号。
2. 取消/下滑/系统返回：不签发 code，页面显示取消状态。
3. 使用其他账号：只进入系统认证组件，凭据不进入自定义 WebView。
4. 宿主切换账号：保活中的 AI 春联清理旧会话并要求重新授权。
5. 弱网、断网和 30 秒签码超时：可重试，无迟到请求覆盖新会话。
6. 超大、错误 MIME、重定向图片：显示文字占位，App 内存稳定且授权仍可完成。
7. 冷启动、后台恢复、杀进程重启各执行一次；检查无崩溃和新控制台错误。
8. 宿主未登录：显示本地“登录并继续”上下文；成功后回原应用再次确认，回跳失败可重试，取消可
   恢复原页面且不签发 code。
