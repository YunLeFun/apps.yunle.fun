# 原生 iOS 0.2.0 (4) 内部发布

2026-10-27，已发布到既有“云乐坊内测组”，沿用 3 位成员与自动分发。中文测试说明已写入；未增加测试员、公开链接、外部测试组或 Beta App Review。本轮未更新物理手机。

## 改动与来源

- 归档源码：`cf7fe582f03fdac3ef4f8bca1c2ae7eeb4530076`，已推送 main。
- 工坊的 `login_required` 过去被客户端当作禁止打开；现在允许已登录账号进入重新核验路径，读取最新工坊权限与应用 URL，再启动。受邀、会员、付费、暂停及未知状态仍保持检查。
- 云居可切换个人云居、自己的工坊与已加入工坊。私有工坊显示管理后台和支持中心，切换不安装到个人库；账号或权限变化、迟到响应都隔离处理。
- 详情页采用系统 Liquid Glass 操作；在线图标在 `YunLeFun/icons` 提交 `678a386a66e15ad5862f31c0ef26604e5b172a23` 登记，复用品牌与支持中心图标。客户端使用在线清单、缓存及生成的 URL 快照，没有新增站点 SVG 副本。
- 后续 `4a45cad493d276dd3e533a802f42bf900deb3e5b` 修正标题 OCR 断言，`30d7b13` 延长大字号滚动截图扫描预算。两次提交均只修改测试文件，发行输入相同；IPA 没有重建或替换。

## 签名与发布

App `6759859441`，Bundle ID `fun.yunle.apps`，Team `QT792GAY4C`。选号读取已处理和上传记录：最高为 3，本轮采用 4。

旧 KVS profile 关联的证书在本机没有私钥。使用现有本机 Apple Distribution 私钥，创建匹配的 `YunleFun Internal KVS 20261027 Local`（ASC ID `JCB32K47SY`），保留 `QT792GAY4C.*` KVS 授权与 `get-task-allow=false`。机器专用导出配置保留在仓库外。

ASC CLI 分别归档、导出；IPA 核验通过唯一 App、正式标识、版本、分发签名、profile、仅内部标记、隐私清单字节一致与加密声明。Apple 返回 **VERIFY SUCCEEDED with no errors**。上传的 SHA-256 与校验的 IPA 一致：

`e933dc5c52fa3087936c1bb28d4bfc459637f26910dcada301f69f1886a042d4`

Xcode 导出建立了仅分析元数据的待上传记录 `4bf9bc5a-bad4-4931-87bd-ae614a853d17`，已查询确认没有 IPA。后续唯一一次 IPA 上传、最终构建 ID 均为 `db510ccf-f118-46d2-9330-b5e05daf6ec5`。

共用 `verify_release.py server --phase published` 已通过：`VALID`、未过期、`INTERNAL_ONLY`，正确应用与 `0.2.0 (4)`，关联内部组 `15cca729-b449-4d73-908c-2ee09f0eef68`，3 位内部成员，`IN_BETA_TESTING`，外部 `NOT_APPLICABLE`。既有组自动关联，因此没有重复执行关联写入。

## 验证边界

本次专项已完成工坊权限、账号切换、首页布局、详情大字号、在线清单与两站真实图标下载。原始 CI 在归档源码上为 636 通过、7 条件跳过、1 个 OCR 断言失败；截图显示内容正确，Vision 将粗体标题“把喜欢的应用带回云居”漏识别一个“的”。后续测试提交改为独立检查选中名称与稳定可见短语“带回云居”，保留切换与数据隔离断言。

本机全量回归为 623 通过、7 条件跳过及 4 个失败记录，包含缓存交互超时、账号存储超时、键盘导航超时及 CoreSimulator 服务退出导致的运行器错误。独立复测前三项均通过；继续导航时备份页又超时，停止该轮后 Xcode 结果收集失败。`retry-log-summary.json` 仅按原始事件记录 7 通过、1 超时，不作为完整 xcresult 通过回执。修正后的切换专项在本机独立结果包 `home-switch-proof.xcresult` 中 1 通过、0 失败。第二次完整 CI（[40382725800](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/40382725800)）为 **635 通过、7 条件跳过、2 失败**，包括工坊最大字号滚动截图与反馈页最大字号联系方式截图。失败的截图 / 扫描记录显示仍停留在第一个应用或联系方式之前，原 5 / 10 秒总预算被多轮 Vision OCR 消耗，未滚到目标。`30d7b13` 将滚动扫描预算统一为 30 秒，保留原内容断言；非滚动等待仍为 5 / 10 秒。修正后在复用的空闲 iPhone 18 Pro / iOS 27.0 上，切回个人云居、工坊最大字号滚动、反馈页最大字号联系方式三项定向验证均通过（3 通过、0 失败、0 跳过），见 `scan-validation-summary.json`。此处不把两次完整 CI 写成全部通过；最新自动 [CI 40387515630](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/40387515630) 在交付时仍运行，结果应按该回执查看。

前次 iOS 27.1 Duo 失败记录、独立 Sandbox 支付服务未部署，以及相机、触觉、锁屏保护、跨设备 iCloud、物理 TestFlight 覆盖升级、iPad、最低系统与完整无障碍矩阵的待验范围，继续见[前次候选验收](./testflight-preflight-20261026.md)。这是核心功能内测发布，不代表支付或完整硬件矩阵验收完成。

## 证据与清理

仓库外目录：`~/.codex/artifacts/yunlefun/testflight-workspaces-20261027-hOVvzx/`（0700）。保留源码 tar 与提交、Archive / dSYM、仅内部 IPA 与 SHA、profile / 导出配置、Apple 校验、上传与最终发布回执，以及测试摘要、失败日志和截图。

分支核对时 apps 与 icons 均无已合并功能分支可删除，已 prune 远端引用。icons 主工作区的无关本地未推送提交保留。临时设备与构建中间产物的最终清理见该目录 `cleanup.json`。

本次关闭并删除唯一临时模拟器 `8DD6E95B-5FCC-45DE-BBC2-F631BFAE7892`；删除归档 / 测试 DerivedData、不完整重试结果包及已导出必要证据的 CI 解包副本，合计 758.2 MiB 已分配文件。同期全卷可用空间变化 +1740.5 MiB，存在并行任务写入，不将两者等同。共享依赖缓存和发行归档保留。

定向验证复用已有空闲设备 `4502D5E9-9630-4AF0-9050-3C9109139FD0`，未擦除，结束后恢复 Shutdown；没有新建设备。再次导出必要结果后回收定向验证 DerivedData 和第二次 CI 的解包副本，本轮累计移除 1211.9 MiB 已分配文件（约 1.18 GiB）。完整来源和两次清理的卷空间变化保存在 `cleanup.json`，共享缓存、源码和唯一发行产物保留。
