# 原生 iOS CI 与开源选择

调研日期：2026-10-16。初次调研时 `YunLeFun/apps.yunle.fun` 为私有仓库，根目录已有 MIT License，组织计划为 GitHub Free。后续按用户确认范围清理 Git 历史并公开仓库，账单预算与 runner 注册未改，实际执行见文末。

## 判断

可以考虑开源，尤其是希望长期吸引贡献、展示原生设计与形成云应用生态时。开源能解决标准托管 runner 的计算费用问题，但不应只凭一次预算阻断就直接公开全部历史。

用户已明确普通历史、后端与运维资料可以公开，因此按整仓开源执行，无需仅因这些内容存在而拆分客户端。已从可写分支历史精确过滤一份真实云居导出路径，保留其余历史；用户随后决定暂缓 PR 缓存处理，详见[公开内容复核](./open-source-review.md)。私有仓库也支持付费托管 runner 或隔离的自托管 Mac，本项目最终选择公开仓库。

## GitHub 当前规则

| 选择                           | CI 计算费用                                                | 本项目影响                                                                              |
| ------------------------------ | ---------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| 整个仓库公开                   | 标准 GitHub 托管 runner 免费，包括标准 macOS               | 同一公开仓库的 Web、桌面与原生 iOS 工作流可受益；代码和既有 Actions 历史 / 日志一起公开 |
| 保持私有，使用托管 runner      | 使用组织计划额度，超额按 runner 类型收费；预算可阻止启动   | 无需整理公开发布，但要给组织的 Actions 用量安排额度与上限                               |
| 保持私有，使用自托管 Mac       | 当前官方文档列自托管 runner 使用免费；硬件、电费和维护自理 | 适合已有专用隔离 Mac 的情况；需要独立管理运行环境和升级，不直接接入带日常凭据的开发环境 |
| 只公开客户端，生产运维保持私有 | 只有公开仓库中的标准 runner 免费                           | 需要维护源码边界和构建依赖；原有私有仓库的 CI 仍受自身额度限制                          |

GitHub Free 组织计划当前含每月 2,000 分钟和 500 MB artifact 存储额度，组织内仓库共享计划额度。标准 macOS 超额计算费当前为每分钟 0.062 美元；例如 300 分钟全部属于收费部分时，计算费约 18.60 美元，未包含超额存储或其他用量。这只是单价示例，不能代替组织账单测量。当前 API 未提供本组织已用额度或预算金额，本次未读取付款信息。

公开免费仅适用于标准托管 runner，larger runner 仍计费；artifact / cache 有各自的额度和规则，不把公开仓库理解为所有服务无限免费。自托管收费的旧公告后来延期，以当前文档和公告顶部更新为准。

