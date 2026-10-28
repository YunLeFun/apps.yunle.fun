# 原生帮助、反馈与诊断日志契约

## 系统分享截图反馈 · 2026-10-27

新增[Share Extension](./ios-share-feedback.md)，从系统截屏预览、照片等图片分享入口选择「云乐坊」，打开「反馈给云乐坊」表单，以访客身份复用本页的私密工单与截图协议。App Group 仅保存有界的工单访问链接，不共享账号凭据、图片或草稿；TestFlight 安装先引导官方反馈。主 App 的「反馈与建议」可以查看本机系统分享工单，切换身份清空。启用 App Group 签名能力及部署截图后端是后续发布条件。

## 截图反馈与 TestFlight 优先入口 · 2026-10-27

- “反馈与建议”和“在线反馈”支持系统 PhotosPicker 选择最多 3 张图片，支持预览和移除；两页共用内存草稿，关闭在线反馈仍保留选择，切换账号清空。
- 使用 ImageIO 在后台缩小到最长边 2048 像素并重新编码 JPEG，每张最多 1 MiB；导入前限制 20 MiB / 6000 万像素，去除原始文件名、EXIF / GPS 等附加信息。
- 截图只随在线私密反馈提交。点击提交先冻结描述、产品、类型和截图，系统确认显示截图数量；图片导入期间禁止提交。失败保留输入，显式重试对同一图片字节复用幂等键；新增、移除或更换图片会更换键。成功后清空截图草稿。
- 日志仍独立预览确认；邮件、分享及日志上传均不自动附带所选截图。系统截屏快捷入口仍不读取或自动附加刚截取的图片。
- Release 真机按 `sandboxReceipt` 识别 TestFlight 渠道（沿用钱包环境判定依据），在反馈页顶部优先解释 TestFlight 截屏 / Beta 版反馈；开发版和模拟器保持通用反馈。TestFlight 不显示本 App 的截屏胶囊，避免干扰 Apple 的系统反馈。没有收据时保留通用入口；未在真实 TestFlight 安装包验证该提示。
- 通用私密反馈扩展 `POST /api/v1/private-feedback` 的可选 `screenshots: [{ mimeType: "image/jpeg", data: "<base64>" }]`，使用原有 Cookie / CSRF / 幂等键；无图片时保持旧请求结构。
- 配套 Support 仓库新增私密截图存储及鉴权查看接口，用户工单和管理工作台复用已有 Reka UI Dialog 预览。上线前需部署 Support 新接口并按其 `docs/feedback-database.json` 准备 `support_feedback_screenshots` 的 ADMINONLY 集合。此任务不部署、不发布 TestFlight。

### 本轮验证

- Support：类型检查、生产构建和根 lint 通过；完整单元测试 212 通过 / 1 既有 live 测试跳过。截图与工单浏览器专项 5 通过，验证移动端深色预览、Escape / 返回焦点、失败重试和既有会话流程。
- 直接编译并执行 `FeedbackScreenshot.swift`：检查真实 JPEG 输出、尺寸、方向、GPS 移除、无效 / 过大输入及 TestFlight 渠道规则；原生实际生成的 JSON 由 Support 解析通过。
- 三张 1024×1024、每张约 873 KiB 的原生 JPEG 通过离线 CloudBase 契约检查：请求限额、9 个附件块的完整重建、失败事务零残留、幂等与事务操作数限制。
- 最终 iOS App + 单元 / UI 测试目标 `build-for-testing` 通过。iOS 27.0 和 26.5 的本轮临时设备均停在系统启动 / 界面服务，未取得 XCTest 运行结果，不计为测试通过；真实 PhotosPicker 导入、预览 / 移除 / 草稿往返、真机和实际 TestFlight 渠道显示继续待验。
- 默认 UI 测试增加选择器取消保留草稿；需要预置合成图片的完整旅程放在 `FeedbackScreenshotUITests` 的独立 Benchmark 中，要求 `FEEDBACK_SCREENSHOT_QA_SEEDED=1`，不让日常 CI 依赖个人照片库。
- 临时设备 `Yunle Screenshot QA 20261027` / `C88DD5C7-FB2F-4991-8A6F-D00D6EAA3655` 与 `Yunle Screenshot QA 26.5 20261027` / `4639CFCB-D953-43AE-ADC5-16151508BBBF` 均在本任务清理。保留小型报告与截图于本地忽略的 `apps/ios/build/feedback-screenshots-20261027/`，回收本轮 DerivedData、验包副本与原始结果包；原有共享缓存及其他任务设备保留。

