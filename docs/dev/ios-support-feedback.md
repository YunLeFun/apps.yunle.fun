# 原生帮助、反馈与诊断日志契约

> 2026-10-17 已接入原生帮助、反馈、诊断缓冲、上传确认和系统邮件界面。下文分别记录接口契约、实现与实际验证范围；不据源码或模拟器夹具声称实际上传、线上留存、系统邮件投递或旧日志迁移已验收。后续仅使用 iOS 模拟器。

## 当前入口与能力缺口

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
- 新帮助与反馈的标准 / 最大辅助字号实际 VoiceOver **4 项通过**，见[朗读与焦点记录](./ios-voiceover-validation.md#原生帮助与反馈-2026-10-17)。系统邮件不可用时的复制入口通过；没有发送邮件、客服消息或真实诊断。
- 同一产品源码锁包 Release 模拟器编译通过且无构建告警：`build_sim_2026-10-17T08-34-54-674Z_pid44279_ce4207da.log`。核对正式 Bundle ID `fun.yunle.apps`、最低 iOS 16、版本 `0.1.0` / 构建 `1`；此产物未安装、归档或上传。根 lint 与文档构建通过，最终完整回归及新提交 CI 另记终态。
- 最终源码完整执行为 **332 通过 / 1 失败 / 0 跳过，共 333 项**：`test_sim_2026-10-17T08-44-32-100Z_pid44279_83ad0a14.xcresult`。323 项单元 / 集成和新增 3 条支持 UI 全部通过；唯一失败是既有标准字号手机号键盘用例超过 120 秒。日志显示键盘收起检查完成后，XCTest 的动画完成通知等待及随后取消操作阻塞；根因仍待查，未提高时限、移除取消断言或重跑替换失败。该执行也超过工具 300 秒观察窗口，继续跟踪原 PID 后读取完整原始结果，不能将 runner 重启后的局部绿色摘要当作整轮全绿。

## 仍需验收

- 实际后端上传、线上权限 / 到期清理部署、系统邮件投递与客服网络连通尚未验证；本轮没有发送邮件、提交支持消息或上传真实诊断。
- 实际 UI runner 仍需验证已登录用户打开完整确认、取消零请求、成功编号提示 / 复制 / 分享，以及上传错误的 VoiceOver 焦点。HTTP / Store 测试和入口截图分别证明各自范围，不能替代这些交互。
- 取消登录会保留反馈草稿；成功登录仍会触发既有“我”导航的身份重建，草稿和原页面续接未实现。后续应使用显式、一次性的登录续接意图，并在新账号下重新准备确认，不取消身份重置或复用旧快照。
- 访客日志保留在访客分区，登录后不会自动合并到账号；旧 Web 日志也未导入。不能据登录后的新日志替代访客问题发生时的记录。
- 新页面的完整深浅色系统审计、横屏 / iPad、iOS 16 运行及更多错误状态继续待验；四 Tab 既有审计失败保持原状态。
