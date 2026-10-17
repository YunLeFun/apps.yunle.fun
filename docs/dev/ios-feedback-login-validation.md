# 原生反馈登录续接验证

更新于 2026-10-17。实现入口为 `apps/ios/Benchmarks/FeedbackLoginBenchmarks.swift`，复用现有 `apps/ios/project.yml` 中的 YunleFunBenchmarks Scheme 和真实 Benchmark App，不增加测试宿主、生产调试入口或假成功按钮。

当前 Goal 已按用户决定收敛为[模拟器体验交付](./ios-simulator-preview.md)，完整反馈登录续接不再是本轮前置。以下失败与真实输入门禁保留；未提交的扩展诊断草稿已归档到仓库外，不继续要求用户查找剪贴板开关来阻塞访客体验交付。

## 当前结果与未完成项

- 首次非敏感 canary 使用 `secureTextField.typeText`，完整 XCTest activity 暴露了密码参数的明文截断前缀。即使界面隐藏密码，该通道仍判为 **不安全**；没有读取或输入真实凭据。
- 该次取消登录后，24 次滚动未能抵达 TextEditor，最终画面有原生“保存密码？”卡片遮挡反馈页；更早的取消后画面尚无卡片，不能认定全部滑动均被它拦截。不能据此声称原稿已丢失，也不能把旅程算作通过。原始失败结果为 `test_sim_2026-10-17T10-35-40-197Z_pid44279_9ebdde12.xcresult`。
- `local-paste-v1` 已在 iPhone 18 Pro / iOS 27 模拟器运行，canary **1 通过 / 0 失败 / 0 跳过，91.440 秒**：`test_sim_2026-10-17T11-21-53-567Z_pid44279_a619137e.xcresult`。实际粘贴、取消、精确多行草稿与“24 小时”保留断言通过；未提交认证、未读凭据。报告为启动无残留保存卡片、输入后实际出现、已点“以后”并确认消失。取消产品问题仍在，不能用测试处理卡片代替修复。
- **host 隔离未通过，真实输入仍禁止。** Mac changeCount 从 1133 到 1134，在监测开始后 88143ms 变化；总监测 148860ms，`changed=true`，未读取正文。计数只能证明发生过变更，不能据此判定复制了 canary、确认 host bridge 的具体行为或排除其他写入者。
- 已审计全部 335 条 activity 和 6 个保留附件（3 PNG、2 AX 文本、1 scope JSON），原始日志/附件字节及文本的完整 canary 与前缀扫描未命中，3 张画面也未见密码明文。但本次成功结果**未保留录屏和输入阶段完整 AX**，不能声称完成逐帧/完整输入树审计。导出与扫描回执在仓库外 `canary-localpaste-v1-audit` 目录，真实登录成功 UI 与通道安全均未验收。
- 本轮隔离 guard 已恢复 `PasteboardAutomaticSync` 原值 `true` 并核对，主账号池从未读取。下一轮需重新建立隔离、保留成功录屏及输入阶段 AX，不能沿用本次开关或 UI 通过作为安全批准。
- Store/coordinator 中直接调用模型 dismissal 的测试，不能证明真实 `LoginView` 提交、系统 sheet 消失或新 Feedback 页面恢复。

## Xcode 27 的控制界面边界

本机实际前端为 `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`，名称 DeviceHub、Bundle ID `com.apple.dt.Devices`，版本 27.0。旧 `Simulator.app` 路径不存在。DeviceKit 的静态资源中有“Use Shared Clipboard”菜单文案及按 device 同步的描述，但这不证明菜单当前状态或 `pasteboardSyncEnabled` 是可写偏好键；不能编造内部设置命令。

因此旧 `com.apple.iphonesimulator` 的 `PasteboardAutomaticSync=false` 即使读回成功，也不能证明 DeviceHub 的实际桥接已关闭。必须核验专用模拟器的真实界面设置，并重新观测 Mac 计数。UI 工具最初因 Mac 锁屏未能读取界面；用户解锁后，已实际选中本轮专用模拟器，并在 Mac 的 Edit 菜单读到 Use Shared Clipboard、Get Clipboard 和 Send Clipboard。该工具未返回菜单勾选状态，菜单截图也不可用，因而尚未确认开关关闭，未切换这个开关或读取任何剪贴板正文。工具可后台操作窗口但没有前台激活接口，已向用户说明先切到 Device Hub，再查看 Mac 顶部 Edit 菜单；没有操作手机，真实凭据验证继续等待可靠隔离。

随后仅扩充 canary 的输入阶段完整 App / SpringBoard AX 保留，真实输入路径的抓取规则未变；这一源代码调整尚未执行新一轮 canary。旧成功包缺少输入阶段完整 AX 和录屏的边界继续保留。

## 隔离与开关

仅运行新建、独占的 **iPhone iOS 模拟器**，不得操作真机或用户已有数据。App 固定为 `fun.yunle.apps.benchmark-dev`；要求空访客云居、没有安装或运行中的应用、没有已登录账号。失败即停止，不能自动清除无关账号。