## 统一支持中心接入 · 2026-10-26

“我 → 反馈与建议”新增在线反馈、需求墙与反馈管理入口，保留原有邮件、微信客服和诊断日志流程。
在线反馈使用 SwiftUI `List` / `Picker` / `TextEditor`，与原反馈页同步问题描述；提交前通过系统确认，
成功后保留工单入口。日志上传仍走原有独立预览确认，不会随在线反馈自动附带。

- 原生渲染：私密反馈提交、公开需求列表及详情、管理员按产品读取私密反馈列表及详情。
  云食册正式 Web / iOS 的应用意见共用 `cook` 队列，按 `context.source` 的 `cook-web` /
  `cook-ios` 展示来源平台，并显示 `context.version`；无上下文的历史记录显示“未记录”。
  这是客户端上报的排查线索，不能作为身份或权限凭据。菜谱纠错仍在 Cook 独立审核后台。
- App 内网页：工单回复、投票、完整路线图与管理编辑。使用独立、非持久化 `WKWebView`，
  标准系统导航和返回手势；外站链接在系统网页打开。
- 当前 Support 产品协议尚无独立 `apps` 产品；客户端默认选择 `www`（云乐坊账号与服务），
  其他产品沿用 Support 已注册的 `cook` / `play` / `yunbox` / `drive` / `cms` / `advjs`。

### 身份与权限

1. 登录用户复用原生 `AccountStore`，通过已注册的 `support-web` 签发一次性授权码；
   使用安全随机 nonce / verifier 和 S256 PKCE，解析注册策略，显式授权策略需要用户点按允许。
2. 授权码经 `https://api.yunle.fun/sso-ticket` 交换取得签名身份断言。
   客户端无需采用返回的临时 CloudBase ticket，也不会修改原生账号会话。
3. `POST https://support.yunle.fun/api/v1/session/exchange` 接收原生 CloudBase access token、
   Support audience 的签名断言与相同 nonce。服务端校验 subject、audience、app、scope、nonce、
   手机号准入和账号状态，再设置 `__Host-ylf-support-session`。
4. 访客通过 `/api/v1/feedback/guest` 获取单独的 HttpOnly 访客 cookie 和 CSRF。
   私密反馈通过 `/api/v1/private-feedback` 提交；保留同一未修改内容的幂等键供用户显式重试。
5. 原生管理列表读取 `/api/internal/v1/dashboard`；每次由服务端按 UID 与产品成员记录授权。
   客户端没有 `yunyoujun` 用户名提权规则，也不会替当前用户登录另一个账号。

凭据、断言、cookie、私密反馈只保留在内存，不进入 URL、日志或本地文件。
WebKit 只收到支持中心的 HttpOnly cookie，拿不到原生 access token、verifier 或身份断言。
切号（含 A→B→A）、退出和取消后拒收旧请求结果；关闭中心或切号时尝试撤销本次 Support 会话，
不退出 App 账号。访客工单访问链接是服务端返回的私密凭证，用户可主动保存到个人备忘录，界面提醒勿转发。

### 验证边界

- 已核对线上公开需求读取与未登录管理接口的 401，以及线上 `support-web` 的 trusted 注册策略。
- 模拟器定向测试覆盖 S256 / nonce、UID 绑定、显式授权、CSRF / 幂等键、无隐式提交、
  HTML 兜底拒绝、管理拒绝、工单链接域名边界、401 刷新一次、切号隐藏私密数据与迟到结果丢弃。
- 原生 UI 旅程检查描述带入、系统 `TextEditor`（无 WebView）和返回保留草稿，截图使用合成内容。
- iOS 26.5 / iPhone 17 Pro 的综合检查为 16 通过 / 0 失败；最后收紧 cookie 允许名单后，
  8 项服务边界复测全部通过（包含 1 项新增 cookie 拒绝用例），合计覆盖 17 个不同用例。
  初轮两项测试因 `URLProtocol` 将请求体转为 stream 而失败，已修正测试记录器并保留原始结果。
  本次临时设备为 `Yunle Support QA 20261026` / `846EC47D-1994-44D6-9C3A-20CC3938B201`，
  导出截图与结果后在同一任务中删除；未操作其他任务设备。结果位于仓库外
  `~/.codex/artifacts/yunlefun/support-ios-20261026-01a1781a/`。
- `yunyoujun` 真实账号自动登录、生产私密反馈写入、真实管理员数据、工单回复与 WebKit 会话延续仍待实际账号验收。
  尚未为此功能打包或发布 TestFlight。

