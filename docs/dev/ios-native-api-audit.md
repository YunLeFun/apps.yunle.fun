# iOS 原生接口盘点

> 2026-10-16。根据当前工作区代码、CloudBase 官方 Auth OpenAPI 与只读请求结果记录；已使用受管合成测试账号进行真实认证与账户读取；会员测试号凭据已审计修复，没有发送验证码或执行真实支付。

## 已验证的访问路径

| 范围           | 当前实现                                                          | 原生接入与证据                                                                                                                                                                                                                 |
| -------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 公开目录       | `GET /api/apps/public`                                            | 生产请求 HTTP 200，返回 `{ items }`，本次观测到 25 项；Swift 已按真实字段解码                                                                                                                                                  |
| 公开详情       | `GET /api/apps/public/{key}`                                      | 源码支持记录 `_id` 或 `marketShortName`，不能把所有旧 `slug` 都视为全局标识                                                                                                                                                    |
| 私有业务鉴权   | `server/utils/cloudbase-auth.ts`                                  | 从 Bearer token 调用 CloudBase `user/me` 确认身份，再派生 uid / 权限；Swift 无需复用浏览器 Cookie                                                                                                                              |
| 个人工坊       | `/api/workshops/*`                                                | 原生创建 / 设置 / 坊客 / 加入页面及协议已接入；mine / joined 无凭据返回 401，当前未知 ID 返回 404；正式账号成功请求仍待验，见[工坊记录](./ios-workshops.md)                                                                    |
| 本人应用与发布 | `/api/apps/mine*`、`/api/apps/submissions` 等                     | 原生列表 / 编辑 / 图标 / 投稿 / 下架与协议已接入，访客入口在 iOS 27 / 18.6 通过；后端修正未部署，真实保存 / 上传 / 投稿 / 下架与审核变化仍待验。见[应用管理与发布](./ios-publishing.md)                                        |
| 评论与举报     | `/api/reviews`、`/api/reports`                                    | 原生列表 / 表单与账号边界已实现，真实公开读取和访客取消在 iOS 27 / 18.6 通过；后端加固尚未部署，真实写入 / 审核 / 个人历史仍待联调。见[评价与举报](./ios-community.md)                                                         |
| 宿主 SSO       | `POST /api/auth/sso/resolve`；CloudBase Functions OpenAPI         | 已接原生 broker、原生登录回跳与共享授权面板，真实 AI 春联访客取消 / 再试通过；正式账号签码仍待联调。见[授权接入](./ios-host-authorization.md)                                                                                  |
| 云居同步       | 旧版 JS SDK；新增 `GET /api/home-screen` / `PUT /api/home-screen` | Swift、本地离线模型、冲突界面与事务适配器已有测试；本地 JSON 401 验证通过，本地完整服务 + 受管账号真实读写、断网恢复与冲突验证通过；生产部署 / 跨硬件 / 旧版并发仍待验。见[同步契约](./ios-home-sync.md)                       |
| 推荐与周榜     | `useDiscovery.ts` 直查 `featured_apps` / `weekly_charts`          | 尚待 HTTP 入口；原生当前只展示真实目录官方作品，不伪造推荐运营数据或排名                                                                                                                                                       |
| 资料与账号     | CloudBase Auth HTTP API                                           | 已有 Swift 服务、Keychain、验证码 / 密码登录、图片验证、多账号和基础资料 UI；iOS 27 三个受管账号真实密码登录 / 刷新 / 切换 / 恢复 / 退出通过，验证码与资料写入待验                                                             |
| 钱包与购买     | `account-api` / `iap-order` / `wxpay-order` 云函数                | 已核对外部源码、安装的共享类型与 Functions OpenAPI，原生钱包 / StoreKit 2 已接入，两系统本地 StoreKit 和访客旅程通过；iOS 27 三个受管账号真实账户与流水读取通过，Sandbox / 外部归属契约仍待验，见[钱包与会员](./ios-wallet.md) |
| 应用获取       | 新增 `POST /api/apps/acquisition`                                 | 原生条件 / 云币确认及本地服务端核价 / 已购读取已实现；接口未部署，真实购买 / 使用与外部专用权益契约仍待验，见[原生应用获取](./ios-acquisition.md)                                                                              |
| AI 助手        | 现有 JS SDK 与 Agent 接口                                         | 原生流式协议、停止 / 重试、会员门控及工具卡片已接入；iOS 27 受管会员号真实请求通过，服务端加固未部署，见[助手记录](./ios-assistant.md)                                                                                         |

