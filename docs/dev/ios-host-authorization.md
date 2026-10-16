# 原生 iOS 宿主授权接入

> 2026-10-16。已接入原生账号与现有 WKWebView 授权协议，并验证真实访客取消 / 再试旅程；真实账号签码、系统其他账号与真机仍待联调。完整目标见 [原生改造 Goal](./ios-native-migration.md)。

## 协议与服务

原生运行时不再让 `window.ylf.authorize` 因缺少宿主回调直接返回“授权代理不可用”。`NativeAuthorizationBroker` 连接现有 WebView、中央注册策略、原生登录 / 授权面板与 Keychain 账号服务，不启动隐藏的 CloudBase JS SDK。

| 阶段         | 原生处理                                                                                                                                |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| 收到请求     | 沿用 WKSecurityOrigin 与主 frame 判断；检查精确 HTTPS 来源、同源 redirect URI、client、单一 scope、nonce 与 S256 challenge              |
| 查询注册策略 | 复用 `POST https://apps.yunle.fun/api/auth/sso/resolve`，不附宿主 Bearer token、Cookie 或客户端自报 UID                                 |
| 核对响应     | issuer 固定为 `https://www.yunle.fun`；逐项核对请求回显、策略版本、注册指纹、展示来源和许可描述；名称 / 图标仅取已验证策略              |
| 选择账号     | 已登录账号从原生会话读取；未登录进入原生“登录并继续”；`select_account` 转交既有 ASWebAuthenticationSession                              |
| 用户确认     | `consent` 使用共享的 UIKit 原生授权面板；访客登录完成后总是再次确认，即便此客户端通常属于 trusted                                       |
| 签发 code    | 使用官方 CloudBase Functions OpenAPI：`POST /v1/functions/sso-ticket`，action 为 `issueSsoCode`，Bearer token 只发给固定 CloudBase 网关 |
| 返回网页     | 只返回 `ok`、单次 code、固定 issuer 与合法的可选到期时间；不把原始服务响应、宿主 token、Cookie 或账号资料整包交给页面                   |

网关沿用国内上海环境 `yunlefun-8g7ybcxc7345c490`。本轮先通过 MCP `searchKnowledgeBase(mode="openapi", apiName="functions")` 读取官方路径与鉴权定义，再实现请求；没有根据函数名猜测另一个 HTTP 触发器 URL。现有 `sso-ticket` 云函数和中央注册表仍是服务端权限与一次性 code 的最终依据，本仓库不重写它们。

原生网络会话禁用 Cookie、共享凭据与缓存，并拒绝跟随重定向。HTTP 失败、HTML、非严格布尔值、协议回显替换、非法 prompt / scope / issuer、错误 code 格式均不能被当作成功。首次签码 HTTP 401 可以通过现有账号服务刷新并重试一次，刷新前后都要核对同一个账号。

## 登录回跳与账号隔离

原生登录表单继续使用系统 Form、Picker、SecureField、一次性验证码填充与 Dynamic Type。待授权场景增加可信应用名称，明确显示“登录后返回……，仍需在原生面板确认。登录本身不会自动授权。”；不在 URL 或本地云居文件里保存凭据。

只有一个特定例外允许保留网页：**已经通过注册策略验证、正在等待原生登录的访客请求，转变为已登录账号时**。它保留原 WebView 与原请求，结束其他会话，等待身份 Cookie 允许名单清理完成，再重新查询注册策略并展示确认面板。此例外不合并访客云居，不自动授权，也不允许从一个已登录账号延续到另一个账号。

切换 / 退出已登录账号、结束应用、网页导航使请求失效、用户取消或超时，都会撤销对应操作。每次异步结果都重新检查原请求、当前文档和账号；取消后的迟到 code 不能交付给新网页或新账号。一次同时处理一个用户决策，另一个请求不会抢占正在显示的面板。

网络阶段使用 30 秒请求期限，登录和确认使用最长 5 分钟决策期限；作出选择后恢复网络期限。过期会关闭授权 UI。完成 / 取消后清理任务与计时器，计时器不保留已经结束的页面。

“使用其他账号”复用既有系统认证会话、state / nonce / PKCE 与 callback 验证，不替换宿主存储的账号。原生工程已注册现有 `yunlefun` callback scheme，并检查生成的 Debug / Benchmark 应用 Info.plist；这不等于系统账号成功回跳已经验收。

## 本轮实测

- 生产公开目录确认 AI 春联和暴力电驴为公开应用；中央只读策略查询均返回 HTTP 200，应用名称 / 精确来源 / scope 信息有效。未发送验证码、登录账号或申请真实 code。
- iPhone 18 Pro / iOS 27：从真实目录获取 AI 春联，打开网页，进入原生“登录并继续”，检查 AI 春联上下文和手机号表单；取消回到同一网页，再试仍能进入原生登录，随后再次取消。XCUITest 通过，已导出截图。
- iPhone 16 Pro / iOS 18.6：相同 AI 春联取消 / 再试旅程与云空调打开 / 收起 / 恢复 / 结束两项 XCUITest 均通过。
- 原生日常 Scheme 共 57 项通过：56 项单元测试与 1 项设置 / 登录取消 UI 旅程。新增授权测试覆盖回显替换、严格协议值、凭据出站范围、登录后重新确认、等待 Cookie、取消 / 超时、账号切换与导航后的迟到结果、401 重试、其他账号路由，以及已完成请求的页面释放。
- 共享容器 / 身份边界 Vitest 26 项通过；旧兼容工程 Release 编译通过。原生 / 兼容壳复用授权面板时，选择回调在面板关闭后继续，避免紧接着呈现另一系统认证界面。

实测也修正了两项假设：iOS 27 默认自动搜索布局未在目录初始页面暴露搜索框，现使用系统导航栏搜索框常显；暴力电驴当前公开页面没有登录入口，排行榜未开放，因此它的“注册策略可查询”不能充当真实登录旅程证据。真实取消旅程使用已确认有登录入口的 AI 春联。AI 春联网页目前将取消结果显示为“同步失败”，原生仍正常返回，第二次请求已验证可用。

聊天本地附件 `ios-native/sso-ai-sfc-ios27` 保存原生登录与取消截图；最终重复取消结果和 iOS 18.6 结果另有 xcresult 记录。Benchmark 方法为 `testNativeGuestAuthorizationLoginCanBeCancelled`，只在访客模拟器运行，遇到已登录账号会跳过，不替开发者退出账号。

## 仍待验收

真实账号登录 / 刷新、授权面板确认后的正式 code 签发 / 消费、系统其他账号完整回跳、真实切换 / 退出、无障碍与浅深色完整矩阵、前后台 / 弱网 / 进程回收、iOS 最低版本和真机均保留未完成。关闭 WebView 与清理现有 Cookie 允许名单不能单独证明所有云应用的持久身份隔离，仍须逐应用核对。单元测试中的模拟 code 不能算生产签码成功；本轮真实旅程只证明访客入口、取消和再试。

## 参考

- [CloudBase Functions HTTP API](https://docs.cloudbase.net/http-api/functions/functions-post)
- [原生授权面板规范](../ui/native-authorization-sheet.md)
- [原生接口盘点](./ios-native-api-audit.md)