实现：`SupportCenterView`、`SupportCenterService`、`SupportCenterStore`、`SupportBrowserView`。
Support API 依据为远端 `YunLeFun/support.yunle.fun` 的 `397bbae` 及本次线上只读核验；
初次盘点时本地 Support 主分支落后；后续 Web 改造已快进到上述远端基准，不能用此前旧版本的 GitHub Discussions 流程描述当前生产站点。

### 完整网页入口与 Web 外观 · 2026-10-26

- “我 → 反馈与建议 → 打开完整支持中心”直接进入 `SupportWebsiteView`，登录账号先完成相同的 Support SSO，访客可直接浏览公开页面。
- `WKWebView` 使用 `YunleFunSupport/1` 的 User-Agent 展示提示，仍然只接受独立 Support cookie。
  网站据此省去重复页头，保留帮助、需求墙、反馈、工单与管理导航；权限验证与 Cookie/CSRF 规则保持不变。
- 原生关闭、返回和刷新集中在顶部；Web 底部导航保留安全区。通过 KVO 跟踪网页历史，覆盖 SPA 内部路由变化。
- Support Web 的系统字体、分组背景、深浅色、表单触摸区域与响应式布局在其仓库统一实现。
  完整页面继续由 WebKit 渲染；前述原生表单与列表继续由 SwiftUI 渲染。
- iOS 26.5 临时设备 `Yunle Support Web QA 20261026` / `BB61D8D8-9644-477C-A24D-E9296B7715D6`
  实际打开完整生产网页并返回原反馈页的 UI 测试通过（1/1）。这验证网页入口，生产网页当时仍使用旧样式；
  新 Web 外观已在本地浏览器验证，待正式站部署。截图与结果保留在本节前述仓库外目录，测试后删除临时设备。

### 提交与发布待办 · 2026-10-26

- [ ] 使用真实 `yunyoujun` 账号验证自动登录、按产品成员记录授权、私密反馈和工单回复；仅凭用户名不得授予全产品管理权限。
- [ ] 在部署新版 Support Web 后复验 App 内网页的主题、键盘、安全区、返回与最大动态字体；真机操作及 iOS 16 覆盖按后续明确验收范围执行。
- [ ] 排查独立 TestFlight 收尾任务报告的 4 项完整回归失败：最大字号详情布局 2 项、帮助页入口 1 项、Duo 导航 1 项。其模拟器同时报告数据迁移失败，原因未定，不将失败归结为本次 Support 代码或记为已解决。
- [ ] 将本次已提交 Support 源码纳入新的候选构建，重新执行相应构建、签名及 IPA 校验，再按发布流程验收和分发；其他任务此前的候选 IPA 不包含这些未提交改动，不能复用其校验结论。

本次源码提交不包含 TestFlight 上传，也不代表 App 完整回归通过。Web 部署与原生构建独立记录。

> 2026-10-17 接入原生帮助、反馈、诊断缓冲、上传确认和系统邮件界面；2026-10-18 已在独占模拟器验证合成日志真实上传、回执恢复及精确清理，范围见文末。自动到期删除、系统邮件投递和旧日志迁移仍待验收。后续仅使用 iOS 模拟器。

## 当前入口与能力缺口

- 2026-10-24 新增默认开启、可在设置关闭的[截屏反馈快捷入口](./ios-screenshot-feedback.md)，只显示短暂按钮，点击后复用原生反馈页；首版不提供图片附件；2026-10-27 增加手动选择并随在线反馈提交，见本文开头。
- 此前 [MeView](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/ios/YunleFun/Features/Me/MeView.swift) 的帮助和反馈为外链。现已改用 `HelpView` / `FeedbackView` 原生导航；“我的举报”保持现有原生实现，文档、隐私与条款使用系统网页。
- 旧版 [help.vue](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/mobile/app/pages/help.vue) 提供新手引导和 FAQ；[feedback.vue](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/mobile/app/pages/feedback.vue) 提供日志范围、确认上传、清除、邮件、微信客服与评分入口。
- 此前 [CatalogStore](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/ios/YunleFun/Services/CatalogStore.swift) 的 OSLog 不等同于可上传缓冲。现由 `DiagnosticLogStore` 单独记录白名单宿主事件，不读取 OSLog 或拦截云应用的 console。
- [LegacyLocalData](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/ios/YunleFun/Models/LegacyLocalData.swift) 的白名单不含 `ylf:diagnostic-logs:v1`，升级前的诊断日志目前不会导入。原生启动后的记录与旧日志迁移必须分别说明。

## 可复用模块

