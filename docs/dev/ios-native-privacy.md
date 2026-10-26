# 原生 iOS 数据流与隐私资源核对

> 2026-10-26：`45b3d28b` 的发行 Archive / IPA 已核对唯一清单、11 类数据、两项 required-reason 和相机用途说明；Xcode Organizer 合并 Privacy Report 已导出、渲染并逐项查看。图标图片、支持内容、诊断、用户标识及购买记录均声明为功能用途、关联用户、不跟踪；本地 StoreKit 夹具未进入 IPA，共用脚本与 Apple altool 零错误通过。ASC Nutrition Labels、线上政策的实际留存 / 删除履约及云应用自身行为仍需另行核对，不能沿用旧 Capacitor 审计。报告和摘要见[本轮验收](./testflight-preflight-20261026.md)。以下为早期源码记录。

2026-10-18。范围为干净源码 `c8d43bc`、同源模拟器候选及本次隐私资源补充；不包含并行缓存 / Web 修改。这里记录客户端行为与证据，不表示 App Store Connect、线上隐私文本、第三方网页或真机保护已经验收。旧版的[发布隐私核对](./privacy-release-audit.md)继续作为历史记录，不能直接代表原生宿主。

## 本次修正

旧原生 `PrivacyInfo.xcprivacy` 只有 File Timestamp / UserDefaults 两项 required-reason 声明，遗漏已有功能的数据类型。现补充下表 11 类，按客户端实际用途标记为 App Functionality、关联用户、不用于跟踪，并显式声明不跟踪与空跟踪域名列表。声明资源不增加任何采集或上传路径。

Apple 的[数据使用声明说明](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests)要求用官方类型、用途与关联 / 跟踪字段描述实际行为；本次字段值已与官方类型列表核对。原 File Timestamp `C617.1` 与 UserDefaults `CA92.1` 保留：云居备份读取自己容器内文件的日期，外观和首页偏好使用本 App 的 UserDefaults。没有新增广告用途、自动分析 SDK 或全局设备标识读取。

## 数据与用途

下列“实现”指请求与存储路径已存在，不代表每条生产业务已联调成功。单元 / 模拟器通过也不能替代服务端留存与删除核对。

| 类型                  | 客户端事实与目标                                                                                                                                | 主要源码                                                    |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Name                  | 昵称、用户名资料通过认证网关读取 / 修改；资料表单两次保存及恢复已真实验证                                                                       | `Account`、`CloudbaseAuthService`                           |
| Email Address         | 用户主动输入邮箱，用于认证 / 验证码；账号资料包含邮箱                                                                                           | `VerificationAddress`、`CloudbaseAuthService`               |
| Phone Number          | 用户主动输入手机号，用于认证 / 验证码；账号资料包含手机号                                                                                       | `VerificationAddress`、`CloudbaseAuthService`               |
| User ID               | CloudBase UID 关联认证、业务请求、云居、内容与支持编号；不把显示昵称当成身份凭据                                                                | `AccountSession`、各业务 Service                            |
| Device ID             | 认证状态创建随机 UUID 并保存在本机 Keychain，通过 `x-device-id` 发送到认证网关；不是 IDFA、IDFV 或 Aegis `aid`                                  | `AccountVaultState`、`CloudbaseAuthService`                 |
| Purchase History      | StoreKit 交易 ID 发送到 `iap-order`，读取云币流水与会员、恢复结果；未读取用户银行卡或支付方式                                                   | `NativeStoreKit`、`WalletService`                           |
| Photos or Videos      | 工坊编辑器可从系统选图 / 文件入口取得图标，归一化 PNG 后上传到 `/api/apps/icon-assets`，与当前账号关联                                          | `ApplicationEditorModel`、`PublishingService`               |
| Other User Content    | 应用资料、版本、评价、举报、资料简介；AI 提示词及会话内容发送到对应业务接口 / CloudBase AI Bot                                                  | `PublishingService`、`CommunityService`、`AssistantService` |
| Customer Support      | 用户填写问题描述，预览后确认提交；系统邮件 / 分享另由用户完成发送                                                                               | `FeedbackView`、`DiagnosticService`、`SupportMailComposer`  |
| Product Interaction   | 安装、常用、最近使用、文件夹与作者来源在本机保存，启用账号同步时发送 `/api/home-screen`；访客开启 iCloud 同步时只写入用户自己的 iCloud 键值存储 | `HomeLibrary`、`HomeSyncService`                            |
| Other Diagnostic Data | 有界宿主事件、所选时间范围、App / 系统版本；确认后发往 `/api/diagnostics/logs`，账号由鉴权关联                                                  | `DiagnosticLogStore`、`DiagnosticService`                   |

