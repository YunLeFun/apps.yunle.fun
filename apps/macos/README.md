# 云乐坊 · 原生 macOS

SwiftUI 主界面、AppKit 网页弹窗、WKWebView 云应用容器，最低 macOS 14。Windows / Linux 继续使用 `apps/desktop` 的 Electron；过渡期 Electron 的 macOS 构建也继续保留。

## 开发

需要 macOS、Xcode 和命令行工具。仓库包含生成的 Xcode 工程；安装 XcodeGen 后，运行脚本会从 `project.yml` 自动更新工程。新增/移动源码时需要重新生成工程。

在仓库根目录执行：

```bash
pnpm dev:macos
pnpm build:macos
pnpm test:macos
./apps/macos/scripts/verify_web_persistence.sh # 两个独立进程验证网页会话恢复
./apps/macos/scripts/verify_managed_sso.sh --help # 独立的受管账号线上验收
./apps/macos/scripts/verify_other_account_sso.sh --help # 真实原生面板与系统浏览器人工验收
# 等价入口，也支持 --verify / --debug / --logs / --telemetry
./script/build_and_run.sh
```

Codex 的 Run 按钮绑定同一脚本。它只停止本工作区的已启动应用，构建并启动 `apps/macos/build/YunleFunMac.app`。默认使用本地 ad-hoc 签名，安装器、Developer ID 签名、公证和正式发布尚未接入。

构建复用 `build/DerivedData` 增量缓存；每轮暂存和日志位于独占临时目录并自动清理。可用 `YLF_MAC_DERIVED_DATA` 指定另一缓存目录。常规测试结果保存在 DerivedData 的 `Logs/Test`；跨进程脚本保留 `build/validation/web-persistence` 中的小型日志与摘要，回收原始结果包。测试配置使用独立的 `fun.yunle.macos.tests-host`，不读取开发应用的账号和网页数据；仅测试宿主开放回环 HTTP 服务所需的 network.server 权限，正式应用仅允许网络客户端连接。

## 共享与平台边界

`project.yml` 直接编译 iOS 的目录模型、图标来源解析、公开目录读取/缓存、账号模型、认证 HTTP 服务、账号状态机、Keychain、网页数据仓库，以及 `HostAuthorizationService` / `NativeAuthorizationBroker`。原生与 Capacitor iOS、Mac 共用 `HostAuthorizationProtocol.swift` 中的 bridge 脚本、PKCE 请求与回调校验。源码只有一份，修改会同时影响消费者；目前保留内部类型访问级别，后续有独立包消费者时再抽 Swift Package。

为收敛共享依赖，只将 `AccountRequestBoundary` 移到 `AccountSignIn.swift`、将 `WorkshopLink` 移到 `ScanResult.swift`；行为不变。UIKit 视图和 iOS 网页控制器不进入 Mac target。目录、认证协议、账号并发和交互登录测试也共享原文件；移动端反馈、云居及移动登录倒计时测试仍只在 iOS 运行。

## 当前行为

- 目录图标与 iOS 共用运行时在线图标清单、持久清单缓存、内置快照兜底，以及 SVG / 位图解码和图片失败回退；优先应用正式图标，全部图片失败才显示 emoji。在线清单与同步命令见[原生目录图标](../../docs/dev/native-catalog-icons.md)。

- 真实公开目录、分类、本地搜索；缓存可浏览，联网确认目录后才能打开应用。邀请、会员、付费、私有作品等入口保持受限。
- 同时运行一个云应用。返回目录保留页面与表单；继续使用恢复同一 WKWebView。结束应用或切换到另一应用时，运行时移除页面、注销授权桥，并将旧文档替换为空白页，结束原页面的脚本和计时器。数据存储对象保留到进程结束，让 WebKit 完成异步 Cookie 写盘，防止快速切换丢失刚建立的会话。目录成功刷新后撤回或改变地址的应用会关闭。
- 原生密码、手机/邮箱验证码、图片验证码登录，账号切换、退出。宿主账号凭据存于不同步的 macOS Keychain，启动时恢复并按需刷新；密码只存在登录表单内存中。
- 网页数据按宿主账号/访客、应用及 Origin 选择稳定的 WebKit 数据仓。重启后重新打开同一应用可继续使用网站保存的 Cookie / localStorage；网站服务端过期或仅会话 Cookie 的有效期仍由网站决定。不会自动保存任意页面 URL、OAuth 回调或未提交表单到磁盘。
- 切换账号关闭旧网页；退出先退役该账号的数据仓，再清理账号凭据。重新登录不会自动接管退役仓；该仓的显式恢复 UI 留待后续接入。
- 支持 HTTPS 导航、网页登录弹窗和 JavaScript 对话框；当前地址域名始终来自正在访问的网页。自定义协议、任意本地文件导航及下载不自动放行。