| 模块                                                                                                                                                                   | 用途与边界                                                                                                                    |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| [AccountRequestAccess](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/ios/YunleFun/Services/AccountRequestAccess.swift) | UID 与 `identityGeneration` 边界、401 刷新一次、取消及切号检查；新增诊断错误类型实现 `AccountRequestFailure`                  |
| [CommunityService](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/ios/YunleFun/Services/CommunityService.swift)         | 复用实现模式：生产 origin、ephemeral URLSession、禁 cookies/cache/credentials、拒绝重定向、限制响应大小；其请求方法为 private |
| [AccountStore](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/ios/YunleFun/Services/AccountStore.swift)                 | 现有登录恢复、凭证授权、账号切换通知；不另建登录状态                                                                          |
| [QRScannerView](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/ios/YunleFun/Features/Scanner/QRScannerView.swift)       | 已有 `SafariView` 系统网页封装、`ShareLink(item: String)` 与可选择文本                                                        |
| [AssistantView](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/ios/YunleFun/Features/Assistant/AssistantView.swift)     | 已有 `UIPasteboard` 复制示例；原生邮件 composer 尚不存在                                                                      |

## HTTP 契约

依据：[上传入口](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/mobile/server/api/diagnostics/logs.post.ts)、[验证器](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/mobile/server/utils/diagnostic-logs.ts)、[鉴权](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/mobile/server/utils/cloudbase-auth.ts)。

```text
POST https://apps.yunle.fun/api/diagnostics/logs
Authorization: Bearer <CloudBase access token>
Content-Type: application/json
Accept: application/json
```

必须是正式、非匿名、active 的注册账号；不要求手机号验证。`ownerUid` 由服务端鉴权生成，客户端不提交。访客仍可联系邮件或微信客服。

| 请求字段                           | 类型与精确限制                                                                                                                                    |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `startTime`, `endTime`             | 有限 number，Unix **毫秒**，服务端截为整数；`start <= end`，跨度最多 `86_400_999ms`；开始不早于服务端当前时间前 7 天，结束不超过当前时间后 5 分钟 |
| `logs`                             | 必须 1–500 条；没有日志时不能调用此接口提交纯文本反馈                                                                                             |
| `logs[].level`                     | `log` / `info` / `warn` / `error` / `debug`                                                                                                       |
| `logs[].timestamp`                 | 有限毫秒数，归一化后必须在所选闭区间内                                                                                                            |
| `logs[].message`                   | 非空文本；原始长度大于 4000 返回 413；二次脱敏后最多保留 1500 个 UTF-16 单元                                                                      |
| `issueDescription`                 | 可选 string；非字符串视为空；trim 后最多 500 个 UTF-16 单元，服务端再次脱敏                                                                       |
| `client`                           | 可缺省；只保留下列六个 string 字段，其他字段丢弃                                                                                                  |
| `client.appVersion`, `buildNumber` | 各最多 50 个 UTF-16 单元                                                                                                                          |
| `client.platform`, `route`         | 分别最多 20、200；原生可用 `ios` 与 `/feedback`                                                                                                   |
| `client.timezone`, `userAgent`     | 分别最多 100、500；timezone 用系统时区；userAgent 可用无标识 App/OS 基本信息或空字符串，无需创建 WebView                                          |

JS 字符串限制按 UTF-16 计数，Swift 应使用 `.utf16.count`。大小上限为 **256 KiB**：脱敏日志 JSON UTF-8 字节数＋归一化 client JSON UTF-8 字节数＋trim 后描述 UTF-8 字节数；不是完整 HTTP body 大小。

成功返回结构：

```text
{ code: 0, data: { uploadId: string, supportCode: string, logCount: number, expiresAt: number } }
```

- `supportCode` 当前为 UUID 前 12 位大写十六进制；管理端接受 `^[A-Z0-9]{12}$`。`expiresAt` 是毫秒时间，上传后 7 天。
- 客户端须校验成功 code、编号格式、条数与冻结快照一致、过期时间合理；`uploadId` 在现实现中可能为空，不能作为用户唯一凭据。
- 服务端保存 `schemaVersion: 1`、`status: new`、ownerUid、范围、大小、日志、client 与创建/更新时间。
- 集合为 [ADMINONLY](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/scripts/cloudbase-rules/diagnostic_log_uploads.json)，支持人员经 [管理员接口](./cloudbase-rules.md) 查询；普通用户知道编号也不能读取。没有用户历史/回执找回接口。
- 仓库已有 [到期清理函数](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/cloudfunctions/cleanup-diagnostic-logs/index.js) 和上传后的兜底清理；文档记载每小时清理，但本次未核验线上定时器或部署。

