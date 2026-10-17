# 原生助手与受管账号验证

> 2026-10-16。SwiftUI 助手已接入现有 CloudBase Agent；本仓库的服务端加固尚未部署。生产服务验证与本地实现验证分别记录。

## 原生界面与使用流程

云居导航栏提供“AI 助手”入口，保留四个主 Tab。界面使用系统 List / Section / TextField / Button / NavigationStack / Sheet，提供问题建议、连续对话、停止、重试、新对话、复制回复、应用详情及获取。输入框随键盘与辅助字号调整。回复期间可滚动阅读历史，点击“查看最新回复”恢复跟随。

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
