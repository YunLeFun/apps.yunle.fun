# iOS 原生钱包、会员与内购

> 2026-10-16。原生界面、账户 HTTP 协议与 StoreKit 2 流程已接入；真实账号读写、Sandbox 验单 / 入账、旧交易跨设备归属及真机尚未验收。本轮没有执行线上购买或部署外部账务服务。

## 界面与数据

“我”新增钱包与云乐坊会员入口。余额、会员状态、到期日期、流水分页、商品与恢复入口使用系统 List / Section / LabeledContent / Button / ProgressView。会员保留现有非自动续期模式，不改为自动续费订阅。

尚未取得余额和权益时明确显示未获取；服务失败不会变成零余额或未开通。已有内存快照可保留并显示获取时间与更新错误。流水核对服务端 userId、金额范围、记录 ID 和分页进度，账号切换与 A → B → A 会立即隐藏旧数据。

访客通过原生“登录并继续”进入账号流程，取消返回原页面。登录与旧购买确认由页面容器呈现，避免在 List 的 Section 上附加弹层导致点击后没有弹出。旧购买确认与操作均绑定账号身份代次，换号后失效。

## 账户与商品契约

请求使用已核实的 CloudBase Functions OpenAPI：固定现有国内上海环境网关，Bearer 只发给该网关，JSON 结果直接解码，不套用 JS SDK 的 `{ result }` 信封。会话不带 Cookie、缓存或 URL 凭据，不跟随重定向。

| 服务与 action                    | 用途                                                      |
| -------------------------------- | --------------------------------------------------------- |
| `account-api / getAccount`       | 云币与会员快照                                            |
| `account-api / listTransactions` | 当前身份的云币流水，skip / limit 分页                     |
| `wxpay-order / reconcileOrders`  | 延续原钱包的历史订单核对与已付款漏发自愈，不发起新付款    |
| `iap-order / restore`（空列表）  | 购买前的服务就绪检查，不发放权益                          |
| `iap-order / verifyPurchase`     | 仅提交 transactionId，由现有服务校验 Apple 交易并幂等处理 |

无凭据访问 account-api 与 iap-order 的 OpenAPI 路径均返回 401 / MISSING_CREDENTIALS。该结果只证明网关拒绝匿名请求，不能证明私有成功路径或本轮读取的外部源码版本已部署。

外部契约来自相邻 `YunLeFun/api` 仓库的 account-api 和 `YunLeFun/www.yunle.fun` 仓库的 iap-order / wxpay-order；本轮只读取源码，没有改写或发布这些服务。当前安装的 `@yunlefun/types` 运行时导出也已核对，保留五个商品 ID：

| Product ID                                                                         | 类型                                 |
| ---------------------------------------------------------------------------------- | ------------------------------------ |
| `fun.yunle.apps.coin_100` / `fun.yunle.apps.coin_500` / `fun.yunle.apps.coin_1000` | 消耗型，分别为 100 / 500 / 1000 云币 |
| `fun.yunle.apps.member_month` / `fun.yunle.apps.member_year`                       | 非续期会员，月度 / 年度              |

原生只展示实际取得且类型匹配的 StoreKit 商品，并使用其 displayPrice。没有商品时提供重试，不使用 Web 的人民币标价替代，也不跳转到外部付款。

## 购买、归属与恢复

购买前检查账号服务与本地归属记录，并向既有 iap-order 发送空交易列表的 restore 检查。该路径会先校验账号状态、测试身份与服务配置，空列表不查询或发放交易；未通过检查时不打开系统购买界面。客户端本地验证交易后，仍须等待服务端返回与该 transactionId 对应的有效处理结果，才结束真实交易。明确 401 可刷新一次；服务或网络失败保留未完成交易。对已处理记录只说明完成核对，不把它当作新增到账。

新购买向 StoreKit 提供按云乐坊 uid 确定的、不含原始 uid 的 UUID v8 appAccountToken。另用独立 Keychain 服务保存交易与账号的待核对 / 已确认归属，保护级别为 AfterFirstUnlockThisDeviceOnly。损坏记录不覆盖；换号、退出及 ABA 变化均不能把旧请求的结果用于新账号。

