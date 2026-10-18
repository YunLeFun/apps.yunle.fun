# 跨 App 授权（设计草案）

> 2026-10-18 · **设计草案，尚未实现**。首个接入方为 Life（云生，`life-ios`）。本文用于决定是否实现，不代表任何链路已经验收。同日修订：按业界 App-to-App 做法，把授权入口改为 `www.yunle.fun` 上由云乐坊 App 认领的同一个 HTTPS 地址，并补充拉起云乐坊 App 时的体验设计。

## 目标

其他 iOS App 可以借助用户已经登录的云乐坊 App 完成授权：**装了云乐坊 App 就自动拉起它，一次确认就返回**，不用再在网页里登录一次。没有安装时，同一个授权地址在系统网页授权中打开，用户不会看到失败，也不会被要求安装。

不在本次范围：共享 Keychain 或 refresh token、第三方 App 内嵌云乐坊登录表单、`identity:bootstrap` 以外的 scope、云币 / 会员授权、Android。

## 现状

| 环节                  | 已有能力                                                                                                                                                      | 位置                                                        |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Life 网页授权         | `ASWebAuthenticationSession` 打开 `https://www.yunle.fun/auth/sso`，HTTPS 回调 `https://life.yunle.fun/auth/callback#ylf_sso=…`，PKCE 兑换 ticket，真机已验证 | `life/apple/Packages/YunleIdentity`                         |
| 注册表                | `life-ios`：`web-sso` adapter，来源 `https://life.yunle.fun`，回调 `/auth/callback`，`consent=explicit`，generation 15                                        | `www.yunle.fun` Registry                                    |
| 云乐坊原生签码        | `HostSsoRequest` 校验 → `resolve` 注册策略 → 原生登录 / 授权面板 → `issueSsoCode`（Bearer 只发 CloudBase 网关）                                               | [宿主授权接入](./ios-host-authorization.md)                 |
| 云乐坊 Universal Link | `applinks:apps.yunle.fun`，AASA 仅 `/app/*`、`/w/*`、`/ulink/*`，App ID `QT792GAY4C.fun.yunle.apps`                                                           | `apps/mobile/public/.well-known/apple-app-site-association` |
| Life 关联域名         | 仅 `webcredentials:life.yunle.fun`，无 `applinks`                                                                                                             | `life/apple/Life/Life.entitlements`                         |
| 失败原因              | `@yunlefun/sso` 的 `SsoFailureReason` 只有 `access_denied`、`invalid_request`、`not_authenticated`、`server_error`                                            | `@yunlefun/sso/protocol`                                    |

两边已具备的部分：云乐坊签发的 code 与网页授权页签发的 code 走同一个 `sso-ticket` 的 `issueSsoCode`（`mode: redirect`、`targetOrigin`、`returnUrl`、PKCE）。Life 的兑换、断言校验和 Keychain 逻辑都不需要改。缺的只是"把请求送进云乐坊 App"和"把结果送回 Life"这两段传递。

## 是否值得做

现有网页授权（`ASWebAuthenticationSession`）是苹果和 RFC 8252 推荐的原生 App 授权方式，**可以直接上线**，不是临时替代品。它的体验代价集中在首次登录：

| 环节                                  | 网页授权                                  | 拉起云乐坊 App         |
| ------------------------------------- | ----------------------------------------- | ---------------------- |
| 系统提示"云生想要使用 yunle.fun 登录" | 每次都有一个系统确认弹窗                  | 没有，直接切换到云乐坊 |
| 页面加载                              | 需要加载 `www.yunle.fun` 页面，弱网下明显 | 原生界面立即出现       |
| 已在云乐坊 App 登录、Safari 未登录    | **需要在网页里再登录一次**（最大的痛点）  | 一次确认即可           |
| Safari 已登录                         | 点"同意"即可                              | 一次确认即可           |
| 未安装云乐坊 App                      | 正常                                      | 同一地址自动走网页授权 |

不建议在 Life 里做原生登录表单（让 Life 直接收集云乐坊的手机号 / 密码）：这样 Life 会拿到云乐坊主账号的会话，绕开授权确认和注册表约束，用户也会被训练成"在第三方 App 输入云乐坊密码"，形成钓鱼习惯。真正的"原生体验"应该由云乐坊 App 提供，也就是本方案。

