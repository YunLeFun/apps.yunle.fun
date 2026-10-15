# Apps 直接注册来源

Apps 使用独立的来源采集，与第三方应用的 SSO `acquisition` 透传分开。服务端写入动作是 `account-api.recordAppsUserAcquisition`，Admin 以 `apps` 展示入口，以 UTM 或可获得的外部 referrer 展示营销渠道。`server_verified` 表示 Apps BFF 验证了会话 UID 并通过私有内部动作写入；营销来源仍是 `client_reported`，不能证明用户跨设备的首次访问或广告平台归因。

## 已接入的路径

- Apps Web/Capacitor 宿主初始页面采集有效 `utm_source`、`utm_medium`、`utm_campaign`；Web 文档入口还可读取外部 referrer host。浏览器首次观察保留 30 天；每个新文档（包括 `/login`、`/signup`）重采注册入口，同文档无 UTM 的内部导航保留落地来源，有新 UTM 的 SPA 导航更新注册时来源。不把 `document.referrer` 重用为站内导航来源，也不把更早文档的 campaign 当作当前文档来源。
- 手机验证码登录、邮箱验证码登录、显式手机号验证码注册以及密码登录在发起认证前冻结一次来源尝试，成功验证并取得真实用户后记录。API 用 `sys_user.createdAt` 判断是否为 30 分钟内的新账号，老账号登录不会覆盖来源。
- Web GitHub/微信 OAuth 在取得 SDK 返回的授权 URL 后，绑定实际 state 再跳转；独立的 pre plugin 只保存与原尝试完全匹配的回调 state，以便 SDK 清理 URL 后仍能匹配。明确不匹配的回调会使之前的快照失效。身份绑定不创建注册来源尝试。
- Native GitHub/微信 OAuth 保留原有 `app-` state、系统浏览器和 provider-token 交换流程，来源尝试留在宿主，回调成功后记录。线上中转页面与身份提供方不成为营销渠道。
- 现有 workshop Universal Link、`yunlefun://workshop/...` 与 `yunlefun://wallet` 热启动/冷启动路径可提取有效 UTM，在本地映射为 Apps 的规范路径后采集。普通 query/hash、OAuth code/state、token 不写入来源。
- Native SSO broker 请求宿主登录时，在认证开始前冻结 `delegatedSso` 标志，跳过 Apps writer。注册成功后的 native request marker 可能已被登录页清理，因此不在回调时重新推断；由现有 Registry SSO writer 记录请求应用与它已有的来源上下文，避免先写 `apps` 抢占 Cook 等原应用入口。

当前 Web 没有对应的宿主 broker 登录跳转：`identity-broker.client.ts` 仅在 Capacitor 且 HostRuntime 可用时注册。Apps 的直接注册来源不读取 SSO 请求中的 `acquisition`、`client_id`、前端 `appId` 或 `from`。

## 身份与可靠性

客户端调用 `POST /api/users/acquisition`。BFF 使用现有 `requireRegisteredCloudbaseUser` 验证 Bearer，拒绝匿名及受限制会话，服务端 UID 是唯一写入身份。客户端的 `expectedUserId` 只是与已验证 UID 的相等条件；不一致返回不可重试的 `409 acquisition_account_changed`，不能用它选择另一个写入用户。

BFF 使用 Node SDK 调用 `account-api`，单次请求 timeout 为 1 秒、SDK retries 为 0，整个 BFF 额外限定 1.5 秒。超时后，尚未完成的身份检查不能新发起内部写入；已经发出的原始写入可以幂等完成。写入结果仅输出 allowlist 的 status/reason/code/statusCode/retryable，不返回内部 token、UID、原始异常或请求头。

客户端最多等待 1.5 秒，有限重试总共最多 3 次，两次补送分别在 0–2 秒、0–10 秒内使用 full jitter 随机退避。只在安排下一次补送时采样并保存到期时间，`online` 或会话恢复沿用原时间。原 UID、来源上下文和认证方式在首次登录成功时冻结，30 分钟内只对明确的网络/超时或服务端 `503 + retryable:true` 补送。`400/401/403/409`、未配置集合/token、未知异常、无效响应均终止；账号切换或尝试过期也终止。同一个未完成的 SDK 调用不会并发重发，晚到的旧任务不能覆盖新任务。

待补送任务在 sessionStorage 保存 UID 与来源数据，**不保存 access/refresh token**；发送时重新取得当前 session，再由 BFF 验证 UID。发送前先保存 `开始时间 + 1.5 秒 + 下一次退避上限` 的保守恢复时间，不预先抽随机数；首次明确失败或超时再保存抽样时间，原调用迟到失败沿用该时间。存储受限时回退到当前进程内存，跨整个 Web OAuth 页面跳转可能丢失，此时保持未知。`online`、认证会话恢复和有限定时器可触发原任务，页面关闭、App 被系统终止或 SDK 永不返回时仍可能漏记。这不是持久服务端队列，不承诺必达。

## 配置与发布

在 Apps Nitro 服务端配置 `NUXT_APPS_ACQUISITION_INTERNAL_TOKEN`，与 `account-api` 服务端的 `APPS_ACQUISITION_INTERNAL_TOKEN` 一致；也支持同一个来源专用的 `APPS_ACQUISITION_INTERNAL_TOKEN` 服务端变量。该凭据只允许来源写入动作，不接受通用资产服务 `ACCOUNT_API_INTERNAL_TOKEN` 作为替代。字段位于私有 runtimeConfig，禁止 `NUXT_PUBLIC_` 前缀，不需要打进 Native 静态包。Node SDK 沿用现有 CloudBase 环境、地域和服务端凭证配置。

先发布支持内部 Apps 动作的 account-api 与私有来源集合，再发布 Apps Nitro BFF 与 Web。已发布 Native 包需按原生发布流程更新前端静态资源；本次仅本地代码、测试和 Web 构建，没有部署、修改生产数据或原生 release。

上线验收使用专门的新账号核对手机号/邮箱 OTP、Web OAuth、Native OAuth、workshop UTM launch 与 Native broker 未登录注册：Admin 分母应匹配真实注册 UID，直接路径入口应为 Apps，broker 路径应为 Registry 请求应用，后续登录不覆盖。模拟临时写入失败应保持登录成功，最多 3 次；账号切换后原任务不得写到新 UID。

## 覆盖边界

无法读取应用商店安装来源、跨设备访问历史或操作系统未交付的 deferred deep link。当前只支持已经由 `resolveNativeDeepLink` 识别的 workshop/wallet 路由，不新增通用营销 deep-link 路由。宿主打开第三方应用网站时，不自动把 Apps 的来源嫁接到所有子应用；各应用仍需主动采集自己的落地参数并随 SSO 传递。

来源记录只写一次：首次未知不能被后续登录重写，超过新账号窗口的失败不能回填。缺失信息显示未知，已有 Apps/SSO 入口也不意味着存在可核验的上游营销渠道。

这里的 `firstTouch` 是当前浏览器 30 天内的首次观察，`registerTouch` 是认证开始前的入口快照，二者都不等同于 GA4 的用户、会话或事件归因模型。GA4 [来源维度范围](https://support.google.com/analytics/answer/11080067?hl=en) 区分了这些范围；[direct/none 的定义](https://support.google.com/analytics/answer/15258820?hl=en) 也包含无法取得清晰来源的访问。因此缺参数/缺 referrer 保持未知，不据此断言用户主动直接访问。Apps 排除自有域名及 SSO 往返的 referrer，只采集白名单 UTM 与域名/路径，不增加完整 URL、query、hash 或设备标识。