App 启动监听交易更新；已标记其他账号的交易不会自动领取。缺少账号标记和本机记录的历史交易先呈现确认，明确尚未绑定的旧交易会首次绑定当前账号。经服务端确认的归属不自动改写。未取得服务端确认的本机尝试可在原账号明确确认后修正，避免一次失败尝试阻止原账号恢复；原型 v1 记录也按未确认尝试迁移。服务端已经首次绑定到另一账号的真实权益仍需服务端 / 支持处理，不能靠删除本机记录转移。

恢复购买仅在用户明确操作时调用 [AppStore.sync](<https://developer.apple.com/documentation/storekit/appstore/sync()>)；随后合并未完成交易与 [currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements) 中的会员，包括已经 finish 的非续期会员。已完成的消耗型云币以云乐坊账户余额为准，不从本机交易历史重新计算余额。取消 App Store 认证显示取消，不显示为入账失败。

结束交易沿用旧插件的做法：从当前未完成队列重新取得验证后的对应交易，再 finish。实际 StoreKit 测试曾发现仅使用保留的购买结果对象时，会员恢复之后的下一笔云币仍留在队列；修正后购买与恢复两项测试均通过。

Xcode 本地交易会完成本地清理，但绝不送往线上验单或发放权益。真实交易的失败不会走这个本地例外。

## 验证

| 范围                   | 结果与限制                                                                                                |
| ---------------------- | --------------------------------------------------------------------------------------------------------- |
| iOS 27 日常测试        | 172 项通过：171 单元 / 集成与 1 UI；其中本轮新增 31 项协议、竞态、购买状态与视觉测试                      |
| iOS 18.6 钱包专项      | 31 项通过，包含浅色钱包与深色辅助字号会员样例                                                             |
| 实际 StoreKit 本地测试 | iOS 27 / 18.6 各 2 项通过：五个商品读取、本地购买不调用线上发放、账号标记回显、结束后队列与已完成会员恢复 |
| 实际访客 UI 旅程       | iOS 27 / 18.6 均通过钱包 / 会员入口、登录呈现与取消返回；没有触发购买                                     |

表单截图使用隔离测试账号、样例余额和“测试价格”，仅证明布局。已查看浅色钱包、深色辅助字号会员首屏及两版系统的访客截图；它们不代表真实账户、完整无障碍或所有滚动区域已经验收。

本地 StoreKit 使用独立 `YunleFunStoreKitValidation` Scheme，显式绑定测试配置；默认 App 与 Benchmark Scheme（包括 Release 归档）不启用本地商品配置，产品资源也不包含该测试文件。仅运行对应模拟器验证：

```sh
xcodebuild -project apps/ios/YunleFun.xcodeproj -scheme YunleFunStoreKitValidation \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath /tmp/yunlefun-ios-storekit CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -parallel-testing-enabled NO test
```

本聊天 `ios-native/wallet` 附件保存 xcresult、截图、无凭据探测、来源文件摘要与验证元数据。源码仍在未提交工作区中，HEAD 不代表本轮实现的完整快照。

## 尚未完成

- 真实账号余额 / 流水 / 历史订单核对，以及 Sandbox 购买、待批准、退款、服务中断后补单和跨设备恢复。两个本地 StoreKit 测试不能替代这些验证。
- 外部验单服务当前源码仍按首次领取账号绑定交易，未校验原生新增的 appAccountToken，也缺少原子首次归属及旧交易纠错所需的完整契约。客户端防误操作不等于服务端已解决跨客户端归属竞争；外部服务变更作为独立依赖处理。
- 目录内会员 / 云币应用的服务端获取和真实使用、钱包 / 会员深链、完整 VoiceOver / 最大字号 / iPad 矩阵、真机与旧版升级。现有付费与会员门控未因钱包页面完成而放开。
- 正式签名和 Sandbox 所需设备 / 账号准备；上一轮真机签名在安装前失败，本轮不据模拟器或未签名编译宣布真机通过。

M3 与整个迁移 Goal 保持未完成，没有上传 TestFlight 或提审。
