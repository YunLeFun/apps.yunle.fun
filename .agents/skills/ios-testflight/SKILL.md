---
name: ios-testflight
description: 云乐坊与云生共用的原生 iOS TestFlight 内部测试发布流程。用于确认项目、版本、归档、IPA 校验、上传、内测组分发及按需手机更新；项目命令从对应仓库发布文档读取。
---

# 共用 TestFlight 内部测试流程

先选择项目并读取对应发布文档；其命令、Bundle ID、版本来源和导出配置是该项目的参数。技能维护源为 `YunLeFun/apps.yunle.fun/.agents/skills/ios-testflight/`，可安装到个人 skills 目录供两个仓库直接调用。

| 应用 | 仓库 | 发布文档 | 专用入口 |
| --- | --- | --- | --- |
| 云乐坊 | `YunLeFun/apps.yunle.fun` | `docs/dev/testflight.md` | `ios-deploy` |
| 云生 | `YunYouJun/life` | `docs/guide/ios-testflight.md` | `life-testflight` |

两者当前发布对象均为 `apps/ios` 下的原生客户端。不要根据旧技能或包名自动转入 Capacitor。当前目录不属于目标项目时，定位其已有 checkout；文档尚未同步时可以读取已 fetch 的 `origin/main`，不 reset 其他任务的改动。

## 共用步骤

1. **源码和授权。** 核对当前用户要求。只打包时完成归档、导出与校验；明确要求上传或更新 TestFlight 时继续内部发布，已有明确授权不重复询问。基于最新 main 或用户指定的已提交源码工作，保护其他任务改动，必要时用独立工作树。
2. **版本。** 查询服务器已用版本和构建号，再更新该项目的版本来源并提交。两套原生工程都使用 `apps/ios/project.yml`，项目文件的跟踪策略以各仓库文档为准。不能从根 package.json 或旧 Capacitor 的 Git 提交计数推算原生构建号。
3. **归档和导出。** 使用对应项目的 Release Scheme 和正式 Bundle ID。分开执行 archive、export、validate、upload；导出固定 `method = app-store-connect`、`destination = export`、`testFlightInternalTestingOnly = true`、`manageAppVersionAndBuildNumber = false`。签名方式、Swift 符号选项和资源准备保留各项目配置，不把一个应用的全部配置复制给另一个。
4. **包与 Apple 校验。** 检查实际 IPA 的唯一 App、Bundle ID、营销版本、构建号、Apple Distribution 签名、App Store 描述文件、关闭调试权限、隐私清单、用途声明和 `TFInternalTestingOnly = true`。归档 `.app` 的开发签名不能替代 IPA 分发签名检查。validate 无错误后才上传同一 SHA-256 的 IPA。
5. **上传和处理。** 保存 delivery UUID、IPA 哈希和脱敏回执。上传结果不明确时先查 delivery/构建状态，不盲目重传；处理延迟时退避查询。校验或处理失败时修复源头，新上传使用未占用的构建号，不绕过仅内部限制。
6. **内部发布。** 精确匹配 App、iOS 营销版本、构建号和 Build ID，不能只按构建号挑“最新”。仅接受 `VALID`、未过期、`INTERNAL_ONLY`。先用 dry run 或只读查询展示目标和拟变更，再执行发布。复用该 App 的已有内部组、自动分发、反馈及成员，不自动新增邀请。首次配置成员或用户明确要求增加时，只选有该 App 权限的现有 ASC 内部用户，不跨 App 复用 betaTester ID。
7. **发布验收。** 核对构建关联正确、内部组有可用测试员、未启用公开链接，页面为“正在测试”或 API 为 `IN_BETA_TESTING`，外部状态为 `NOT_APPLICABLE`。上传命令成功不能替代这一步；不启用外部测试或提交商店审核。
8. **按需更新手机。** 仅在用户要求安装/更新手机时继续。从 TestFlight 更新正式标识，确认版本、“打开”、正常启动、本机数据保留和该 App 自动更新。不要先卸载现有正式版；遇到开发版或其他标识先按项目迁移文档备份和核验，再清理重复版本。开发签名迁移包不算 TestFlight 安装完成。

## 项目边界

- 云乐坊旧 Capacitor 与原生正式版共用标识，覆盖安装后保留容器不等于旧 WebKit 数据已导入；按该项目旧版导入与备份流程核验。
- 云生 `.dev` 与正式版容器独立，首次迁移读取 `docs/guide/ios-testflight-migration.md`；完成首次切换后，常规同标识更新不再迁移或删除 App。
- 同一团队可复用已有授权的 API Key 和签名环境，但 App ID、Bundle ID、版本、组、测试说明及回执分别记录。切换项目时不继承上一个应用的 `ASC_BUNDLE_ID`、组或元数据。

## 凭据、阻塞和交付

仅通过运行时变量 `ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8` 提供凭据，`.p8` 权限为 600，文件名和 altool 查找路径按项目文档核对。不要打印私钥、JWT、完整测试员邮箱或把个人设备数据写入共享日志。

登录、协议或设备锁定需用户处理时，保留已完成阶段并说明具体待办，不伪报后续完成。不抢占其他任务的模拟器；发布若无需模拟器就不创建。确需临时设备时记录归属并在本任务结束前清理。

产物放在仓库外，保留源码提交、副本、版本/构建、归档和 dSYM、导出配置、IPA 与哈希、校验/上传/发布回执及可核对的截图。最终分别报告服务器发布和手机安装/数据核验的实际结果，不把产物或凭据提交 Git。