公开目录中包含 `invite_only` 等使用条件，公开可见不等于可匿名使用。Swift 默认拒绝未知的非 `public` 访问方式，保留会员 / 云币门控，不从本地 UI 推导真实购买权益。

## CloudBase Auth 契约

原生客户端不使用 CloudBase Web SDK。已通过 MCP `searchKnowledgeBase(mode="openapi", apiName="auth")` 读取官方协议，环境为现有国内上海环境 `yunlefun-8g7ybcxc7345c490`，网关为 `https://yunlefun-8g7ybcxc7345c490.api.tcloudbasegateway.com`。

| 操作       | 正式协议                                                                                                  |
| ---------- | --------------------------------------------------------------------------------------------------------- |
| 验证码发送 | `POST /auth/v1/verification`，提供手机号或邮箱与 `target`；保留验证码防护与频率限制                       |
| 验证验证码 | `POST /auth/v1/verification/verify`，传 `verification_id`、`verification_code`，获得 `verification_token` |
| 登录       | `POST /auth/v1/signin`，密码与验证码模式互斥；验证码模式使用前一步 token                                  |
| 注册       | `POST /auth/v1/signup`，具体字段按官方 schema 与现有注册流程核对                                          |
| 刷新       | `POST /auth/v1/token`，`grant_type=refresh_token`；旧 refresh token 轮换失效，必须合并并发刷新            |
| 读取身份   | `GET /auth/v1/user/me`，使用 Bearer access token；无凭据请求已确认 HTTP 401                               |
| 退出       | `POST /auth/v1/user/signout`；需结合业务宿主登出、Keychain、缓存与云应用身份会话清理                      |

本轮通过 `DescribeLoginConfig` 只读核实当前环境：手机号、邮箱与用户名密码登录均开启，匿名登录关闭；未修改 provider。现有客户端微信与 GitHub 开关当前关闭，本次不新增其登录入口。

Swift 按正式协议发送：密码模式为 `username` 与 `password`（手机号按既有 SDK 格式化为 `+86 138…`）；验证码发送使用 `target=ANY`，验证后已有用户 `signin`，新用户 `signup`，与当前 Web SDK 的登录或注册行为一致。图片验证分别使用 `captcha/data` 与 `captcha/data/verify`；只有服务端要求时才展示，并通过 `x-captcha-token` 重试用户刚才的动作。退出使用 Bearer 与空 JSON，不发送协议不存在的 `refresh_token` 字段。基础资料编辑使用 `user/basic/edit` 的 `user_id`、`nickname` 与 `description`。

上述参数、错误、令牌轮换和身份竞态已用 XCTest 验证。2026-10-16 新增显式启用的受管合成账号测试：iOS 27 三个账号密码登录、强制刷新、多账号切换、Keychain 恢复、账户与流水读取、远端退出、退出后重启通过；会员号真实助手请求通过。验证码 / 图片防护、资料写入、真机与旧版升级仍待验，见[验证记录](./ios-assistant.md)。

## 数据与身份约束

Swift 保留 `_id` 作为记录身份，使用 `marketShortName` 构建公开链接；旧云居的 slug / 历史别名需在迁移时映射，不能把私人空间内 slug 当作全局唯一标识。

本地云居已接入账号目录切换，访客使用独立命名空间；切换时先清空旧投影，再读取新目录。访客数据不会自动合并到账号。JSON 损坏时报告错误并保留原文件，不用空状态覆盖。

账号凭据与设备标识保存在单个版本化 Keychain 项，保护级别为 `AfterFirstUnlockThisDeviceOnly`，不进入云居 JSON、UserDefaults 或日志。单账号并发刷新合并；轮换后的凭据须安全保存后才交给业务请求。若 Keychain 临时写入失败，保留新令牌在内存中重试保存，避免再次使用已消耗的旧 refresh token。离线失败保留账号，明确失效才移除；退出先处理本地身份，远端失败单独提示。账号变化会撤销运行时中的待授权请求、结束旧会话，并等待既有第一方身份 Cookie 允许名单清理完毕后开放新会话。

账号变化处理有一个受限例外：已验证注册策略、正在等待原生登录的访客授权可保留原网页，结束其他会话并等待身份 Cookie 清理；登录后重新核对策略，始终再作一次明确确认。已登录账号的切换 / 退出没有此例外，不合并访客云居，详见[授权接入](./ios-host-authorization.md)。

新增云居 / 推荐等接口时，继续使用既有服务端身份校验和目录可见性规则；客户端不得靠自报 uid 获得读取或写入权限。