来源：[Actions 计费](https://docs.github.com/en/billing/concepts/product-billing/github-actions)、[runner 单价](https://docs.github.com/en/billing/reference/actions-runner-pricing)、[标准 runner 列表](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、[自托管计费公告更新](https://github.blog/changelog/2025-12-16-coming-soon-simpler-pricing-and-a-better-experience-for-github-actions/)。

## 项目公开范围

当前是包括原生 iOS、Web / 桌面、Nitro 后端、CloudBase 配置与运维资料的单仓库。客户端工程还直接引用 `apps/mobile/ios/App/App` 的 Swift 运行时和图片资源。只复制 `apps/ios` 到公开仓库会失去这些构建依赖，拆分需要同时保留运行时、资源、锁定依赖及服务契约，不能靠公开一个空 CI 仓库解决。

MIT 文件表明现有代码已选择宽松许可证，但它不能证明所有第三方素材、贡献和历史内容都已完成公开授权核对。生产账号数据、凭据与签名材料继续保存在仓库外；服务端源码是否公开可作为单独的商业决定。客户端开源也不改变会员、支付和私有内容必须由服务端鉴权的边界。

GitHub 明确说明，私有转公开会使代码和 Actions 历史 / 日志可见，其他人能 fork。之后改回私有不会让已经公开的 fork 一起变私有。因此最终公开前还需复核历史日志、附件、Issue / PR 中的测试记录、品牌素材及第三方资源，而不只检查当前目录。[可见性变更说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility)。

本轮只做了初步只读盘点：

- 当前被 Git 跟踪的敏感文件名检查未发现 `.p8` / `.p12` / 私钥或真实 `.env`；有 `.env.example`。本机真实账号文件留在仓库外。
- Gitleaks 8.30.1 对本机完整、非浅克隆的全部本地可达 refs / 235 个提交运行默认规则，报告 4 个 `generic-api-key` 匹配。报告已脱敏，保存在仓库外。
- 其中 2 个匹配横跨历史 `.env.example` 的空 secret 字段与下一变量；另外 2 个已核实为第三方 Coze 文档中顺序数字组成的短示例，均未确认为真实凭据。本次未对任何历史字符串进行认证，也未轮换凭据或添加扫描忽略规则。
- 后续复核覆盖 236 个本地可达提交、48 条 Issue / PR 正文、28 条评论和 458 份可取得的 Actions 日志，未新增凭据命中；但在常规密钥扫描之外发现一份真实云居导出。当前源码已移除，历史对应路径待处理。完整范围、不可取得的日志及附件 / 素材边界见[公开内容复核](./open-source-review.md)。

## 原生 iOS CI

新增 `.github/workflows/ios.yml`，只在原生工程、共享 iOS 运行时 / 资源或工作流变更时自动运行，并保留手动入口。配置适用于公开或私有仓库：

1. GitHub 官方 `xcode-27` 标准镜像，固定 Xcode 27.0，与本机验证版本一致。该 runner 标签仍是 public preview，可能有可用性与队列限制；不悄悄退回旧 SDK。
2. 使用已提交的 Xcode 工程与 `Package.resolved`，只解析锁定的 SwiftDraw 版本并核对锁文件不变。
3. 新建独立 iPhone 18 Pro / iOS 27 模拟器，用 `simctl bootstatus -b` 等待启动迁移结束，再串行运行日常 `YunleFun` Scheme 的单元、集成和访客 UI 测试；每项测试有执行时限。
4. 模拟器 ad-hoc 签名保留 Keychain 测试能力，随后只编译 Release 模拟器产物；不安装正式 Bundle ID，不归档上传。
5. 有结果包时，无论成功或失败都导出摘要、测试明细和来源 / 文件摘要回执，保留七天；失败时另外保留完整日志 / xcresult 三天。完成后删除本次新建模拟器。只授予 `contents: read`，checkout 不保留凭据；两个 Action 固定官方仓库的完整提交 SHA。

线上账号联调、真实扣费、Sandbox、签名、TestFlight 与商店提交不包含在日常工作流。整个 job 不注入仓库 secret，使用普通 `pull_request` 事件；公开后外部贡献也不应取得生产或签名凭据。自托管 runner 的信任边界需单独设计，不能直接让外部 PR 在日常开发 Mac 上执行。[工作流安全说明](https://docs.github.com/en/actions/reference/security/secure-use)。

官方 `macos-latest` 当前仍可能提供较旧的默认 Xcode，不能把它等同于最新 iOS SDK。`xcode-27` 镜像及 Xcode 27.0 / iOS 27.0 的来源已核对：[官方镜像清单](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)。actionlint 1.7.12 尚未内置这个标准预览标签，`.github/actionlint.yaml` 仅扩展标签白名单，不注册自托管机器。

配置和本机验证不能代替远端执行通过；公开后以实际工作流结果验证标准 runner。完整原生迁移、真机、最低系统、升级和发布验收继续按[原生改造 Goal](./ios-native-migration.md)推进。

## 冷启动验证记录

初次本机新建模拟器试跑在第一条 WebKit Cookie 写入等待回调，124 项通过后为定位而中断；原始结果保留失败 / 取消状态。Cookie 夹具改为 XCTest 异步 expectation 并逐个回调设置 10 秒时限，单项通过，但另一全新模拟器完整试跑仍为 257 通过 / 3 失败，涉及 Cookie、实际旧版 WebKit 读取和旧版导入 UI；不把之后的单项通过合并成全套通过。

第二次工具观察在 300 秒超时后，原 `xcodebuild` 仍在运行；已核对进程，随后中断并读取实际终态 xcresult，未因观察超时重启测试。其结果为 `test_sim_2026-10-16T09-42-22-417Z_pid91503_2bf7d3cf.xcresult`。相关 WebKit / RunningBoard 日志和主线程采样保存在仓库外 `ios-native/ci-research`，不据此把原因归到业务逻辑或宣布已修复系统问题。

工作流现显式等待新模拟器启动完成；第三台设备实际观察到 LaunchServices、Keychain 与 WebBookmarks 的初始迁移，37 秒后结束。但 Cookie 首次写入仍超时，为继续定位而中断该轮；这证明启动等待本身不足以解决问题。第三轮结果为 `test_sim_2026-10-16T09-51-44-751Z_pid91503_258dfe31.xcresult`，不是完整回归通过。

Cookie 夹具还显式保留非持久化 `WKWebsiteDataStore` 至异步调用结束；WebKit 的 Cookie store 实现对拥有它的数据存储使用弱引用，不能只持有 Cookie store 推定所有者仍在。[WebKit 源码](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/APIHTTPCookieStore.h)。这项防御性修正尚不能被当作冷启动根因结论：第四台本机新模拟器在测试之前即因 `launchd_sim` 无法绑定会话而启动失败，系统返回码 60。

四台本轮创建的模拟器均已删除；原有设备与数据保留。本机冷环境的 WebKit / CoreSimulator 问题、远端执行和完整原生迁移验收继续列待验。后续应在独立可正常启动的环境重现原始完整旅程，不能通过跳过这些测试判定完成。

原有模拟器上的首次当前源码复测也出现 Cookie 读取超时（259 通过 / 1 失败）；只保持数据存储存活还不足以通过该轮。在夹具中按实际宿主创建 `WKWebViewConfiguration` / `WKWebView`，从其配置取得 Cookie store，并让两个所有者跨过异步回调后，原有设备完整日常回归为 260 项通过（257 单元 / 集成 + 3 UI），无跳过或构建诊断。结果为 `test_sim_2026-10-16T10-00-43-026Z_pid91503_7e6a9cad.xcresult`。此处没有修改产品的 Cookie 清理实现，也没有减少原有删除 / 保留断言；这是原有可运行环境的回归证据，不替代新建模拟器与远端验证。

锁定依赖的独立 Release 模拟器编译通过，无构建诊断；产物核对为 `fun.yunle.apps`、最低 iOS 16，且包含原生隐私用途资源。未安装此 Release 产物。actionlint、根 lint 与文档构建通过，文档仅有既有高亮 / 包大小提示。

## 公开后的实际执行

按用户后续确认，将已清理可写 Git 历史的仓库公开；PR 缓存暂缓处理，没有提交 Support 工单。已核对匿名 GitHub API 返回 200、`private: false`。

在同一清理后提交 `6f2d1eb` 重跑三条工作流的第二次尝试：[原生 iOS](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38895225888/attempts/2)、[Web / 移动端](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38895225919/attempts/2)、[桌面](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38895225899/attempts/2)。六个 job 均已实际启动，不再因组织 Actions 预算而停在运行前；原生已核对 Xcode / 锁包并进入独立模拟器创建。这只证明预算阻断解除，最终结果仍以工作流终态为准。

该轮 Web / 移动端与 Chromium 两项通过，Windows 桌面通过。macOS 桌面请求 840pt 内容高度，runner 实际限制为 677pt，尺寸断言失败；Linux 未安装目录中的 Chromium 沙箱辅助程序缺少 root / 4755 权限，启动检查中止。

桌面工作流为临时 runner 配置打包目录下的沙箱辅助程序，保留沙箱运行；`0d9d05c` 的 Linux 检查随后通过。第一次屏幕适配错误地同时限制宽度，macOS / Windows 分别得到 1024 / 1008pt，而原宽屏测试需要 1280pt；这轮失败保留。后续修正只适配 macOS 内容高度，保留两种请求宽度、精确视口尺寸、最小 600pt 高度、溢出与操作入口可见性断言，截图标明实际尺寸。本机重新构建后的专项通过；首次本机试跑在 Electron 启动处超时，记录保留。

窗口高度调整依据 [Electron BaseWindow](https://www.electronjs.org/docs/latest/api/base-window) 的原生尺寸与 macOS 屏幕限制，使用窗口外框 / 内容差和 [screen 的工作区](https://www.electronjs.org/docs/latest/api/screen/)计算。沙箱权限依据 [Chromium SUID sandbox](https://chromium.googlesource.com/chromium/src/+/26b424af1258efd1d49bd9e2c68bdd8db4ae4d1e/docs/linux/suid_sandbox_development.md)，没有给应用增加 `--no-sandbox`。

原生首轮日志中 4 个访客 UI 旅程通过；会话测试出现 4 处断言失败，集中于两个嵌套呈现用例。该轮被后续提交的 concurrency 规则取消，不能计为完整回归通过。夹具原先只等待 50 / 100ms，现改为等待 UIKit 呈现完成、控制器稳定进入窗口，以及旧控制器和视图实际离开；账号模型必须立即清空的断言保留。修改后本机会话专项 **10 项通过**：`test_sim_2026-10-16T15-09-19-495Z_pid91503_d07c27ab.xcresult`。没有修改产品的账号清理逻辑或跳过嵌套弹层断言，远端冷环境仍以修正后工作流终态为准。

后续提交的运行与最终结论同步记录在[草稿 PR #48](https://github.com/YunLeFun/apps.yunle.fun/pull/48)；未验证的真机、完整辅助功能、Sandbox 与升级范围继续保留。

原生 CI 还显式关闭 Xcode 的自动机器级测试诊断采集，与本机工具的执行条件一致；测试失败仍返回失败状态，日志、xcresult 和测试附件继续上传。没有关闭测试、重试后改记通过或取消原有断言。

`2bcee4b` 的 [Web / 移动端](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38923475588) 通过，[桌面](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38923475488) 的 macOS 与 Linux 通过。Windows 打包启动已输出成功标记，但退出后的临时 profile 删除遇到 `Network/Trust Tokens-journal` 文件占用，整项仍判失败。清理改用 Node 的有上限重试（最多五次、初始间隔 200ms），持续占用仍返回失败，未跳过启动或吞掉清理错误。重试行为依据 [Node fs.rm](https://nodejs.org/docs/latest-v24.x/api/fs.html#fspromisesrmpath-options)；脚本三项单元测试与专项 lint 通过，实际 Windows 验证仍以新提交的工作流为准。

同一提交的 [Native iOS CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38923475502) 最终 **成功**：官方 Xcode 27 runner 新建独立模拟器后，260 项单元 / 集成与 4 项访客 UI 测试全部通过，随后 Release 模拟器编译通过，专用模拟器删除完成。日志分别记录 `TEST SUCCEEDED` 与 `BUILD SUCCEEDED`，没有测试失败或跳过。这是本轮首份完整远端冷环境通过证据；不代表线上账号、正式安装升级、真机、完整辅助功能或发布验收完成。原先失败和取消的记录继续保留，后续提交以其自身 CI 为准。

## 登录改进后的冷环境执行 · 2026-10-17

`6051799` 的 [Native iOS CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38936977208) 为 **264 通过 / 2 失败**：260 项单元 / 集成通过，6 项 UI 中标准字号键盘可操作性查询和旧版导入空状态失败，Release 编译未执行。失败日志、xcresult 和附件已取得，专用模拟器删除完成。同提交 Web / 移动端、Chromium、macOS / Linux / Windows 桌面与 GitGuardian 六项检查通过；没有据此将原生项改记成功。

键盘改为按名称跨角色查询，保留实际可见 / 可点击与收起断言；导入将超时单独提示，只允许显式点击一次原生重试后核对真正的空状态，未将错误或无响应视为空记录。首次冷启动成功率仍未验收。拒绝了可能漏读真实 localStorage 的网站数据记录捷径，未提交该候选；已有记录与凭据不改写的检查保留。中间失败、环境清理与新建模拟器的恢复旅程分别记录，见[键盘](./ios-keyboard-layout-diagnostics.md#托管执行中的按键查询)与[导入](./ios-upgrade-migration.md#冷启动超时与原生重试-·-2026-10-17)。

修正后的本机完整日常回归 **268 通过 / 0 失败 / 0 跳过**（262 单元 / 集成 + 6 UI）：`test_sim_2026-10-16T18-02-29-211Z_pid44279_5d51481a.xcresult`，没有临时日志插桩。测试存储释放的等待上限调整后单项复核另 **1 项通过**：`test_sim_2026-10-16T18-07-30-695Z_pid44279_e2e452d4.xcresult`，不减少内容或清理断言。新提交 CI 以其终态记录在 PR #48，不能用本机通过或先前提交的绿色检查替代。

`842cef1` 的[第二轮原生 CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38945616136) 为 **267 通过 / 1 失败 / 0 跳过**：262 项单元 / 集成与其余五条 UI 通过，标准字号登录用例在进入表单前按组合文字查找入口时卡住，超过原有 120 秒限制；Release 未执行。导入旅程已通过，两次失败原因分别保留，不能归为同一键盘失败。

访客登录入口补充 `me.login` 标识，旅程先确认“我”页导航就绪，再按标识进入，并继续核对“登录云乐坊”的可访问文字。新建隔离模拟器的全部 **6 UI 通过，0 失败 / 跳过**：`test_sim_2026-10-16T18-34-51-200Z_pid44279_82a73a01.xcresult`。没有扩大用例时限；最新提交的完整远端执行仍以终态为准。

`8793087` 的[第三轮原生 CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38949308097) 为 **267 通过 / 1 失败 / 0 跳过**，六条 UI 全部通过。失败来自既有 `NativeApplicationMenuTests.testMenuActionEndsExactlyOneSessionAfterDismissal` 的两条回调计数断言，Release 未执行。夹具原先固定等待呈现 150ms、菜单 450ms、退出 650ms；现等待 UIKit 呈现完成、控制器稳定进入 / 离开窗口及实际关闭回调。重复动作只执行一次、身份失效丢弃动作、保留回调不能干扰后续状态等断言保留，局部启用的动画设置在结束时恢复。

该菜单专项本机 **5 通过 / 0 失败 / 0 跳过**：`test_sim_2026-10-16T18-58-10-745Z_pid44279_f733d6b0.xcresult`。初次测试修正的两处 await / 断言编译错误已修正，构建失败记录保留。下一提交仍需完整远端终态，不以 UI 六例通过覆盖菜单失败。

`7e62fbf` 的[第四轮原生 CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38952150899) 为 **267 通过 / 1 失败 / 0 跳过**：全部 262 单元 / 集成与其余五条 UI 通过，导入的初次和一次原生重试均在附件中记录明确的 8 秒超时，Release 未执行。只读 WebKit 加载预算调整为 20 秒，UI 等待实际结果 / 超时为 25 秒；用例总时限、固定来源、取消、一次重试和数据校验保持。冷启动耗时仍需性能验收，新提交按自身完整执行核对。

上述预算调整后的新建隔离模拟器专项 **25 通过 / 0 失败 / 0 跳过**（19 导入检查 + 6 UI）：`test_sim_2026-10-16T19-35-11-698Z_pid44279_b76e41f8.xcresult`。四轮失败原始包均已保留在仓库外；更长等待不代表冷启动性能改善，最新托管结果继续单独记录。

同一产品源码的独立锁包 Release 模拟器编译另通过，无构建诊断：`build_sim_2026-10-16T19-40-08-815Z_pid44279_dcfe8b2e.log`。正式 Bundle ID `fun.yunle.apps`、最低 iOS 16 与原生隐私用途资源已核对，锁文件无变化。此本机结果不能代替下一轮完整远端 CI，也不代表正式安装、签名归档或发布。

`096f076` 的[第五轮原生 CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38957237812) 为 **267 通过 / 1 失败 / 0 跳过**，六条 UI 全部通过，包括 20 秒预算下的导入。持久化导入夹具在准备样例页面时仅等候 5 秒，导航未就绪便继续写入脚本，造成导航断言和后续脚本错误；Release 未执行。夹具改为等待实际导航完成 / 失败事件，上限 20 秒，准备失败立即停止后续脚本并清理视图，内容、凭据与清理断言保留。

该修正的导入专项本机 **19 通过 / 0 失败 / 0 跳过**：`test_sim_2026-10-16T20-08-41-527Z_pid44279_f2a65b35.xcresult`。组合手机号 / 密码用例在托管执行耗时 114 秒，现拆为独立登录旅程，每项仍保持原 120 秒时限及实际输入 / 键盘可操作 / 收起断言。新建隔离模拟器 **7 UI 通过，0 失败 / 跳过**：`test_sim_2026-10-16T20-13-59-437Z_pid44279_eba5992b.xcresult`；完整日常现为 262 单元 / 集成 + 7 UI，共 269 项，最新远端仍以自身终态为准。

夹具的完成事件还核对实际固定 URL 后，持久化记录专项另 **1 项通过**：`test_sim_2026-10-16T20-23-39-544Z_pid44279_70d1b010.xcresult`。导航到其他页面不能触发样例写入的就绪信号。

`167aed5` 的[第六轮原生 CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38962372915)完整成功：**262 单元 / 集成 + 7 UI，共 269 项通过，0 失败 / 跳过**；Release 模拟器编译及隔离模拟器删除成功。同提交的 Web / 移动端、Chromium、macOS / Windows / Linux 桌面与 GitGuardian 一并通过，共七项检查成功。前五轮失败记录继续保留。

后续字号与 VoiceOver 改进的本机专项分别见[系统审计](./ios-accessibility-audits.md)和[VoiceOver 验证](./ios-voiceover-validation.md)。显式 Benchmark 审计与 VoiceOver 不在日常 269 项之内；系统审计失败不能被日常绿色检查覆盖。当前提交的远端终态继续记录在[草稿 PR #48](https://github.com/YunLeFun/apps.yunle.fun/pull/48)，不使用上一提交的结果代替。

## Cookie 夹具完整性复核 · 2026-10-17

字号与 VoiceOver 提交 `0a4249d` 的[原生 CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38989327105)为 **268 通过 / 1 失败 / 0 跳过**：七项 UI 均通过，Cookie 清理用例在清理前仅读到五条样例，预期为六条；清理后的三条无关 Cookie 保留断言通过。Release 未执行，隔离模拟器已删除，其余六项检查成功。这个日志没有记录缺少的具体名称，不能据此认定产品删除规则有误，也未证明冷启动的唯一根因。

夹具现先完成非持久化 store 的一次读取，再通过 HTTPS 响应头解析不带 Domain、具有 Secure 和根路径的 Cookie；每条只写入一次，随后读回并核对累计的完整域名 / 名称集合及数量。准备不完整立即失败，停止清理断言并报告具体差异。最终六条准备和三条保留断言继续执行，10 秒回调时限保持；产品清理代码、允许清理的主机与名称未改，没有睡眠、写入重试或忽略失败。

全新隔离 iPhone 18 Pro / iOS 27 上，该用例的三次进程重启执行均通过：`test_sim_2026-10-17T01-29-37-509Z_pid44279_99ba521b.xcresult`，为 **1 个不同用例、3 次通过执行，0 失败 / 跳过**。此项不能代替修正后提交的完整远端回归；其终态仍在 PR #48 记录。

同一后续提交 `a51bd93` 的[Windows 桌面执行](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38991315161/job/117274108734)在目录网络专项的首次窗口中等待“探索”标题五秒超时，Electron 集成为 2 通过 / 1 失败；不是 Cookie 清理失败。trace 的 `app://shell/` 快照当时只有文档头，没有正文，尚不能据此判定具体资源或系统耗时根因。夹具增加等待实际 `domcontentloaded` 事件，上限 15 秒，再执行原有五秒标题断言；整体 30 秒时限、代理路由、请求 / 响应 Cookie 隔离、拒绝跳转与清理断言保留。本机该网络专项 1 项通过，修正后的 Windows 与完整 CI 仍以最新提交终态为准，不将本机 macOS 结果算作 Windows 通过。

修正后的 `2a8ab45` [Windows job](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38991942710/job/117276027659)已成功，Web / 移动端、Chromium、macOS / Linux 桌面与 GitGuardian 同提交成功。`a51bd93` 原生运行由后续提交的 concurrency 自动取消，未完成 Release，专用模拟器删除成功，不能计为完整通过。后续 VoiceOver 夹具收紧与 iPad 专项单列于[验证记录](./ios-voiceover-validation.md)，日常原生 CI 的最新终态继续记录在 PR #48。

`2a8ab45` 的[原生 CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38991942668)随后完整成功：**262 单元 / 集成 + 7 UI，共 269 项通过，0 失败 / 跳过**；Release 模拟器编译与专用模拟器删除成功，共七项检查通过。Cookie 夹具完整性修正与 Windows 启动同步在该提交均有完整远端通过证据；这不覆盖仍失败的独立系统审计或真机验收，后续提交按自身终态核对。

## 详情布局后的完整 CI · 2026-10-17

`c548960` 的[原生 CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39011289451)完整成功：**266 单元 / 集成 + 7 UI，共 273 项通过，0 失败 / 跳过**。日志已核对两类测试计数、`TEST SUCCEEDED` 和 `BUILD SUCCEEDED`；Release 模拟器编译与隔离模拟器删除均成功。同提交的 [Web / 移动端与 Chromium](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39011289495)、[三平台桌面](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39011289463)及 GitGuardian 一并通过，共七项检查成功。

新增四项详情布局样例属于日常 273 项。独立 Benchmark 的 VoiceOver、系统审计与尺寸专项不在该集合中，仍按[详情布局](./ios-detail-accessibility.md)与[朗读记录](./ios-voiceover-validation.md)保留各自通过和失败。本机完整集合中的三条键盘失败没有被远端通过改写；后续仅模拟器测试的范围见[当前 Goal](./ios-native-migration.md)。

`ceee732` 的 [Native iOS CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39013218418)也已完整成功：**266 单元 / 集成 + 7 UI，共 273 项通过，0 失败 / 跳过**；Release 模拟器编译与隔离设备清理成功，日志中的两组计数、`TEST SUCCEEDED`、`BUILD SUCCEEDED` 已核对。同提交的 [Web / 移动端与 Chromium](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39013219007)、[三平台桌面](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39013218419)及 GitGuardian 均成功，共七项检查通过。该提交只补充 Benchmark 的原生 iPad 导航适配和验证记录，不包括后续云居状态修复。

## 云居修复后的冷 CI · 2026-10-17

`be3b92f` 的[原生执行](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39015276862)终态失败：**281 个不同用例，279 通过 / 2 失败 / 0 跳过**。274 个单元 / 集成中 273 通过、1 失败；7 个 UI 中 6 通过、1 失败。日志另记录同一 Home 用例的 XCTest `InvalidTransition` 事件，不能多算为一个失败用例。Release 未执行，隔离模拟器清理成功。

- Home 会话入口用例在调用 `open` 前等待初次身份 Cookie 清理五秒超时。附件证明 anchor、window 和 key window 正常，未呈现浏览器、没有运行会话或业务错误；尚不能归因于空态 UI 或断言会话打开失败。
- 标准字号密码键盘用例在点击收起后等待旧 Keyboard 对象不存在超时。原始视频第 69、73 秒可见键盘和收起按钮已经消失、表单恢复全高；系统导出的 AX 快照没有足够子节点，不能据此断定缓存的具体属性。后续测试补充收起后截图 / 完整树，并核对键盘与按键不可交互、焦点操作消失；五秒限制保持。
- [Web / 移动端与 Chromium](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39015276853)、[三平台桌面](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39015276850)及 GitGuardian 同提交成功。原生日常失败独立保留，不能引用这些结果或此前绿色提交作为当前原生验收。

本轮原生帮助 / 反馈源码不在该提交内；按自身模拟器结果和新提交 CI 分别记录。冷 Cookie 清理、完整新提交 CI 与系统审计继续待验，不通过延长等待、重发应用打开或跳过失败关闭问题。

只读复核未支持“没有先创建 WKWebView”这一根因：公开 WebKit 的 [Cookie 读取实现](https://github.com/WebKit/WebKit/blob/ddf2b17a528bde63603600ed71ab9ba358af3c12/Source/WebKit/UIProcess/API/APIHTTPCookieStore.cpp#L81)会主动启动网络进程，[官方无预热测试](https://github.com/WebKit/WebKit/blob/ddf2b17a528bde63603600ed71ab9ba358af3c12/Tools/TestWebKitAPI/Tests/WebKit/WKWebView/WKHTTPCookieStore.mm#L462)也先于 WebView 创建读写 Cookie；默认 Store 有全局持有。CI 最初网络进程启动早于失败约 40 秒，但当时尚无中途重建或清理阶段记录，公开主线也不等于运行库的精确版本。随后在原五秒预算内采集读取、删除、主队列通知和 Runtime 代次阶段，结果见下文；不能先把预热或持有方式当作修复。

## 原生帮助反馈的本机回归 · 2026-10-17

源码 `abe06fa` 的日常集合扩为 **323 单元 / 集成 + 10 UI，共 333 项**。首次完整执行 331 通过 / 2 失败，两项新增截图夹具失败已分别核对原始截图与懒加载几何，修正后页面专项 5 项通过。最终完整执行 **332 通过 / 1 失败 / 0 跳过**：`test_sim_2026-10-17T08-44-32-100Z_pid44279_83ad0a14.xcresult`，323 项单元 / 集成及全部 3 条新支持 UI 通过。

唯一失败是标准字号手机号键盘用例超过原 120 秒。键盘收起后的交互状态检查及截图已完成，XCTest 日志记录未收到动画完成通知，随后取消操作卡于 idle 等待；尚未定因。两次完整运行均超过工具 300 秒观察窗口，继续跟踪各自原 PID 并从原始结果包核对终态，runner 自动重启后的局部绿色摘要不代表整轮通过。没有延长时限或重复执行后替换失败。

锁包 Release 模拟器编译、根 lint 与文档构建通过；原生帮助 / 反馈四项实际 VoiceOver 另行通过。当前提交的托管状态以[草稿 PR #48 的头提交检查](https://github.com/YunLeFun/apps.yunle.fun/pull/48/checks)为准；此前绿色提交、本机部分通过和未完成的独立系统审计分别保留。

## 帮助反馈提交的远端终态 · 2026-10-17

`a35cc44` 的[原生 CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39019145600)终态失败：**333 个不同用例，332 通过 / 1 失败 / 0 跳过**。323 个单元 / 集成中 322 通过、1 失败；10 个 UI 全部通过。唯一失败仍为 `HomeLayoutVisualTests.testRemovingLastInstalledApplicationKeepsRunningSessionDiscoverable` 的初次身份 Cookie 清理五秒超时；同一用例随后记录 `InvalidTransition { phase: idle, targetPhase: failed(deinit) }`，两个失败事件不能多算为两个失败用例。

Release 模拟器编译跳过，失败诊断上传与隔离模拟器删除成功。同提交的 [Web / 移动端与 Chromium](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39019145536)、[三平台桌面](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39019145590)及 GitGuardian 均成功，合计其余六项检查通过；原生项独立保留失败。

远端计数、步骤终态与逐例结果归档于 `/tmp/yunlefun-ios-support-20261017/ci-a35cc44`，包括 `verification-summary.json`、`native-case-counts.json`、`pr-final-checks.json` 和原始 `native.log`。本节没有把尚未核对的远端完整 xcresult 附件用作内部阶段证据；以下阶段记录来自同源码的本机隔离复现。

## 默认 Cookie 读取的隔离诊断 · 2026-10-17

以 `a35cc44` 为基线，在专用 iPhone 18 Pro / iOS 27 模拟器串行运行，保留原五秒身份准备等待、120 秒默认用例预算和 180 秒最大用例预算。安装 / 启动准备耗时单列；工具观察窗口结束后继续跟踪原执行进程至终态，没有将观察超时作为测试重试。

| 集合                         | 进程与执行计数                             | 已确认结果                                           | 原始结果包                                                     |
| ---------------------------- | ------------------------------------------ | ---------------------------------------------------- | -------------------------------------------------------------- |
| 无插桩的原始 Home 完整 class | 11 个不同用例，两个独立进程，共 22 次执行  | 每轮 10 通过 / 1 失败 / 0 跳过；均为同一初次清理超时 | `test_sim_2026-10-17T09-21-05-257Z_pid44279_4349ab5b.xcresult` |
| 带 trace 的单独目标用例      | 1 个用例、一次执行                         | 1 通过 / 0 失败 / 0 跳过；不能代替完整 class         | `test_sim_2026-10-17T09-31-36-790Z_pid44279_6ec59f19.xcresult` |
| 带 trace 的 Home 完整 class  | 相同 11 个用例，两个独立进程，共 22 次执行 | 每轮仍为 10 通过 / 1 失败 / 0 跳过                   | `test_sim_2026-10-17T09-35-56-655Z_pid44279_edfa5e10.xcresult` |

临时 trace 只在 Debug 且测试进程设置 `YUNLEFUN_IDENTITY_CLEANUP_TRACE=1` 时启用，用锁保护最多 512 条事件；只记录固定阶段名、进程内 runtime / reset / operation 序号、计数、主线程布尔值及单调时间，不记录 Cookie 值、名称、域名、账号、URL 或错误文本。没有添加 Cookie 读取、写入或预热，没有额外持有 runtime / store，也没有修改清理允许名单、代次 guard、删除完成等待或超时。五秒准备失败时向 stdout 输出一次相同的有界快照，超时和夹具关闭时另附测试附件，避免只能依赖远端大附件下载来定位阶段。

单例通过时，两个清理操作都实际读到零条 Cookie，并通过 owner / generation 检查。目标操作读取回调用时 204ms，空 group 的主队列通知另等待 3050ms；其中 OCR 占用主线程 2138ms，其后仍有 682ms 间隔。这只能说明该次通过执行存在额外通知调度等待，不能解释之后完整 class 的失败。

两轮完整 class 的失败快照均无事件丢弃，卡点出现在真实 `getAllCookies` 回调之前：

| trace 轮次 | 回调阶段                                                                                                                         | 五秒准备等待与活性证据                                                            | 快照中的未回调 Native 清理数 |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- | ---------------------------- |
| 第一次进程 | op1–3 读到零条并完成；op4–11 已发起读取且方法返回，却没有进入读取回调。最早未回调的 op4 已等待 17,773ms，目标 op11 已等待 6229ms | 等待 5001ms，97 次轮询，最大轮询间隔 53ms；所有 main probe 已执行，等待区间无 OCR | 8                            |
| 第二次进程 | op1–11 均无读取回调入口；最早读取已等待 17,894ms，目标 op11 已等待 6114ms                                                        | 等待 5015ms，96 次轮询，最大轮询间隔 59ms；所有 main probe 已执行，等待区间无 OCR | 11                           |

这里的“无回调”限于超时快照覆盖的窗口，不代表证明回调永远不会到达。主队列与 MainActor 轮询仍能前进，不能据此证明 WebKit 内部 IPC、转换或回调投递正常。失败操作没有到达删除、group notify 或 Runtime 代次检查阶段，因而**不支持用空 Cookie 集合直接 completion 的候选修复这两次失败**；本轮没有实施该候选，也没有延长五秒等待。仍按未修复记录。

同一时段的 NetworkProcess 日志包含挂起 / 恢复转换：17:37:05.676 准备挂起、06.391 恢复、06.992 再挂起、07.334 恢复；这些状态记录没有给出 Cookie 请求到回调的完整链路，不能推断必须预热或默认 Store 未保活。[Apple 的公开读取契约](https://developer.apple.com/documentation/webkit/wkhttpcookiestore/getallcookies%28_%3A%29)规定异步 MainActor completion；[WebKit 主线的转换与投递实现](https://github.com/WebKit/WebKit/blob/e1c510bc7fae8b20c296f2bcc3aeac3c5c8df578/Source/WebKit/UIProcess/API/Cocoa/WKHTTPCookieStore.mm#L76-L89)提供进一步分段的参考，但尚未建立与本机运行库精确版本的对应关系。

本轮临时诊断插桩已从主工作目录的四个文件清理，未作为产品修复保留。`ios-identity-cleanup` 隔离 worktree 继续保留，原始失败结果、临时补丁、带 trace 的单例附件、两进程逐阶段汇总及 WebKit 日志归档于 `/tmp/yunlefun-ios-cookie-diagnosis-20261017`；`traced-home11-two-process-summary.md` 保留逐 operation 和 OCR 区间。诊断证据与原始失败均继续保留，后续仍需在真实完整 class 和新提交 CI 中验证修复。

### 缩减为三用例后仍可复现

随后在同一隔离 worktree 中仅选择原 class 的 `testCompactHomeWithLargestAccessibilityText`、`testCompactHomeWithStandardText` 和目标 `testRemovingLastInstalledApplicationKeepsRunningSessionDiscoverable`。沿用已准备测试产物中的两轮独立进程配置，日志实际包含 **3 个不同用例、6 次执行，每轮 2 通过 / 1 失败**；不是新增六个不同用例。两轮目标均在原五秒初次身份清理等待处失败，随后各记录同一用例的 `InvalidTransition` 事件。

| 三用例轮次 | 读取回调阶段                                  | 目标五秒等待                                      | 快照中的未回调 Native 清理数 |
| ---------- | --------------------------------------------- | ------------------------------------------------- | ---------------------------- |
| 第一次进程 | op1–3 已完成，目标 op4 发起读取后没有回调入口 | 6062→11093ms，共 5031ms；97 次轮询，最大间隔 62ms | 1                            |
| 第二次进程 | op1–4 均没有读取回调入口                      | 4276→9292ms，共 5016ms；97 次轮询，最大间隔 53ms  | 4                            |

两轮 main probe 都已执行，五秒等待区间没有 OCR；失败阶段仍在读取回调之前。结果包为 `test_sim_2026-10-17T09-42-32-310Z_pid44279_5148a697.xcresult`，原始日志为 `test_sim_2026-10-17T09-42-32-310Z_pid44279_7380d1ad.log`，两份有界快照另存 `/tmp/yunlefun-ios-cookie-diagnosis-20261017/minimized-three-trace.txt`。这将可复现集合从 11 例缩为“两个 CompactHome 前序 + 目标”三例，**尚未证明不能继续缩小，也不是修复或最小复现完成**；原清理边界和五秒预算保持。

## 反馈续接提交的完整 CI · 2026-10-17

`18c8e86` 的[完整原生执行](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39023604431)在第 1 次运行终态成功：**376 个不同用例，376 通过 / 0 失败 / 0 跳过**，其中 366 个单元 / 集成和 10 个 UI。已从完整原始日志独立去重计数并核对套件摘要，不以预计集合大小代替实际结果。Release 模拟器编译与同一独占模拟器清理成功，失败附件上传按条件跳过。

同一头提交的 Web / 移动端、Chromium、三平台桌面与 GitGuardian 合计其余六项检查也全部成功；PR #48 仍为草稿。逐例行号、完整日志和终态 JSON 保存在仓库外 `/tmp/yunlefun-ios-cookie-diagnosis-20261017/ci-18c8e86`。这次 Cookie 目标和键盘用例通过只证明本次执行，不关闭前述间歇问题；真实登录成功后的完整反馈 UI 与其他未验收范围分别推进。

### 当前头提交的缩减对照

后续把隔离 worktree 的基线移到 `18c8e86`，确认四个探针接缝文件没有生产差异，并保存原补丁。在新的独占模拟器中，显式 `-test-iterations 2` 的三用例执行是**同一宿主内每例重复两次**：3 个不同用例、6 次执行，4 通过 / 2 失败，不能写成两个独立 class 进程。该次与之前 `a35cc44` 的两进程结果分开计数。

去掉重复参数后，两个 CompactHome 前序加目标用例仍为 2 通过 / 1 失败；原五秒等待为 3854→8860ms，97 次轮询、最大间隔 54ms。op1–3 读取空集合并完成，目标 op4 在 2510ms 请求读取、2511ms 方法返回，至 8860ms 仍未进入回调。删除任一 CompactHome 前序的两例对照分别各 2 通过 / 0 失败。这只缩小了触发条件，间歇行为尚未统计验证到最小复现，不据此实施修复或放宽预算。

原日志、逐次执行和探针补丁保存于仓库外 `/tmp/yunlefun-ios-native-continuation-20261017`。这些结果来自明确的 `18c8e86` 诊断基线，不能冒充后续作者页改动的完整验收。

## 作者主页提交的完整 CI · 2026-10-17

头提交 `9181f2160905aa721949b7142a15c7684ba98e71` 的[原生 CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39028849489)终态成功。该 `pull_request` 运行的实际 checkout 是合并提交 `095632a2c3a8b105f8ca2b43b2f2fc3783dd8545`，日志明确记录将该头提交合入 `c741d0200fe4a86638f50145395ae291ba305a9a`；没有用其他头提交的绿色结果替代本次证据。

完整日志独立解析为 **405 个不同测试方法，395 单元 / 集成 + 10 UI，405 通过 / 0 失败 / 0 跳过**。810 条开始 / 通过事件中没有重复开始、重复终态或缺失终态，两组 XCTest 套件摘要与逐例计数一致，并记录 `TEST SUCCEEDED`。Xcode 27.0（27A266a）/ iOS 27.0 上的 Release 模拟器编译记录 `BUILD SUCCEEDED`；本次独占模拟器 `B6F3D733-1746-4938-953F-23C7C89913B0` 的删除命令与清理步骤成功。shutdown 命令保留 `|| true`，日志未额外查询删除后的设备列表，因此不把它写成单独断言 shutdown 成功。失败附件上传按条件跳过，不是 XCTest 跳过。

同一完整 SHA 的 [Web / 移动端与 Chromium](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39028849501)、[macOS / Ubuntu / Windows 桌面](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39028849434)及 GitGuardian 全部成功，合计 **7 项 check-runs 均为 completed / success**。传统 commit statuses 接口没有 context；其空集合默认 `pending` 不代表另有待运行检查。

这轮仍有 **32 条 appearance transition 不平衡消息**：按串行日志中最近的测试开始事件归属，`NativeRuntimeSessionTests` 11 条、`NativeWebNavigationTests` 10 条，其余布局、菜单、导入和二维码样例合计 11 条。该归属只提供发生上下文，不证明生产故障来源；生命周期问题继续保留，不能由绿色检查关闭。另外有 9 条编译 / 工具 warning：5 条测试目标最低 iOS 16 与 XCTest iOS 17 库的链接版本提示，4 条无 AppIntents 依赖时的元数据提取提示。日志另有 WebKit / RBS、系统 AX 重复类、模型预检和 debugger `noURL` 等诊断，完整行号与计数独立归档，不计作 XCTest 失败，也未宣称已解决。

完整原生 / Web / 桌面日志、原生原始日志 zip、405 个方法的开始 / 终态行号、全部检查 JSON、warning 归属和 SHA-256 保存在仓库外 `/tmp/yunlefun-ios-native-continuation-20261017/ci-9181f21`。当前本机未提交的 `DeveloperProfileBenchmarks` 及其他显式 Benchmark UI / 系统无障碍项目不在该 SHA 的这次日常集合中，不能用 405 项作为其通过证据；实际界面与辅助功能验收仍以各自记录为准。此前 Cookie、键盘和其他失败记录继续保留，原生改造 Goal 尚未据本次 CI 宣告完成。

## 作者页显式 UI 验收 CI

作者验收位于独立的 `.github/workflows/ios-author-benchmark.yml`，由 `ci:ios-author-benchmark` 标签门禁控制。带标签的同步提交执行浅色 / 深色两格；单独添加该标签只触发可选工作流。日常 `.github/workflows/ios.yml` 不再监听标签事件，避免创建同名 skipped 原生检查并遮蔽已有日常失败。两个工作流使用各自的并发组，可选作者验收不会取消日常检查；无关标签事件使用独立组，不取消仍在运行 / 排队的有效作者验收。

每格在 Xcode 27 / iOS 27 新建独占 iPhone 模拟器，使用现有 `YunleFunBenchmarks` / Benchmark 配置，串行执行作者页标准 / 最大辅助字号的普通触摸和实际 VoiceOver 四个方法。合计是 **4 个不同方法 × 2 外观 = 8 次执行**，启用时新增两项实际检查；不是新增八个不同方法，也不能与日常计数混淆。每例原 120 秒时限和 180 秒上限保留，无重试；逐格要求四个方法各开始、通过一次，任何跳过、缺项、重复或失败都不能验收。

仅使用匿名公开作者页面与新建空访客云居，不选择物理设备或已有模拟器，不运行真实登录、反馈 canary、获取、购买或云应用。开关只含固定 opt-in、外观与该格新建模拟器 UUID，不传凭据；继续只读仓库权限、固定 Actions、锁包和不持久化 checkout 凭据。产品仍支持 iOS 16，iOS 27 只用于本次实际 VoiceOver API。

成功与失败均保留完整 xcresult、原始测试日志及方法计数 JSON 三天，不上传构建产品或依赖缓存；完整朗读、AX 和截图须下载后复核，不能以方法计数代替实际无障碍验收。每格最后尝试关闭并删除自己的模拟器，分别核对步骤终态。带标签的验收结束后可移除标签，使后续提交恢复原日常范围。

显式作者验收使用 PR 标签入口，不依赖默认分支的手动 dispatch 注册，也不为注册入口合并草稿。以上是可复现执行入口，实际结果按相应提交与运行 ID 记录；静态 actionlint 通过不等于八次旅程已通过。

## 体验版源码的实际 CI · 2026-10-17

`c358899a34013abf8d181faa2d59088ee7f6e6c6` 的[日常原生执行](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39032659106)自然终态失败，实际 checkout 为合并提交 `78824ae9b28e5831f88df61f66061b55d300d0ac`，将该 source 合入 `c741d0200fe4a86638f50145395ae291ba305a9a`。

完整日志独立解析为 **405 个不同方法，404 通过 / 1 失败 / 0 跳过**：单元 / 集成 394 通过、1 失败，全部 10 条 UI 通过。唯一失败仍是 `HomeLayoutVisualTests.testRemovingLastInstalledApplicationKeepsRunningSessionDiscoverable` 在首次打开前等待身份 Cookie 清理五秒；同一方法后续追加 `InvalidTransition` 失败事件，不能计作另一失败用例。日志有 405 条方法终态、404 条开始记录，其中一个实际通过方法缺开始行，原始 zip 与 artifact 内日志复核一致，不补造 810 条完整事件。Release 步骤跳过，完整失败 artifact 上传及独占模拟器删除成功。其他六项常规检查成功，日常原生失败继续保留。

日常执行终态后才添加可选标签，旧版单工作流的[作者专项](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39033883456)也自然终态失败。两格 checkout 同一合并提交，各四个方法开始 / 终态完整，合计 **8 次执行，1 通过 / 7 失败 / 0 跳过**：

| 方法                   | 浅色                    | 深色                       |
| ---------------------- | ----------------------- | -------------------------- |
| 标准字号触摸           | 通过                    | 返回画面 / OCR 检查失败    |
| 最大辅助字号触摸       | 返回画面 / OCR 检查失败 | 返回画面 / OCR 检查失败    |
| 标准字号 VoiceOver     | 未能找到作者标题朗读    | 等待真实作者资料失败       |
| 最大辅助字号 VoiceOver | 未能找到作者标题朗读    | 系统 `No speech available` |

三条触摸失败已经到达返回作者页部分，在原五秒内未通过实际画面绘制检查；不能仅凭 AX 存在宣称已正常绘制，也不能在未审完整截图前认定是产品、OCR 或托管环境根因。两格完整 xcresult 已上传，模拟器清理成功；测试失败后计数步骤 skipped 不代表测试方法被跳过。此前同 source 一共留下 11 条历史 check-run 记录：6 success、3 failure、2 skipped，不能写成九项全绿或用后来的同名 skipped 日常记录覆盖原失败。工作流拆分修正的是后续状态呈现，历史失败不删除。

完整日常日志 / xcresult 和作者日志 / artifact 元数据分别保存在本机 `ci-c358899-daily`、`ci-c358899-author-benchmarks`。用户随后将本轮 Goal 收敛为可体验模拟器版，作者全矩阵和完整迁移验收后移，不再追加探针或重跑来扩张交付前置。作者标签已移除，后续不自动继续该矩阵。

同一运行时代码的有限核心体验另在本机实际模拟器 **2 通过 / 0 失败 / 0 跳过**，包括真实发现详情、免费获取、云应用网页绘制、收起 / 恢复、结束与返回；七张原始截图已核对。该结果与上述日常 / 作者失败分别记录，详见[模拟器体验交付](./ios-simulator-preview.md)。

## 来源同步提交的完整 CI · 2026-10-18

来源提交 `e7ea1cd6e0d00bbad58273c2510322b3ba28e38d` 的 [Native CI 39067045605](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39067045605) 已自然结束。实际 checkout 为 PR 合并提交 `d9b80434143e88385336cd3139b63bdb3e38621a`，原 xcresult 独立解析为 **433 个不同用例，431 通过 / 2 失败 / 0 跳过**，无结果包运行时警告。423 项单元 / 集成中 421 通过，全部 10 条 UI（含三条键盘旅程）通过。

失败为首页 `testRemovingLastInstalledApplicationKeepsRunningSessionDiscoverable` 的初次 Cookie 清理五秒期限，以及反馈页 `testCorruptSavedReceiptRendersReadFailureWithoutReplacingEvidence` 的文字扫描。首页方法随后产生 `InvalidTransition` 事件，日志的三次断言 / 异常失败属于两个用例，不能写成三个失败用例。Release 跳过，失败附件上传和独占模拟器删除成功；Web、三种桌面构建、Chromium smoke 和 GitGuardian 成功，不代替原生全绿。

反馈原始 viewport scan 记录六次截图：最后采样 offset.y=1568、contentSize.height=2648.83、viewport.height=800，下一步请求底部 offset.y=1848.83 后已到原十秒期限，没有再采样。截图显示日志范围和数量，尚未显示末尾支持编号错误。这支持扫描未到目标的夹具问题；不是用 OCR 文案匹配放宽来消除失败。

两个待检查目标都位于反馈表单末尾，现复用已有 `fromBottom` 原生列表定位，再读取真实截图文字。保留十秒期限、完整错误子句、未发送 HTTP 和损坏原文件逐字节不变断言；产品 `FeedbackView` 未修改。Cookie 路径接入独立 [PR #49](https://github.com/YunLeFun/apps.yunle.fun/pull/49) 已验证的上下文生命周期修复，见[Cookie 对照与边界](./ios-identity-cookie-cleanup.md)。集成后的专项与新 CI 按自身执行结果验收，原失败保留。

集成后在本任务隔离 iPhone / iOS 27 运行完整 `HomeLayoutVisualTests`、`HostIdentitySessionsTests` 和 `SupportViewTests`，**17 通过 / 0 失败 / 0 跳过**，无结果包运行时警告（`ci-repairs-tests.xcresult`）。反馈两条目标均在底部定位后的首张截图读到完整文字；已逐图复核支持编号错误与上传预览入口。原文件保留、未提交日志及真实 Cookie 删除 / 保留断言全部通过。Cookie 原三条提交以 cherry-pick 保留在当前分支，没有合并或关闭 PR #49；后续完整 CI 仍需独立确认。

随后来源提交 `5c2e85ff5246d00f8fc37874cd0e9ddca9042cf0` 的 [Native CI 39069021230](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39069021230) 自然结束并成功。实际 checkout 为 PR 合并提交 `db453e6ef9482769f9d47d409a69b61da2ea8d71`；完整原始日志按完成用例名独立去重，**433 通过 / 0 失败 / 0 跳过**（423 单元 / 集成 + 10 UI）。Release 模拟器编译和隔离模拟器删除成功，失败附件步骤按条件跳过，因此本次计数来源是日志而非未生成的上传附件。该头的七项常规检查全部成功；可选作者 Benchmark 跳过，不能计为通过。

此结果验证两项修复在本次完整 CI 中有效，原失败记录继续保留。原日志、运行元数据与独立计数位于持久目录的 `native-ci-5c2e85f.log`、`native-ci-5c2e85f-summary.json`、`native-ci-5c2e85f-counts.json`。后续新增的 opt-in 真实反馈登录夹具按自己的构建与执行证据记录，不追溯计入这 433 项。

原日志、完整结果包与三份反馈附件保存于 `/Users/yunyou/.codex/artifacts/ios-native-goal-20261018/native-ci-e7ea1cd-artifact`、`native-ci-e7ea1cd-support-failure`。初次只导出与失败事件直接关联的附件得到空列表，随后按失败方法 ID 导出其 keepAlways 附件；空导出不代表没有截图证据。

## 反馈登录提交的 CI 与等待诊断 · 2026-10-18

来源提交 `c726d6416c5236199adf5b72a39fb327ec793dc5` 的 [Native CI 39071245366 第一轮](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39071245366/attempts/1) 自然结束为 **431 通过 / 2 失败 / 0 跳过**，结果包无运行时警告。实际 checkout 为 `10433e0d7ec0e616dcad1831b9d974ffcf6ab39c`，Release 跳过，失败附件上传与隔离模拟器清理成功。六项其他常规检查成功，可选作者 Benchmark 跳过。

失败方法为 `LegacyImportTests/testRealWebKitReaderUsesSameOriginAndNeverReadsCredentialKeys` 和 `NativeNavigationUITests/testGuestCanDismissPhoneKeyboardAtStandardTextSize`。前者抛出 `InvalidTransition { phase: idle; targetPhase: failed(deinit) }`；原包没有具体阶段，当前尚未定位到调用。新增七个不含数据值的 XCTest activity 阶段，标记夹具导航、种子写入、强制超时、两次读取及原数据检查；不改变产品读取路径，不吞错或自动重试。

键盘方法在点击收起后查询消失按钮的 `count`，日志显示查询内部重试消耗了原 5 秒等待；失败后的原截图与 AX 均已没有键盘和收起按钮。现先使用 XCTest 原生 `waitForNonExistence(timeout: 10)`，再单独等待保留键盘节点及输入键均不可点击。屏幕内且可操作的初始键盘、实际点击、焦点动作消失和所有键盘节点不可操作的断言均保留，没有修改登录页面。

第一次本机专项 `ci-keyboard-legacy-diagnostics.xcresult` 为 **3 通过 / 3 失败 / 0 跳过**：三个真实 WebKit 读取用例通过，三条 UI 在初始软件键盘可见性断言失败，键盘矩形位于屏幕外，尚未执行收起判断。随后在本任务独占模拟器的已聚焦访客表单，使用 Device → Keyboard → Toggle Software Keyboard 显示数字键盘并保留截图 / AX；没有修改硬件键盘或全局偏好，也未输入账号或提交认证。后续复验按单独结果记录，原失败保留。

同一测试构建随后只复验三条键盘 UI，`ci-keyboard-software-shown.xcresult` 为 **3 通过 / 0 失败 / 0 跳过**，结果包无运行时警告；标准字号手机号与密码、最大辅助字号手机号均从实际可用键盘执行收起并取消回“我”。该结果支持等待检查在本机可用，不能解释所有远端负载情形，也不将尚未定位的 WebKit 异常改记为已修复。完整原始日志、附件和初次键盘前置失败均留在持久证据目录的 `ci-keyboard-*`。

同一远端 run 的[第二轮](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39071245366/attempts/2)自然结束并成功。仍为来源 `c726d64`、checkout `10433e0`，按原日志完成用例名独立去重为 **423 单元 / 集成 + 10 UI，共 433 通过 / 0 失败 / 0 跳过**；Release 模拟器编译与独占模拟器清理成功。原失败没有因此消失，不能称已定位 WebKit 根因或验证尚未推送的后续改动。

第一轮日志、job 元数据、xcresult 和全部附件位于持久目录的 `native-ci-c726d64-attempt1-*`，第二轮日志、元数据和独立计数为 `native-ci-c726d64-attempt2-*`。API 记录第二轮 triggering actor 为 `YunYouJun`，本轮没有取消或重新发起该 run；新提交在它自然结束后推送，避免 concurrency 自动取消原证据。

## 账号保护与候选提交的完整 CI · 2026-10-18

来源提交 `6c968f61ac1d50aad373fec6b4d069f13162f292` 的 [Native CI 39075735071](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39075735071) 首轮自然结束并成功，实际 checkout 为 `6bd49f156e1d6c5acb4fd9d611010c1650c6be14`。原始日志独立核对为 **426 单元 / 集成 + 10 UI，共 436 通过 / 0 失败 / 0 跳过**；Release 模拟器编译、隔离模拟器删除与同提交七项常规检查全部成功，可选作者 Benchmark 按条件跳过。

原日志有 436 条开始记录和 435 条完整方法终态。另一条作者版本权限方法的终态被 WebKit 进程日志从方法名中间插入，原始 zip 同样如此；核对相邻的原前缀与 `tions]' passed (0.018 seconds).` 后精确恢复该条，数量与 XCTest 套件汇总一致。未改写原日志，原始 zip、文本、元数据及含这两行原文的独立计数保存为 `native-ci-6c968f6-*`。此次成功没有上传失败用 xcresult，不能描述为结果包逐项解析。

此执行覆盖新增资料会话保护、键盘分阶段等待和 WebKit activity 诊断；opt-in 真实账号 Benchmark 仍以各自结果为准。先前 WebKit 异常、作者全矩阵及系统无障碍失败继续保留，单次全绿不等于全部稳定性问题已经定位或关闭。

### 后续文档来源的完整 CI · 2026-10-18

来源 `20278613b502ab819c517f915a956a58ce238ac2` 的 [Native iOS CI 39077144058](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39077144058) 首次执行自然成功，实际 PR 合并 checkout 为 `3cadc3bea4ccd0c8f5ac6303129ee6d1c9927b7a`。独立原始日志核对为 **436 通过 / 0 失败 / 0 跳过**（426 单元 / 集成 + 10 UI），Release 模拟器编译与实例清理成功，七项常规检查成功，可选作者矩阵跳过。作业耗时 32 分 37 秒，在现有 35 分钟上限内完成。

日志仍有同一 `PersonalMarketVersionTests` 方法名称被 WebKit 输出插断：完整终态行 435 条，另用原始 `...RestrictedPubli` 与下一行 `cations]' passed (0.033 seconds).` 精确拼回，与 436 条开始记录和套件计数交叉核对。原 ZIP、未改日志、两个原片段及计数说明保存在本轮 `native-ci-2027861-*`，没有修改原日志来凑出通过数；成功运行按现有策略不上传失败专用 xcresult。

该结果仅覆盖 `2027861`。后续原生隐私资源、宿主 GPU 采样和候选文档有自己的本机验证，推送后仍须等待新来源的 CI；不把这次成功转移为后续提交的远端结论，也不据此关闭历史 WebKit 间歇异常或完整辅助功能审计。

## 键盘实际输入与登录倒计时 · 2026-10-18

来源 `fc31b7a` 的 [Native CI 39079516884](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39079516884) 首轮自然结束为 **435 通过 / 1 失败 / 0 跳过**：426 单元 / 集成全部通过，10 条 UI 中标准字号手机号键盘可用性检查失败。实际 checkout 为 `bebeccdfd496c6d10d20f613f43eff7be920931a`；直接读取该提交源码确认当时等待为 **10 秒**。Release 跳过，专用模拟器清理成功。原始 ZIP、完整日志、xcresult、截图、局部与整页无障碍树均保留。

失败画面已显示软件键盘；整页树包含数字键，局部 `Keyboard.firstMatch` 查询却没有子节点。现从应用当前 `keys` 查询按键，仍要求键盘在屏幕内、按键可交互且矩形位于键盘内，并实际点按，确认焦点字段长度增加；收起后继续要求焦点操作消失、键盘与按键不可交互，并取消返回“我”。保留 `c41cf65` 已引入的 30 秒可见性等待及原 120 秒用例时限，不以截图存在代替可用性。

在本任务独占 iOS 27 模拟器上，原 10 秒手机号用例固定三轮全部通过；因此没有稳定复现远端前置失败。新查询与实际输入断言的首次固定两轮共六次为 **5 通过 / 1 失败**，失败发生在已收起键盘后等待 App 空闲并取消页面，触发 120 秒时限。工具 300 秒返回超时后 Xcode 仍自然完成并生成失败结果，没有把工具超时或后续空测试进程计为产品结果。

另一个确定问题是登录验证码区在未发送、已到期时仍永久每秒刷新。三个调度回归先以原周期行为适配器复现 **0 通过 / 3 失败**；改为有限 `TimelineSchedule` 后，每秒更新到精确到期点即结束，从过期时间恢复只生成当前状态。冷却期和发送行为保留，三条回归通过；同次发布专项 28 条通过，合计 **31 / 0 / 0**。首次编译的 `min` 名称冲突日志保留，修正为 `Swift.min` 后编译及测试通过。

仅替换倒计时调度后，相同键盘查询、断言、模拟器与固定两轮命令得到 **6 次通过 / 0 失败 / 0 跳过**，3 个不同方法；标准密码 32.181 / 30.558 秒，最大字号手机号 27.380 / 27.618 秒，标准手机号 35.042 / 28.403 秒。结果包没有运行时警告。该小样本支持本机改动可用，不能证明倒计时是远端间歇失败的唯一根因，也不能覆盖完整 CI。

原始对照、失败与通过结果、命令和源码散列在本聊天 `publishing-concurrency/`：`keyboard-original-repeat.xcresult`、`keyboard-current-keys.xcresult`、`resend-timeline-baseline.xcresult`、`native-final-and-timer.xcresult`、`keyboard-finite-timer.xcresult`。产品修正提交为 `5f38de5`，输入检查为 `4085f12`；最新远端 CI 终态须按自身来源另行记录。

### 30 秒等待来源的远端终态

来源 `c41cf65342a2f68727ac32e7775515bdb1210af0` 的 [Native CI 39080850043](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39080850043) 首轮自然结束失败，实际 checkout `e4bef05234e2f448f32b076db3451c818f4da5e7`。原 xcresult 独立解析为 **436 个不同用例：434 通过 / 2 失败 / 0 跳过**；424 单元 / 集成通过、2 失败，10 条 UI 全部通过。Release 跳过，失败诊断上传与实例清理成功。它不含本次条件写入、有限倒计时或当前按键查询改动。

- `HomeLayoutVisualTests.testRemovingLastInstalledApplicationKeepsRunningSessionDiscoverable` 在首次打开前等待身份清理失败；同一方法还记录 `InvalidTransition`，不另算一个失败用例。附件确认宿主已在窗口、没有运行应用，尚未开始打开。原五秒等待和 Cookie 清理行为保留，根因未关闭。
- `SupportViewTests.testLargestTextHelpCanScrollToNativeFeedbackEntry` 在最大字号下扫描六个视口，最后截图仍只显示反馈入口的一部分。轨迹记录下一次滚动目标 `1856pt`，但十秒预算已结束，没有获取该位置的 OCR；不能据此判定完整入口无法显示。后续通过相同原生列表从末端定位，单独核对扫描行为。

原日志 ZIP、未改日志、失败结果包、两项附件与检查状态保存在本聊天 `native-ci-c41cf65-*`。此前全绿与本机六次键盘通过不会改写本轮失败。

帮助页专项随后复用已有末端实体化逻辑，从末端向上扫描入口，保留原十秒预算、最大辅助字号、完整“反馈与建议”OCR 和无 HTTP 写入断言，未修改产品布局。`support-bottom-final.xcresult` 的五个支持页用例 **5 / 0 / 0**；目标用例 1.957 秒，两个样本后完整识别，截图确认入口显示在视口内。原 CI 轨迹、最后半截入口截图与本机新轨迹均保留。修正提交 `b3386aa`；这项本机结果不关闭云居身份清理失败，也不代替新来源 CI。

### 最新源码的身份清理复现边界

冻结 `22fbbfc91e654252351ef85c14559fbcaba1fa00` 的 `git archive`，在本任务独占 iPhone / iOS 27 模拟器复验，未包含工作区并行缓存改动。原三条最小序列 **3 / 0 / 0**；完整云居组在两个独立进程中 **22 次通过**，11 个不同方法；补入 CI 中云居之前的测试后，两个独立进程共 **432 次通过**，216 个不同方法。原始日志和 xcresult 交叉核对重复次数，不能只按工具汇总的不同方法数计算执行次数。

隔离副本另有一次临时压力夹具，连续创建并释放 50 个真实 `NativeWebRuntime`，每次仍要求五秒内结束首次身份清理；该方法 3.267 秒通过。临时夹具已从源码副本移除，只保留证据。以上均未复现原远端超时，因此没有改动产品清理路径、放宽等待或将原失败记作已修复。阶段证据保存于本聊天 `identity-cleanup-22fbbfc/`，包括源码来源、原日志、四份结果包和独立计数。

来源 `22fbbfc` 的 [Native CI 39082896403](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39082896403) 被后续并行提交 `92449da` 的 concurrency 规则取消，实际 checkout 为 `59093b5`；取消前没有用例终态，Release 与失败附件上传跳过，隔离模拟器清理成功。这不是通过或完整失败的测试集合。该来源 Web CI 的旧提交调用字符串断言失败，随后并行提交 `92449da` 修正了契约测试；新来源 Web、Chromium 与三平台桌面检查已成功，Native CI 按自身终态继续记录。原取消日志和 Web 失败日志均保留。

### 发布保护来源的完整 CI

来源 `92449da0d31a23cd1ca1608c64f87191d5e65066` 的 [Native CI 39083170036](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39083170036) 首轮自然结束并成功，实际 PR 合并 checkout 为 `00b10d57df4cb9411cd603b9f445a6ce9a5c3138`。原日志独立核对 **435 单元 / 集成 + 10 UI，共 445 通过 / 0 失败 / 0 跳过**；445 条不同方法开始记录与 445 条完整通过终态逐条一致，无需拼接插断的方法名，套件汇总同样一致。

Release 模拟器编译、隔离模拟器清理和七项常规检查全部成功，可选作者 Benchmark 跳过。成功运行没有上传失败专用 xcresult，计数来自原始日志；ZIP、未改日志、job 元数据、检查状态及独立计数保存在本聊天 `native-ci-92449da-*`。

这轮覆盖条件写入、登录有限倒计时、实际键盘输入和帮助页末端取样。云居原失败本轮通过，但单次完整通过及上述本机复验都不能证明已定位间歇根因；此前失败继续保留。随后新增的 opt-in iPad 横屏 Benchmark 和说明有自己的本机结果，不继承此来源的远端结论。

## 70f9cb4 首轮超时记录 · 2026-10-18 {#ci-70f9cb4-timeout}

来源 `70f9cb4ad6c6f0c36fd2bd4d8c779e69ec067419` 的 [Native CI 39085050054](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39085050054) 自然结束为失败，实际合并 checkout 为 `1b2e16320b812a1ebb4fed3c1a48f2e71813b716`。下载的故障 ZIP 与 GitHub SHA-256 一致；独立解析原 xcresult 得到 **445 个不同方法，444 通过 / 1 失败 / 0 跳过**：435 单元 / 集成通过，UI 为 9 通过 / 1 失败。Release 编译跳过，故障附件上传与模拟器清理成功。

失败方法为 `testGuestCanDismissPhoneKeyboardAtStandardTextSize`，原因是超过原有 120 秒总执行预算。日志显示它完成实际按键输入、收起键盘，并于 111.24 秒检查到“我”导航栏，111.38 秒开始收尾；120 秒超时仍属于失败。日志紧接着打印了 `passed (120.382 seconds)`，与最终结果冲突，必须以 xcresult 的失败状态记录，不能仅统计 passed 文本。

随后 `testGuestCanReachSyncSettingsAndCancelNativeLogin` 在启动前终止旧 App 时失败并超时，Xcode 自动重启测试进程后，重新执行该方法于 31.981 秒通过。原始日志共有 446 条开始、445 个不同方法和 445 条终态；自动重启不增加不同方法数，也不能把这次异常删除。超时堆栈采样已经落在后一方法等待 `XCUIApplicationImpl terminate` 的阶段，App 主线程在采样的 230 次中处于运行循环等待；这不能解释之前无障碍查询变慢的根因，也不能据此断言产品没有问题。

原始日志、xcresult、测试明细、全部附件与 11 MB 堆栈在本聊天 `native-ci-70f9cb4-*` 附件中。没有重跑远端任务、增加预算、删除断言或把旧 Cookie 根因套用到这次超时。上一来源 `92449da` 的 445 项通过仍按其来源保留；当前 G1 的间歇超时与清理问题未关闭。

随后在自有隔离模拟器按最大字号手机号、普通字号手机号、同步设置的顺序连续复测，原生源码与 `70f9cb4` 的 181 个跟踪文件逐字节一致。三项 **3 / 0 / 0**，分别为 29.956 / 28.774 / 21.543 秒，仍使用原有 120 秒预算与全部交互断言；没有复现远端超时，不能据此将其关闭。结果另存 `native-ci-70f9cb4-local-keyboard-sync.xcresult`。

## db4503e 完整 CI · 2026-10-18 {#ci-db4503e}

来源 `db4503ec9f86f8a6b290c8aca93225c7711ce199` 的 [Native CI 39086828603](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39086828603) 首轮自然成功，实际合并 checkout 为 `d657cafa6c3025b89312e82ce70b35c937d7db48`。原始 ZIP 与完整日志保留；445 个不同方法的开始和完整终态逐条对应，**445 通过 / 0 失败 / 0 跳过**，其中单元 / 集成 435、UI 10；没有根据截断日志补造结果。成功运行没有上传故障 xcresult，因此这些数量来自原始日志及套件总数的独立核对。

前一失败的普通字号手机号方法本次 31.727 秒通过，随后同步设置 24.516 秒通过。Release 编译、独占模拟器清理成功；七项常规检查成功，可选作者 Benchmark 跳过。总 job 1100 秒。未提高任何预算、删除断言或人工重跑这次任务；不据此关闭历史身份清理、WebKit 或手机号旅程的间歇问题。

另保存 `70f9cb4` 第二次运行的取消终态及原始日志。该次运行并非本聊天发起，01:28:37Z 开始，01:32:24Z 日志记录取消，最终状态在 01:34:09Z 更新；仍 checkout `1b2e163`，日志没有测试方法开始或完成记录。它在本聊天推送 `db4503e` 后被观察到，不能把零项执行算成成功，也不覆盖此前第一轮的 444 / 1 / 0。证据分别在 `native-ci-db4503e-*` 与 `native-ci-70f9cb4-attempt2-*`。

## 1d6f2e0 完整 CI · 2026-10-18 {#ci-1d6f2e0}

来源 `1d6f2e0fc631c26e9db8507229faf8b3e6c06ab1` 的 [Native CI 39088379741](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39088379741) 首轮自然成功，实际合并 checkout 为 `897f9103432cfe7ca94515638c999e44c4030f97`。原始日志 445 条不同方法的开始与完整终态逐项一致，**435 单元 / 集成 + 10 UI，合计 445 通过 / 0 失败 / 0 跳过**，套件总数一致；没有成功运行的 xcresult 上传，计数依据为原日志。

普通字号手机号方法 29.577 秒、随后同步设置 23.208 秒通过。Release 编译、隔离模拟器清理及同来源七项常规检查均成功，可选作者 Benchmark 跳过，job 总计 916 秒。原 ZIP、文本、元数据和独立核对保存为 `native-ci-1d6f2e0-*`。

此结果覆盖 `b18e92f` 的正式动效修复；独立 live 验证按各自结果计数，不额外加到 CI 的 445 项中。没有提高预算、移除断言或人工重跑；历史身份清理、WebKit 和手机号旅程的间歇根因仍未关闭。

## b61908b 完整 CI · 2026-10-18 {#ci-b61908b}

来源 `b61908ba71687c0a2ed2538b629035f706106388` 的 [Native CI 39089850201](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39089850201) 首轮自然成功，实际合并 checkout 为 `dcec0f6b1cd9cdc3bda6df1c94611d5e55556d97`。原始 ZIP 日志的 445 个不同方法开始与完整终态逐项一致，套件汇总同为 **435 单元 / 集成 + 10 UI，合计 445 通过 / 0 失败 / 0 跳过**。没有成功运行 xcresult 上传；计数来自原日志，不包含独立 live 验证。

普通字号手机号方法 31.369 秒、随后同步设置 23.773 秒通过。Release、隔离模拟器清理和七项常规检查成功，可选作者 Benchmark 跳过，job 总计 1088 秒。证据保存为 `native-ci-b61908b-*`。该结果属于余额数字修复前的来源；历史间歇问题未据此关闭，未调整任何预算或断言。

## 937bc29 完整 CI · 2026-10-18 {#ci-937bc29}

来源 `937bc296b1a87f193ea9c9dcedea3b5b0d985582` 的 [Native CI 39092630865](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39092630865) 首轮自然成功，实际合并 checkout 为 `076c6026c9539ef5fdbaff7659accb8e818d3335`。原始日志 445 条唯一开始与完整终态对应，套件总数一致：**435 单元 / 集成 + 10 UI，共 445 / 0 / 0**。Release、隔离模拟器清理和七项常规检查成功，可选作者 Benchmark 跳过，job 1320 秒；日志与元数据保存为 `native-ci-937bc29-*`，成功运行没有上传故障 xcresult。

这轮 CI 不包含随后新增的显式多账号线上夹具，也没有覆盖现已复现的[网页持久身份缺陷](./ios-host-authorization.md#persistent-identity-defect)。原型和故障对照按各自来源单独记账。历史 Cookie 清理及普通字号手机号超时的间歇根因仍未关闭，没有放宽预算或断言。

## dff60c0 完整 CI · 2026-10-18 {#ci-dff60c0}

来源 `dff60c08ebd1fb7829d4d05194e38d304a531332` 的 [Native CI 39094684982](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39094684982) 首轮自然成功，实际合并 checkout `e3fa164ba50cc5e4bc853df52ede2991bba86547`。原始日志 **445 个唯一开始与 445 条完整终态**逐项一致，套件总数同为 **435 单元 / 集成 + 10 UI，445 / 0 / 0**；Release、模拟器清理和七项常规检查成功，可选作者 Benchmark 跳过，job 1747 秒。成功运行没有上传故障 xcresult，数量来自原始 ZIP 日志；元数据与核对结果保存为 `native-ci-dff60c0-*`。

该轮只包含默认跳过的显式线上夹具源码，不包含随后实现的 WebProfileRepository。真实网络旅程与新分仓测试独立记录，不能算入这 445 项或用此 CI 代替新实现验收。历史间歇故障仍保留，没有提高预算、删除断言或人工重跑。

## 8bb346b 完整 CI · 2026-10-18 {#ci-8bb346b}

来源 `8bb346b73423dd2d54b5f66b753c8b726dc7d64d` 的 [Native CI 39097051280](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39097051280) 首轮自然成功，实际合并 checkout 为 `eb47356f7d724a622873d132b98d805f1dd2564b`。原始日志 **462 个唯一开始与 462 条完整终态**逐项一致，套件总数为 **452 单元 / 集成 + 10 UI，462 / 0 / 0**。Release、隔离模拟器清理和七项常规检查成功，可选作者 Benchmark 跳过，job 1230 秒。成功运行没有上传故障 xcresult，数量依据原始 ZIP 日志，保存为 `native-ci-8bb346b-*`。

此轮首次包含 iOS 17+ 持久分仓与新增的归属 / 移除预检回归；尚不包含后续恢复入口与独立进程 live 夹具。普通字号手机号方法 31.018 秒、随后同步设置 22.793 秒通过。没有提高预算、删除断言或人工重跑；历史身份清理、WebKit 和 AX / 退出延迟的间歇根因仍未关闭。

## 083a841 完整 CI · 2026-10-18 {#ci-083a841}

来源 `083a841317be34bcd1fcdfaa502bcdfd8be4eea3` 的 [Native CI 39098612979](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39098612979) 首轮自然成功，实际合并 checkout 为 `0e76bed360226b645dbfb1ce7a8eb064888f76b7`。套件汇总为 **458 单元 / 集成 + 10 UI，共 468 通过 / 0 失败 / 0 跳过**。Release、隔离模拟器清理与七项常规检查成功，可选作者 Benchmark 跳过，job 1194 秒。

原日志各有 467 条完整开始和完整终态；一个二维码解码方法的通过终态、一个仓库来源边界方法的开始记录分别被系统日志插入拆开。保留原始 ZIP 和相邻原行，仅对这两个明确片段重建记录后，468 个唯一开始与 468 个唯一通过终态逐项一致，且与套件总数相符。它们不是额外执行或重跑；没有修改原日志，也没有把原始完整行数写成 468。证据为 `native-ci-083a841-*`，本次成功运行尚未上传 xcresult。

此轮包含恢复入口与新增回归，不包含随后新增的真实账号恢复 live 夹具。普通字号手机号方法 33.840 秒、随后同步设置 29.695 秒通过。历史身份清理、WebKit、AX / 退出延迟故障继续保留，不根据这次绿色结果关闭根因。

### 后续结构化报告

工作流新增 `xcresulttool get test-results summary` 与 `tests` 导出；有结果包就生成 JSON，并保存 PR 来源、实际 checkout、run / attempt 以及两份文件的 SHA-256。成功和失败均上传该报告，完整故障附件继续沿用原策略。没有生成结果包时不伪造测试数量，保留构建日志。

actionlint 通过；从实际工作流提取相同脚本，分别对本轮候选通过结果 **2 / 0 / 0**、真实恢复首轮失败结果 **0 / 1 / 0** 及缺少结果包三种情况执行，退出状态、计数、输出标记与文件摘要均符合预期。原始失败结果未改动。证据保存在 `structured-test-report-validation-083a841/`；GitHub 上传步骤仍须由新来源 CI 验证。测试预算、断言、失败附件和清理条件未调整。

## PR50 的结构化 CI 证据 · 2026-10-18 {#ci-d51f6a6}

PR48 由外部操作合并后，恢复验证和结构化报告改动移到独立草稿 PR50。来源 `d51f6a66d124fbe7dc043efb777a5aba80d5b231` 的 [Native CI 39100483603](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39100483603) 首轮自然成功，实际 checkout 为 `1c6b66f51963c62d428a564437b02ee06a8ade5b`。Release、报告导出 / 上传与隔离模拟器清理均成功；原生、Web / mobile、Chromium 和 GitGuardian 四项检查成功，可选作者 Benchmark 跳过，本次路径未触发桌面工作流。

下载的报告 ZIP 与 GitHub artifact SHA-256 相同；来源回执中的两个文件摘要逐一匹配。直接解析上传的 xcresult 摘要和 **468 个唯一 Test Case 节点**，结果为 **458 单元 / 集成 + 10 UI，共 468 通过 / 0 失败 / 0 跳过**。本次计数不依赖控制台行拼接，原始 ZIP 日志、元数据、摘要、完整测试树和独立计数仍一并归档为 `native-ci-d51f6a6-*`。

该结果验证了真实 GitHub 环境中的结构化报告导出、上传与来源绑定。显式线上夹具不计入日常测试；本轮后续新增的消费端跨进程夹具仍以自己的结果为准。历史 Cookie、WebKit、AX 查询和退出延迟的间歇根因没有因这次成功而关闭，预算与断言未放宽。

## 当前系统验收范围 · 2026-10-18 {#ci-current-ios}

本轮验收按用户确认使用当前最新 iOS，现有环境为 Xcode 27 / iOS 27。撤回新增的 iOS 16 手动 CI 入口，停止旧运行时安装与专项实跑；本任务不再因旧系统工具链或磁盘空间等待。日常 CI 继续使用原有当前系统工作流、测试预算与结构化报告。

本次调整的是验收范围，未修改工程的最低安装版本声明，也未证明 iOS 16 兼容或修复旧系统共享 WebKit 仓库问题。后续结果以实际测试系统为准；其余原生改造、账号隔离、升级迁移和业务验收继续推进。

## a32d24b 失败证据与待验修正 · 2026-10-18 {#ci-a32d24b}

来源 `a32d24b4d59b4e480fd88e69cbea35cdfc890fdd` 的 [Native CI 39104913250](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39104913250) 首轮完成，checkout 为 `91cdd883151b7acceeb3df579f078504a1285e55`。结构化测试树与原始日志的 472 个唯一方法一致：**468 通过 / 4 失败 / 0 跳过**，无重复开始。新增的两项账号移除和两项钱包加载回归均通过；Release 步骤跳过，报告导出、附件上传及专用模拟器清理成功。

故障 ZIP 为 27,292,914 字节，SHA-256 为 `c744335ecbd30f805f333f597a7a239a0cfc3edbab49ba6086b14d73c753e395`，完整校验后导出了四个失败方法的活动、截图、扫描文字和键盘录像。原始结果及离线重放脚本保存在本地证据目录 `sandbox-native-routing-a32d24b/failure-diagnostics/`。

- 两项支持页失败：10 秒 OCR 扫描结束时仍未到目标视口。普通字号停在社交媒体和日志范围；最大字号从底部往上扫描到空日志说明的后半句，目标前半句仍在导航栏上方。离线重放原附件可重现两个失败断言。夹具改为先通过原生列表定位无回执访客页面的日志分区，再向下扫描；保留原超时、完整文字断言和磁盘证据保留检查。
- 密码键盘失败：录像 50 秒处有一位密码，58 秒处显示原掩码加新输入字母，62 秒处为两位掩码。软件键实际完成输入，而旧断言要求辅助功能值的字符串长度增长。安全字段改为检查辅助功能值发生变化，普通字段仍检查长度；仍需点真实可交互的软件键并验证收起。确切的旧辅助功能取值没有保留，不能将本地化字符描述断言为已证实根因；新增失败附件只记录长度、是否变化和是否等于占位文字，不记录密码。
- 持久 WebKit 夹具失败：导航前置等待 20 秒；同一日志记录对应启动窗口内 WebContent 启动耗时约 23 秒，另两个进程约 34 秒。失败早于数据种子和生产读取。夹具增加独立的 45 秒引擎启动阶段，以实际本地 scheme 请求或导航错误结束；随后仍用 20 秒等待导航完成。保留阶段日志，生产读取超时及完整数据断言不变。

以上是基于失败证据的修正候选，Swift 语法解析和差异检查通过；**尚未用新源码完成 iOS 实跑，不记为四项已修复或 CI 成功**。共享主机仍由并行缓存任务使用，未为本轮启动本地模拟器或构建。后续须核对新来源的完整结果及 Release，保留本次失败记录。

## 2b76fc9 完整 CI · 2026-10-18 {#ci-2b76fc9}

上述修正及 Debug Sandbox 钱包路由随来源 `2b76fc957afa43bce0a11f657d35516402240554` 完成 [Native CI 39108974817](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39108974817) 首轮验证，checkout 为 `cbf7465a474c8898fcf676428248b4b86bcd9f5c`。上传摘要、**477 个唯一测试节点**和原始日志各 477 条唯一开始 / 终态一致：**467 单元 / 集成 + 10 UI，477 通过 / 0 失败 / 0 跳过**。无重复开始或崩溃重启标记；Release 编译、结构化报告导出 / 上传与专用模拟器清理成功。

前次四个失败方法本次均通过：持久 WebKit 夹具 3.329 秒、损坏日志清除入口 2.452 秒、最大字号联系 / 空日志说明 6.333 秒、普通字号密码键盘 39.760 秒。11 项 WalletService HTTP 测试（含新增 Sandbox 路由、标记和禁止回落规则）也全部通过。这验证了该源码本轮完整运行，不据此关闭所有历史间歇故障、真实 Apple Sandbox 或真实消费端跨进程验收。

报告 ZIP 的 SHA-256 `2c661b5c8c0fa22767392c51db15d562e2c46d9e8fd481ade4e562800cdd0b33` 与 GitHub artifact `12130221012` 一致，文件摘要与来源回执匹配。证据为本聊天 `ci-recovery-2b76fc9/`，原 `a32d24b` 失败附件完整保留。

## 7612daf 完整 CI · 2026-10-18 {#ci-7612daf}

针对 `7612daf6644cb8c8f15f9084351f6bd3d04628d1` 显式触发的 [Native CI 39111325397](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39111325397) 第一次执行完成，checkout 与来源 SHA 相同。结构化报告中的 **477 个唯一测试节点**，与完整原日志的 477 个唯一开始、477 个通过终态逐项对应：**467 单元 / 集成 + 10 UI，477 / 0 / 0**。无重复开始或已检查的崩溃重启标记；Release 编译、报告导出 / 上传及隔离模拟器清理均成功。

报告 ZIP 的 SHA-256 为 `99b7ea6267781c33b56ec9d680f0bcfe6ff286f4b06b8688abad8ea0a3522054`，与 GitHub artifact `12130009660` 匹配；摘要、测试树、来源与 run / attempt 回执一致。完整 job 日志下载成功后再核对计数，其 SHA-256 为 `3e78341696428056792834ead303fccb9cd7157972e3d094f2f06d8afc56f5d1`。证据位于本聊天 `ci-7612daf/`。

随后 `6911d60` 仅修改显式 LiveValidation 夹具和证据文档，产品源码及日常测试源码未变；其云乐坊间真实账号切换另有独立编译和实跑证据，不计入这 477 项。历史 WebKit、辅助功能查询与退出延迟的间歇根因仍未全部关闭，本轮没有放宽日常预算或删除断言。

## 合入最新 main 后的完整 CI · 2026-10-18 {#ci-1530189}

远端将网站首页、扫码任务等待接口及扫码 / 支持页 / WebKit 测试修正合入 PR50 后，来源 `1530189ee1766db9575d0e4ce8e9dae56e5073c8` 的 [Native CI 39114172380](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39114172380) 首轮成功，checkout 为 `9bda78c609bb95b099589eb7932fde9f28caa84b`。结构化结果为 **467 单元 / 集成 + 10 UI，共 477 通过 / 0 失败 / 0 跳过**；Release 编译、报告导出 / 上传和隔离模拟器清理均成功。

477 个唯一结构化方法与原日志的 477 个唯一开始一致。原日志有 476 条完整终态，另一个 `PersonalMarketVersionTests.testCachedProvenanceCannotAuthorizeWithdrawnOrNewlyRestrictedPublications` 的通过行被一条 WebKit `ProcessSuspension` 日志插断。核对相邻两行的前后缀后，在派生解析输入中只连接这一处，得到对应的通过终态（0.019 秒）；477 个方法逐一匹配，无重复开始或已检查的崩溃重启标记。原始日志保持不变，解析规则及行号单独留存，没有把缺少完整单行误记为测试失败。

报告 ZIP 的 SHA-256 `1a9cb056b0ef25ddec37a6466a6f6a601f50ea2d6677eb7ae74e978c05c98097` 与 artifact `12131704306` 一致，回执、摘要和测试树的文件摘要匹配。完整日志 SHA-256 为 `b518765b83063b89f1fcd413731af12bab52c4db2c7fbac4b6d07c00b7e9ead1`，证据保存在 `ci-1530189/`。

本轮两个真实消费端共同保留会话、确认阶段切号的 live 夹具及文档提交接在该远端来源之后，产品与日常测试源码没有再次改变；集成构建与实际线上夹具有各自证据，不能将其算入这 477 项。推送后的新 head 仍须查看对应 CI 状态，历史间歇根因不因此全部关闭。

## 371d67a 首轮失败 · 2026-10-18 {#ci-371d67a}

PR54 来源 `371d67a461b8b18d003217bb1ba41ba4a5d2d607` 的 [Native CI 39115836187](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39115836187) 第一次执行自然结束为失败，checkout 为 `09dfc4ab567cf43a0cee8bb15f7e97cd0ca318c6`。结构化报告包含 **477 个唯一方法，475 通过 / 2 失败 / 0 跳过**：单元 / 集成 466 / 1 / 0，UI 9 / 1 / 0。Release 编译跳过，结构化报告导出 / 上传、故障附件上传与隔离模拟器清理成功。

两个失败方法为：

- `NativeRuntimeSessionTests.testAccountSwitchPartitionsWebStorageWithoutDeletingDrafts` 超过原有 120 秒预算。原日志随后打印 `passed (165.108 seconds)`，与最终 xcresult 冲突，仍记为失败。
- `NativeNavigationUITests.testGuestCanDismissPasswordKeyboardAtStandardTextSize` 未通过“键盘和输入按键不再可交互”的检查，并超过 120 秒总预算。

原始日志有 639 条完整开始和 638 条完整终态，二者去重后的 477 个方法名均与结构化结果一致；162 个方法出现重复开始，并记录两次测试宿主自动重启。没有拼接或修改原日志，没有将自动重启后的结果或迟到的 `passed` 文本用作整轮通过证明。

结构化报告 ZIP 的 SHA-256 `bc6e822ff175ac698ccf94750b5a44f36653ece059817b55b343f74964c9ff57` 与 artifact `12133375103` 匹配，摘要 / 测试树摘要与来源回执一致。原日志、解析脚本和独立核对位于本聊天 `ci-371d67a/`。没有手工重跑本次 CI、提高预算或删除断言；历史间歇故障仍未关闭。

## c4f25ee 完整执行与本地候选对照 · 2026-10-18 {#ci-c4f25ee}

来源 `c4f25ee91ba69e6f5148aef5cca75485611f0a61` 的[首轮原生 CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39117922094)完整成功：**477 / 0 / 0**（467 单元 / 集成 + 10 UI）。结构化报告、477 条完整开始和结束日志的方法集合一致，没有重启标记；Release、报告导出 / 上传和模拟器清理成功。artifact `12133582032` 的 ZIP SHA-256 为 `3ff16025370f36fdccd7ed6dc5d7b524e0c1f67829ba4f4e42127aee2eb092f8`，来源回执与报告摘要一致，原始证据及核对脚本在 `ci-c4f25ee/`。此前两项间歇失败的根因仍未关闭。

本地 `5306f39` 候选缩减为直接打开云空调，仍为 **0 / 1 / 0，57.842 秒**，失败在原 20 秒内容就绪等待。随后直接启动同一 App、通过 Device Hub 打开，5.893 / 18.386 秒观察均为空白和 10% 进度，约 53 秒保存的截图仍为空白；111.684 秒观察已出现“便携小空调”，首次就绪时刻未知。后段采样期间本机一分钟负载为 558–581，24 个采样中 22 个成功、2 个超时。实际加载延迟已复现，采样开销与系统压力仍是混杂因素，不能据此确认业务根因或性能通过。两份本地证据在 `candidate-5306f39-minimal-open/` 与 `candidate-5306f39-manual-open-capture/`，候选尚不可交付。

### 同期候选构建

随后只加入钱包展示 live 夹具的来源 `5306f39909c82ce944a163e4fda7ce1f49ad68c5`，从独立源码导出构建成功，187 个文件与提交一致。自有 iOS 27 模拟器的两项候选 UI 验证为 **1 通过 / 1 失败 / 0 跳过**：最大字号详情页 27.270 秒通过；云空调获取、移除后恢复旅程在首次网页打开阶段超时，尚未执行到移除和恢复。因此这份候选尚不可交付，不能用构建成功或钱包的四项独立通过代替完整旅程。

失败 AX 附件中的 WebView 进度为 10%，没有“便携小空调”文本；进入详情时另有约 44.76 秒的 XCTest 空闲等待。原始采样时 App 主线程在事件循环等待，RunningBoard 的一个启动工作线程等待 launchd 的 XPC 回复；这些只能缩小排查范围，尚不能证明网页网络错误、App 死锁或系统服务死锁。工具的 300 秒观察超时后，底层进程自然退出，最终 xcresult 已保存；没有终止后重跑或增加预算。证据位于 `candidate-5306f39-verification/`。