| runner 环境变量                          | 要求                                            |
| ---------------------------------------- | ----------------------------------------------- |
| `YLF_FEEDBACK_LOGIN_CANARY`              | `1`：仅非敏感输入，实际取消，不提交认证         |
| `YLF_FEEDBACK_LOGIN_UI`                  | `1`：请求真实登录旅程，默认不得启用             |
| `YLF_FEEDBACK_LOGIN_CANARY_AUDITED`      | 真实旅程必须为 `local-paste-v1`；旧值 `1` 无效  |
| `YLF_FEEDBACK_LOGIN_FRESH_GUEST_FIXTURE` | `1`：执行者声明本次新建的空访客夹具             |
| `YLF_OWNED_BENCHMARK_SIMULATOR_UDID`     | 必须与 runner 的 `SIMULATOR_UDID` 一致          |
| `YLF_FEEDBACK_LOGIN_PASTEBOARD_ISOLATED` | `1`：执行者已隔离 host 桥并启动剪贴板元数据监测 |

不得将 `YLF_BENCHMARK_TARGET` 设为 `legacy`。这些变量只包含开关或模拟器标识，不能携带密码、token 或账号池内容。测试通过开关检查不等于已经完成外部审计。

## 先审计非敏感 canary

canary 为源码内公开字符串 `YLF_Feedback_Canary_20261017_Aa9!`。这一方法完全不读取凭据文件，先走真实反馈页，输入多行 emoji 草稿、选择“24 小时”，再打开真实密码表单。

1. 在 `apps/ios` 中执行 `xcodegen generate` 登记 Benchmark 源码；由执行者串行构建并准备专用模拟器。不要与其他模拟器测试并发运行。
2. 记录当前 Simulator 自动同步设置的原值及是否存在，安排不会影响其他使用者的隔离窗口。若必须暂改全局设置，验证后立即恢复并核对；本测试不会替执行者修改设置。
3. 在任何测试剪贴板写入前，开始记录 Mac `NSPasteboard.general.changeCount`，持续覆盖写入、原生粘贴、清理、取消及结束。只读计数，不读、复制或输出用户剪贴板正文；计数发生变化即本轮隔离证据失败，不能靠事后正文检查放宽结论。
4. 不投递任何真实输入文件，仅启用 canary 和三个公共夹具/隔离开关。先只运行下列方法，不能运行整个 Benchmark 集合。

在仓库根执行；`YLF_VALIDATION_SIMULATOR_UDID` 和 `YLF_VALIDATION_CANARY_RESULT` 分别由执行者设置为专用设备标识和新的结果路径，二者均不含秘密：

```sh
TEST_RUNNER_YLF_FEEDBACK_LOGIN_CANARY=1 \
TEST_RUNNER_YLF_FEEDBACK_LOGIN_FRESH_GUEST_FIXTURE=1 \
TEST_RUNNER_YLF_FEEDBACK_LOGIN_PASTEBOARD_ISOLATED=1 \
TEST_RUNNER_YLF_OWNED_BENCHMARK_SIMULATOR_UDID="$YLF_VALIDATION_SIMULATOR_UDID" \
xcodebuild -project apps/ios/YunleFun.xcodeproj \
  -scheme YunleFunBenchmarks -configuration Benchmark \
  -destination "platform=iOS Simulator,id=$YLF_VALIDATION_SIMULATOR_UDID" \
  -derivedDataPath /tmp/yunlefun-ios-feedback-login-validation \
  -resultBundlePath "$YLF_VALIDATION_CANARY_RESULT" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -only-testing:YunleFunBenchmarksTests/FeedbackLoginBenchmarks/testSecurePasswordCanaryWithoutSubmittingAuthentication test
```

5. 保留并提取完整 xcresult activities、原始日志、全部附件和录屏。扫描完整 canary **及其明文前缀**，解析 JSON/plist 等附件并核对画面；终端截断输出、成功状态或仅搜索完整字符串均不够。
6. canary 受控失败会保留现场截图、App 与 SpringBoard 的完整 AX 树及具体 `JourneyFailure`。真实凭据失败仍只记录固定阶段，不附密码字段树或值。不得把 canary 的宽诊断模式用于真实输入。
7. 核对实际“粘贴”发生、没有点击登录/按 Return、取消后仍为访客、草稿逐字相同且范围仍为“24 小时”。若系统有“保存密码？”卡片，只能点“以后”，不保存任何测试密码。
8. 所有活动/附件/画面无密码泄漏、完整 AX 审查完成、host 计数全程未变且 canary UI 断言通过后，才可认可 **该版本、该输入通道、该环境**。任一项失败均不得读取主池或运行真实输入；修改通道后必须重新审计。

`local-paste-v1` 在 runner 内调用 `UIPasteboard.general.setObjects`，设置 `localOnly: true` 和 45 秒过期，再真实长按安全字段并点击系统“粘贴”。它不向 XCUI 的文本输入动作传递密码，也不查询安全字段值。退出 helper 时，仅当 changeCount 仍属于本次写入才清空，避免覆盖后续写入者；不会读取/恢复原剪贴板内容。

