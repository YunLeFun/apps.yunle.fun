# 云乐坊 · 原生 iOS

SwiftUI 主壳，系统组件优先，云应用复用现有 UIKit / WKWebView 运行时。使用最新 SDK 编译，最低部署版本暂为 iOS 16.0；同时支持 iPhone 和 iPad。完整目标见 [原生改造 Goal](../../docs/dev/ios-native-migration.md) 和 [原生 UI 规范](../../docs/ui/ios-native.md)。

## 开发

提交的 `YunleFun.xcodeproj` 可直接用 Xcode 打开。修改 `project.yml` 后用 XcodeGen 重新生成；首次实施使用 XcodeGen 2.46.0 与 Xcode 27.0。

```sh
cd apps/ios
xcodegen generate
open YunleFun.xcodeproj
```

选择 `YunleFun` Scheme 与本机可用的 iPhone / iPad 模拟器运行。Debug 使用 `fun.yunle.apps.native-dev`，可与旧版同时安装；Release 使用现有正式标识 `fun.yunle.apps`。尚未完成升级迁移和完整回归前，不将开发版本覆盖安装到正式用户设备。

无需 CocoaPods、Capacitor runtime 或打包 Nuxt 来启动原生客户端。SVG 图标通过 Swift Package Manager 引入固定版本 SwiftDraw 0.29.0；首次构建需解析依赖，具体修订由 Package.resolved 锁定。当前工程直接编译兼容工程里的 `WebViewController.swift` 与原生图片 / 授权辅助代码；`CAPPlugin` 部分仅在有 Capacitor 模块的兼容工程编译。原生宿主通过页面工厂提供 SwiftUI 详情与开发者作品页。

命令行编译：

