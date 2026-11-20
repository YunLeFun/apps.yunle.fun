# 认证

## Universal Link

位于 `/public/.well-known/apple-app-site-association`

当前由 App 接管的路径：

- `/app/*`
- `/w/*`：个人工坊分享链接，进入 App 后映射为本地 `/w/{id}` 路由
- `/ulink/*`
- `/cards/*`：原生 iOS 共享卡片，登录后继续操作
- `/boards/*`：兼容旧版五子棋邀请

`app/plugins/deeplink.client.ts` 同时处理运行中的 `appUrlOpen` 事件和冷启动
`App.getLaunchUrl()`，避免 App 未启动时丢失目标页面。未安装 App 的用户会继续
打开同一个 HTTPS 在线页面。

> Apple 会通过 CDN 缓存 AASA。线上文件更新后，已安装设备不一定立即刷新；
> 发布新包或重装 App 后再验证最可靠。

### 辅助工具

[Apple App Site Association (AASA) Validator](https://branch.io/resources/aasa-validator/#resultsbox)

## 微信登录

云乐坊网页的 `/login` 使用现有 CloudBase `wx_open` OAuth 流程。入口默认隐藏，由 Admin「系统设置 → 登录方式」控制；刷新登录页即可读取新配置。`GET /api/login-options` 只返回 `weChatLoginVisible`，缺少配置、格式错误或读取失败时按关闭处理。

Admin 和 Apps 共用 `ADMINONLY` 的 `app_login_options` 集合；只有 Admin owner 可以修改 `web` 和 `ios` 各自的配置。网页开关只控制网页入口，开放前应先验证微信 OAuth 和 `/auth/callback`。iOS 使用独立的原生授权和绑定流程，见 [iOS 微信登录](./ios-wechat-login.md)。

## 登录方式开关配置

登录页面支持通过配置文件快速启用/禁用各种登录方式，无需修改页面组件代码。

### 配置文件

配置位于 `app/config/auth.ts`，导出 `authMethods` 对象：

```ts
export const authMethods: AuthMethodConfig = {
  phoneOtp: true, // 手机号 OTP 登录
  emailOtp: true, // 邮箱 OTP 登录
  password: true, // 密码登录
  github: false, // GitHub OAuth 登录（当前关闭）
  phoneSignup: true, // 手机号注册
}
```

### 开关项说明

| 配置项        | 类型      | 说明              | 影响范围                 |
| ------------- | --------- | ----------------- | ------------------------ |
| `phoneOtp`    | `boolean` | 手机号验证码登录  | 登录 Tab、手机号输入表单 |
| `emailOtp`    | `boolean` | 邮箱验证码登录    | 登录 Tab、邮箱输入表单   |
| `password`    | `boolean` | 账号密码登录      | 登录 Tab、密码表单       |
| `github`      | `boolean` | GitHub 第三方登录 | 第三方登录区域           |
| `phoneSignup` | `boolean` | 手机号注册入口    | 注册入口链接、注册页面   |

### 行为规则

- 当所有 Tab 类登录方式（`phoneOtp`、`emailOtp`、`password`）中仅启用一种时，Segmented Control 将自动隐藏
- 当 GitHub 和后台设置的微信入口均关闭时，「其他登录方式」区域将隐藏
- 当 `phoneSignup` 关闭时，登录页底部的「还没有账号？」注册入口将隐藏

### 辅助函数

`getEnabledLoginTabs()` 返回当前启用的登录方式列表。
