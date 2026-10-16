# 原生云居备份与恢复

原生入口为“我 → 设置 → 云居备份”。系统列表按保存时间展示当前云居的本机备份，详情可查看应用、顺序、Dock 和最近使用，再通过系统确认框恢复。用户可以只恢复布局，或同时恢复云同步、自动同步和常用应用显示设置。

## 来源与账号边界

备份保存在当前应用的 `Application Support/HomeLibrary`，沿用原有文件，不要求重新导入：

| 来源                 | 文件模式                            |
| -------------------- | ----------------------------------- |
| 旧版导入前           | `<云居>.before-legacy-<摘要>.json`  |
| 同步冲突中选择云端前 | `<云居>.conflict-<UUID>.json`       |
| 恢复其他备份前       | `<云居>.before-restore-<UUID>.json` |

列表只接受当前账号或访客云居的完整文件前缀和已知后缀；不会把其他账号的备份显示出来，也不接受任意路径或符号链接。后台读取有取消检查；打开详情前验证格式，恢复执行前重新读取并核对摘要。损坏或超过 16 MiB 的记录保留在原处，详情显示失败，不会拿它替换当前云居。

页面数据投影与确认同时绑定账号代次、当前云居代次及所属文件。账号 A → B → A、切换云居、迟到读取、备份内容变化及当前布局变化都会使旧确认失效。恢复设置开启时，也检查确认之后的设置变化；关闭时保留当前设置。

## 恢复行为

恢复按以下顺序进行：

1. 重新核对备份内容和目标；保留当前完整文件作为恢复前备份。
2. 将选中布局作为一次新的本地更改保存，生成新 mutation ID 与恢复操作标记，保留当前云端修订和已有旧版导入标记。
3. 切换本地云居代次，取消旧同步读取或过期冲突选择，再按当前同步设置进行版本检查。

不把备份中的旧云端修订当成当前服务版本。应用资料合并时继续保护工坊 / 私有版本的访问范围，打开时仍需现有权限核验；未知引用保留位置。当前账号、认证和支付权益不从云居文件恢复。

同一个已完成操作的回调不会重复替换，也不会覆盖恢复之后的新编辑。每次明确选择另一备份恢复前都会再保存当前版本，因此可从“恢复其他备份前”找回前一个布局。

如果当前主文件已损坏，先保留其原始字节到 `<云居>.before-repair-<UUID>.bin`，再写入验证通过的云居。原始损坏文件不作为可正常恢复的 JSON 备份展示，仍保留在设备中以便后续检查。存储错误时不丢弃原文件或已建立的副本，可以修复后重新确认。

当前备份恢复的是云居及其设置，不恢复全局外观、浏览器或其他尚未迁移的设置。跨设备备份、手动文件导入 / 导出与备份清理尚未加入；这不等同于完整系统备份或覆盖升级回退验收。

## 验证

`HomeBackupTests` 覆盖文件归属 / 路径 / 符号链接、布局与设置选择、当前云端修订和旧导入标记保留、原始版本副本、重复完成、损坏主文件恢复、存储失败重试、迟到同步及过期冲突选择。另有原生列表、详情、空、失败、大字号深色、损坏原文件提示和完成状态截图。

最终日常回归 260 项（257 单元 / 集成 + 3 UI）通过，含备份专项 13 项；结果为 `test_sim_2026-10-16T08-40-51-685Z_pid92585_0661020f.xcresult`，无测试失败或构建诊断。原生 Release 模拟器编译通过，核对产物仍为 `fun.yunle.apps`、最低 iOS 16，且包含下述 API 用途资源；没有安装此 Release 产物。根 lint 与文档构建通过。

日常 UI 包含“设置 → 云居备份”的真实空状态与原云居保持。独立 Benchmark 用例 `testNativeHomeBackupCancellationRestoreRestartAndUndo` 需要显式启用 `YLF_HOME_BACKUP_UI=1`，并准备已备份的合成访客记录。它验证预览、系统确认取消、恢复、重启保留，以及从恢复前自动副本找回原布局。

本轮实际点击旅程通过，结果为 `test_sim_2026-10-16T08-38-14-520Z_pid92585_654b46f4.xcresult`。测试后核对两级恢复操作标记、保存的布局与当前原布局，再按当前应用容器恢复原 `guest.json` 的每个字节，删除合成备份与两份新增副本。没有修改正式应用或真实账号。

