# 原生 iOS 0.2.0 (3) 上传前验收

2026-10-26，范围截至 IPA 校验。没有上传 IPA、分发、提审或安装真机。Xcode 导出准备产生的远端记录及分析元数据另见下文。

## 交付结论

IPA 已通过共用 `ios-testflight/scripts/verify_release.py ipa` 和 Apple `altool --validate-app`，可以作为**核心功能内部测试**的待上传产物。支付环境尚未具备完整内测条件：独立 Sandbox 钱包 / 验单函数未部署，TestFlight 钱包会安全失败，不回退正式账本。不能将本轮写成购买、恢复到账或退款验收通过。

完整设备矩阵也未完成。现有 iOS 27.1 运行时只支持 iPhone Duo，首轮在该设备出现布局断言和黑屏导航失败；iOS 26.5 / 27.0 标准 iPhone 的结果分别记录，不能用它们宣布 Duo 问题已经修复。

## 源码与版本

- 起点及本轮结束前重新获取的远端 main：`a71870133049254a4a976c1a1168acae55aa5d8a`。
- 分支：`codex/ios-testflight-preflight`，独立工作树，未合并或推送。
- 归档提交：`45b3d28b505b13723dda5d83ac949bc59668107a`。
- 后续提交只调整 LiveValidation、StoreKit 测试夹具及文档；132 个原生 App / 共享运行时 / 资产输入与归档提交逐字节相同，记录于 `source-provenance.json`。测试夹具未进入 IPA。
- 选号前 ASC 已处理及上传记录最高均为 2，因此采用 3。结束查询发现 Xcode 自动签名导出于 20:27:22 创建了本次构建 3 的 `AWAITING_UPLOAD` 记录 `387c07b2-f763-4dab-b949-c05ecb74faff`，并完成两个分析资产（`ASSET_SPI` / `ASSET_DESCRIPTION`）的传输，随后签名失败。没有 IPA 资产，也没有已处理的构建 3。当前新建下一号为 4；后续真正上传应先检查这条属于本次导出准备的记录，再恢复同版上传，不能把 3 当作全新空闲号或盲目重复预留。见 `asc-build-preparation.json` 与 ASC 查询回执。
- `project.yml` 与跟踪的 Xcode 工程均为 **0.2.0 (3)**。正式标识 `fun.yunle.apps`，Team `QT792GAY4C`，App ID `6759859441`。
- 主工作区并行的支持中心改动、根目录未跟踪的 `ios/`、`android/` 不属于本候选。

## 作品修复与 iOS 验收

`ownerUid`（兼容旧 `_openid`）继续决定作品所有权。历史版本的 `submitterUid` 是作者记录，允许与当前所有者不同，不改写或伪造历史提交人。仍拒绝错误所有者、跨作品版本、无效版本 ID、空提交人和非正版本号。

新保存回执继续要求：回执及最新版本的提交人均为当前账号，作品与版本关联、版本号、草稿审核状态、当前修订、已发布修订、写入前提及关键内容全部一致。读取历史版本的宽容不适用于新写入回执。

`PublishingCandidateLiveTests` 在真实 iOS 中完成：

1. 受管账号真实登录、强制刷新、正式 `mine` / `access` HTTP 读取。
2. 将明确标注的历史作者响应通过实际 `PublishingService` 解码，显示实际“我的应用”列表和作品详情。
3. 实际点击编辑、核对已填字段并取消；没有保存版本、投稿、下架或上传图标。
4. 实际点击预览，再次经作品所有权核验，加载真实 Cook 网页；收起后再次预览，保留 WebKit 会话。

这是 iOS 原生 UI、HTTP 解码与真实网页的验收；历史作者记录来自受控回放。没有宣称读取了个人账号的全部 27 份作品，也没有把旧 macOS 服务层测试或 27 条回放当成本轮 iOS 验收。真实私有作品保存 / 投稿仍留给账号所有者的内测路径，避免修改真实用户数据制造成功。

## 本轮测试

