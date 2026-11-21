# 原生助手与受管账号验证

> 2026-10-16。SwiftUI 助手已接入现有 CloudBase Agent；本仓库的服务端加固尚未部署。生产服务验证与本地实现验证分别记录。

## 原生界面与使用流程

云居导航栏提供“AI 助手”入口（受下文灰度开关控制），保留四个主 Tab；进入对话页后隐藏 Tab 栏，让输入栏贴底。界面使用 NavigationStack / ScrollView / Button / Sheet 与包装 UITextView 的输入框：空状态由居中简短引导与“试试这样问”纵向建议区组成，三个示例分别配系统蓝 / FC 风格复古红 / 系统橙的单色 SF Symbol、语义正文色和分隔线，支持动态字号完整换行，辅助字号省去装饰图标与箭头；无消息时显示，点按只填入草稿并聚焦，不直接发送。AI 标识与可用发送按钮保留品牌蓝，应用图标保留原始品牌彩色。示例保留在可滚动内容中，避免占用底部输入与键盘区域，不再在助手页重复列出公开应用（“寻乐”已承担浏览）。提问以右侧气泡展示（长按可复制或修改后重新提问）；回复左对齐，流式过程中即用原生 Markdown 渲染，首字前显示三点指示，检索期间显示骨架卡片；复制、系统分享和重新生成只在最新回复下方显示，更早的回复通过长按菜单复制或分享。应用卡片整行进入详情，尾部只有一个“打开”（已在云居）或“获取”按钮。输入框为圆角多行样式，最多展开 6 行，占位“想找什么应用？”；空内容时发送按钮置灰。输入框是包装 UITextView 的 `AssistantComposerField`：软键盘“发送”键与硬件键盘 Return / ⌘Return 直接提交，Shift+Return 换行；只有键盘输入的回车会提交，粘贴（包括单独一个换行）、拖放、听写与示例问题等程序填入都只改草稿，输入法组字时的回车只确认候选。SwiftUI 纵向 TextField 无法区分键盘回车与粘贴的换行，因此改用 UIKit；样式、自动增高（最多 6 行后滚动并保持光标可见）、占位与焦点保持不变，生成中按钮变为停止；接近 4000 字时显示计数。新对话在已有内容时先确认。回复期间可滚动阅读历史，向上浏览即暂停跟随，滚回底部或点“查看最新回复”浮动按钮恢复。进入卡片详情不会停止生成；只有助手页真正出栈（以页面状态的生命周期判断，`onDisappear` 在推入详情时也会触发，出栈时 `isPresented` 仍读到 true，均不可靠）或应用进入后台时才停止。

消息区与输入区在宽窗口中居中并限制为 640pt；输入栏至少 48pt 高，发送 / 停止至少 44pt 点击范围。iOS 26+ 在原生 `safeAreaBar` 中通过 `GlassEffectContainer` 组织输入框与返回最新回复控件，早期系统使用 `safeAreaInset` 与系统栏材质。键盘展开时导航栏提供“收起键盘”，收起后保留草稿。

访问提示收为输入框下方脚注，整行提供至少 44pt 的操作范围，大字号放不下时纵向排列：访客“AI 助手为会员功能 · 登录”、非会员“需要有效会员 · 查看会员”、核对中显示进度。现有 app-discovery 是关键词检索服务，并不调用通用大模型，因此没有加入“换一批”“再具体点”之类依赖模型改写的追问胶囊。

## 历史对话

登录账号的对话保存在本机：Application Support/Assistant/<sha256(uid)>.json，每个账号一个文件，文件名不含账号 ID，写入使用 completeUnlessOpen 文件保护并排除在 iCloud / iTunes 备份之外。每段对话以 threadId 为标识，标题取首个提问前 40 个字，保存更新时间与消息（流式中的回复存为“已停止”，失败 / 停止原样保留，不保存工具进度）；最多 20 段、单文件 2 MiB，按更新时间倒序。一次回复结束（完成、停止或失败）以及开始新对话前保存，内容未变化时不重写，避免打开旧对话就改变排序。导航栏“历史对话”打开列表，可左滑删除、清除全部（需确认）或点开继续同一线程。访客不保存；切换账号后只显示当前账号的历史；退出并移除账号时删除该账号的文件。

## 入口灰度开关

Web 服务公开提供 `GET /api/features`，返回 `{ "assistant": { "audience": "members", "percent": 100 } }`，`Cache-Control: public, max-age=300`，不含账号或名单。取值来自 Nuxt runtimeConfig：

