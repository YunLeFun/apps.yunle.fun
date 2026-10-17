# 原生 VoiceOver 验证

## 范围与执行

`NativeVoiceOverTests` 使用 Xcode 27 新增的公开 [XCUIVoiceOverService](https://developer.apple.com/documentation/xcuiautomation/xcuivoiceoverservice)，通过 `enable`、`moveForward`、`moveBackward` 和 `currentSpeech` 读取实际朗读输出。控件使用定点双击激活；用例不以辅助功能树的标签冒充 VoiceOver 输出，也不向登录表单提交凭据。

该 API 需要 iOS 27。它只属于独立的 `YunleFunBenchmarks` Scheme，产品仍支持 iOS 16，日常 `YunleFun` Scheme 不自动启用 VoiceOver。使用独立访客模拟器与 `fun.yunle.apps.benchmark-dev`；若已有账号则跳过，不替开发者退出账号。跳过不能计为通过。

```sh
cd apps/ios
TEST_RUNNER_YLF_VOICEOVER_VALIDATION=1 xcodebuild \
  -project YunleFun.xcodeproj -scheme YunleFunBenchmarks \
  -configuration Benchmark \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath build-voiceover \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 180 \
  -only-testing:YunleFunBenchmarksTests/NativeVoiceOverTests test
```

两种字号由进程启动参数指定：标准 `UICTContentSizeCategoryL`、最大辅助字号 `UICTContentSizeCategoryAccessibilityXXXL`，不修改设备的全局字号。每例记录初始 VoiceOver 状态，清理阶段先恢复该状态，再保存朗读记录与返回页面截图；断言失败也执行清理。测试维持原有 120 秒用例时限与 180 秒上限。

按需设置 `TEST_RUNNER_YLF_ACCESSIBILITY_APPEARANCE=dark`（或 `light` / `system`），通过现有 `appearance` 偏好的 [UserDefaults 参数域](https://developer.apple.com/documentation/foundation/userdefaults/argumentdomain)临时切换应用外观。它随进程启动重置，不写入应用偏好，也不修改模拟器全局主题；截图仍需复核实际外观。

## 旅程

| 页面     | 两种字号均覆盖的行为                                                                                                                                          |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 我       | 登录说明、云居数量、钱包 / 会员 / 应用 / 工坊 / 账号 / 设置的顺序朗读；双击进入设置并读到显示模式；返回后焦点恢复到设置；继续读到关于、支持标题和末尾支持入口 |
| 工坊入口 | 搜索提示与三个快捷入口的顺序朗读；双击进入工坊查找，读到编号输入与禁用的打开按钮；返回后焦点恢复到原入口                                                      |
| 登录弹层 | 双击登录入口，读到原生手机号输入框；双击取消并回到原登录入口，不发送验证码、不登录                                                                            |
| 工坊应用 | 读到真实公开的 FC 红白机，核对完整标题和摘要，并检查聚焦内容能在系统导航栏与 Tab 栏之间完整显示                                                               |

返回焦点等待实际朗读状态，最多 5 秒；不移动焦点来伪造恢复结果。查找有步数和重复输出上限，无法到达目标仍失败。朗读输出、实际页面以及系统全量审计分别验收，不能相互替代。

## 实现与已核实结果

“我”与工坊使用限定于 VoiceOver 的 `AccessibilityFocusState`，记录实际打开的原生入口，并在页面返回时恢复；登录弹层取消返回登录入口，成功登录则指向账号资料入口。页面没有自绘导航、返回控件或 Tab 栏，也没有通过缩小字体处理辅助字号。

iPhone 18 Pro / iOS 27.0（24A434）、Xcode 27.0（27A266a）上，完整浅色集合 `test_sim_2026-10-17T00-38-26-649Z_pid44279_d4abdb81.xcresult` 的 **八项 VoiceOver 全部通过，0 失败 / 跳过**。同次八项系统审计为 2 通过 / 6 失败，整个 16 例集合仍失败；不以 VoiceOver 通过覆盖系统审计。

深色集合 `test_sim_2026-10-17T00-52-01-607Z_pid44279_f26f837b.xcresult` 的两项应用完整朗读 / 可见性检查也通过，真实截图已复核深色外观和完整内容。同次八项系统审计为 4 通过 / 4 失败，整个 10 例集合仍失败。浅色八例及深色两例的记录均明确保存 `restoredEnabled: false; expected: false`，没有遗留开启的 VoiceOver 状态。

深色入口增量 `test_sim_2026-10-17T01-33-02-200Z_pid44279_d9d97a51.xcresult` 另 **6 通过 / 0 失败 / 0 跳过**，补齐“我”、工坊与登录弹层的两种字号实际朗读、双击与返回焦点。截图已复核真实深色，六份状态记录均为 `restoredEnabled: false; expected: false`。至此八条深色旅程均有通过记录，明确属于先后两次执行，不能合并为一次完整集合，也不改写系统审计的失败。

复核截图与完整朗读附件后发现，上述早期登录用例中的“手机号”先匹配到登录方式选择器；其通过能证明弹层进退与返回焦点，不能当作输入框朗读证据。现要求朗读以“手机号”开头且包含“文本栏”，同时核对 `login.phone` 确为可见、可交互的 TextField。收紧后的标准 / 最大辅助字号在浅色 **2 项通过**（`test_sim_2026-10-17T01-55-22-414Z_pid44279_4193edd7.xcresult`）、深色 **2 项通过**（`test_sim_2026-10-17T01-57-26-456Z_pid44279_09409e6c.xcresult`），均无失败 / 跳过。记录明确读到“手机号 手机号 文本栏”，截图显示光标围住真实输入框；四例均恢复原 VoiceOver 状态，没有输入凭据或发送验证码。

早期分别运行的四项入口、两项登录弹层与两项应用内容专项继续保留；不把不同运行的增量结果合并成一次执行。公开 FC 红白机是内容旅程的真实样例，缺少该样例会使验证失败，不自动跳过。

## iPad 入口专项

iPad Pro 11-inch（M5）/ iOS 27、竖屏浅色、最大辅助字号的首次三例均在导航前置条件失败：`test_sim_2026-10-17T01-43-48-472Z_pid44279_ff2bc059.xcresult`。实际辅助功能树显示，原生顶部浮动导航是独立 Button，位于 TabBar 之外。夹具现等待手机 TabBar 或具有实际图标标识和标题的原生浮动按钮，再核对可交互并导航；没有为测试改变产品导航。

调整后的“我”、工坊与登录取消旅程 **3 通过 / 0 失败 / 0 跳过**：`test_sim_2026-10-17T01-49-26-784Z_pid44279_2246c85c.xcresult`。该集合的登录仍属于上文旧选择器匹配；收紧后的真实输入框另 **1 项通过**：`test_sim_2026-10-17T01-59-18-193Z_pid44279_66814a9a.xcresult`，已复核实际输入框聚焦、取消、返回焦点与清理。手机端工坊标准字号 / “我”最大字号的导航回归另 **2 项通过**：`test_sim_2026-10-17T01-53-18-760Z_pid44279_155536fb.xcresult`。这些执行分别保留，不能合成一次完整矩阵。

四项 iPad 执行的状态均恢复为原先关闭，专用模拟器已删除。这不覆盖 iPad 横屏、其他字号 / 外观或完整系统审计；FC 应用的“两栏之间”几何检查目前以 iPhone 布局为准。

## 保留的失败与限制

- 初次屏幕中心双击和单击不能完成目标导航，已改为目标控件的双击，没有取消导航断言。返回按钮朗读使用空格分隔，早期仅接受逗号的查找失败，已修正分隔判断并保留步数上限。
- 返回最初读到“我 标题”，未恢复设置入口；增加原生返回焦点状态后，上述四项旅程通过。没有删除恢复焦点断言。
- 早期用例把可变数组以 `inout` 跨越测试中断，清理时 runner 在 `swift_beginAccess` 崩溃；改用独立记录对象，并在 `tearDownWithError` 恢复系统状态。原始崩溃与一次中断集合保留，清理专项的通过不算产品旅程通过。
- 系统 `.all` 审计仍报告对比度问题，详见[系统辅助功能审计](./ios-accessibility-audits.md)。本记录不把模拟器的朗读通过扩大为全量无障碍通过。
- 已登录资料、登录成功后的资料焦点、密码 / 自动填充 / 验证码、SSO 授权、错误反馈及所有业务页面尚未完成 VoiceOver 矩阵；本轮没有重跑真实账号登录。
- 真机手势、屏幕幕帘、转子、盲文、Voice Control / Switch Control，以及 iPad、横屏、最低系统和减少动态效果等组合仍待验。新 API 的模拟器结果不能替代这些人工与设备验收。
- 本轮已连通的真机为 iOS 26.6.1，不能运行该 iOS 27 API。Benchmark 的 iPhoneOS 未签名构建通过，但可运行构建受 Xcode 账号、开发签名私钥及 Associated Domains 描述文件阻断；自动配置尝试也未解决。没有安装真机包或在真机启用 VoiceOver，见[设备验收条件](./ios-accessibility-audits.md)。

原始结果包与导出媒体保留在本机工作记录中，不进入 Git；没有安装正式 Bundle、归档或发布。
