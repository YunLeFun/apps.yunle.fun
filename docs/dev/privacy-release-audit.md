# iOS 发布隐私与协议核对（2026-07-26）

> 范围：当前仓库代码、iOS 工程与已归档 App，以及线上
> [隐私政策](https://www.yunle.fun/docs/privacy-policy) /
> [软件许可及服务协议](https://www.yunle.fun/docs/terms-of-service)。
>
> 本文是发布核对与修订草案，不替代法律意见，也不直接修改线上法律文本。

## 结论

- 两个线上 URL 均可公开访问并返回 HTTP 200。
- 隐私政策已覆盖手机号/邮箱、一般设备与日志信息、境内存储、删除/注销/副本权利、未成年人、生效/更新日期。
- iOS `Info.plist` 已配置相机与相册用途说明；工程未申请定位权限。
- **公开上架前仍有阻断项**：线上隐私政策与实际处理活动不完全一致，第三方处理方、RUM、AI、IAP、用户内容和本地存储披露不足；App Store Connect 隐私标签也必须与下面的矩阵一致。
- 现行协议有一般用户行为、违约处理、知识产权、免责和争议解决条款，但缺少云应用/工坊、内容审核下架、开发者授权、AI 输出与 IAP 交易的专项规则。

## 代码事实清单

| 类别       | 当前实际行为                                                                                      | 数据去向/位置                                              | 是否离开设备 |
| ---------- | ------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- | ------------ |
| 账号       | 手机号、邮箱、用户名、昵称、头像、CloudBase UID、微信 OpenID/UnionID                              | 腾讯云 CloudBase（上海）/ 微信 OpenSDK                     | 是           |
| 会话       | access token、refresh token、用户资料镜像、记住的登录账号和完整手机号（Base64 仅为混淆）          | Cookie / WKWebView localStorage；认证请求发送 CloudBase    | 部分         |
| 云居与目录 | 已安装应用、Dock、最近使用、排序、云同步设置、购买过的应用                                        | 本地存储；开启同步后写 CloudBase                           | 部分         |
| 工坊与社区 | 应用资料、评论、评分、举报理由及详情、审核结果                                                    | CloudBase；评论/举报文本会经过腾讯云 TMS                   | 是           |
| AI 助手    | 用户提示词、会话 ID、历史消息、工具调用上下文、AI 回复                                            | CloudBase AI Bot/所配置模型服务                            | 是           |
| IAP        | product ID、transaction ID、购买/恢复结果、会员与云币流水                                         | Apple StoreKit；transaction ID 发送 `iap-order` 服务端核验 | 是           |
| RUM        | 页面 URL/PV、Aegis `aid`、登录后的 CloudBase UID、JS/Promise/资源错误、接口与资源测速、Web Vitals | 腾讯云 RUM（广州）                                         | 是           |
| 扫码       | 相机画面或用户选择的相册图片                                                                      | 当前代码仅在设备上识别；没有上传路径                       | 否           |
| 内嵌云应用 | 用户打开第三方网站，网站可能按自身规则使用 Cookie/网络请求                                        | 对应云应用运营者                                           | 取决于第三方 |

补充事实：

- `aegis-web-sdk` 会在 localStorage 写入持久化 `aid` 用于 UV；代码还会在登录后把 CloudBase UID 设置为 RUM `uin`。
- 当前代码没有调用定位 API，也没有 `NSLocation*UsageDescription`。
- 当前代码没有证据表明读取 IMEI、Android ID、IDFA 或 IDFV。
- 相机/相册权限说明位于 `ios/App/App/Info.plist`；微信 SDK 自带 UserDefaults required-reason privacy manifest。

## 线上隐私政策差异

### P0：公开上架前必须修订

1. **明确第三方处理方与目的**
   - 腾讯云 CloudBase：认证、数据库、云函数、存储。
   - 腾讯云 RUM（Aegis）：错误、性能、PV、接口/资源测速，含 `aid` 与登录 UID。
   - 腾讯云 AI Bot/所配置模型服务：处理 AI 对话内容。
   - 腾讯云文本内容安全 TMS：处理评论、举报等待审核文本。
   - 微信 OpenSDK：微信登录及 OpenID/UnionID。
   - Apple StoreKit/App Store Server API：IAP 购买、恢复和交易核验。

2. **补齐业务数据**
   - 云居安装、Dock、最近使用、应用打开记录和同步设置。
   - 工坊应用资料、评论、评分、举报理由与审核信息。
   - AI 提示词、上下文与回复。
   - IAP 商品、交易 ID、购买历史、会员及云币流水。

3. **修正设备与定位描述**
   - 删除或限定当前并未实际读取的 IMEI、Android ID、IDFA、GPS。
   - 改为实际存在的浏览器/系统信息、IP、Aegis `aid`、CloudBase UID。
   - 相机/相册应说明“仅在用户主动扫码时申请，图片默认仅在设备端识别，不上传”。

4. **补齐存储与留存**
   - CloudBase 业务数据位于上海；RUM 数据位于广州；均为中国大陆境内。
   - 分别说明账号、内容、交易、审核和监控数据的留存规则，而不只写笼统的“必要期限”。
   - 说明注销冷静期结束后，依法必须保留的交易/审计数据不会同步立即删除。

5. **补齐 Cookie/localStorage**
   - 认证：`ylf_access_token`、用户资料、CloudBase refresh token/会话数据。
   - 登录便利：已保存账号、上次手机号、上次密码登录账号。
   - 业务：主屏/Dock/最近使用、目录缓存、工坊草稿、购买记录、主题与同步设置。
   - 监控：Aegis `aid`。
   - 明确完整手机号的 Base64 只是可逆混淆，不应描述为加密。

6. **统一联系方式**
   - 线上政策当前只写 `i@yunle.fun`，仓库清单同时使用 `kf@yunle.fun`。
   - 选定一个隐私权请求主邮箱，并保证政策、App 内页面、App Store Connect 一致。

### 合规评审项

RUM 插件当前随生产 App 启动，早于登录页“登录即表示同意”的提示，也没有独立的首次启动隐私确认记录。若面向中国大陆公开分发，建议由法律/合规负责人确认是否需要在任何非必要 SDK 初始化前增加首次启动同意，并提供撤回入口。受控内部 TestFlight 可先验证功能，但不应把它视为公开上架合规完成。

## 服务协议差异

公开上架前建议在协议中增加：

1. 云应用/工坊提交需审核，平台可因违法违规、侵权、安全风险或质量问题拒绝、下架或删除。
2. 提交者保证拥有内容与商标/素材权利，并授予平台为审核、存储、展示、推广和提供下载/访问所需的非独占许可。
3. 第三方云应用由各运营者负责，平台提供入口与容器；其内容、账号、Cookie、交易和隐私规则由相应运营者说明。
4. 评论、举报和 AI 内容可能进行自动审核与人工复核；AI 输出可能不准确，用户不得将其作为医疗、法律、金融等专业结论。
5. IAP 由 Apple 处理，购买、恢复、退款和订阅规则同时受 App Store 条款约束；平台保留必要交易记录用于履约、对账和争议处理。
6. 明确通知—申诉—复核渠道、协议生效/更新日期以及统一联系邮箱。

## App Store Connect 建议填报矩阵

以下按当前代码采取保守披露；最终应与线上政策和 App Store Connect 实际选项逐项复核。

| App Privacy 数据类型                                  | 用途                         | 关联用户                   | 跟踪 |
| ----------------------------------------------------- | ---------------------------- | -------------------------- | ---- |
| Name、Email Address、Phone Number                     | App Functionality            | 是                         | 否   |
| User ID                                               | App Functionality、Analytics | 是                         | 否   |
| Device ID（Aegis `aid`，不是 IDFA/IDFV）              | Analytics                    | 是（登录后同批日志含 UID） | 否   |
| Purchase History                                      | App Functionality            | 是                         | 否   |
| Other User Content（工坊、评论、举报、AI 对话）       | App Functionality            | 是                         | 否   |
| Product Interaction（页面、安装、最近使用、打开应用） | App Functionality、Analytics | 是                         | 否   |
| Crash Data、Performance Data、Other Diagnostic Data   | Analytics                    | 是                         | 否   |

不应勾选：

- Precise Location / Coarse Location：当前没有定位功能。
- Payment Info：支付方式由 Apple 处理，App 只接收交易标识与结果。
- Tracking：当前没有跨公司广告跟踪或 ATT 用途。
- Photos or Videos：当前相册图片只在设备端扫码识别，没有上传。

## iOS 原生提交清单

- [x] `NSCameraUsageDescription`
- [x] `NSPhotoLibraryUsageDescription`
- [x] `ITSAppUsesNonExemptEncryption = false`
- [x] Universal Links associated domains
- [x] App target privacy manifest（账号、内容、IAP、RUM；不跟踪）
- [x] 微信 SDK privacy manifest（UserDefaults reason，随静态 SDK 进入 `CordovaPlugins.framework`）
- [ ] App Store Connect Privacy Policy URL 填写并核对可访问性
- [ ] App Store Connect App Privacy 按上表发布
- [ ] 从 Xcode Archive 生成 Privacy Report，逐项确认合并后的 SDK 声明
- [ ] 线上政策完成 P0 修订并更新生效/最近更新日期
- [ ] 协议完成云应用、内容、AI 和 IAP 专项条款

Apple 要求 iOS App 提供公开隐私政策 URL，并在 App Store Connect 声明本 App 及第三方代码的数据实践：

- <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/>
- <https://developer.apple.com/app-store/app-privacy-details/>
- <https://developer.apple.com/documentation/bundleresources/privacy-manifest-files>