| 环境变量                         | 取值                                                                                     | 默认                          |
| -------------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------- |
| `NUXT_ASSISTANT_AUDIENCE`        | `off`（全部隐藏）/ `members`（有效会员）/ `signedIn`（已登录账号）/ `everyone`（含访客） | `members`，非法值按 `members` |
| `NUXT_ASSISTANT_ROLLOUT_PERCENT` | 0–100，在上述人群内按账号稳定分桶放量                                                    | `100`，越界截断               |

修改后重新部署 Web 应用即可；iOS 在下次启动或回到前台（间隔不少于 5 分钟）时拉取，失败时沿用上次成功值（UserDefaults `assistantRolloutAudience` / `assistantRolloutPercent`），从未成功时使用内置默认“会员 100%”。分桶为 SHA256("assistant:" + uid) 前 4 字节取模 100，提高百分比只会新增账号；访客没有稳定标识，只有 `everyone` 且 100% 时可见。members 人群在会员状态未知时不显示入口，云居会在需要时读取一次账户快照。开关只决定入口是否出现，会员校验仍由服务端在每次请求时执行。调试或 UI 测试可用启动参数覆盖，例如 `-assistantRolloutAudience everyone -assistantRolloutPercent 100`。

访客发送问题时进入带用途说明的原生登录页；取消后保留当前草稿。会员状态通过新的账户快照核对；非会员可打开会员页，账户受限、服务故障和会员过期分别处理。切换或退出账号后，旧草稿、对话和迟到的响应均不能进入新身份，包含 A → B → A 的情况。

回复通过原生视图展示 Markdown 标题、正文、列表、引用和代码；保留流式内容中的空格、换行和 Unicode。只允许 HTTPS 链接，不执行 HTML，也不自动加载模型给出的远程图片。应用卡片只接收最小标识与说明，再匹配公开目录；网址、价格、权限和打开动作始终使用目录与现有获取流程。

## 网络与协议

使用 URLSession.bytes、无 Cookie / URLCredentialStorage / 磁盘缓存的临时会话，拒绝重定向。宿主 Bearer 只发送给固定 CloudBase 网关或受控 Apps 接口，不进入 WebView。停止、离开页面和退到后台会取消本机网络任务。服务端已接收的尝试仍可能计入每日次数。

接收标准 SSE 的 UTF-8、BOM、CR / LF / CRLF、多行 data、注释与空格规则；验证 AG-UI threadId / runId、消息生命周期和搜索工具关联，兼容旧 content / reasoning_content 及显式 [DONE]。思考过程只作为状态显示，不并入回复。仅允许确认结束的回复成为成功状态，缺少结束事件的断流显示为中断。流内鉴权错误不会自动重放请求。

每个事件 / 行上限 512 KiB，流总量 2 MiB，回复正文 64 KiB，卡片最多 6 个；缓冲溢出明确失败，不能静默丢事件。输入最多 4000 UTF-16 单元，网络历史最多 32 条并受 128 KiB 请求限制。会话只驻留内存，累计长度设有上限。

保留现有环境 yunlefun-8g7ybcxc7345c490 和 Agent agent-yunlefun-1g1ef4a470aefe98。现有 app-discovery 是关键词 / 模糊应用检索服务，并没有调用通用大模型；本次没有新增模型、AI 计费或云资源。

## 服务端改进与部署边界

agents/app-discovery 分离 HTTP 处理与启动代码：注册身份与账户限制使用真实 user/me 和规范 account-api 快照；会员要求有效到期时间；用 CloudBase 事务检查每日次数，读取失败不能重置计数，不能并发越限。流开始后失败发送 RUN_ERROR 并结束，不能再次写 JSON 响应头。历史与体积先校验；不打印访问令牌、对话和上游错误原文。

搜索只使用已发布的公开市场投影，不能读取私人草稿或把应用本地 slug 当作市场标识；Agent 公开目录请求不转发用户凭据。Apps 搜索备用接口同样要求注册用户，并使用公共目录解析器。这些加固已在本地验证，尚未部署；现网助手成功响应并不能证明新鉴权与事务代码已上线。

## 会话里的公开联机房间

在 iOS 助手发送「找联机房间」会查询 Play 的公开目录，返回最多三张房间卡。会员与历史沿用助手的现有流程，房间查询由客户端直接完成。卡片保存房间引用，历史对话打开时重新读取状态。