这条实际旅程先于最后两处小修正：损坏原文件的已有副本在重试时也设置文件保护；详情失效后显示重新打开入口。最终日常回归与状态截图使用修正后的源码，实际旅程覆盖的正常恢复路径没有变化。

仓库外证据目录为 `ios-native/home-backups`。原生文件保护的锁屏 / 重启、最低系统、iPad、VoiceOver 与正式旧版覆盖升级仍待验；真实账号联调的范围见下一节，M2 / M4 的整体升级验收保持未完成。

## 真实账号恢复与云同步

2026-10-16，新增独立显式用例 `HomeSyncLiveTests/testAccountBackupRestoreSyncConflictAndUndo`。当前完整 Nitro 构建在 `127.0.0.1:18746` 连接既有 CloudBase 环境 `yunlefun-8g7ybcxc7345c490`；使用固定受管合成账号 `production-zero-balance` 和 `production-standard`，不改认证配置、集合或安全规则。

本次 iOS 27 真实联调 1 项通过：

- 账号 A → B → A 后，其他账号不显示备份，原确认失效，当前云居保持。
- 先上传备份时的内容，再上传后续编辑，形成真实的新修订；在原生详情页实际点击系统“确认恢复”，核对旧布局、设置、未知引用及恢复前副本，同时保留当前云端修订。
- 从 Keychain 和磁盘重建账号 / 云居对象，恢复标记和待上传内容仍在；上传按当前修订成功，服务端再次读取与恢复内容一致。
- 同一模拟器的另一独立本地目录上传新内容后，再从恢复前副本找回本机布局；同步进入真实修订冲突，云端新内容未被覆盖。选择云端后，待同步本地版本也保存为可读副本。
- 最后按当前修订恢复原云居三组引用内容并再次读取核对；第二账号的完整远端快照未变化。远端退出两个测试会话，清除专用 Keychain 项和本地测试目录，一次性凭据输入也已删除。

结果为 `test_sim_2026-10-16T08-53-54-571Z_pid92585_581c144f.xcresult`，无构建诊断或测试失败。安全报告、原生恢复完成、深色大字号冲突与系统确认截图位于仓库外 `ios-native/home-backups-live`。日志另有一条 `IOSurfaceClientSetSurfaceNotify failed e00002c7`，没有测试失败；不将本轮结果作为完整渲染或性能验收。

这里的重启是对象与本地存储重建；另一客户端仍在同一模拟器中。本次没有终止 / 重启进程、覆盖安装、硬件跨设备或正式域名部署，也没有进行支付。实际点击覆盖备份详情及系统恢复确认；冲突选择由测试调用真实协调器完成，不能冒充这次实际点击证据。

复测使用 `YunleFunLiveValidation` Scheme 和专用测试模拟器。先启动当前完整服务，再将仓库外 0600 文件中的两个固定账号一次性写入当前应用容器的 `Library/Caches/iOSNativeValidation/home-backup-accounts.json`；顶层为 `accounts` 数组，每项包含 `id`、`environment`、`username`、`password`。不把值写入源码、启动参数、环境变量或附件。测试在读取后立即删除输入，使用独立 Keychain service。

```sh
TEST_RUNNER_YUNLEFUN_LIVE_HOME_BACKUP=1 xcodebuild \
  -project apps/ios/YunleFun.xcodeproj -scheme YunleFunLiveValidation \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath /tmp/yunlefun-ios-live-validation \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- -parallel-testing-enabled NO \
  -only-testing:YunleFunLiveTests/HomeSyncLiveTests/testAccountBackupRestoreSyncConflictAndUndo test
```

需要实际点击时，再显式启用 `TEST_RUNNER_YUNLEFUN_LIVE_BACKUP_UI_TAP=1`；测试等待原生详情页的外部输入，120 秒内完成系统确认。无人操作的 CI 不启用此模式。未启用主开关的默认跳过已验证，不计作真实联调通过。若清理遇到无关云端变化，保留基线和测试目录，不强行覆盖。

## 本机 API 用途

原生工程新增实际随包的 `PrivacyInfo.xcprivacy`，声明本机备份日期 / 文件元数据和应用自身偏好的用途：`FileTimestamp / C617.1`、`UserDefaults / CA92.1`。本轮已从 Apple 官方文档核对这两个用途，并用实际 Bundle 资源测试验证打包；这份声明未替代候选版本的完整数据收集、第三方组件与商店隐私核对。

参见 Apple [required reason API 用途说明](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)。时间仅用于本机备份列表和预览，不上传备份文件元数据。
