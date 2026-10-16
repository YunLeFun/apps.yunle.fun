# 原生系统辅助功能审计

`NativeAccessibilityAudits` 使用 Apple 的 [XCUIAccessibilityAuditType](https://developer.apple.com/documentation/xcuiautomation/xcuiaccessibilityaudittype) 与 `performAccessibilityAudit`，检查对比度、识别、点击区域、描述、动态字体、文字裁切和 trait。使用 `.all`，问题处理器只附加诊断并返回 `false`，保留 XCTest 失败；没有为通过审计而忽略某类问题。

## 执行

测试属于独立 `YunleFunBenchmarks` Scheme，只启动 `fun.yunle.apps.benchmark-dev`。在专用访客模拟器运行，保留已有云居数据，不替开发者退出账号。没有显式启用或运行于 iOS 17 之前时会跳过；跳过不能计为通过，也不在日常 `YunleFun` Scheme 中运行。

```sh
cd apps/ios
TEST_RUNNER_YLF_ACCESSIBILITY_AUDIT=1 xcodebuild \
  -project YunleFun.xcodeproj -scheme YunleFunBenchmarks \
  -configuration Benchmark \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath build-accessibility \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 180 \
  -only-testing:YunleFunBenchmarksTests/NativeAccessibilityAudits test
```

每个 Tab 分别以标准字号 `UICTContentSizeCategoryL` 和最大辅助字号 `UICTContentSizeCategoryAccessibilityXXXL` 启动，通过进程参数指定，不修改设备的全局偏好。每例附加当前截图和辅助功能树；失败另附问题类型、说明及系统能够定位的元素 / 范围。原始媒体留在本地结果包，不提交仓库。

导航和访客前置条件失败会立即停止；进入审计后允许继续记录多个 XCTest issue，仍将该例判为失败。无法在当前树中找到的系统元素只记录为 `none`，不会因为缺少定位而过滤该问题。

## 本轮界面调整

- “我”页的登录说明原先继承按钮的层级样式，实际显示为浅蓝色。改用系统 `Color.primary`，保留标题和图标的操作色；辅助字号改为图标与文字纵向排列，文字使用完整高度和可用宽度。
- “我”页的支持标题、工坊的应用分组标题和寻乐首个分组标题增强为系统主文字色，继续使用原生 Section 的布局与字体层级。
- 寻乐的“云乐坊出品”在辅助字号下省去装饰性符号，让完整文字使用可用宽度；普通字号仍使用原生 Label。没有缩小辅助字号，也没有固定行高来掩盖裁切。

这些改动不改变账号、云居内容或应用权限；实际审计结果与未解决的问题分别保留，不能根据截图直接判定系统审计通过。

## 实际结果

本轮使用原有 iPhone 18 Pro / iOS 27 模拟器。首次云居两例为 1 通过 / 1 失败；补齐问题附件后，“我”页报告登录说明对比度、文字裁切和支持标题对比度。第一次八例矩阵为 1 通过 / 7 失败，保留 `test_sim_2026-10-16T11-24-57-434Z_pid91503_98ac50b3.xcresult`。

完成上述界面调整并允许收集同一例的多个 issue 后，八例矩阵为 **2 通过 / 6 失败，0 跳过**：`test_sim_2026-10-16T11-29-33-181Z_pid91503_d44cf19d.xcresult`。这是一次完整失败的集合，不能把通过的两例代表整轮通过。

| 页面 | 标准字号                             | 最大辅助字号     |
| ---- | ------------------------------------ | ---------------- |
| 云居 | 对比度、裁切报告                     | 通过             |
| 寻乐 | 对比度、裁切报告                     | 通过             |
| 工坊 | 对比度、裁切报告                     | 对比度、裁切报告 |
| 我   | 对比度、裁切、部分动态字号不支持报告 | 对比度报告       |

截图已复核：登录说明完整换行，寻乐的出品说明在辅助字号下完整显示，工坊分组标题使用清晰的主文字色。寻乐最大字号的全部审计通过。“我”页两种字号仍失败，不能只根据登录说明的变化宣称整页已修复。

尚未解决的定位包括工坊的“个人工坊 / 打开个人工坊”、搜索提示，以及“我”页的部分原生操作行。多条对比度报告未提供可定位元素；这不构成忽略或认定系统误报的依据。普通目录的两行摘要也需与真实裁切问题分别复核，完整审计继续作为待完成项。

为排除测试传入字号参数的影响，在系统字号确认为 `large` 后去掉标准字号启动参数，仅重跑“我”页，仍得到相同 11 条报告：5 条动态字号、3 条裁切、3 条对比度，`test_sim_2026-10-16T11-34-46-921Z_pid91503_c5afab89.xcresult`。没有证据支持该参数是原因，已恢复原测试条件；尚不能据此判断剩余报告的根因。

未启用审计的对照为 **0 通过 / 0 失败 / 1 跳过**：`test_sim_2026-10-16T11-33-37-623Z_pid91503_ca162315.xcresult`。这是开关验证，不算辅助功能通过。

当前产品源码的日常回归为 **264 通过 / 0 失败 / 0 跳过**（260 单元 / 集成 + 4 UI）：`test_sim_2026-10-16T11-35-57-981Z_pid91503_57544a7a.xcresult`。审计代码不属于日常 Scheme，该结果不能覆盖或抵消上述审计失败。根 lint、受改文档检查和文档构建通过；Benchmark 的 release 优化编译通过，未安装正式 Bundle、发布或改动生产接口。

## 工坊辅助字号复测

继续以同一审计定位三个裁切报告。单纯对原生 Label 增加自然高度未改变问题，试验已撤回，失败结果 `test_sim_2026-10-16T14-54-41-550Z_pid91503_002fa812.xcresult` 保留。

辅助字号下改为完整 Text 入口、普通字号保留 Label，三条入口仍是原来的 NavigationLink。随后缩短辅助字号的搜索提示为“搜索应用”，保留普通字号的完整提示和原有检索行为。最终单项 `test_sim_2026-10-16T15-12-43-145Z_pid91503_782e7963.xcresult` 中三个裁切报告均消失，截图已复核完整文字与搜索提示。

该单项仍为 **0 通过 / 1 失败**：两条未定位元素的对比度报告保留，没有过滤 issue。这里是工坊最大字号的增量结果，不把上轮八例矩阵改写为整轮通过，也不替代人工 VoiceOver 或其他设备状态。

## 独立系统组件对照

在仓库外建立仅含标准 SwiftUI Tab、导航、列表、按钮、分组标题的独立应用，分别检查 Label 和纯 Text 操作行，不连接服务或读取产品数据。相同 iOS 27 模拟器与 `.all` 审计下，两例均失败：都报告对比度和“支持”标题的部分动态字号不支持，Label / Text 版本分别还有三条 / 两条裁切报告。结果保留为 `test_sim_2026-10-16T15-29-52-843Z_pid91503_fbb7ade4.xcresult`，对照应用已卸载。

这证明相同类别也出现在独立的标准组件组合中，尚不能证明产品报告全部属于系统问题。产品审计继续保留失败，不忽略问题或降低字体；后续需结合具体元素、系统版本与人工操作继续定位。

## 覆盖边界

审计只覆盖当时视口内呈现的内容，不能证明滚动末尾、其他状态、登录后页面或弹层全部通过。云居采用该访客已有的本机布局；目录内容来自现有公开服务或缓存，没有改写线上资料。还需人工 VoiceOver 阅读 / 焦点 / 操作，减少动态效果与透明度，以及浅色 / 深色、iPad、横屏、最低系统和真机验收。完整迁移 Goal 的相关勾选继续保留未完成。