Android 可读取 `packages/app-core/contracts/conversation-card.v1.schema.json`，Web 可使用同一个包的 `@yunlefun/app-core/contracts/conversation-card.v1.schema.json` 导出。每张 `play.public-room` 卡片的 `id` 是 `play-room:` 加 `payload.inviteCode`。未知类型、版本或无效引用展示 `fallbackText`。

公开快照沿用 `GET https://api.play.yunle.fun/v1/rooms/public`，响应为 `{ ok: true, rooms: [...] }`。每个房间包含 `inviteCode`、可空的 `gameId`、`status`（`waiting`、`playing`、`completed`）、`memberCount` 和 `capacity`。客户端按房间号关联卡片和快照。Web 使用 `https://play.yunle.fun/room/<inviteCode>` 进入，观战时加 `?role=spectator`。

助手页面可见、处于前台且有房间卡时，共用一次前台轮询。成功后间隔 5 秒，连续失败时退避到最多 30 秒。座位条显示公开接口的房间成员数与容量。公开列表会省略满员、下架或不再具备展示条件的房间，因此缺席显示「房间暂不在公开列表」。等待或结算中的房间走玩家入口，对局中的房间走观战入口，登录、房态与席位仍由原有 Play 进房流程确认。

## 通用原生会话卡片

组队报名和联机棋盘共用 [ConversationCard v2](../../packages/app-core/contracts/conversation-card.v2.schema.json)。新消息保存 `type`、`payload.instanceId` 和 `fallbackText`，`id` 由类型、冒号和实例 ID 拼成。iOS 能从两种旧 v1 引用恢复同一卡片。旧客户端收到 v2 消息时显示摘要。当前客户端遇到未支持的模板版本或组件也显示摘要。

`GET /api/conversation-cards/<type>/<instanceId>` 返回一份面向当前登录用户的快照。快照包含独立版本的模板、数据、动作状态和单调递增的 `revision`。模板按数组顺序渲染标题、文本、席位条、按钮或专用五子棋 Canvas。标题和席位从 `data` 读对应字段。按钮由 `actions` 声明标签和是否可用，省略动作时隐藏按钮。报名模板在服务端配置。棋盘用同一份模板嵌入 `gomoku` 组件，移动和点按反馈在各端本地渲染。

若连接 SSE，向同一地址的 `/events` 发送带 Bearer 的 GET。连接先发完整快照，随后推送更高的 `revision`。服务端约每 2 秒检查报名状态，每 1 秒检查棋局状态。连接约 20 秒轮换，重连直接拿到最新快照。Web 可用带 `Authorization` 请求头的 `fetch` 流式读取。

在同一资源上用 PATCH 提交 `schemaVersion: 1`、`action`、`expectedRevision` 和 UUID v4 的 `actionId`。当前动作是 `signup.join`、`signup.cancel`、`board.join` 和 `board.place`。只有落子还需要 `input: { row, column }`。服务端通过报名和棋局事务校验资格与版本并回传完整快照。冲突时客户端重新读取。

分享使用 `https://apps.yunle.fun/cards/<type>/<instanceId>`，浏览器落地页的原生入口为 `yunlefun://card/<type>/<instanceId>`。iOS 复用账户恢复和登录续接，完成登录后打开原卡。安卓和 Web 可沿用路径及接口。旧棋盘 `/boards/<boardId>` 链接、旧的创建和业务读取接口继续兼容。首版由服务端注册两种卡片模板，发布时沿用已有报名和棋局集合权限。

## 会话里的组队报名

发送「创建组队报名」创建默认四人队，也可发送「创建组队报名 6 周末联机」指定人数和标题。用卡片的「分享卡片」发送通用链接。旧的「`打开组队报名 <signupId>`」指令也可打开同一张卡。

共用 JSON Schema 的 `team.signup` 类型固定为 `schemaVersion: 1`，卡片 `id` 由 `team-signup:` 加 `payload.signupId` 组成。报名接口使用现有云乐坊 Bearer 鉴权，请求路径为 `/api/team-signups/<signupId>`。`PUT` 用 `{ title, capacity }` 创建，`GET` 读取，`PATCH` 用 `{ joined: true }` 报名或用 `{ joined: false }` 取消。三个请求成功时返回 Schema 中的 `teamSignupSnapshot`。满员返回 HTTP 409 和 `SIGNUP_FULL`。

服务端以同一份 CloudBase 文档做事务，重复操作返回当前快照，真实变化增加 `revision`。通用卡片通过 SSE 读取并按版本更新。旧接口的 `joined` 由当前登录身份决定。部署时先创建 `conversation_team_signups` 集合并应用同名 `ADMINONLY` 规则，再发布 Nitro 路由。