取舍建议：

- **现在保持网页授权**，先做低成本优化（见[没有安装云乐坊 App 时的体验](#没有安装云乐坊-app-时的体验)的第 3 项：共享密码自动填充）。
- 在 Life 中统计 `开始授权 → 收到回调 → 登录成功` 的转化率和耗时。如果大量用户已经安装云乐坊 App，或者首次登录的流失率明显偏高，再实施本方案的 P1。

## 业界做法

| 做法                                                                                                                   | 来源                                                   | 本方案对应                                                      |
| ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ | --------------------------------------------------------------- |
| 授权入口是一个 HTTPS 地址，由提供方 App 认领为 Universal Link；装了 App 就由系统拉起，没装就在浏览器打开**同一个地址** | 英国 Open Banking / FAPI 的 App-to-App 授权            | `https://www.yunle.fun/auth/app`，云乐坊 App 认领，网页同址兜底 |
| 回调用接入方 App 认领的 HTTPS 地址，不用自定义 scheme                                                                  | RFC 8252 §7.2；Open Banking 禁止自定义 scheme 回传结果 | 回调 `https://life.yunle.fun/auth/callback`，Life 认领          |
| 原生 App 必须使用 PKCE，不用内嵌 WebView 登录                                                                          | RFC 8252                                               | 沿用现有 S256 PKCE；兜底仍用 `ASWebAuthenticationSession`       |
| 自动优先 App，不加选择页或中间页                                                                                       | Open Banking 体验指南                                  | Life 只有一个"登录云乐坊"按钮，`universalLinksOnly` 静默判断    |
| 不强制安装提供方 App                                                                                                   | App Store 审核口径（拒绝"只能通过另一个 App 登录"）    | 未安装时网页授权，体验不降级                                    |
| 交互失败用标准错误码                                                                                                   | OpenID Connect Core 的 `account_selection_required` 等 | 新增 `account_selection_required`，Life 收到后自动转网页授权    |

反面经验：Google 和 Facebook 的 iOS SDK 早年都有"跳到自家 App 登录"，后来都改成了系统浏览器会话。原因是当时的审核口径和跳出 App 的体验争议，加上系统浏览器会话已经能共享登录态。所以 App 跳转只在"用户大概率已在提供方 App 登录"时才有明显收益，这也是上面建议先统计转化率的原因。

## 协议

### 授权入口：`https://www.yunle.fun/auth/app`

所有原生接入方都使用同一个地址，**既是 Universal Link，也是网页授权地址**：

```text
https://www.yunle.fun/auth/app
  ?client_id=life-ios
  &redirect_uri=https://life.yunle.fun/auth/callback
  &scope=identity:bootstrap
  &nonce=<32–128 位 base64url>
  &code_challenge=<43 位 base64url>
  &code_challenge_method=S256
  &prompt=select_account
```

- 参数与 `/auth/sso` 完全一致。Life 现有的 `SSOTransaction.authorizationURL` 只需把路径从 `auth/sso` 改成 `auth/app`，App 跳转和网页兜底共用这一个 URL。
- 每个参数恰好出现一次，不允许额外参数、fragment、userinfo 或端口，总长度不超过 4 KiB。不接受 `native_callback_uri`（云乐坊自身的网页授权继续走 `/auth/sso`）。
- `prompt` 只接受 `select_account` 或 `consent`，不支持 `none`。云乐坊 App 总是显式确认。

**为什么不直接认领 `/auth/sso`**：网页子应用在手机 Safari 中也会跳转到 `/auth/sso`。如果云乐坊 App 认领了这个路径，装了 App 的用户在 Safari 里点击登录时也会被拉进 App，而结果必须回到 Safari 里的原网页标签（PKCE verifier 可能只存在那个标签的 `sessionStorage`）。App 无法可靠地把结果送回原标签，网页 SSO 会被打断。`/auth/app` 只给原生接入方使用，网页客户端永远不会走到这里。

**`/auth/app` 网页版**：与 `/auth/sso` 使用同一个页面组件和校验逻辑，只多一条限制：`redirect_uri` 必须属于注册表中的原生客户端（v1 为允许名单 `life-ios`，P3 改为 `native-app` adapter）。在 `ASWebAuthenticationSession` 内部打开时不会触发 Universal Link，所以兜底路径就是现在的网页授权。

### 总体流程

```text
Life                                    云乐坊 App                          服务端
 │ beginSignIn(): nonce / verifier / challenge（持久化）
 │ open(www.yunle.fun/auth/app?…, universalLinksOnly)
 │   ├─ false（未安装 / AASA 未就绪 / 用户关闭了通用链接）
 │   │     → ASWebAuthenticationSession(同一个 URL) → 现有网页授权
 │   └─ true ───────────────────────────▶ 严格校验参数
 │                                         resolve(注册策略) ─────────────▶ /api/auth/sso/resolve
 │                                         未登录 → 原生登录表单
 │                                         原生授权面板（总是显式确认）
 │                                         issueSsoCode(Bearer) ──────────▶ sso-ticket
 │ ◀──── open(redirect_uri#ylf_sso=…, universalLinksOnly)
 │ consume(callback)：核对 nonce / iss / 地址
 │ exchangeSsoCode(code, verifier) ───────────────────────────────────────▶ sso-ticket
```

### 响应：云乐坊 → Life

```text
https://life.yunle.fun/auth/callback#ylf_sso=<base64url(JSON)>
```

JSON 与 `@yunlefun/sso` 的 `encodeSsoRedirectResult` **逐字节兼容**：

| 结果                   | JSON                                                                                           | Life 的处理                  |
| ---------------------- | ---------------------------------------------------------------------------------------------- | ---------------------------- |
| 同意                   | `{"ok":true,"code":"<43 位>","nonce":"…","iss":"https://www.yunle.fun"}`                       | 兑换并登录                   |
| 拒绝 / 取消 / 超时     | `{"ok":false,"nonce":"…","iss":"https://www.yunle.fun","reason":"access_denied"}`              | 显示"未授权登录"             |
| 用户选择"使用其他账号" | `{"ok":false,"nonce":"…","iss":"https://www.yunle.fun","reason":"account_selection_required"}` | **自动**用新事务打开网页授权 |

`account_selection_required` 是 OpenID Connect Core 的标准错误码，需要加入 `@yunlefun/sso` 的 `SsoFailureReason`。Life 目前遇到未知原因会报"回调无效"，所以也要同步更新。

请求无效时（参数非法、注册策略不通过），云乐坊**不回跳**，只在 App 内提示"该授权请求无效"，防止把云乐坊当作跳板向任意 Universal Link 发送内容。

两端共享同一份契约 fixture（固定 nonce / code 的编码结果），云乐坊、Life 和 `@yunlefun/sso` 的单元测试都用它比对。

### 返回地址的选择（需要决定）

| 方案                                     | 说明                                                        | 代价                                                                                                                                                                             |
| ---------------------------------------- | ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **A. 复用 `/auth/callback`（推荐先试）** | 注册表不用改，`resolve` 按现有的 `web-sso` adapter 就能通过 | Life 的 AASA 需要为 `/auth/callback` 增加 `applinks`。必须在真机上确认 `ASWebAuthenticationSession` 的 `.https` 回调仍然先于 Universal Link 被系统认证会话截获，网页授权不受影响 |
| B. 新增 `/auth/app-callback`             | 网页授权和跨 App 返回彻底分开，排查更清楚                   | 注册表要发 generation 16，需要走飞书审批；Life 兑换时要根据来源发送对应的 `redirectUri`                                                                                          |

建议先用方案 A 做真机验证；如果系统认证会话的回调行为受到影响，再改用方案 B。

## 拉起云乐坊 App 的体验设计

原则：**一个按钮、零选择页、任何时候都有退路**。

### Life 端

| 时刻                  | 界面                                                                                                                                                                   |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 登录前                | 只有一个按钮"登录云乐坊"。可选：用 `canOpenURL("yunlefun://")` 检测到云乐坊时，按钮下加一行"将在云乐坊 App 中确认"，提前告知会切换 App。这一行只是提示，不用于安全判断 |
| 点击后，云乐坊已安装  | 系统直接切换到云乐坊，**没有**"想要使用 yunle.fun 登录"的弹窗。Life 留在等待状态："正在云乐坊中确认…"，下面有"取消"和"改用网页登录"两个按钮                            |
| 点击后，云乐坊未安装  | 直接出现现在的网页授权，用户感觉不到区别                                                                                                                               |
| 用户没确认就切回 Life | 保持等待状态，不判定失败；"改用网页登录"始终可用                                                                                                                       |
| 收到同意结果          | 等待状态变成"正在登录…"，完成后显示账号                                                                                                                                |
| 收到"使用其他账号"    | 不提示错误，直接打开网页授权（`prompt=select_account`），用户在网页里换账号                                                                                            |
| 收到拒绝              | 回到登录前状态，提示"未授权登录，你仍可以继续记录成就。"（与现有网页拒绝一致）                                                                                         |

### 云乐坊端

| 时刻                            | 界面                                                                                                                      |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| 被拉起（冷启动或从后台）        | **不切换 Tab、不打断当前页面**，直接在最上层弹出授权面板。冷启动时面板优先于首页数据加载出现                              |
| 面板内容                        | 接入方图标和名称（只取注册策略）、"来自另一个 App 的登录请求"、当前账号头像和昵称、权限"账号标识、昵称和头像"             |
| 按钮                            | 主按钮"同意并返回云生"；次按钮"拒绝"；文字按钮"使用其他账号"                                                              |
| 未登录                          | 面板先显示现有原生登录表单（"登录后返回云生，仍需确认授权"），登录后回到授权面板                                          |
| 同意                            | 显示"正在返回云生…"，签码成功后立即切回 Life；面板随即关闭，用户之后回到云乐坊时看到的是原来的页面                        |
| 拒绝 / 关闭面板 / 5 分钟超时    | 回跳 `access_denied`，用户回到 Life                                                                                       |
| 使用其他账号                    | 回跳 `account_selection_required`，Life 自动转网页授权。v1 不在云乐坊内切换账号，避免影响云乐坊自身的登录状态和网页运行时 |
| 用户中途切回 Life               | iOS 左上角的"‹ 云生"返回按钮由系统提供；云乐坊保留面板直到超时或用户操作                                                  |
| 无法返回（Life 未安装或旧版本） | 提示"无法返回云生，请更新后重试"，丢弃 code，不在 Safari 中打开                                                           |

面板支持 Dynamic Type、VoiceOver 和深色模式，沿用[原生授权面板规范](../ui/native-authorization-sheet.md)。

## 各仓库改动

### 云乐坊 iOS（本仓库）

1. **Entitlements**：增加 `applinks:www.yunle.fun`（`webcredentials:www.yunle.fun` [已准备](#shared-web-credentials)）。
2. **路由**：新增 `CrossAppAuthorizationLink.parse`，只匹配 `https://www.yunle.fun/auth/app`；与 `NativeLink` 分开（`NativeLink` 拒绝 query，保持不变）。`AppRootView.handleLink` 先尝试这个解析器。
3. **请求模型**：新增 `CrossAppAuthorizationRequest`，内部构造 `HostSsoRequest`，`sourceOrigin` 取自 `redirect_uri` 的 origin。类型上与 WebView 请求区分：WebView 请求的来源由 `WKSecurityOrigin` 证明，跨 App 请求的来源**无法证明**，只能靠"注册表 + Universal Link 归属"把结果的去向限定住。
4. **协调器**：新增 `CrossAppAuthorizationCoordinator`，复用 `HostAuthorizationService`、原生 `LoginView` 和 `AuthorizationConsentViewController`。
   - 同一时间只处理一个授权决策，与 `NativeAuthorizationBroker` 互斥：任一方有进行中的流程时，另一方的请求提示"有一个授权正在进行"。
   - 不管策略是 `trusted` 还是 `explicit`，**总是显式确认**。
   - 账号切换 / 退出、5 分钟超时、用户取消，都会撤销流程，迟到的 code 不能回跳。
   - 首次签码遇到 401 时，与现有逻辑一样刷新一次并核对是同一账号。
5. **回跳**：`UIApplication.open(callback, options: [.universalLinksOnly: true])`。返回 `false` 时丢弃 code，**绝不在 Safari 打开带 code 的地址**。
6. **日志**：不记录完整 URL、nonce、challenge 或 code，诊断日志只记 client ID 和结果类别。

### `www.yunle.fun`

1. **AASA**：在已准备的文件中增加 `applinks`，只认领 `/auth/app`：

   ```json
   {
     "applinks": {
       "details": [
         {
           "appIDs": ["QT792GAY4C.fun.yunle.apps", "QT792GAY4C.fun.yunle.apps.native-dev"],
           "components": [{ "/": "/auth/app", "?": { "client_id": "?*" } }]
         }
       ]
     },
     "webcredentials": { "apps": ["QT792GAY4C.fun.yunle.apps", "QT792GAY4C.fun.yunle.apps.native-dev"] }
   }
   ```

   `edgeone-config.test.js` 同步断言：只认领 `/auth/app`，`/auth/sso` 不在其中。

2. **页面**：新增 `/auth/app`，复用 `sso.vue` 的逻辑，增加原生客户端限制，并沿用 `/auth/sso` 的 `no-store`、`no-referrer`、`noindex` 响应头。
3. **协议包**：`@yunlefun/sso` 的 `SsoFailureReason` 增加 `account_selection_required`，发布新版本。

### Life

1. **Entitlements 与 AASA**：增加 `applinks:life.yunle.fun`；`integrations/yunlefun-sso/public/.well-known/apple-app-site-association` 增加 `applinks`，只匹配回调路径。部署后用现有 `verify-deployment.mjs` 加上 Apple CDN 校验。
2. **授权地址**：`SSOTransaction` 的路径改为 `auth/app`，App 跳转和网页兜底共用。
3. **登录入口**：

   ```swift
   let transaction = try await service.beginSignIn(persisting: true)
   let opened = await UIApplication.shared.open(transaction.authorizationURL,
                                                options: [.universalLinksOnly: true])
   if !opened {
     let callback = try await browser.authenticate(transaction, anchor: anchor) // 同一个 URL
     user = try await service.completeSignIn(transaction.id, callback: callback)
   }
   // opened == true：进入等待状态，等待 onOpenURL
   ```

4. **事务持久化**：现有事务只保存在 actor 内存中。用户在云乐坊中操作期间，Life 可能被系统回收。跨 App 路径要把 `nonce`、`verifier`、创建时间写入 Keychain（`AfterFirstUnlockThisDeviceOnly`、不同步），10 分钟过期，单次使用，消费、取消或过期时删除。
5. **接收回调**：`onOpenURL` / `onContinueUserActivity` 把匹配 `redirect_uri` 的 URL 交给 `completeSignIn`。**没有待处理事务时直接丢弃**，防止被诱导登录到别人的账号（login CSRF）。
6. **`account_selection_required`**：`consume` 识别这个原因，`YunleAccountModel` 收到后清除旧事务，用新事务直接调用网页授权。

## 没有安装云乐坊 App 时的体验

**结论：不需要安装云乐坊 App。**同一个授权地址会在系统网页授权中打开，这条路径今天已经能用。要优化未安装用户的体验，下面几项按投入产出比排序：

| 优先级 | 措施                                                                                                | 效果                                                               | 成本                                                                       |
| ------ | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| 1      | **静默降级**（上文 `universalLinksOnly`）                                                           | 未安装的用户看不到任何失败或安装提示                               | 已包含在本方案中                                                           |
| 2      | **保持 Safari 登录态**（Life 已设 `prefersEphemeralWebBrowserSession = false`）                     | 用户在 Safari 或任意接入方登录过一次后，之后只需点"同意"           | 已具备，回归测试时保持即可                                                 |
| 3      | **共享密码自动填充**：云乐坊 App 增加 `webcredentials:www.yunle.fun`，`www.yunle.fun` 发布对应 AASA | 在云乐坊 App 中保存的密码可以在网页授权里一键填充（iCloud 钥匙串） | 低：一个 entitlement 加一个静态文件                                        |
| 4      | 网页登录页已有手机号 / 邮箱验证码，并设置了 `autocomplete="one-time-code"`                          | 短信验证码可以从键盘上方直接填入                                   | 已具备                                                                     |
| 5      | **通行密钥（Passkey）**                                                                             | Face ID 一步登录，网页、云乐坊 App 和 Life 通用，体验最好          | 高：需要后端 WebAuthn 支持，CloudBase 是否原生支持还待确认，应作为独立项目 |

### 共享密码自动填充：已准备，未上线 {#shared-web-credentials}

2026-10-18 已完成第 3 项的代码准备，**尚未部署，也未在真机上验收**：

- 云乐坊 iOS：`apps/ios/YunleFun/YunleFun.entitlements` 增加 `webcredentials:www.yunle.fun`，原有 `applinks:apps.yunle.fun` 保持不变。Debug 模拟器构建成功，签名产物的 entitlements 包含两项，App ID 为 `QT792GAY4C.fun.yunle.apps.native-dev`。
- `www.yunle.fun`：新增 `public/.well-known/apple-app-site-association`，只包含 `webcredentials`，列出 `fun.yunle.apps` 和 `fun.yunle.apps.native-dev`；`edgeone.json` 在 `/*` 之前为它设置 `Content-Type: application/json`。`tests/edgeone-config.test.js` 新增一条用例，8 项全部通过。
- **这一步不加 `applinks`**：P1 之前没有任何路径需要被云乐坊 App 认领。P1 时只增加 `/auth/app`（见上文），`/auth/sso` 等其他路径始终在浏览器中打开。旧兼容壳的 entitlements 里虽有 `applinks:www.yunle.fun`，但线上从来没有 AASA 文件，所以这次不改变它的行为。

上线后需要验证：

1. `https://www.yunle.fun/.well-known/apple-app-site-association` 返回 HTTPS 200、无重定向、`application/json`，`https://app-site-association.cdn-apple.com/a/v1/www.yunle.fun` 同步到相同内容。
2. 真机：在云乐坊原生登录表单中用密码登录，系统提示存入钥匙串；随后在 Life 的网页授权中，用户名字段出现该账号的自动填充建议。反过来，在网页中保存的密码也能在云乐坊原生表单中填充。
3. 不影响现有能力：`apps.yunle.fun` 的 Universal Link 照常打开 App，Life 的网页授权与 HTTPS 回调照常完成。

不建议在 Life 中强制或弹窗引导安装云乐坊 App。如果要推广，最多在网页授权成功后、账号页底部放一句"安装云乐坊 App，下次一键确认"，不打断主流程。

## 安全分析

| 威胁                                                       | 处理                                                                                                                                                                                        |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 恶意 App 冒用 `client_id=life-ios` 发起请求                | code 只会回跳到注册表中登记、并经 AASA 证明归属 Life 的 Universal Link，恶意 App 拿不到；它也没有 Life 的 verifier                                                                          |
| 恶意 App 借云乐坊把用户的账号登录进 Life（login CSRF）     | Life 只在有待处理事务且 nonce 匹配时才接受回调                                                                                                                                              |
| 授权钓鱼（伪造"某 App 请求登录"）                          | 名称和图标只取注册策略；跨 App 请求总是显式确认，并标明"来自另一个 App"；不支持 `prompt=none`                                                                                               |
| 网页 SSO 被 App 劫持                                       | 云乐坊只认领 `/auth/app`，网页客户端使用的 `/auth/sso` 不被认领；`/auth/app` 拒绝非原生客户端                                                                                               |
| code 泄漏到浏览器                                          | 回跳只用 `universalLinksOnly`，失败就丢弃；code 单次使用，绑定 PKCE，有效期很短                                                                                                             |
| 伪造"使用其他账号"结果                                     | 回调同样要求 nonce 匹配待处理事务；它只会触发一次新的网页授权，不会登录任何账号                                                                                                             |
| 来源 App 识别                                              | 通过 Universal Link 进入时，`NSUserActivity` 不携带来源 App；`sourceApplication` 只对同一开发团队的 App 可用。因此**不把来源 App 作为安全依据**                                             |
| 用户为某个域名关闭了通用链接（长按选择"在 Safari 中打开"） | `open` 返回 `false`，自动走网页授权                                                                                                                                                         |
| 将来开放给其他开发者的 App                                 | 在注册表中增加 `native-app` adapter（显式声明允许跨 App 授权、登记 Universal Link 回调），云乐坊和 `/auth/app` 只接受声明了该 adapter 的 client。Life 是同团队的首个接入方，v1 先用允许名单 |

## 测试与验收

**云乐坊单元测试**

- 参数解析：只接受 `www.yunle.fun/auth/app`；拒绝重复参数、额外参数、`native_callback_uri`、非 HTTPS、带端口、`prompt=none`、超长输入。
- `resolve` 回显不一致时拒绝；`trusted` 策略仍然弹出确认。
- 三种回调编码与共享 fixture 一致。
- 账号切换、超时、取消时不回跳 code；`open` 返回 `false` 时丢弃 code。
- 与 `NativeAuthorizationBroker` 互斥。

**`www.yunle.fun` 测试**

- AASA 只认领 `/auth/app`；`/auth/app` 拒绝非原生客户端；响应头与 `/auth/sso` 一致。
- `encodeSsoRedirectResult` / `parseSsoRedirectResult` 支持 `account_selection_required`。

**Life 单元测试**

- 持久化事务过期、单次使用、取消后清除。
- 没有待处理事务时的回调被丢弃；同一回调第二次被拒绝。
- `universalLinksOnly` 返回 `false` 时用同一个 URL 进入网页授权。
- `account_selection_required` 触发新事务的网页授权，旧事务被清除。

**真机（两个 App 都用 `QT792GAY4C` 签名）**

| 场景                            | 预期                                                     |
| ------------------------------- | -------------------------------------------------------- |
| 两个 App 都已安装，云乐坊已登录 | 无系统弹窗，切换到云乐坊，一次确认后回到 Life 并完成登录 |
| 云乐坊冷启动                    | 授权面板直接出现在最上层，不切换 Tab                     |
| 云乐坊已安装但未登录            | 先显示原生登录，登录后仍需确认                           |
| 未安装云乐坊                    | 直接进入网页授权，没有任何错误提示                       |
| 云乐坊中拒绝                    | Life 显示"未授权登录"                                    |
| 云乐坊中选择"使用其他账号"      | Life 自动打开网页授权                                    |
| 未确认就通过"‹ 云生"切回        | Life 保持等待，"改用网页登录"可用                        |
| 授权期间 Life 被系统回收        | 回跳后从 Keychain 恢复事务并完成登录                     |
| 授权期间在云乐坊中切换账号      | 流程被撤销，不回跳                                       |
| 手机 Safari 中的网页子应用登录  | 仍在 Safari 中完成，不会拉起云乐坊                       |
| 方案 A：网页授权回归            | `ASWebAuthenticationSession` 的 HTTPS 回调仍然正常       |
| 卸载 Life 后打开授权链接        | 云乐坊拒绝回跳，code 被丢弃                              |

## 分阶段

1. **P0 · 低成本优化**：`webcredentials:www.yunle.fun` 共享密码（[已准备，未上线](#shared-web-credentials)）。
2. **P1 · 首方跨 App**：`/auth/app` 页面与 AASA、`account_selection_required`、云乐坊协调器与面板、Life 跳转与等待界面，按方案 A 做真机验收。注册表不变。
3. **P2 · 开放**：注册表增加 `native-app` adapter 和审批流程，提供 Swift 包（从 `YunleIdentity` 抽出）给其他开发者接入。
4. **独立项目**：通行密钥；云乐坊面板内直接切换已保存的账号。

## 待决定

1. 返回地址用方案 A（复用 `/auth/callback`）还是方案 B（新路径，需要注册表审批）。
2. Life 是否用 `canOpenURL("yunlefun://")` 显示"将在云乐坊 App 中确认"的提示（需要声明 `LSApplicationQueriesSchemes`）。
3. P2 开放给其他开发者的时间点，以及 `native-app` adapter 是否需要单独的审批级别。

## 参考

- [RFC 8252 · OAuth 2.0 for Native Apps](https://www.rfc-editor.org/rfc/rfc8252)
- [OpenID Connect Core 1.0 · 认证错误码](https://openid.net/specs/openid-connect-core-1_0.html#AuthError)
- [Open Banking 客户体验指南](https://standards.openbanking.org.uk/customer-experience-guidelines/)
- [UIApplication.OpenExternalURLOptionsKey.universalLinksOnly](https://developer.apple.com/documentation/uikit/uiapplication/openexternalurloptionskey/universallinksonly)
- [ASWebAuthenticationSession.Callback.https](<https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/https(host:path:)>)
- [Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)
- [原生宿主授权接入](./ios-host-authorization.md)
- [原生授权面板规范](../ui/native-authorization-sheet.md)