## 账号、冻结快照与脱敏

旧版 [采集插件](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/mobile/app/plugins/diagnostic-logs.client.ts) 在启动时拦截宿主 WebView 自己的五种 console 方法；[console store](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/mobile/app/stores/console.ts) 将诊断缓冲先脱敏，再延迟 150ms 写 localStorage。它不读取 iOS 系统、其他 App 或所有子应用 WebView 的日志。

[诊断工具](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/mobile/app/utils/diagnostic-logs.ts) 保持时间升序、最多 500 条、7 天有效期，排除未来超过 5 分钟的数据；本地存储失败时仅保留内存缓冲。

脱敏顺序为 Authorization/Bearer、敏感键值、JWT、HTTP(S) URL、邮箱、16–20 位长数字、国内手机号，再截断。敏感键包含 access/refresh token、password/passwd、secret、cookie、session、q-signature/signature、token；URL 整体变为 `[redacted-url:<hostname>]`，不保留路径、参数或签名。服务端使用同一函数再次处理日志、描述和 client。

原生实现约束（已接入，验证范围见文末）：

- 从启动初始化受限文件环形缓冲，落盘前脱敏、原子写入和文件保护；沿用 500 条/7 天/1500 UTF-16 上限，并显示当前可用范围。
- 只记录宿主安全事件名、状态码、错误域/码等白名单信息；不记录请求/响应正文、凭证、账号资料、聊天内容或完整 URL。正则无法识别所有自由文本隐私和任意 UID，不能替代字段白名单。
- 对账号相关日志分区或在切号时清除，避免以新账号上传旧账号内容；现有旧版缓冲没有账号分区。
- 确认前冻结 **账号边界、范围、日志、描述、client、条数和大小**，明确展示将上传的同一份快照。确认后不得重新计算为另一份日志；切号、取消或编辑使快照失效时重新确认。
- 上传确认说明账号标识/App基本信息、仅支持人员可见与 7 天保留；无确认不得发请求。仅收集本 App 日志，不读取系统或第三方应用日志。

## 失败与重试边界

| 状态                         | 处理要求                                                            |
| ---------------------------- | ------------------------------------------------------------------- |
| 400                          | 范围、条目、格式或描述无效；保留输入并提供修正方向                  |
| 401                          | 通过账号访问边界刷新 token 后仅重试一次；仍失效则提示重新登录       |
| 403                          | 匿名或账号状态不可用；不通过刷新或改 UID 绕过                       |
| 413                          | 条数、原始单条长度或 256 KiB 超限；要求缩短范围/内容                |
| 429                          | 同 UID 上次上传不足 60 秒；当前没有 `Retry-After`，提示一分钟后再试 |
| 503 / 其他 5xx               | 鉴权或存储服务暂不可用；保留草稿并给重试入口                        |
| 超时、断网、取消、回执不合法 | 不能显示成功；切号后不接受旧结果，保留当前身份边界                  |

当前无幂等键。超时可能已经写入，不能对一般网络错误自动重传；区分“失败”和“结果未确认”，也不能自动重新上传完整日志。服务端错误文本须经安全处理，不能把原始网络错误/响应正文直接展示或再次记录。

## 最小完整原生 UI

沿用 [项目最低 iOS 16](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/ios/project.yml)，以 SwiftUI `List` / `Form` / `Section` / `DisclosureGroup` 和系统导航实现，随新系统采用系统样式；不得用 GitHub 外链替代原功能。

1. 原生帮助：新手引导、可展开 FAQ、原生设置/反馈入口；文案按当前“云居/寻乐/工坊”和已实现登录方式更新，不能照搬旧“收藏/微信登录”说明。
2. 原生反馈：问题描述、联系方式、15 分钟/1 小时/24 小时与自定义 `DatePicker`、可用范围、条数/大小、空日志和未登录状态；清除本地日志需确认并说明不影响已上传记录。
3. 上传完成后保留可选择、复制和分享的支持编号/反馈摘要，不能仅用短暂 toast；失败保留描述和范围。
4. 邮件模板保留问题、步骤、期望/实际结果、基本信息和已有支持编号。封装系统邮件 composer；`canSendMail == false` 时仍提供复制邮箱、复制/分享反馈内容，不能依赖 `mailto` 成功。发送由用户在系统界面完成，不自动附带日志。
5. 保留微信客服、业务合作、评分与社交入口；隐私/条款可用系统网页。微信客服打不开时可复制/分享链接；所有联系能力不要求登录或存在日志。

