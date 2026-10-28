# iOS 系统分享反馈

2026-10-27：新增 `YunleFunFeedbackShare` Share Extension。正式版用户可以在系统截屏预览、照片或其他支持图片分享的页面选择「云乐坊」，打开「反馈给云乐坊」表单，复用支持中心的私密工单与截图接口。支持 iOS 16 起的系统，不新增第三方反馈 SDK。

## 用户流程

1. 截图后打开系统分享菜单，选择「云乐坊」；首次可能需要在「更多」里启用。系统使用主 App 名称，Debug 显示「云乐坊 Native」，扩展内的页面标题是「反馈给云乐坊」。这是 Apple 的[分享菜单命名规则](https://developer.apple.com/videos/play/tech-talks/210/)。
2. 扩展读取用户明确分享的图片，提供预览、移除、产品与类型选择、问题描述。只分享文字、链接或 PDF 不会激活这个入口；系统激活规则最多接收 3 张图片。
3. 点击「提交反馈」，再次确认具体产品、描述和截图数量。确认前不会建立访客网络会话或提交内容，不自动附带诊断日志。
4. 以访客身份提交，无需登录。成功后可复制私密工单链接，或回到「我 → 反馈与建议 → 从系统分享提交的反馈」继续查看工单。
5. TestFlight 安装优先显示 Apple 的「共享 Beta 版反馈 / 发送 Beta 版反馈」说明；用户明确选择「仍使用云乐坊通用反馈」后才读取图片。关闭说明只关闭扩展，不承诺自动跳转 TestFlight。正式收据与测试收据来自包含扩展的主 App；扩展没有自己的 App Store 收据，无法读取时回退到主 App 最近记录的渠道。开发版与模拟器按通用反馈处理。

扩展不会绕过系统打开主 App，也不自动获取用户刚截取的图片。TestFlight 与 App Store 使用同一套扩展激活配置，因此测试版分享菜单仍可能显示该入口，打开后优先引导官方反馈。

## 图片与提交协议

- `SharedScreenshotImporter` 通过 `NSItemProvider.loadFileRepresentation` 接收图片，在回调有效期内复制成自己持有的 `Data`，不保存临时 URL。串行导入、允许取消，忽略私有图片表示类型。
- 单张原始文件最多 20 MiB、1200 万像素；后台 ImageIO 缩小到最长边 2048 像素并重新编码 JPEG，每张最多 1 MiB，去除原文件名、GPS / EXIF 等附加信息。扩展采用较低像素上限控制内存；App 内手动选图仍沿用原有上限。
- `SharedFeedback/SupportFeedbackClient` 与主 App 共用访客连接、Cookie 允许名单、CSRF、幂等键和响应校验。扩展只使用访客 Cookie，不共享 App Token、Keychain 或主 App 登录 Cookie。
- 请求仍为 `POST /api/v1/private-feedback`，图片结构见[截图反馈契约](./ios-support-feedback.md)。额外上下文是 `context.source = apps-ios-share` 与 App 版本 / 构建号；沿用已有可选字段，不新增后端协议。
- 确认后的请求内容被冻结。超时保留草稿，由用户显式重试；相同内容复用幂等键，修改描述、产品、类型或图片后更换键。成功、关闭或取消时清理内存中的图片与草稿，不在 App Group 中暂存待上传图片。
- 网络只访问固定支持中心 HTTPS 域名，拒绝重定向和 HTML 兜底；访客回执必须包含经过验证的同源工单访问链接。保存本机回执失败时明确提示复制链接，不重复提交已成功的反馈。

## App Group 与身份边界

| 配置      | 主 App Bundle ID               | 扩展 Bundle ID                                | App Group                            |
| --------- | ------------------------------ | --------------------------------------------- | ------------------------------------ |
| Release   | `fun.yunle.apps`               | `fun.yunle.apps.feedback-share`               | `group.fun.yunle.apps`               |
| Debug     | `fun.yunle.apps.native-dev`    | `fun.yunle.apps.native-dev.feedback-share`    | `group.fun.yunle.apps.native-dev`    |
| Benchmark | `fun.yunle.apps.benchmark-dev` | `fun.yunle.apps.benchmark-dev.feedback-share` | `group.fun.yunle.apps.benchmark-dev` |

`project.yml` 是配置源；XcodeGen 生成扩展目标、嵌入关系、Info 与 entitlements。扩展开启 `APPLICATION_EXTENSION_API_ONLY`，版本与构建号跟随主 App，包含独立的 `PrivacyInfo.xcprivacy`。

共享容器仅保存最多 20 条访客回执、访问链接、创建时间、渠道及账号作用域摘要。链接本身是私密访问凭证；文件使用完整保护、排除备份，通过 `NSFileCoordinator` 协调原子读改写。拒绝损坏、超限与符号链接文件，保留原文件并显示可理解的错误。

主 App 在身份变化时同步轮换作用域代次并清空记录；迟到响应和旧的清除确认无法跨越 A→B→A 切号。首次打开 App 之前提交的无归属记录，可以在首次身份恢复结束后接管一次；同一身份正常恢复不清空。主 App 用原生工单页读取访客工单，网页回复由显式入口打开，不把访客工单伪装成账号工单。

## 验证与发布条件

### 系统分享完整流程续验 · 2026-10-27

本轮在独占 iPhone 16 Pro / iOS 18.6 设备上，通过照片的真实系统 Share 菜单进入扩展，使用本地支持中心完成提交和回看。系统入口实际点选，扩展及后续 App / WebKit 流程由 XCTest 操作验证；不把它描述为无人操作的 Photos 自动化。后端使用 Support 真实业务服务、鉴权和持久化适配器，仅将 CloudBase 数据库替换为现有离线夹具；页面使用未经修改的 Support Nuxt 构建，没有向生产环境写入工单。

- **4 次 UI 验收通过、0 失败 / 跳过**，对应 3 条用例：JPEG 与 PNG 各一次完整流程；TestFlight 官方反馈关闭；明确选择通用反馈后导入、移除、取消。
- 完整流程验证截图预览、系统确认取消前零网络请求、服务端已提交但返回 503 后保留草稿、同一幂等键重试仅生成一张工单、成功回执、App 终止重启后的工单恢复、真实私密工单与截图预览，以及清除本机记录不删除服务端工单。
- PNG 输入来自本轮模拟器画面，照片 App 标识为「截屏」，原图 **1206×2622**，服务端回看的 JPEG 为 **942×2048 / 189331 bytes**。这验证 PNG 经过系统分享的实际文件提供器、客户端压缩、后端存储与鉴权回看，不等同于真机硬件截屏 / 系统悬浮预览的验收。
- TestFlight 提示使用本轮 App Group 的模拟记忆渠道；确认优先说明页不导入截图，选择官方反馈只关闭扩展，明确选择通用反馈后才导入。两条分支均无反馈网络请求。真实 TestFlight 安装的收据识别仍待候选包验证。
- 验收修复了分区重复弹窗：`Section` 上的浏览器会产生多个并发呈现请求；工单浏览器和清除确认现由 `FeedbackView` 的稳定根容器统一呈现，账号变化仍清除待处理路由与确认。
- 最终共享核心 **19 项 XCTest 通过**，Debug 测试目标和 Release 模拟器构建通过；Release 主 App / 扩展的二进制检查均不包含 loopback 端点，扩展保留正式支持中心域名。

可重复执行的夹具、预检、渠道准备和 UI 运行方式见 [`Validation/ShareFeedback/README.md`](https://github.com/YunLeFun/apps.yunle.fun/blob/main/apps/ios/Validation/ShareFeedback/README.md)。本地小型报告与截图位于忽略目录 `apps/ios/build/share-feedback-e2e-20261027/`。本轮临时设备 `Yunle Share E2E 18.6 20261027` / `259EB562-B760-4112-B6D9-DA046366B2C6` 已关闭并删除，设备列表复核无残留，本地 API / Web 端口均已关闭。回收约 1.48 GiB 构建 / 结果包及原占约 1.65 GiB 的临时设备，清理期间磁盘可用空间净增加约 3.16 GiB（包含并行任务及恢复设备的空间变化），共享依赖缓存保留。经用户明确授权暂时关闭的三台 Cook 模拟器均已恢复 Booted，未擦除数据。

### 初轮构建与核心验证

- Debug、Release 模拟器构建通过；扩展嵌入、Bundle 前缀、版本号、配置隔离、图片激活规则与隐私清单检查通过。模拟器 entitlement 不能替代真机分发签名验证。
- iOS 26.5 专项 XCTest **35 通过、0 失败**：新增共享核心 19 项，原有支持中心服务 11 项、状态管理 5 项。覆盖临时文件读取与取消、JPEG 清洗、冻结确认、显式重试、CSRF / Cookie / HTTP 边界、回执恢复、损坏文件与账号切换。
- 最终源码使用 `python3 apps/ios/scripts/test-shared-feedback.py` 在 macOS 再运行共享核心 **19 通过、0 失败**。此脚本直接链接实际源文件，不依赖模拟器；它不替代 iOS UI 或真机验收。
- 初轮系统服务经历长时间初始化，iOS 单元测试与 Release 安装 / 启动成功，但系统分享入口、预览和取消当时未取得运行结果。上面的续验已补齐本地完整流程；生产工单写入、真机截屏分享、TestFlight 安装渠道、最低系统与分发签名仍待验收。
- 本轮仅操作临时设备 `Yunle Share Feedback QA 20261027` / `E3BFE867-2282-4F33-A28A-B88D8BB6C984`，清理后设备列表已确认不再包含该 UDID。导出必要报告后回收约 1164 MiB 可重建构建 / 测试产物并删除本轮模拟器；共享依赖缓存保留。清理期间磁盘可用空间增加约 2413 MiB，包含模拟器回收与并行任务的空间变化，不能全部归于构建目录。小型验证报告位于本地忽略目录 `apps/ios/build/share-feedback-20261027/`。

发布前需在 Apple Developer 为所用配置注册相应 App Group，并同时为主 App 与扩展 App ID 启用该组，更新开发 / 分发描述文件后重新验签与验包。本轮不注册线上能力、不发布 TestFlight、不提审。

截图上传还要求先部署 Support 截图接口，并按其 `docs/feedback-database.json` 准备私密 `support_feedback_screenshots` ADMINONLY 集合；详情见[已有截图后端契约](./ios-support-feedback.md)。不满足时不能将模拟器编译成功当作线上截图上传已可用。

实现依据：[Apple Share Extension](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html)、[系统分享界面规范](https://developer.apple.com/design/human-interface-guidelines/activity-views)、[共享数据与 App Group](https://developer.apple.com/documentation/technologyoverviews/shared-data)、[隐私清单](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)。

## 原生回看与 iOS 26 视觉验收（2026-10-28）

系统分享菜单启动的是随云乐坊安装的 Share Extension；表单由 SwiftUI 呈现，完成后返回照片等发起分享的 App。Share Extension 没有通用的自动拉起主 App 能力，不能用 responder 链或私有接口绕过。主 App 通过 App Group 恢复工单回执。参见 [Apple NSExtensionContext.open](<https://developer.apple.com/documentation/foundation/nsextensioncontext/open(_:completionhandler:)>)。

旧版分享回执用 WebKit 直接打开支持中心工单，所以工单中的截图预览仍是网页弹窗。现在系统分享记录与 App 内新提交的工单都先进入原生 `SupportTicketView`，显示状态、交流记录和私密截图。回复等完整网页操作保留为显式入口。仍复用 Support 的现有 requester API，不复制工单数据源、不改生产接口。

`SupportTicketClient` 只将私密链接 fragment 中的工单凭证以 POST body 交换为该工单专用的 HttpOnly Cookie；图片地址不包含凭证，不进入 WebKit，使用无缓存的临时 URLSession，并核对工单归属、图片元数据及 JPEG 实际尺寸。账号变化会关闭当前工单，内存中的工单、Cookie 与图片随页面释放。

分享扩展、App 草稿和工单截图共用 `ScreenshotPreview`：UIKit `UIScrollView` 提供捏合、双击缩放及按视图尺寸适配，SwiftUI 标准导航提供关闭控件。图片保持独立内容层，系统负责 iOS 26 导航控件的 Liquid Glass；不在图片上叠加自制模糊层，旧系统继续使用标准原生外观。草稿预览由稳定根容器统一呈现，避免 `Section` 重复呈现弹窗。

本轮在 iPhone 16 Pro / **iOS 26.5（23F77）模拟器**上，使用照片中标识为「截屏」的本轮 PNG，通过真实系统分享菜单进入扩展。浅色与深色完整流程均已通过：原生预览和双击缩放、确认取消前零请求、成功后响应丢失的幂等重试、回执、App 重启恢复、原生工单及鉴权 JPEG 回看、清除本机记录但保留服务端工单。默认回看路径断言无 WebView。本地 API 复用 Support 实际服务与适配器，数据库为进程内合成夹具；本轮未启动工单网页服务，也未写入生产数据。

另已通过原生反馈页面检查、草稿系统选图 / 预览 / 关闭保留描述与图片 / 移除 / 零提交，以及 TestFlight 记忆渠道的「官方反馈关闭」和「明确选择通用反馈」两条分支。共享核心 **25 项通过**（含新增工单读取边界 6 项）；Debug 测试构建与 Release 模拟器构建通过，Release 主 App 和扩展均核验不含本地验收地址。

初轮视觉证据覆盖竖屏浅色 / 深色表单、系统确认、原生工单和图片预览。当时额外横屏检查未取得可靠结果，误命名的 landscape 图片已移除；下方“横屏续验”已修正验收方式并补齐运行证据。真机截屏悬浮预览、真实 TestFlight 收据与分发签名仍需后续候选包验证；本轮不发布。

启动阻塞诊断中曾定位到本轮自动日志流使 runningboardd 卡在 `_os_activity_stream_reflect`；停止该任务日志流后安装 / 启动恢复。照片选择器通过其 `com.apple.mobileslideshow.photospicker` 进程查询。报告与合成截图保留在本地忽略目录 `apps/ios/build/share-feedback-glass26-20261028/`；此前 iOS 18.6 网页截图仅为历史功能记录，不作为 iOS 26 视觉依据。设备 `F69F6452-D87D-4C56-ACDE-6E3E6A144CB3` 已由共享池维护流程指定为保留的 iOS 26 设备，收尾保留该设备并清理本轮构建、服务和验收凭证。

收尾已移除本轮 Debug / UI Runner、精确匹配的本轮 CA 证书及本地私钥，关闭本地服务并释放共享设备。回收任务构建与原始结果包 **2.84 GiB**；清理期间磁盘可用空间净增加 **2.61 GiB**，该净值包含并行任务影响。保留小型报告、必要截图和共享依赖缓存；照片库中两张合成截图作为共享 QA 输入保留，未改动 Apple 默认样片。设备状态按最新共享池维护结果保留，没有重新创建已淘汰的 Cook 重复设备或 iOS 18 设备。

### 横屏续验（2026-10-28）

本次在同一共享 iPhone 16 Pro / iOS 26.5（23F77）上，先用 LLDB 读取实际 UIKit 方向能力：App mask 为 26（竖屏及左右横屏），SwiftUI 根控制器和预览呈现控制器 mask 均为 30，且允许自动旋转。直接旋转设备与独立自动化均能使原生预览横屏。`ScreenshotPreview.swift` 和 `project.yml` 与上一轮验收的 SHA-256 一致，说明当前证据不支持修改 App 方向配置。

定位并修复了验收方式的问题：`app.screenshot()` 的 App 范围截图在横屏中出现裁剪 / 方向元数据异常，不能依靠其 `image.size` 或 PNG 编码像素尺寸判断界面是否横屏。现在以实际窗口宽高等待旋转完成，并断言图片比例、完整可见、居中及关闭按钮可达性；证据统一使用 `XCUIScreen.main.screenshot()`，同时保存窗口 / 图片框和方向元数据。图片查看器和方向配置保持原实现。

新增可独立运行的草稿横屏用例，并将相同断言复用到真实系统分享和原生私密工单流程。覆盖左右横屏、横屏放大后旋回竖屏自动适配、关闭保留草稿及移除图片。实测横屏窗口为 **874×402 pt**，完整竖向截图在其中居中显示为约 **139.83×304 pt**，没有拉伸或超出窗口。复现命令见 [`Validation/ShareFeedback/README.md`](https://github.com/YunLeFun/apps.yunle.fun/blob/main/apps/ios/Validation/ShareFeedback/README.md)；报告与真实整屏截图位于本地忽略目录 `apps/ios/build/share-feedback-rotation26-20261028/`。

最终 **3 次验收通过，0 失败 / 跳过**：独立草稿横屏、浅色完整系统分享、深色完整系统分享。后两次均从 Photos 真实分享菜单进入，继续验证提交确认、丢失响应后的幂等重试、App 重启恢复、原生工单与鉴权截图、左右横屏，以及清除本机回执不删除服务端工单；两次都只生成一张合成工单。最终 Debug 测试构建通过。本轮仅修改验收代码、生成的测试文件索引与文档；原生预览和方向配置保持原实现，没有发布。

横屏续验收尾已回收 **0.52 GiB** 可重建产物，期间磁盘可用空间净变化 **+0.52 GiB**（含并行任务影响）。本轮 Debug / UI Runner、服务、CA 和私钥均已清理；共享设备恢复浅色外观后关闭并保留，未新增模拟器。
