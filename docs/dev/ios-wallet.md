# iOS 原生钱包、会员与内购

> 2026-10-18。三个托管账号的真实余额、流水分页及原生 WalletStore 换号隔离已验证，见[真实只读验证](#managed-wallet-reads)。真实钱包 UI、账务写入、Sandbox 验单 / 入账、旧交易跨设备归属及真机仍未验收；没有执行线上购买或部署外部账务服务。

## 界面与数据

“我”新增钱包与云乐坊会员入口。余额、会员状态、到期日期、流水分页、商品与恢复入口使用系统 List / Section / LabeledContent / Button / ProgressView。会员保留现有非自动续期模式，不改为自动续费订阅。

尚未取得余额和权益时明确显示未获取；服务失败不会变成零余额或未开通。已有内存快照可保留并显示获取时间与更新错误。流水核对服务端 userId、金额范围、记录 ID 和分页进度，账号切换与 A → B → A 会立即隐藏旧数据。

首次进入钱包时，历史订单核对也计入余额和流水的加载状态，避免实际读取前短暂显示“暂无流水”。核对失败后仍读取当前余额与流水，并保留核对错误提示；换号立即隔离旧操作的加载状态与结果。

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

外部契约来自相邻 `YunLeFun/api` 仓库的 account-api 和 `YunLeFun/www.yunle.fun` 仓库的 iap-order / wxpay-order。初始接入只读取源码；10 月 18 日另准备了未部署的 IAP 候选补丁，见后文。当前安装的 `@yunlefun/types` 运行时导出也已核对，保留五个商品 ID：

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

初始钱包验证的 `ios-native/wallet` 附件保存 xcresult、截图、无凭据探测、来源文件摘要与验证元数据；当时为未提交源码，不能将该次证据归到任意后续 HEAD。后续真实只读验证另有精确来源记录。

## 尚未完成

- 真实钱包 UI 与历史订单核对，以及 Sandbox 购买、待批准、退款、服务中断后补单和跨设备恢复。下述真实余额 / 流水读取与两个本地 StoreKit 测试不能替代这些验证。
- 外部验单服务当前源码仍按首次领取账号绑定交易，未校验原生新增的 appAccountToken，也缺少原子首次归属及旧交易纠错所需的完整契约。客户端防误操作不等于服务端已解决跨客户端归属竞争；外部服务变更作为独立依赖处理。
- 目录内会员 / 云币应用的服务端获取和真实使用、钱包 / 会员深链、完整 VoiceOver / 最大字号 / iPad 矩阵、真机与旧版升级。现有付费与会员门控未因钱包页面完成而放开。
- 正式签名和 Sandbox 所需设备 / 账号准备；上一轮真机签名在安装前失败，本轮不据模拟器或未签名编译宣布真机通过。

M3 与整个迁移 Goal 保持未完成，没有上传 TestFlight 或提审。

## IAP 服务端候选修复 · 2026-10-18

在外部 `www.yunle.fun` 的独立工作区 `/Users/yunyou/.codex/artifacts/ios-native-goal-20261018/iap-service`，从 `3f7ff5d0be186ff1e54f3fc6666fa31b959152e2` 准备账号归属与发放修复，保存为本地提交 `ffaabaa1c99105dfda811ae7518660c5140a6b40`。生产尚未部署，前述外部服务缺口不能按本地源码视为已解决。

服务端候选开始核对 Apple 签名交易的 `appAccountToken` 与 CloudBase 已认证 UID；原生 Swift 与 Node 的三个固定输入（含中文 UID）分别执行，UUID 完全一致。新 IAP 订单使用稳定文档 ID，并将订单、会员 / 云币、充值流水和发放凭据同事务提交；已有随机 ID 订单在事务内重读校验，不因客户端首次请求竞争而创建第二份权益。旧会员已付款却无发放凭据时，仅能证明当前最后一次发放的记录可补凭据，其余返回人工核对，不能虚报已处理或再次延期。微信查询 / 对账入口也已加入 IAP 隔离保护。

本地使用外部仓库原始 Vitest 配置执行完整支付目录 **19 文件 / 293 项通过**，包括退款、并发、响应丢失、回滚及旧记录。首次 Node 子集通过 98 项；扩大时因缺少 Nuxt 生成配置有一套件未加载，生成本地配置后完整重跑成功，原失败日志保留。证据为持久目录的 `iap-wxpay-regression-final.log`、`native-iap-token-vectors.log`；没有将夹具当作真实云数据库或 Apple Sandbox 证据。

该版候选继续保留既有 Server API 的 Sandbox 回退，尚未完成测试环境权益数据隔离；后续加入下述正式权益拒绝保护。真实 CloudBase 事务、历史异常订单盘点、协调排空旧发放实例、隔离 Sandbox 账号 / 环境和跨设备恢复仍是验收条件；部署说明保存在外部补丁的 `docs/ios-iap-settlement.md`。本轮未改商品类型或价格，未部署、上传或提审。

## 三账号真实只读与换号隔离 · 2026-10-18 {#managed-wallet-reads}

在自有 iOS 27 模拟器上执行 `ManagedWalletReadLiveTests.testManagedWalletReadsPaginationAndAccountIsolation`，**1 通过 / 0 失败 / 0 跳过，9.802 秒**。三个已授权托管账号分别完成真实登录、会话刷新和 CloudBase HTTP 读取；使用实际 `WalletService` / `WalletStore`，没有构造余额或流水响应。

| 账号类别 | 流水条数 | 每页 2 条的请求页数 | 余额 / 会员状态 |
| -------- | -------- | ------------------- | --------------- |
| 标准账号 | 4        | 3（含末尾空页）     | 非零 / 未开通   |
| 有效会员 | 3        | 2                   | 非零 / 已开通   |
| 零余额   | 0        | 1                   | 零 / 未开通     |

所有流水的 `userId` 均核对当前真实身份，页间没有重复 ID，完整分页与 WalletStore 首次列表一致；再次读取账户快照相同。共 **10 次 getAccount + 12 次 listTransactions**。在 A → B → A 换号中，旧投影立即隐藏，各账号重新读取与基线一致；把已从服务器取得的旧 A 响应延迟交付，返回 A 后再释放，快照、流水及 `checkedAt` 均不被旧响应覆盖。这里只控制响应交付时机，没有伪造服务器内容，也不代表实际页面手势已经验收。

对账补发、验单和购买就绪方法调用均为 **0**，测试代理会在这些方法处直接拒绝。当前钱包页面进入时会触发历史对账及未完成交易处理，因此本次没有直接打开真实已登录钱包页面，不能把只读模型验证计作完整钱包 UI 或购买成功。

一次性凭据输入只允许指定三个账号、仅本人可读，读取后删除；测试使用独立 Keychain，结束后撤销全部会话并重新读取确认无账号，磁盘再次确认输入已删除。证据不保存密码、令牌、原始 UID 或完整金额 / 流水内容。

干净构建以 `1d6f2e0fc631c26e9db8507229faf8b3e6c06ab1` 为基线，181 个原生与共享跟踪文件逐字节核对，仅新增本测试。最终测试源码 SHA-256 为 `e4dfbf5254f9d5f4666ee8189ef1cc24090217757ef865a623b5fc13f4d7834f`。证据保存在本聊天 `wallet-live-1d6f2e0/`：原 xcresult、附件、报告、独立 HTTP 探测、源码比对和清理记录。相邻 account-api 源码 `faeeec1` 的只读路径已审阅，但线上部署版本未知，不将本地提交当作部署证明。

## Sandbox 正式权益拒绝保护 · 2026-10-18 {#sandbox-entitlement-guard}

外部 IAP 工作区以本地提交 `7c8bed39feda55d456a7ae8fa3829e521737906f` 进一步修复 Sandbox 交易可进入正式发放 / 退款路径的问题。当前权益库只接受验签结果明确声明且与查询环境一致的 Production 交易；Sandbox 在任何账务访问前返回 `IAP_ENVIRONMENT_UNSUPPORTED`，恢复列表对应项失败。通知环境不再默认为 Production，必须与签名交易相同；退款还需匹配订单的支付方式、环境与 bundle ID。已验签的 Sandbox 退款明确忽略并返回 200，不修改同 ID 的正式订单。

12 条新增结算边界测试在旧实现上失败，修复后通过；完整支付目录 **21 文件 / 312 通过 / 0 失败 / 0 跳过**。其中 7 条入口测试覆盖实际 `iap-order` / `appstore-notify` 路由，但 Apple 服务与数据库为本地替身；正式发放、恢复去重及退款仍通过。库同步和定向 lint 通过，原始失败及修复证据保存为 `iap-environment-*`。

该次提交只提供正式权益保护；后续独立 Sandbox 候选见下节。候选尚未部署，不能代替真实 Sandbox 发放、退款、App Review 测试购买或跨设备恢复验收；完整 G5 和 G1–G6 目标继续保持未完成。

后续只读盘点中，CloudBase 连接器当前账号 / 区域视图仅返回现有上海正式环境，尚未确认独立 Sandbox 权益环境；这不代表已盘点所有区域或其他账号。App Store Connect 商品、Sandbox Apple Account 与开发签名仍需实际确认。Apple 将[本地 Xcode 测试和 Sandbox](https://developer.apple.com/documentation/storekit/testing-at-all-stages-of-development-with-xcode-and-the-sandbox)明确区分：前者交易由 Xcode 签名，不能替代 App Store 签名交易和服务端联调。本次仅列环境，没有创建资源、部署或尝试购买；记录为 `sandbox-readiness-b61908b.json`。

## 余额减少动态效果 · 2026-10-18

已修复余额数字变化忽略系统“减少动态效果”的问题：开启后直接更新，普通模式保留数字过渡。实际 `WalletCoinBalance` 样例取样中，旧实现开启时仍有 30 个中间帧，修复后为 0；普通模式保留 31 个中间帧，最终两种模式 **2 / 0 / 0**，真实系统开关恢复。完整方法、原始失败和证据边界见[余额渲染验证](./ios-accessibility-audits.md#wallet-numeric-reduced-motion)。这项视觉夹具没有读取或修改真实余额。

## 同环境 Sandbox 钱包候选 · 2026-10-18

按后续要求复用既有 CloudBase 环境，测试账本使用固定 `ios_sandbox_` 集合，不再要求另外建立环境。支付与退款入口位于 www 候选，账户读取入口位于 API 候选，三个独立函数为 `iap-order-sandbox`、`appstore-notify-sandbox`、`account-api-sandbox`。它们尚未部署；不能把下面的本地验证视为在线可用。

Debug 构建在启动时显式传入 `--iap-sandbox` 才选择测试钱包；Release 和 Benchmark 忽略该参数。配置在进程内固定，钱包存储和购买协调器共用同一服务实例。余额、会员、流水使用 `account-api-sandbox`，购买校验、就绪检查和恢复使用 `iap-order-sandbox`。客户端不传 UID、集合或环境覆盖参数，所有测试响应必须带 `ledgerEnvironment: "Sandbox"`，缺失、错误或服务不可用时直接失败，没有正式端点回退。

测试钱包不调用正式 `wxpay-order/reconcileOrders`；Sandbox 仅有 IAP，未完成交易及恢复仍由 StoreKit 路径重新验单。购买归属 Keychain 使用独立 `.iap-sandbox-owners` 服务，正式 `.iap-owners` 保持兼容，防止两种环境相同交易 ID 混淆归属。钱包和会员页显示“内购测试钱包”。这只隔离内购钱包，其他应用功能仍使用真实账号服务，不能当作整个 App 的测试环境。

账户读取服务只开放余额/会员快照和流水分页，通过真实账号封禁/注销状态后读取独立测试账本；不会复制完整账户 action 或开放扣币、兑换、管理员入口。后端测试 UID 白名单、Apple 验签环境及账号标记均由服务端决定。离线包不含密钥、不会调用部署工具。

本地账户回归 **580 项通过**；支付回归 **371 项通过**。原生实际 `WalletService` 和模型、现有 HTTP 测试及新增路由用例抽取至 macOS 测试宿主，Debug / Release 各 **11 项通过**，覆盖测试路由、禁止正式对账、标记校验、失败不回退、默认正式模式和独立归属存储。仅账号类型为最小测试声明；这些结果证明 HTTP 路由及编译分支，不证明 iOS 页面、Keychain 实跑或真实 Apple/CloudBase 服务。Swift 语法检查通过；并行任务占用模拟器期间没有启动本任务的 iOS 构建或测试。

后续仍需在自有模拟器完成完整 iOS 构建与测试标识检查，确认云端集合、索引、权限、函数配置及实际事务，并取得独立的真实 Apple Sandbox 交易证据。仅模拟器约束下继续本地 StoreKit 验证，不将它计作真实 Sandbox 购买。
