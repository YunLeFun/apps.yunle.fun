# 原生 macOS 验证

验证日期：2026-10-24。环境：Apple Silicon、macOS 26.6.2（25G83）、Xcode 27.1（27A9275）。本地 ad-hoc 签名；部署目标为 macOS 14，尚未在 macOS 14 真机运行。

## 构建与自动测试

| 检查 | 结果 |
| --- | --- |
| `./script/build_and_run.sh --test` | **142 项通过，0 失败，0 跳过**；含旧文档清空回归及并行图标工作新增的共享测试，摘要见 `build/validation/full-tests-summary.json` |
| `./apps/macos/scripts/verify_web_persistence.sh` | seed / restore 两个独立进程，各 1 项通过，0 失败，0 跳过 |
| `./apps/macos/scripts/verify_managed_sso.sh --run-managed-accounts` | 真实 Play SSO 与隔离旅程 1 项通过，0 失败，0 跳过；远端退出与本地清理完成 |
| `./apps/macos/scripts/verify_other_account_sso.sh --run-managed-accounts` | AI 春联、原生面板和 Chrome 155 完整真实 UI 旅程及 purge 各 1 项通过，0 失败，0 跳过；脚本退出码 0，剩余仓 0 |
| `./script/build_and_run.sh --verify` | 最终 Debug 构建通过，脚本退出码 0，`apps/macos/build/YunleFunMac.app` 成功启动 |
| iOS `YunleFun / Debug / generic iOS Simulator` | App 编译通过；未启动或新建模拟器 |
| 移动端 `native-auth-boundary.test.ts` | 22 项通过；共享协议的 acquisition / PKCE Swift 检查通过 |
| Shell 语法、package.json、`git diff --check` | 通过 |
| Electron 边界 | 本轮 SSO 未修改 Electron 实现；Windows / Linux 仍走现有 Electron 构建 |

测试覆盖共享目录与认证协议、登录取消与并发、凭据轮换、退出后禁止恢复、真实 macOS Keychain、导航限制、网页生命周期、账号/访客隔离与退役仓隔离，以及共享 SSO 服务/状态机和真实 WebKit 桥。常规账号测试使用合成认证 API；真实 Keychain 测试使用随机 service 并精确删除测试项。独立的夹具恢复用例在没有指定 UUID 时不执行清理；不会扫描其他任务的数据仓。

最终常规测试摘要位于 `build/validation/full-tests-summary.json`；完整结果位于 `build/DerivedData/Logs/Test`。跨进程日志和摘要位于 `build/validation/web-persistence`。这些本地产物不进入版本控制。

## 网页持久化

本轮发现：创建 Cookie 后立即释放整个 `WKWebsiteDataStore`，可能早于 WebKit 异步写盘，导致下次创建数据仓时 Cookie 丢失。原生 runtime 因此按 UUID 保留数据存储对象至进程结束，切换应用或账号时仍销毁网页与弹窗。

跨进程脚本通过本地 HTTP 的 `Set-Cookie` 分别写入账号 A、账号 B 和访客的合成数据。seed 不添加刷盘等待，正常退出；restore 在新进程重建仓库与 WebView，验证三组 `localStorage`、原生持久 Cookie（值、有效期、非会话属性）及 `document.cookie`。本次进程 PID 为 81339 → 81445，全部通过。

常规测试按生产生命周期保留 store 并重建 WebView；跨进程测试验证真正的退出与恢复。两者均不依赖 WebKit 私有文件布局。测试只使用独立 Testing 宿主，回环服务权限不进入 Debug / Release 应用。

## 第一阶段真实界面检查

- 线上目录成功显示 25 个应用；搜索“云空调”得到 1 个结果，清空后恢复完整目录。
- 打开云空调、将温度调至 27°C、返回目录再继续，页面状态保留；重建并重启原生应用后重新打开，仍显示 27°C。
- 云空调的独立遥控器通过原生窗口打开并完成加载，关闭后返回主窗口。
- 原生账号设置和手机/邮箱/密码登录表单可打开、切换及取消；未提交真实账号、发送验证码或执行注册。
- 最终应用保留在应用目录。截图：`build/validation/catalog.png`、`build/validation/cloud-application.png`。

## 边界与后续验收

macOS 已复用 iOS 的授权服务、状态机、bridge 和 PKCE 协议。完整线上验收已覆盖 Play 自动 SSO，以及 AI 春联、原生面板、Chrome 155 的“使用其他账号”真实 UI 旅程，包含宿主退出、访客隔离、重新登录和清理。Safari 承载系统认证、验证码与风控、第三方 OAuth、正式签名下的 Keychain 连续升级，以及 macOS 14 真机运行仍待分别验收。下载、付费/私有应用入口、正式安装器与公证不属于本阶段。

