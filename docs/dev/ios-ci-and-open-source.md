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
5. 失败时保留日志 / xcresult 三天，完成后删除本次新建模拟器。只授予 `contents: read`，checkout 不保留凭据；两个 Action 固定官方仓库的完整提交 SHA。

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