联系方式以 [links.ts](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/mobile/app/constants/links.ts) 为准：问题反馈 `kf@yunle.fun`、业务合作 `i@yunle.fun`、微信客服 `https://work.weixin.qq.com/kfid/kfc9d4dcc4b6bd1c69e`、公众号“云乐坊工作室”；评分 App ID 见 [config](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/mobile/app/config/index.ts)。

## 仅模拟器验收矩阵

- [ ] 在 iOS 16 与当前可用最新 iOS 模拟器验证原生导航、横竖屏、深浅色、最大动态字体和 VoiceOver/返回焦点；不操作真机。
- [x] 移植 [脱敏/环形缓冲](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/mobile/test/unit/diagnostic-logs.test.ts) 和 [上传校验](https://github.com/YunLeFun/apps.yunle.fun/blob/ceee732aac6dbaed547fffb6728708fb9afb2a1e/apps/mobile/test/unit/diagnostic-log-upload.test.ts) 的边界；包括 UTF-16、URL、凭证、过期、损坏文件及落盘失败。
- [x] 用隔离 URLProtocol 检查 endpoint、headers、毫秒时间、完整快照、响应校验和 401/403/413/429/5xx；切号 A→B→A、取消及断网不串号、不自动重传。
- [ ] UI 检查空日志/访客仍可联系、取消确认零请求、确认前后快照一致、清除不影响服务端回执、成功编号可复制/分享、邮件不可用和客服打开失败的兜底。
- [ ] 分开记录模拟器自动化、系统邮件/分享交互及实际后端上传的验收范围；本文不证明原生上传、线上留存或旧日志迁移已完成。

## 原生实现 · 2026-10-17

源码：[FeedbackView](https://github.com/YunLeFun/apps.yunle.fun/blob/abe06faece81487bd5a5e0d6b9817c70e56aaffe/apps/ios/YunleFun/Features/Support/FeedbackView.swift)、[HelpView](https://github.com/YunLeFun/apps.yunle.fun/blob/abe06faece81487bd5a5e0d6b9817c70e56aaffe/apps/ios/YunleFun/Features/Support/HelpView.swift)、[日志缓冲](https://github.com/YunLeFun/apps.yunle.fun/blob/abe06faece81487bd5a5e0d6b9817c70e56aaffe/apps/ios/YunleFun/Services/DiagnosticLogStore.swift)、[上传与回执](https://github.com/YunLeFun/apps.yunle.fun/blob/abe06faece81487bd5a5e0d6b9817c70e56aaffe/apps/ios/YunleFun/Services/DiagnosticUploadStore.swift)。前文旧版与复用模块链接保留盘点时的提交。

- `YunleFunApp` 创建共享 `DiagnosticLogStore`，从启动记录固定宿主事件名；账号身份通知先切换日志分区，再重置云应用运行时和云居。日志不包含账号资料、原始错误、URL、请求正文或云应用内容。
- 文件环形缓冲按账号 SHA-256 分区，访客单独保存；落盘前脱敏，7 天 / 500 条 / 1500 UTF-16 上限。拒绝父目录和文件符号链接；损坏或过大文件保留，新事件暂存内存，清除操作需用户确认且绑定当前日志代次。
- `DiagnosticUploadStore` 冻结账号代次、日志分区代次和完整脱敏 payload；只接受该确认一次。编辑、取消、清除或切号使确认失效；成功回执只显示在其账号下。上传进入服务后取消会提示“结果尚未确认”，不声称服务端回滚，也不自动重传。
- `FeedbackView` 使用系统 Form / TextEditor / Picker / DatePicker / DisclosureGroup，上传前原生 Sheet 明确展示账号、时间、条数、大小、描述和全部日志。成功后用系统提示告知支持编号，并保留编号复制、分享和到期时间。错误与复制确认补充 VoiceOver 焦点。
- `HelpView` 使用系统 List 和可展开引导 / FAQ，可前往对应 Tab、设置和反馈。邮件使用 MessageUI，由用户决定是否发送；系统邮件不可用时仍可复制邮箱、复制或分享内容。微信客服、业务合作、评分和社交入口保留。
- 回执文件只保存支持编号、条数、期限及存储元数据，不保存反馈描述或日志。原生日志与回执均指定原子写入和文件保护选项；模拟器不提供真实硬件文件保护验收。

## 模拟器验证 · 2026-10-17

- 专用 iPhone 18 Pro / iOS 27 上，首轮完整日常为 **331 通过 / 2 失败 / 0 跳过，共 333 项**：`test_sim_2026-10-17T08-25-30-020Z_pid44279_4038cd13.xcresult`。323 项单元 / 集成中 321 通过；10 条 UI 全部通过，包含帮助展开与切换 Tab、反馈输入 / 收起键盘 / 取消登录保留草稿、最大字号复制与清除确认。工具在 300 秒观察超时后继续跟踪同一测试进程，终态来自原始结果包，没有重跑后替换该结果。
- 两项新截图检查失败分别是 Vision 省略语气连接字、SwiftUI List 尚未实化的估算高度使扫描漏过目标。保留原始图片和 OCR；前者改为完整的失败语义子句，后者用公开原生末项定位并校准真实底部，再在原 10 秒预算内扫描。未缩小最大字号 / 320pt 视口，未修改生产文案或隐藏内容。
- 修正后全部页面渲染专项 **5 通过 / 0 失败 / 0 跳过**：`test_sim_2026-10-17T08-43-09-615Z_pid44279_3cd4f50c.xcresult`。最终截图完整显示“所选时间内没有本地日志。你仍可以通过邮件或微信客服反馈。”；损坏日志 / 回执文件逐字节保持，已登录入口渲染不触发上传或自动打开确认页。
- 新增 14 项日志存储、10 项真实 Service + URLProtocol、16 项上传 Store 和 4 项联系方式测试在上述完整执行中全部通过。覆盖 UTF-16 / 脱敏幂等、范围与字节预算、Cookie / 重定向策略、错误状态与仅一次 401 刷新、冻结快照、A→B→A、取消与迟到响应、符号链接、损坏文件、回执隔离及存储失败；不等于真实后端或已登录 UI 上传验收。
- 新帮助与反馈的标准 / 最大辅助字号实际 VoiceOver **4 项通过**，见[朗读与焦点记录](./ios-voiceover-validation.md#原生帮助与反馈-·-2026-10-17)。系统邮件不可用时的复制入口通过；没有发送邮件、客服消息或真实诊断。
- 同一产品源码锁包 Release 模拟器编译通过且无构建告警：`build_sim_2026-10-17T08-34-54-674Z_pid44279_ce4207da.log`。核对正式 Bundle ID `fun.yunle.apps`、最低 iOS 16、版本 `0.1.0` / 构建 `1`；此产物未安装、归档或上传。根 lint 与文档构建通过，最终完整回归及新提交 CI 另记终态。
- 最终源码完整执行为 **332 通过 / 1 失败 / 0 跳过，共 333 项**：`test_sim_2026-10-17T08-44-32-100Z_pid44279_83ad0a14.xcresult`。323 项单元 / 集成和新增 3 条支持 UI 全部通过；唯一失败是既有标准字号手机号键盘用例超过 120 秒。日志显示键盘收起检查完成后，XCTest 的动画完成通知等待及随后取消操作阻塞；根因仍待查，未提高时限、移除取消断言或重跑替换失败。该执行也超过工具 300 秒观察窗口，继续跟踪原 PID 后读取完整原始结果，不能将 runner 重启后的局部绿色摘要当作整轮全绿。

## 仍需验收

- 真实合成日志上传、线上 `ADMINONLY` 规则读回和 7 天到期字段已验证；自动到期删除、跨角色访问、系统邮件投递与客服网络连通仍待验收。
- 真实页面已验证完整确认、取消后本次记录不存在、成功提示、编号持久化恢复和系统分享预览。取消零网络请求、复制 / 分享投递及上传错误的 VoiceOver 焦点仍待独立验证。
- 真实 SwiftUI 登录提交、Sheet 消失、原稿恢复和仅一次续接已验证，见文末；硬件键盘、AutoFill、其他登录方式及系统密码保存提示仍按其独立范围验收。
- 访客日志保留在访客分区，登录后不会自动合并到账号；旧 Web 日志也未导入。不能据登录后的新日志替代访客问题发生时的记录。
- 新页面的完整深浅色系统审计、横屏 / iPad、iOS 16 运行及更多错误状态继续待验；四 Tab 既有审计失败保持原状态。

## 游客登录后的草稿续接 · 2026-10-17

反馈登录意图和登录 Sheet 移到“我”页身份重建范围之外，继续保留原有账号代次重建。用户明确从反馈页登录时，只暂存当前问题描述；认证层提交真实账号后返回绑定本次请求、登录 attempt、原身份和目标身份的结果。协调器必须等实际 Sheet 的 `onDismiss`，才进入该账号下一张全新反馈页。

续接只转移原文。时间范围、日志分区、上传 Store 和确认均重新创建；不携带旧上传快照、不自动上传。取消、外部切号、同 UID 的另一轮交互登录、过期结果和旧导航栈的迟到更新不能恢复草稿；返回“我”后再次进入反馈也不能重复恢复该意图。

账号发布与成功通知处于同一个 MainActor 执行段；普通登录仍使用原完成回调，不生成反馈续接凭据。取消按 attempt 在 Store 和认证 actor 两层核对，已取消任务在登记 attempt 前退出，避免旧登录页面的迟到任务干扰下一轮登录。

取消入口的两项反事实回归已先验证为失败：暂时移除入口检查后，已取消的旧密码 / 验证码请求均触达认证 API，并使较新的登录收到 `sessionChanged`。两项实际执行共 0.428 秒，无超时或跳过；结果包为 `test_sim_2026-10-17T09-46-37-582Z_pid44279_c48df708.xcresult`。修复随后恢复，未将该反事实失败改写为通过。

修复后新增 **43 项全部通过**（30 认证、13 协调器）。同次既有账号、认证 HTTP、授权 Broker、上传 Store、真实 Cookie 和支持页面回归合计 **93 项单元 / 集成 / 渲染检查通过，0 失败 / 跳过**，结果包为 `test_sim_2026-10-17T09-51-15-672Z_pid44279_11c7939a.xcresult`。协调器测试直接驱动其呈现状态方法，不是实际 SwiftUI Sheet 成功旅程；实际 UI 及完整新提交 CI 分别记录。后续仅使用 iOS 模拟器。

同一次执行的全部 **10 条 UI 也通过**，专项合计 **103 通过 / 0 失败 / 0 跳过**。三条支持旅程验证帮助导航、最大辅助字号的联系 / 清除确认，以及真实反馈输入、收起键盘、进入带续接说明的登录页、取消后原文保留；另七条既有导航 / 键盘 / 导入旅程通过。工具在 300 秒观察超时后继续跟踪原 PID，结果包与原日志的终态一致，没有重跑替换结果。此专项没有包含原先 Home Cookie 超时用例，也没有验证登录成功后的真实 Sheet 续接或线上上传。

同一产品源码的 Release 模拟器编译通过，无构建诊断，包含 arm64 / x86_64：`build_sim_2026-10-17T10-01-13-850Z_pid44279_56a9ea89.log`。正式 Bundle ID `fun.yunle.apps`、最低 iOS 16、版本 `0.1.0` / 构建 `1` 保持；此产物没有安装、归档或上传。根 lint 与文档构建通过；下一头提交完整 CI 仍按其独立终态记录。

## 真实登录续接增量 · 2026-10-18

使用实际原生页面、外部 UI 点击与已审计的 UIKit 输入通道，固定零余额账号登录续接 **1 通过 / 0 失败 / 0 跳过**。多行原稿完整恢复、范围回到默认 1 小时、再次新建反馈为空；实际账号管理退出后，本次 signout 成功返回且 Keychain 重读为空。前置非敏感 canary、旧通道失败及隐私审计分别留证，详见[反馈登录验证](./ios-feedback-login-validation.md#uikit-输入通道与真实登录-·-2026-10-18)。

线上诊断入口的无凭据空 JSON 请求返回 401 JSON，说明路由可达；该次没有携带账号凭据、诊断日志或创建记录。后续真实上传结果单独记录如下。

## 合成日志真实上传 · 2026-10-18

修改后的夹具重新通过 canary，随后真实登录、预览取消、明确同意上传、支持编号恢复与账号退出 **1 通过 / 0 失败 / 0 跳过，218.958 秒**。首次取消后云端本次记录为 0；再次预览实际展开两条合成日志，再确认上传，默认 HTTPS 服务返回真实回执，独立 CloudBase 读回恰好一条匹配记录。条数 2、大小 528 字节、描述及账号一致，期限字段为 7 天；线上规则为 `ADMINONLY`。

页面和系统分享预览显示同一支持编号，关闭后重新进入反馈仍能读取；未发送邮件、客服或分享消息。账号经原生 UI 退出且真实远端注销成功；本地回执恢复运行前状态，一次性凭据、私有日志和测试 Keychain 清理完成。云端按本次记录 ID、账号、编号与唯一描述精确删除 1 条，随后查询为 0。实际到期删除和上传中取消仍未验证，详见[完整旅程与证据边界](./ios-feedback-login-validation.md#真实诊断上传与清理-·-2026-10-18)。
