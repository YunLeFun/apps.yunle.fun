# iOS 微信登录

Admin → 系统设置 → 登录方式分别管理 Web 和 iOS。`app_login_options/ios` 缺失或读取失败时关闭。安装了微信的 SDK 构建才会读取 `sso-ticket` 的可用状态；服务端还要求独立的移动应用凭据和 SSO 签票配置有效。开关关闭后，已绑定的用户仍可在个人资料解除绑定。

首次使用时，先用原方式登录云乐坊，在「个人资料」绑定微信。后续可通过微信登录同一 CloudBase UID。网页 `wx_open` 与云食册的绑定独立；未绑定的微信不自动注册或合并账号。沿用既有 SSO 手机号及账号状态校验，绑定和登录前均需符合现有准入条件。解绑阻止后续微信登录；已建立的登录会话按正常退出流程处理。

- OpenSDK 只在用户选择授权后注册与调起微信；本次回调须匹配短时随机 state。服务端只用云乐坊移动应用 AppID 换码，原始微信标识、授权码和微信 token 不入库；只保存独立密钥计算的摘要和 UID。一次性授权码的摘要沿用 SSO 限流集合与清理任务。
- `sso-ticket` 校验本人会话、双向绑定、账号状态和手机号后签发 custom ticket。Swift 使用现有 CloudBase 会话层兑换票据、确认 UID、写入 Keychain 并延续原登录上下文。

上线顺序：

1. 在微信开放平台确认云乐坊移动应用 `wx925d6e320d64f30a` 已开放 iOS 微信登录，Bundle ID 为 `fun.yunle.apps`，Universal Link 登记为 `https://apps.yunle.fun/auth/wechat/`（保留尾斜线）。网页侧发布该路径和 AASA 后，验证 Apple CDN 及真机回跳。
2. 在和 Admin 相同的 CloudBase 环境创建 `sso_apps_ios_wechat_bindings`，权限 `ADMINONLY`，为 `uid` 建非唯一索引供注销清理；复用现有的 `app_login_options` 和 `sso_security_limits`。先部署 `YunLeFun/api` 的 `account-api` 注销清理，再部署 `YunLeFun/www.yunle.fun` 的 `sso-ticket`，保留既有路由和环境变量。
3. 只在 `sso-ticket` 服务端配置 `APPS_IOS_WECHAT_APP_SECRET`（该移动应用的 AppSecret）和 `APPS_IOS_WECHAT_BINDING_KEY`（独立、持久的 32 字节随机值，64 位十六进制）。轮换 AppSecret 时保留绑定密钥。不要更改网页微信 Provider 和云食册配置。
4. 发布 Admin 和 iOS 新版，先保持 iOS 开关关闭。Release 的 iPhoneOS 构建包含校验固定 SHA-256 的官方 OpenSDK 及隐私清单；模拟器和默认 Debug 不链接此设备库。先在具备配置的隔离环境、装有微信的 iPhone 上检查绑定、身份一致、取消、重复回调、解绑、账号注销及 Apple 登录审核要求，再通过 Admin 开启生产入口。

回滚时关闭 Admin 的 iOS 开关即可；现有网页、云食册和其它登录方式继续使用各自配置。
