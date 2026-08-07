# 原生应用授权面板设计规范

## 目的

授权面板是云乐坊 App 的可信系统界面，用于回答四个问题：哪个应用正在申请登录、将使用哪个
云乐坊账号、应用会获得哪些信息、当前操作是否产生费用。面板由宿主原生代码渲染，不允许内嵌
网页提供名称、图标、域名、权限或费用文案。

首版服务第一方单账号、单 scope 登录。后续增加长期授权、多 scope 或第三方应用时，应沿用本文
的信息顺序和数据来源，而不是在页面中另建授权弹窗。

## 视觉方向

- **风格**：Brutally minimal，克制、可信、信息优先。
- **品牌主色**：`#B3261E`，用于可信连接标识和主要操作。
- **浅暖背景**：`#FFF8F6`；暗色模式由平台动态色适配。
- **主要文字**：`#1D1B20`；次要文字：`#625B71`；分隔色：`#E7E0DC`。
- **字体**：iOS 使用 San Francisco 与 Dynamic Type；Android 使用 Material Typography 与系统
  字号缩放。授权界面不加载远程字体。
- **图标**：只使用 SF Symbols、Android 系统/Material 图标和注册表中的 HTTPS 应用图标；禁止
  使用页面传入的 emoji 作为可信应用标识。

## 信息结构

从上到下固定为：

1. Sheet 拖动指示器。
2. 身份连接：应用图标与名称 → “云乐坊认证” → 当前账号头像与昵称。
3. 标题“登录到 {应用名}”及精确注册域名。
4. 权限区：“将向 {应用名} 提供”及 scope 映射出的可读权限。
5. 可选业务提示，例如“登录本身不会消耗云币；生成春联时会另行提示消耗”。
6. 安全说明：“不会共享你的密码或云乐坊长期登录凭证”。
7. 操作区：主要操作“以「{账号名}」登录”、次要操作“使用其他账号”、取消。

长账号名在可视按钮中截断，但辅助功能标签保留完整名称。正文必须支持 Dynamic Type、系统字体
缩放和多行显示；内容超出屏幕时正文可滚动，操作区保持可达。

## 跨平台一致性

| 语义       | iOS                             | Android                          |
| ---------- | ------------------------------- | -------------------------------- |
| 容器       | `UISheetPresentationController` | Material `BottomSheetDialog`     |
| 关闭       | 下拉、取消按钮                  | 下滑、返回键、取消按钮           |
| 主操作     | Filled button                   | Filled button                    |
| 切换账号   | Tinted/secondary button         | Outlined/secondary button        |
| 字体与间距 | Apple HIG / Dynamic Type        | Material Components / font scale |

两端可以按平台调整圆角、动效、安全区和返回手势，但信息顺序、文案、选择结果与辅助功能语义必须
一致。所有关闭路径统一返回 `choice: 'cancel'`；切换账号返回 `choice: 'other'`；确认返回
`choice: 'current'`。

## 可信数据协议

`HostRuntime.confirmAuthorization` 的展示字段只由宿主身份代理提供：

- `applicationName`、`applicationOrigin`、`applicationIconUrl`：来自精确 SSO 注册表。
- `permissionDescription`：由已验证 scope 在宿主中映射。
- `authorizationNotice`：来自注册表的可选业务策略。
- `accountName`、`accountAvatarUrl`：来自宿主已验证的当前会话。

内嵌页面仍只能提交 `clientId`、`redirectUri`、scope、nonce、PKCE challenge 和 prompt。展示数据
不得从页面请求中透传。

## 状态与错误

- `ready`：展示全部可信信息并允许选择。
- `submitting`：后续若授权码签发并入 Sheet，主要按钮进入加载且禁止重复提交。
- `error`：保留面板和账号上下文，展示可重试错误；不得暴露 token 或底层异常详情。
- `dismissed`：所有手势、返回键和取消操作只结算一次，统一视为拒绝。

当前协议在用户选择后关闭 Sheet，再由宿主签发一次性 code；因此首版实现 `ready` 与
`dismissed`，并通过 `authorizationPromptActive` 防止重复面板。