| 项目 | 结果 | 证据与范围 |
| --- | --- | --- |
| iPhone 17 / iOS 26.5 日常单元与集成 | 594 项：590 通过、4 条件跳过、0 失败 | `candidate-unit.xcresult`；含作品及钱包环境边界 |
| iPhone 17 / iOS 27.0 布局及访客导航专项 | 16 通过、0 失败、0 跳过 | `ios27-focused.xcresult`；详情、帮助、键盘、同步设置、备份及导入入口 |
| 完整访客 UI / iOS 27.0 | 15 项：12 通过、3 条件跳过、0 失败 | `ui-regression-final.xcresult`；缓存专项未启用，跳过不代表验收 |
| 真实三账号、钱包与正式云同步 | 3 通过、0 失败、0 跳过 | `managed-final.xcresult` |
| 真实 Cook 原生 SSO | 1 通过 | `candidate-live2.xcresult`；原生密码登录、授权取消与重试、能力调用 |
| 历史作者作品 UI / 预览 | 1 通过 | `candidate-live4.xcresult` 中对应测试及三张截图；同一结果包中旧凭据导致的另两项失败保留，重跑由 `managed-final` 解决 |
| 实际 Xcode StoreKit 本地购买、会员恢复 | 2 通过、0 失败、0 跳过 | `storekit-valid-identifiers.xcresult`；不调用线上发放 |
| 支付服务端完整本地回归 | 19 文件 / 267 通过 | `iap-regression-rerun.log`；包括环境边界、真实通知入口的依赖隔离测试 |
| Release | 设备 Archive、Release 模拟器构建均成功 | `archive.json`、`release-simulator-build.log` |

三账号验证包括真实登录、刷新、账号选择、Keychain 重建恢复、退出后重建无账号；钱包分页、A → B → A 的迟到响应隔离；会员号还执行已有原生助手流测试。云同步使用正式域名、两个独立本地客户端，覆盖写入、断网后的磁盘恢复、冲突与账号隔离，最终回读确认云端原内容已还原、测试项已移除、会话已退出。只操作受管合成账号。

旧本机标准 / 会员账号凭据首轮返回 `invalidCredentials`；从 Admin 读取当前共享凭据，仅写入仓库外 0600 文件后重跑通过，没有重置账号或修改权益。失败记录没有删除。

StoreKit 首轮在两版系统上均读取不到商品。配置中的内部 ID 原为非 UUID 字符串，改为有效 UUID 后，实际商品读取、购买、交易清理及已完成会员恢复通过；SKU、类型、价格不变。这是本地 StoreKit 测试修复，不是 Apple Sandbox 成功证据。

## 覆盖升级

在复用的 iPhone 17 / iOS 26.5 上安装 `a7187013` 的正式标识 Release **0.2.0 (2)**，通过真实目录“获取云空调”形成云居数据。随后终止进程、同标识覆盖安装 `45b3d28b` 的 **(3)**，没有卸载或擦除设备。

升级后启动正常，“云空调”仍在云居。`HomeLibrary/guest.json` 升级前后 SHA-256 均为 `cf5f7cbacedb4da8cd1582f058ec1b9dcb83f9f77b2410a30b78879c8239f404`。模拟器重定位了数据容器路径，文件字节保留；没有把“容器路径不变”作为通过条件。见 `upgrade-verification.json`、`upgrade-before.png`、`upgrade-after.png`。

范围是原生版本 2 → 3 的模拟器覆盖升级，不能代替旧 Capacitor 数据导入、物理设备 TestFlight 升级或跨 iCloud 账号验证。

## 内购安全及剩余验收

Apple 明确说明 [TestFlight 内购使用 Sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox)。Release 通过 `sandboxReceipt` 自动选择 `account-api-sandbox` / `iap-order-sandbox`，购买归属 Keychain 与正式钱包隔离。Debug 的显式开关保留；Release 普通 App Store receipt 仍选正式钱包。

已验证交易的环境还须匹配当前钱包。Sandbox / 未知环境的交易不允许提交到正式验单，不调用 finish；失败及恢复重试保留待核对交易。本地 `.xcode` 交易只清理本地队列。

本次实际盘点正式 CloudBase 环境 42 个函数，未发现独立测试钱包三函数。ASC 的正式与 Sandbox 通知均指向现有 `appstore-notify`，因此原服务必须先保护正式账本。

经本次明确授权，将外部 `www.yunle.fun` 提交 **`8267e58`** 的最小保护部署到 `iap-order` 和 `appstore-notify`：

- 正式发放在账本访问前要求已验签交易与查询环境均明确为 Production，Bundle ID 正确。
- 通知不得缺省环境，通知与交易的环境必须一致；已验签 Sandbox 退款返回 200 并忽略，不访问正式账本。
- Production 退款还要求订单为 IAP 且记录的环境为 Production；异常留待核对，不自动改账。

部署包基于刚下载的线上代码，仅替换目标入口 / 库文件，不覆盖函数配置或依赖。重新下载后全部目标文件哈希相同，见 `deployment-source-verification.json`。没有执行真实购买、退款、账务迁移或历史补发。