Apple 的 [`localOnly` 参数](<https://developer.apple.com/documentation/uikit/uipasteboard/setobjects(_:localonly:expirationdate:)-3h3iz>)只约束 Handoff，**不等于 Simulator 与 Mac 的 host bridge 已隔离**。[Simulator 官方说明](https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/simulator_help_topics/Chapter/Chapter.html)记录了 Edit → Automatically Sync Pasteboard 开关；本机 `simctl help pbsync` 仅提供一次性源到目标同步，没有 disable 命令。当前没有已核实的公开 per-device 自动同步禁用方式，不能编造命令或省略 host 计数观测。

## 审计通过后的一次性输入

此节是后续步骤，**当前禁止执行真实输入**。仅复用既有固定零余额受管合成账号；不新建账号、不重置凭据、不改余额、会员、资料或权限。主凭据规则见[受管账号说明](./ios-assistant.md#受管测试账号)，本页不提供任何池内容。

- 先确认 UI runner 已安装并定位其数据容器。投递路径是 **runner 自有** `Library/Caches/iOSNativeValidation/feedback-login-account.json`，不是 Benchmark App 或 app-hosted unit-test 的 cache；安装导致容器变化后须重新定位。
- 只在不回显内容的私有进程中从仓库外主文件筛选固定账号一项。中转目录、runner 的 `iOSNativeValidation` 目录均为当前用户所有的 `0700`，文件以排他创建方式写为 `0600`；不把整池复制进模拟器。
- 输入顶层为 `accounts` 数组，仅一项，字段为 `id`、`environment`、`username`、`password`；允许的身份由源码固定校验。不把任何字段值放入聊天、源码、命令参数、环境变量、异常、测试附件或日志。
- reader 使用 no-follow 打开目录/文件，校验所有者、严格权限、regular-file、单硬链接、1–65536 字节限制。验证后先 unlink 路径，再从已打开的文件描述符读取并解析，格式失败也没有可重复读取的路径。权限/类型校验失败会拒读，不能声称输入已消费；执行者须清理自己本次投递的残留。
- 真实旅程在全部 opt-ins、访客检查和实际密码表单就绪后才消费文件。没有从主文件、App 参数或其他路径读取的 fallback。密码非空、最多 1024 UTF-8 字节且无控制字符，避免把换行解释为键盘提交。

审计认可后，复用同一构建及模拟器调用，把 canary 开关换成 `TEST_RUNNER_YLF_FEEDBACK_LOGIN_UI=1`，另加 `TEST_RUNNER_YLF_FEEDBACK_LOGIN_CANARY_AUDITED=local-paste-v1`，保留三个夹具/隔离开关，使用新的 result 路径，且只运行：

```text
YunleFunBenchmarksTests/FeedbackLoginBenchmarks/testManagedGuestLoginResumesFreshFeedbackOnlyOnce
```

## 真实旅程与证据界限

真实点击“我”→反馈→输入精确多行 emoji 原文→选择“24 小时”→登录→密码方式→原生粘贴→点击提交。等待实际登录 sheet 消失，再核对新 Feedback 中原文逐字一致、默认范围为“1 小时”、无上传确认及成功 alert。Back 返回“我”核对固定身份，再从入口新建反馈应为空，证明一次性续接。不能用直接调 Store/coordinator 代替这些交互。

不点击日志预览/上传、邮件发送、微信、授权或其他业务写操作，不获取/运行应用、不编辑云居。要求账号本地云居为无 pending changes 的新夹具；后台读取和原生日志不等于本次已审计全部网络，测试报告不得声称完整 zero-HTTP 证据。

提交后即使中途断言失败，仍尝试经真实账号管理“退出当前账号”→“退出并移除”；只允许移除已核对的本次受管身份。没有确认移除会明确失败，并保留原始失败阶段。测试不靠删除 App 伪装清理，Benchmark 的默认 Keychain service 为 `fun.yunle.apps.benchmark-dev.accounts`。

Me 身份 reset 会先重建页面，远端 signout 仍可能在进行中。当前 harness 确认回到访客，并在既有 30 秒 auth resource timeout 外再留余量，观察 35 秒内无退出失败提示。**本地 UI 移除与 35 秒无失败，不是独立的 HTTP signout 成功确认。** 若需要该级别结论，必须另有与本次会话对应的脱敏回执；不能沿用旧 live test 的结果。

`feedback-login-ui-scope` 报告包含：

- `passwordSavePromptAtLaunch`：启动时是否已有残留保存卡片。
- `passwordSavePromptObservedAfterInput`：输入后是否实际识别到该卡片。
- `passwordSavePromptDeclinedAfterInput`：是否点击“以后”并确认卡片消失。
- 凭据消费、真实提交、新页面恢复、原生移除及失败阶段等布尔/固定文字；这些观察不等于产品取消行为已修复。

保留每次失败和原始结果，恢复并核对自动同步设置，清理本人本次一次性输入及专用模拟器。未确认远端撤销时如实记录待核验，不能通过删除模拟器把它改写为已撤销。最低系统、其他设备与登录方式、成功 AutoFill、拖拽取消和完整辅助功能均按各自证据单独验收。