认证服务为 `yunlefun-8g7ybcxc7345c490.api.tcloudbasegateway.com`，第一方业务默认域名为 `apps.yunle.fun`。本次没有重新验证所有线上路由；生产同步入口与其他业务缺口按各专项继续保留。

**扫码与图标上传是不同路径。** 相机扫码及系统选择的二维码图片由 AVFoundation / Vision / Core Image 在设备上识别，解码器没有图片上传请求；工坊图标则存在真实 multipart 上传实现。因此不沿用旧审计里笼统的“Photos or Videos 不勾选”结论。扫码产生的链接经路由处理后仍可能请求对应站点。

## 本机存储与网络边界

账号资料、访问 / 刷新令牌和认证 UUID 保存在一个 Keychain 状态中，设置为 `AfterFirstUnlockThisDeviceOnly`、不通过 iCloud Keychain 同步。该状态模型不保存登录密码；系统密码保存入口是另一条由用户决定的流程。退出移除对应账号并写回状态，不等于删除其他账号、云居副本或远端业务数据。

云居、升级前副本、导入副本、工坊草稿、诊断缓冲和支持编号各有独立存储路径及账号边界。文件保护选项是实现事实，模拟器无法据此证明锁屏后的保护效果。旧版导入只读取允许的业务键，不把旧令牌或已购缓存转换成原生授权，见[升级与回退](./ios-upgrade-migration.md)。

认证、诊断及多数账号业务请求采用 ephemeral URLSession，禁用 Cookie / URLCredentialStorage，敏感请求拒绝重定向。公开目录、图标缓存和云应用 WebKit 是另行管理的路径，不能把上述配置描述成整个 App 不持久化 Cookie 或不访问第三方网络。SSO 通过受限授权流程传递一次性 code，宿主长期令牌不作为通用网页桥接返回值。

当前原生宿主源码未接入 Aegis / 微信 OpenSDK；候选包没有嵌入第三方 framework，`otool -L` 为 Apple 系统 / Swift 依赖。静态源码搜索与动态依赖列表不等于全网络审计，也不能约束用户打开的云应用。第三方网页及其 SDK 的行为、服务端日志和运行期请求仍需单独核实。

诊断上传需要登录、完整预览和确认，不自动重传；真实合成旅程已验证取消前后为零记录、确认后唯一记录、支持编号恢复和精确清理。原生事件缓冲与上传有数量 / 时间 / 字节上限，服务端回读到 7 天到期字段及管理员规则，但未据此证明定时删除已实际发生。详见[真实诊断验证](./ios-feedback-login-validation.md#真实诊断上传与清理-·-2026-10-18)。

## 包内核对与未完成项

`c8d43bc` 原 ZIP 保持不变，仍只有修正前的两项 API 声明；其签名、摘要与已完成体验测试不受本次源码修改影响。后续 `a8b16f7` 的干净 Benchmark / arm64 已在实际测试二进制与新交付包中逐字节核对清单、11 类声明及完整签名；两条核心旅程通过。新包与原 ZIP 分开保留，不能追溯宣称旧候选已包含新声明，见[更新候选](./ios-simulator-preview.md#含隐私声明的新候选-·-2026-10-18)。

独立导出 `2027861` 并只覆盖本次隐私资源后，正式标识 Release 模拟器编译通过（76.445 秒，零构建诊断）。产物中的清单与当前源文件逐字节一致，11 类均为官方枚举，原两项 required-reason 保持；arm64 / x86_64 签名校验通过，最低系统声明仍为 iOS 16。该包仅做编译与资源核对，未安装，未生成发行 Archive 或 Xcode Privacy Report。来源摘要、原候选资源、新产物与日志保存于本轮证据目录 `native-privacy-20261018`。

包内相机用途说明为“用于扫描云应用和个人工坊二维码。”；没有定位、麦克风、通讯录或 ATT 用途键。选图使用系统 PhotosPicker；权限键缺失或系统库弱链接都不能独立证明整个 App 从不访问某类数据，结论需结合调用路径。

仍需完成：发行 Archive 的合并 Privacy Report、App Store Connect 标签与线上政策的一致性、云应用和服务端的实际采集 / 留存检查、真机锁屏保护与账号删除流程。当前未改线上法律文本、App Store Connect 或生产服务；这份源码清单不构成发布验收通过。