**仍待部署及 TestFlight 验收：** 独立 Sandbox 账户 / 流水 / 验单 / 通知；仅测试权益的发放和退款、归属竞争及 appAccountToken 校验；真实购买、恢复、取消 / 待批准、断网和响应丢失后的重试、退款以及正式权益前后不变。当前只具备拒绝污染正式权益的保护，不能启用正式权益作为测试钱包。

## 签名与发行包

已恢复 ASC CLI **5.17.0**，使用既有团队 API Key 的安全运行时环境；未提交凭据。Xcode **27.1**、XcodeGen **2.46.0**。

正式 Bundle ID 原只有内购及 Associated Domains，现已启用 iCloud capability。新 profile `YunleFun Internal KVS 20261026`，ASC ID `4TGDFFQMX6`，包含 `QT792GAY4C.*` 的 KVS 授权、正确 App ID、`get-task-allow=false`；有效至 2027-07-04。包内 KVS entitlement 为 **`QT792GAY4C.fun.yunle.apps`**。没有删除产品权限。

自动导出因本机账号没有云托管分发证书权限而失败；它在失败前已执行上述远端构建准备和分析元数据传输。使用现有本机 Apple Distribution 私钥及新 profile 的手动导出成功。机器专用配置只在产物目录的 `ExportOptions-Local.plist`，没有改仓库的通用自动签名模板。仍固定局部 export、仅内部 TestFlight、不自动改版本号。

共用脚本通过：唯一 App、Bundle / Team / 版本 / 构建号、仅内部标记、Distribution 签名、App Store profile、无调试权限、隐私清单逐字节匹配、加密声明。Apple 回执为 **`VERIFY SUCCEEDED with no errors`**。

相机用途为“用于扫描云应用和个人工坊二维码。”；系统 PhotosPicker 图标上传无需相册全库权限。Archive 仅有一份隐私清单，11 类数据、两项 required-reason；Xcode Organizer 生成了合并 `YunleFun-PrivacyReport.pdf` 并完成文本与视觉核对。图片、支持内容、诊断、用户标识及购买记录均声明为功能用途、关联用户、不跟踪。IPA 不含本地 StoreKit 配置。ASC 隐私标签、线上政策的所有服务端留存 / 删除承诺仍需发布负责人另行核对，不能用旧 Capacitor 审计替代。

## 产物与回执

仓库外目录：`~/.codex/artifacts/yunlefun/testflight-preflight-20261026-2015/`（0700）。

| 文件 | 用途 |
| --- | --- |
| `YunleFun.xcarchive` | 提交 `45b3d28b` 的 Release Archive，包含 dSYM |
| `export/YunleFun.ipa` | 仅内部 TestFlight，未上传 |
| `ipa-check-final.json` | 共用脚本成功回执与 IPA 摘要 |
| `validate.json` / `validate.log` | Apple 零错误校验回执 |
| `YunleFun-PrivacyReport.pdf` | Xcode 合并隐私报告 |
| `source-provenance.json` | 源码提交及 132 个发行输入的摘要 |
| `asc-build-preparation.json` | Xcode 创建的待上传记录、两个分析资产及未上传 IPA 的核对 |
| `upgrade-verification.json` | 版本、数据文件及覆盖安装验证 |
| `release-manifest.json` / `SHA256SUMS` | 最终产物目录及摘要 |
| `iap-production-safety.patch` | 服务端保护的可审查补丁 |

IPA SHA-256：`1c6400a57519b55094be11fc12ca7d5f3cecbbded77870bf8a19bdeaa76b8a8a`。

App / dSYM UUID：`615CE577-27F3-3E87-82F9-4EF55D06DDAD`（arm64）。Privacy Report SHA-256：`ac7318c1cb0c98782f4b92b34cde285ca86389ec49ad09f6dcdf09bf02e8b0f1`。

复用设备：iPhone 17 / iOS 26.5，`01FE903A-4A70-4B18-B970-B84AE10207A1`；初始空闲、无云乐坊安装。另复用 iPhone Duo / 27.1 `388406F2-5C67-448B-9394-E39BF543D2BA` 取得首轮失败。其他任务的设备未关闭、擦除或删除。临时设备仅 `YunleFun Preflight iOS27 20261026` / `32C05BB0-C4D7-410B-9649-B8CC4C05C901`，用于隔离的跨运行时回归，完成后删除并记录清理回执。尝试建立标准 iPhone 的 27.1 对照设备被运行时以 incompatible device 拒绝，未产生新设备。

硬件相机、锁屏 Keychain / 文件保护、实际触觉、跨设备 iCloud、物理 TestFlight 覆盖升级、iPad、最低 iOS 16、完整无障碍及性能矩阵均未由本轮覆盖。整个原生迁移目标不因此关闭。