## 会话里的联机棋盘

在 iOS 助手发送「创建联机棋盘」开始一局 9×9 五子棋。创建者执黑，卡片通过通用 `/cards/play.board/<boardId>` 链接分享。iOS 通过 Universal Link 打开同一局，访客完成登录后返回棋盘。空席可加入执白，两席占满时可直接观战。轮到自己时点按空交点即可落子，也可以把棋子从棋盘下方拖过去。VoiceOver 提供行、列和落子控件。SwiftUI Canvas 使用 iOS 16 可用接口。「减少动态效果」启用时即时显示回合切换。

旧的 `/boards/<boardId>` 与 `yunlefun://board/<boardId>` 仍会续接到原棋局。原「打开联机棋盘 <boardId>」指令仍可在助手里使用。

三端共用 [ConversationCard v1](../../packages/app-core/contracts/conversation-card.v1.schema.json)。`play.board` 的 `id` 是 `play-board:` 加 `payload.boardId`。消息只保存棋局引用和降级文案。快照里的 `scene` 单独版本化，声明方格尺寸、纯色画布、线条、两种棋子配色和拖放动作。交点使用从左上起算的零基 `row` / `column`，横纵均以 `size` 为上界。绘制时按棋盘尺寸划分等宽单元，交点位于单元中心。渲染器实现这些动作和绘制指令，服务端应用规则。

所有接口复用云乐坊 Bearer 鉴权与 `private, no-store`。端点 `/api/boards/<boardId>` 支持以下操作。

- `PUT` 用 `{}` 创建默认棋盘，或传 `{ "scene": ... }` 创建自定义版本 1 场景。同一创建者可重试，棋局使用创建时的场景版本。
- `GET` 获取针对当前身份的 `boardSnapshot`。`seat` 为 `null` 表示观战者，`pieces` 按落子先后排序。
- `PATCH` 用 `{ "action": "join" }` 执白，或发 `{ "action": "place", "row": 4, "column": 4, "expectedRevision": 2, "actionId": "<uuid-v4>" }`。满席、过期版本、重复占位都由事务校验；已接受的同一落子指令可重试。
- `GET /api/boards/<boardId>/events` 返回 UTF-8 SSE。每次连接先给完整快照，随后推送更新后的快照，`revision` 单调增加。服务端间隔约 1 秒（等待加入时约 2 秒）读取共享文档。20 秒后重连，断线后直接恢复到最新快照。Web 可使用带 `Authorization` 请求头的 `fetch` 流式读取。

开局后执黑先落，交替在空交点落子，横、竖或斜线连成至少五子即获胜，棋盘填满则判和。此卡有独立的会话棋局 ID。部署时在服务端创建 `conversation_boards` 集合并应用同名 `ADMINONLY` 规则，再发布 Nitro 路由和原生客户端。

## 受管测试账号

经用户授权，通过 Admin 复用 production-standard、production-member-active、production-zero-balance 三个 ready 固定合成账号。未新建常驻账号、重置余额或修改会员。发现会员测试号的加密主凭据与认证端不一致后，使用既有受管凭据轮换服务修复该号，保留审计；其余账号密码未变。

主凭据只保存在仓库外 ~/.config/yunlefun/test-accounts.json，权限 0600。测试从专用模拟器缓存一次性读取后立即删除输入文件，不把密码或令牌放入聊天、源码、启动参数、测试附件或日志；会话令牌使用独立 Keychain service。测试结束撤销本次会话并清除测试 Keychain 项。

YunleFunLiveValidation Scheme 的 ManagedAccountLiveTests 必须显式传入 YUNLEFUN_LIVE_FIXED_ACCOUNTS=1，并预置上述受管输入，默认跳过。它使用真正的 AccountStore / AccountSession / CloudbaseAuthService / WalletService / AssistantStore，没有替换认证、钱包或 Agent 响应。

iOS 27 已验证三个账号的密码登录、user/me、强制刷新、多账号切换、Keychain 新会话恢复、钱包和流水读取、远端退出和退出后重启；会员号完成一次真实助手回复，工具卡片均能在当前公开目录解析。没有发送短信或邮件、修改个人资料、购买或恢复真实内购。登录表单的真实凭据输入 UI、验证码与图片防护、跨设备、真机和旧版覆盖升级仍待验。

## 验证状态