## 真实云应用 SSO 与隔离 · 2026-10-24

独立 `YunleFunMacLiveValidation` 使用两个既有生产受管测试账号，真实 `AccountStore`、`CloudbaseAuthService`、`HostAuthorizationService`、`MacWebRuntime` 和线上公开目录中的 Play。宿主登录后只打开应用，不点击网页登录、授权确认，也不由测试直接调用 `authorize()`；由 Play 自身启动授权。每次成功都通过无缓存、携带网页 Cookie 的 `GET https://api.play.yunle.fun/v1/session` 检查返回身份与当前宿主账号一致。

- A 自动登录，写入本轮唯一 localStorage 草稿键。
- B 登录时销毁 A 网页；B 使用另一数据仓，读不到 A 草稿，服务端身份匹配 B。
- 切回 A，恢复原仓和 A 草稿，服务端身份仍匹配 A。
- 退出 A，原仓退役；访客使用独立仓，读不到 A/B 草稿，服务端返回 401。
- 重新登录 A，使用新仓、没有旧草稿，并自动完成 SSO。

本轮 UUID：`6F3A879A-6EEA-4A72-A5AF-90F68E37D30D`。结果为 `journeyPassed=true`、`cleanupComplete=true`、`remainingProfiles=0`。报告保存在 `build/validation/managed-sso/<UUID>/`，不记录密码、token、授权 code 或用户 ID。测试逐仓通过网站退出控件退出并确认服务端 401，撤销本轮宿主会话，再删除网页数据仓、独占账号 Keychain 和撤销 journal；额外核对两项 Keychain 均不存在，run 目录已删除。普通 `pnpm test:macos` 不包含这项线上测试。

授权边界回归使用合成账号：来源与主 frame 校验、继承主页面 handler 的弹窗拒绝、导航/隐藏/关闭窗口及切号后丢弃迟到 code、访客登录后持久化归属再显式确认、已有账号仓旁的访客续接仓、刷新目录撤回可信域名。同文档 fragment 导航曾被误判为新文档，真实 WebKit 回归复现后修正；路径、查询、Origin 与端口校验仍保留。

## 真实系统认证与旧文档释放诊断

`verify_other_account_sso.sh` 使用 AI 春联真实登录入口、原生“使用其他账号”面板和 Chrome 155 的 `ASWebAuthenticationSession`。已完成的交互包括首次取消、系统浏览器登录 B、网站退出后再次取消，以及重新登录 B。夹具用网页自身会话向 CloudBase `/auth/v1/user/me` 发起无缓存请求，确认网页为 B，同时宿主仍为 A、身份 generation 和数据仓 UUID 未变。浏览器新窗口的空白登录表单只作为临时会话隔离的可见证据。

此前三轮均未通过完整旅程，原始失败结论保留：

| 轮次 UUID | 旅程停止位置 | 后续精确清理 |
| --- | --- | --- |
| `48905EBA-6CCA-468C-9382-13C0DA1D66E5` | 四个系统浏览器交互阶段通过，停在 `host-signout-retirement-and-guest` | purge 完成，剩余仓 0 |
| `2E6F0466-D215-4266-9999-EB15382B42AA` | 首次取消通过，操作超时停在 `login-b-system-session` | purge 完成，剩余仓 0 |
| `A37B79B3-F14E-4118-A66C-44956E512D90` | 四个系统浏览器交互阶段及宿主账号移除通过，停在 `host-signout-old-page-released` | purge 完成，剩余仓 0 |

报告位于 `build/validation/other-account-sso/<UUID>/`；上述三轮 `journeyPassed=false`，清理成功不改变旅程失败结论。

针对最后一轮的 5 秒弱引用释放断言，使用同一编译产物、未登录公开页进行对照：没有外部辅助功能访问时 WKWebView 弱引用归零；仅通过辅助功能读取页面也能复现对象仍存活，而 runtime 已释放。重置 CUA 会话或刷新辅助功能树仍可复现，说明该释放时序与 SSO 登录无关。复现输入和脱敏结果保存在 `build/validation/other-account-lifetime/`。

运行时现会在移除授权桥、handler 和 delegate 后，将退场网页加载为空白文档。新增常规回归主动保留旧 WKWebView，验证 `about:blank`、空 DOM、旧 JavaScript 状态与计时器变量消失、bridge/handler 消失；释放外部引用后仍严格要求弱引用归零。该用例单项通过，随后完整回归 142 项通过。真实 UI 夹具改为检查 runtime 的页面/会话集合为空、旧视图脱离窗口，以及仍被辅助功能持有时旧文档和授权桥已清空；不把外部持有期间立刻析构作为通过条件。