## 云应用 SSO

已接入宿主授权的云应用可通过 `window.ylf.authorize()` 使用 iOS 同一套单次 code / PKCE 流程。宿主已登录时，注册表允许静默授权的应用可自动登录；要求确认的应用使用原生授权面板。未登录时先打开原生登录面板，成功后重新校验应用政策并请求确认。未接入该协议的网站仍按自身流程登录。

Mac 仅开放 `canIUse`、`getEnv` 和 `authorize`。授权只接受可见主窗口中可信 HTTPS 主文档的请求，实际来源取自 WebKit；iframe 与弹窗无授权权限。导航、返回目录、隐藏/关闭窗口和切换身份会取消待完成请求，晚到结果不能交给新页面。宿主长期 token 只发往认证服务，不进入网页。

普通账号切换结束旧网页文档并选择对应账号的数据仓；即使辅助功能客户端仍持有旧 WKWebView，它也会脱离窗口、清空文档并失去授权桥。登录面板接受的访客登录可保留当前页面：先把该仓归属持久化到新账号，再恢复授权；若账号已有独立仓，访客续接仓只保留给当前会话，之后重新打开使用原有仓。退出先退役数据仓，重新登录使用新仓；旧网站会话不会自动恢复。授权面板的“使用其他账号”走临时系统认证会话，不切换宿主账号。

## 验证

本机验证记录见 [验证记录](./validation.md)。自动测试使用合成身份与独占数据，真实 Keychain 项使用随机 service，WebKit 仓只清理本次记录的 UUID。清理失败会保留清单和精确路径以便恢复清理，不扫描或删除其他账号数据。

`YunleFunMacLiveValidation` 是单独的线上验收 scheme，不属于 `pnpm test:macos`。只有显式运行 `./apps/macos/scripts/verify_managed_sso.sh --run-managed-accounts` 才读取私有受管账号池中的两个指定生产测试账号，并通过真实 Play 验证自动登录、A→B→A、退出和重新登录。测试输入读后删除，认证材料仅进入独占 Keychain；报告只保存阶段、布尔值和测试计数。每轮会退出网站与宿主会话，再删除该轮 WebKit 仓与 Keychain；中断后可按脚本输出的 UUID 执行 `--cleanup UUID` 恢复清理。

系统“使用其他账号”的独立入口为 `verify_other_account_sso.sh --run-managed-accounts`。操作人员按 `--status UUID` 提示点击真实 AI 春联、原生授权面板和系统浏览器，观察后用 `--ack` 记录；夹具另向服务端核对网页身份，确认宿主账号没有切换。2026-10-24 已在 macOS 26.6.2、Chrome 155 完成全部 12 个阶段，包括取消、网页登录 B 而宿主保持 A、网站退出及重登、宿主退出后的访客隔离，以及 A 重登新仓后原生授权。旅程和新进程 purge 各 1 项通过，脚本退出码为 0，本轮数据仓、Keychain 项和临时目录均已清理。流程说明见 [OtherAccountValidation.md](./LiveValidation/OtherAccountValidation.md)，报告见[验证记录](./validation.md)。

脚本要求每阶段恰好 1 项通过、0 失败、0 跳过及匹配的本轮报告，失败后继续清理并保留失败状态。清理先确认消费者 SDK 退出、匿名请求返回 401 和宿主退出 API 成功，再由新进程删除记录的数据仓；这些检查不证明旧令牌立即失效。中央系统浏览器会话的远端撤销与服务端过期时间未观测，不能以临时窗口关闭或空白登录表单代替撤销证据。

本阶段不创建模拟器，iOS 回归仅使用 generic simulator 编译目标，不占用正在运行的设备。普通测试不会访问受管真实账号。Safari 承载系统认证、验证码发送与风控、第三方 OAuth、正式签名身份下的 Keychain 连续升级恢复，以及 macOS 14 真机兼容性仍需分别验收。