- 原生协议 / 网络 / 状态测试覆盖 UTF-8、SSE 边界、断流、真正的流式取消、身份切换、失败重试与卡片信任边界。
- 原生浅色、深色辅助字号回复与卡片使用隔离样例渲染，不计为真实账号 UI 验收。
- Agent 的 Node 测试 17 项、移动端单元测试 638 项和类型检查通过。
- 真实云居同步仍取决于 GET / PUT /api/home-screen 部署；同样不能把尚未部署的应用获取、发布或其他加固视为现网能力。
- 完整 VoiceOver、iPad、真机、性能、正式签名、Sandbox 和升级兼容仍未验收，原生迁移 Goal 保持进行中。

协议参考：[CloudBase 密码登录](https://docs.cloudbase.net/en/http-api/auth/auth-sign-in)、[CloudBase Agent 消息](https://docs.cloudbase.net/en/http-api/ai-bot/send-message)、[AG-UI 生命周期](https://github.com/ag-ui-protocol/ag-ui/blob/main/docs/concepts/events.mdx)、[SSE 标准](https://html.spec.whatwg.org/multipage/server-sent-events.html)。

验证补充：iOS 27 助手访客登录取消 / 草稿保留 / 再进入旅程通过；iOS 18.6 的 22 项助手专项测试通过并已导出截图，随后该运行时与专用设备不可用，最后一条 iOS 18.6 点击旅程未能启动，仍列为待验。Web 生产构建、文档构建和 unsigned arm64 Benchmark 构建通过；后者不代表正式签名或真机运行通过。按 CloudBase AUTH001 / SEC001 核对现有 HTTP 身份验证、匿名拒绝与敏感运行时数据不回显，未增加集合或改动安全规则。

## 2026-10-27 排版复核

将引导与示例问题拆开，三个问题在默认字号下完整呈现，辅助字号省去装饰图标与箭头、保留完整换行；输入区不再承载示例列表。输入栏至少 48pt，发送 / 停止提供 44pt 的实际可命中区域（通过 `contentShape` 包括留白），访问提示整行可操作。宽窗口将内容与输入居中限制为 640pt。原生导航在编辑时提供收起键盘操作。

实际点按输入框暴露了焦点同步竞态：UIKit 已开始编辑，延迟回写的绑定仍可能让 SwiftUI 排队收起键盘。现改为及时发布焦点事件，异步焦点请求执行前再次核对最新绑定，避免过期请求关闭刚激活的输入框。

复用已有 iPhone 18 Pro（`4502D5E9-9630-4AF0-9050-3C9109139FD0`，iOS 27.0），未创建临时模拟器。首次排版复核分两轮通过 13 项专项：输入行为 5 项、浅色 / 深色辅助字号 3 的引导与回复及历史页渲染 5 项、UI 旅程 3 项。UI 检查包括 Tab 栏隐藏、默认字号下三个示例完整可见、发送区域至少 44pt、输入与发送位于实际软件键盘上方、收起后草稿保留，以及示例填入 / 回车发送 / 登录取消 / 粘贴换行。初次发现的 30pt 命中区域和直接点按失焦均修复后复测通过。

本机截图与摘要保存在 `apps/ios/build/artifacts/assistant-layout-20261027/`，包括实际导航下的浅深色空态、实际软件键盘、隔离样例的大字体与回复，以及两轮最终测试摘要。测试为访客及隔离样例，未发送真实会员请求。iPad 真实窗口、横屏、最大辅助字号、VoiceOver、最低系统和真机仍待验；本轮未发布或安装手机构建。

三色方案复核采用开发工具蓝、好玩应用紫、灵感工具橙，每个符号只使用一种系统色；AI 标识与可用发送按钮保留品牌蓝，应用品牌图标保留原色。完整重跑 14 项专项全部通过：输入行为 5 项、浅深色 / 大字体 / 历史渲染 6 项、真实 UI 旅程 3 项。XcodeBuildMCP 等待总时长超限后，继续读取同一次底层 Xcode 运行，结果包确认为 Passed、14 通过 / 0 失败 / 0 跳过，无运行时警告。最终本机图片与摘要保存在 `apps/ios/build/artifacts/assistant-color-20261027/`。

游戏入口随后采用 FC 风格复古红，浅色为 `#A62B32`、深色提亮为 `#E87880`，仍使用同一单色 SF Symbol；开发工具蓝、灵感工具橙保持不变。该配色的浅深色默认字号实际渲染 2 项通过，本机截图与摘要保存在 `apps/ios/build/artifacts/assistant-fc-red-20261027/`。

设计依据：[Apple HIG 布局与安全区](https://developer.apple.com/design/human-interface-guidelines/layout)、[原生玻璃控件组合](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)。