后续 `88F153DB-074D-4DE0-968A-194498B0BB5B` 完成全部 12 个阶段，`journeyPassed=true`：包含旧文档清空、宿主账号移除、原仓退役、新访客仓匿名 401、A 重新登录新仓，以及最后真实点击原生“使用此账号继续”后网页身份匹配 A。但同进程清理临时 WebView 时，三个仓均在 SDK 退出与匿名 401 成功后触发 `consumer-webview-release-failed`；该阶段 `phasePassed=false`，测试为 0 通过、1 失败，脚本最终退出码为 65。自动恢复的 cleanup 与新进程 purge 各 1 项通过，最终 `completeIncludingStorePurge=true`、剩余仓 0。该轮保留失败退出结论，后续完整通过记录如下。

清理临时 WebView 现也复用空白文档、脱离窗口及旧 bridge 消失的检查；辅助功能仍持有对象时只记录该事实。SDK 退出、本地会话为空和匿名 401 的条件继续保留，真正的数据仓移除仍须由新进程调用公开 WebKit API 确认。

## 最终真实系统认证验收 · 2026-10-24

最终轮次 `EBE3FC64-CE4E-47E2-8E94-CE9D00E2BE7A` 在 macOS 26.6.2、Chrome 155 完成全部 12 个阶段。操作人员实际点击网站登录、原生“使用其他账号”、系统浏览器登录与确认，以及最后的原生“使用此账号继续”；没有伪造授权回调。两次网页登录 B 后，服务端身份均匹配 B，而宿主账号、身份 generation 和原数据仓仍为 A；取消保持网站匿名。网站退出后重登、宿主退出时旧文档销毁、原仓退役、访客新仓匿名 401、A 重登新仓及最后授权为 A 均通过。

旅程报告 `journeyPassed=true`、`phasePassed=true`，测试为 1 通过、0 失败、0 跳过。进程 94718 完成三个仓的消费者 SDK 退出、本地会话清空、匿名 HTTP 401 和宿主退出 API 检查；随后新进程 8775 通过公开 WebKit API 移除三个记录的数据仓。purge 另为 1 通过、0 失败、0 跳过，`completeIncludingStorePurge=true`、`ownedWebsiteStoresRemoved=true`、`pendingStorePurge=false`、`remainingProfiles=0`，整条脚本退出码为 0。

最终复核本轮 run 目录已不存在；对账号 vault 和 sign-out journal 两项独占 Keychain 的精确查询均返回不存在。报告保存在 `build/validation/other-account-sso/EBE3FC64-CE4E-47E2-8E94-CE9D00E2BE7A/`，不包含密码、token、授权 code 或用户 ID。

清理报告分别记录消费者 SDK 退出成功、匿名请求返回 401、宿主退出 API 成功，以及新进程删除本轮记录的数据仓。匿名 401 不证明旧 access token 已立即失效；中央系统浏览器会话始终记录 `centralSessionRemoteRevocation=not-observed`，其服务端过期时间也未观测。每阶段还必须有恰好 1 项通过、0 失败、0 跳过的测试摘要和匹配的本轮报告；缺失、跳过或未完成 purge 均不能让脚本成功。

## 产物回收

临时 iOS 构建与日志回收 676.9 MiB；WebKit 历史诊断产物回收 943,067 字节；早期开发容器中已确认仅含空仓盐文件的 9 个测试仓回收 36,864 字节。保留运行中的应用、增量缓存、最后结果和小型验证记录。

SSO 迭代的 iOS 编译回归另回收 661.5 MiB（693,633,024 字节）。受管验收的原始日志与 xcresult 在任务独占临时目录中，结束后回收；仅保留脱敏阶段日志、测试计数与布尔报告。

新增 retained 续接测试曾因夹具跨 await 持有 WebView / 自动释放配置，留下两个合成测试仓；调整测试引用生命周期和 autoreleasepool 后全套通过。两个旧仓已在新 Testing 进程中，通过精确 UUID 清单和公开 `WKWebsiteDataStore.remove` API 回收；复核没有 `mac-runtime-sso-*` 待清理清单。恢复入口只接受指定 run UUID，可用 `TEST_RUNNER_MAC_RUNTIME_SSO_CLEANUP_ID=<UUID>` 运行 `RuntimeSSOTests/testRecoverExplicitPendingFixtureIfRequested`，无环境变量时不执行清理。

结束时复核：Testing 宿主没有本轮 WebKit 仓、待清理清单或 Keychain 测试项；本任务没有创建模拟器，也未关闭或擦除原有设备。并行任务已有的 iOS 反馈改动保持原样。