```sh
xcodebuild -project YunleFun.xcodeproj -scheme YunleFun \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

测试时使用 Xcode 的 Product → Test，或将下例 UUID 替换为 `xcrun simctl list devices available` 中本机可用模拟器的 UUID：

```sh
xcodebuild -project YunleFun.xcodeproj -scheme YunleFun \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -parallel-testing-enabled NO test
```

测试包含实际 Keychain 读写，模拟器构建必须保留本地 ad-hoc 签名；完全关闭签名会使 Keychain 返回权限错误。该命令不上传构建，也不需要分发证书。

## 当前能力与缺口

另有按需运行的 `YunleFunBenchmarks` Scheme，使用 release 优化和独立的 `fun.yunle.apps.benchmark-dev` 标识，包含四 Tab、真实云空调旅程与显式启用的启动测量。测量条件、环境变量、结果导出和首轮原始数据见 [性能基线](../../docs/dev/ios-performance-baseline.md)。它要求独立访客测试模拟器，不包含在日常单元测试 Scheme 中。

已实现真实公开目录读取、原生分类 / 本地搜索、详情、免费公开应用获取到本地云居、排序 / 移除、最近使用与系统外观设置。使用现有运行时管理打开 / 收起 / 会话恢复 / 结束，仍需按真实网页内容逐项验证。邀请、会员与付费条件不会被当作免费公开应用绕过。

已接入官方 CloudBase Auth HTTP 协议：手机号 / 邮箱验证码登录或注册、密码登录、图片验证、资料读取 / 编辑、刷新、退出与本机多账号。原生登录、账号管理和资料表单使用系统组件。凭据与设备标识保存在 Keychain；刷新请求合并，账号切换先清空旧数据投影、结束运行会话并清理现有允许名单内的身份 Cookie。云居本地文件按账号分开，访客数据不自动并入账号。

认证已通过协议 / 竞态测试、真实模拟器 Keychain 与访客 UI 检查；另在 iOS 27 使用三个受管合成账号完成真实密码登录、强制刷新、多账号切换、Keychain 恢复、钱包 / 流水读取及远端退出。验证码、防护、资料写入、真实表单输入与真机仍待验。当前原生单元 / 集成测试 205 项与 UI 旅程 1 项通过，另有独立的相册 / 链接及发布管理访客 UI 旅程，覆盖目录、持久化、认证、同步协议、宿主授权、评价 / 举报、迟到响应、冲突恢复和身份边界。UI 旅程要求独立的访客测试模拟器，不会替开发者退出真实账号；只运行单元测试可添加 `-only-testing:YunleFunTests`。

原生宿主授权已接入注册策略、原生账号和共享 UIKit 面板；真实 AI 春联的“登录并继续 → 取消返回 → 再试”在 iOS 27 与 iOS 18.6 通过。宿主凭据只发送给 CloudBase 网关，云应用只接收单次 code。真实账号签码 / 消费及系统其他账号回跳仍待联调，详见[授权接入](../../docs/dev/ios-host-authorization.md)。

已实现云居离线模型、同步服务、同步设置、版本比较与常用应用管理，对应同仓库新增 GET / PUT `/api/home-screen`。生产接口尚未部署，当前生产路径返回 HTML 首页，原生会拒绝将其视为成功。完整协议、历史文档保留方式和旧 SDK 并发限制见 [同步契约](../../docs/dev/ios-home-sync.md)。本地完整服务连接现有 CloudBase 的受管账号真实同步、不可达请求后的磁盘恢复、独立本地客户端冲突和账号切换已通过；生产端点、跨硬件、真实 UI 点击和覆盖升级仍待验。

原生评价 / 举报页面与协议已实现，真实公开读取和访客取消已验证；真实写入 / 审核 / 个人记录仍待联调，详见[评价与举报](../../docs/dev/ios-community.md)。个人工坊的原生创建 / 设置 / 坊客管理 / 加入 / 离开 / 二维码分享已接入协议，访客入口已验证；真实写入和私有工坊内容仍待联调，详见[个人工坊](../../docs/dev/ios-workshops.md)。原生相机 / 相册扫码与应用 / 工坊链接接收已实现，iOS 27 / 18.6 的相册识别和 URL 接收已验证，硬件相机及正式 Universal Link 分发待验，详见[扫码与链接](../../docs/dev/ios-scanner.md)。应用管理与发布已有原生列表 / 编辑、版本保存、市场投稿、下架、图标上传协议和分账号本机草稿；真实写入与私有预览仍待联调，详见[应用管理与发布](../../docs/dev/ios-publishing.md)。原生图标已支持当前公开云图标解析、深色变体、独立 SVG 与有界缓存，真实 SVG 在 iOS 27 / 18.6 验证通过；全目录检查仍有 2 个远端 404，详见[图标资产](../../docs/dev/ios-icon-assets.md)。钱包 / 会员、账户 HTTP 与原生 StoreKit 2 购买 / 归属 / 恢复流程已接入；iOS 27 / 18.6 的实际本地 StoreKit 测试与访客旅程通过，iOS 27 三个受管账号的真实钱包与流水读取通过，Sandbox 尚未验收，见[钱包与会员](../../docs/dev/ios-wallet.md)。原生应用获取新增统一条件页、云币确认及服务端核价 / 已购查询，接口未部署，真实账号购买和使用待联调，见[应用获取](../../docs/dev/ios-acquisition.md)。云同步与发布的真实账号闭环、付费应用获取验收、Sandbox、完整图标资产验收、其余深链及旧版数据导入尚未完成。寻乐当前从真实目录展示官方和公开作品，没有把目录顺序冒充编辑推荐或热门榜单。

最新系统的 Tab、导航、搜索、表单和菜单由 SwiftUI 自动提供视觉。现有 WebRuntime 的自定义标题栏与菜单还需逐步对齐原生 UI 规范，不能据此判定全量 UI 改造完成。正式签名、隐私声明、构建号与发布材料在候选版本阶段统一核验；当前不上传或提审。

本地内购验证使用独立 `YunleFunStoreKitValidation` Scheme，显式绑定测试配置；它的交易只完成本地清理，不调用线上发放。日常 `YunleFun` / `YunleFunBenchmarks` 及 Release 归档不启用该配置。实际 StoreKit 本地购买和已完成非续期会员恢复在 iOS 27 / 18.6 各 2 项通过，不能替代 Sandbox。测试命令和接口范围见[钱包与会员](../../docs/dev/ios-wallet.md)。


原生 AI 助手已接入现有 Agent，使用原生 SSE / Markdown / 应用卡片，包含会员门控、停止 / 重试、登录取消与身份隔离。iOS 27 受管会员号真实请求通过；现有服务是应用检索，不新增通用大模型。Agent 账户鉴权、次数事务与公开目录加固尚未部署。受管账号输入与真实联调的显式运行要求见[原生助手与受管账号验证](../../docs/dev/ios-assistant.md)，测试凭据必须留在仓库外安全文件中。
