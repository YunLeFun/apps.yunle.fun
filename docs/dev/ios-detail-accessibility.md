# 应用详情的动态字号

详情继续使用原生 NavigationStack、List、系统按钮和语义字体，最低 iOS 16。辅助字号下将图标放在名称 / 作者上方，让正文使用整行宽度；标准字号保留并排布局。使用系统 [AnyLayout](https://developer.apple.com/documentation/swiftui/anylayout) 切换排列，操作与页面状态沿用同一实现。

“获取 / 试用”使用 [ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits) 按实际宽度选择横排或纵排。按钮仍执行原有获取、权限核验和运行时操作，没有缩小字体、截断名称或用图片替代正文。

## 复现与布局验证 · 2026-10-17

原布局在 320 × 800pt 测试窗口、最大辅助字号下，被 84pt 图标挤占的名称接近两字一行。长名称样例的首个信息区高 **855pt**，超过列表 **684pt** 的可见高度，主要操作被推至屏幕外。实际产品视图的回归断言失败：`test_sim_2026-10-17T06-18-08-438Z_pid44279_b1b6db6b.xcresult`。

只调整图标方向后，首区高度检查通过，但截图中“获取”仍拆成上下两个字；此中间结果未作为完成证据。增加操作区的原生宽度适配后，完整名称自然换行，两个操作分别单行显示。首区高 **656.7pt**，标准字号为 **176.7pt**；字体、图标尺寸和内容均保留。

`ApplicationDetailLayoutTests` 在实际产品视图中使用隔离的访客云居和内存账号，附加截图及列表几何结果，并核对没有获取 / 启动应用。长名称和 `example.invalid` 是明确的离线样例，不算真实目录或账号证据。

标准 / 最大辅助字号 × 浅色 / 深色的四项为 **4 通过 / 0 失败 / 0 跳过**：`test_sim_2026-10-17T06-20-19-917Z_pid44279_18165ce8.xcresult`。截图已复核；随后夹具改为等待实际首个列表单元就绪，避免固定睡眠与渲染速度耦合。

本轮完整日常集合为 **270 通过 / 3 失败 / 0 跳过**：`test_sim_2026-10-17T06-21-16-023Z_pid44279_967d9abe.xcresult`。266 单元 / 集成和其余四条 UI 通过，三条登录键盘用例失败，日志显示软键盘位于屏幕外；这是完整失败的执行，不能记作 273 项通过。原断言、执行时限和失败包保留，改用新建隔离模拟器验证环境差异，不为通过而减少软键盘检查。

新建隔离 iPhone 18 Pro / iOS 27 模拟器完成启动迁移后，三条原键盘用例与更新后的四项详情布局检查为 **7 通过 / 0 失败 / 0 跳过**：`test_sim_2026-10-17T06-27-22-800Z_pid44279_0e5a9643.xcresult`。这是专项复验，原完整集合仍保留失败；当前证据支持原模拟器状态存在差异，尚未确定其内部原因。专用模拟器已关闭删除，原有模拟器与用户偏好保留。

## 真机与 VoiceOver 范围

新的开发签名 Benchmark 已在 iPhone 15 Pro / iOS 26.6.1 上复验真实云空调会话与 AI 春联取消返回，**2 通过 / 0 失败 / 0 跳过**；云空调增加实际截图标题识别，见[真机记录](./ios-device-validation.md)。

另用系统启动接口将公开云空调链接明确交给 Benchmark，在最大辅助字号、浅色 / 深色分别截图。名称、作者及“打开”按钮完整显示；之后不带临时参数重启，恢复原应用字号 / 外观选择。该验证不修改系统全局偏好，也不是 Universal Link 系统分发或两按钮状态的点击验收。

新增 iOS 27 VoiceOver 用例检查从寻乐双击进入真实详情、朗读并揭示主要操作、“试用”的相邻顺序，以及返回后的原入口焦点。执行结果见[VoiceOver 验证](./ios-voiceover-validation.md)；iOS 26 无法运行该服务 API，硬件朗读按用户当前范围保留为未覆盖，不再安排执行。

随后发现并修复返回寻乐时焦点落到页面标题的问题。标准 / 最大字号的详情朗读在浅色、深色分别 **2 项通过**，四例均恢复原 VoiceOver 状态；深色同次普通触摸详情进入 / 返回另 **1 项通过**。用户后续明确仅用模拟器，因此这些焦点与普通触摸增量都在 iOS 27 模拟器执行，不再安排真机复验。

原有四 Tab 的系统审计仍有对比度失败，寻乐在 iOS 27 模拟器中的裁切尚未关闭。详情布局和寻乐返回焦点分别验证，不把局部布局与朗读结果扩大为全量 UI / 无障碍通过。

## 紧凑模拟器 · 2026-10-17

按用户后续仅使用模拟器的范围，新建 iPhone SE（第 3 代）/ iOS 27，在 375 × 667pt、浅色最大辅助字号下完成普通触摸“寻乐 → 真实详情 → 系统返回”。“今天来做菜”、作者和获取 / 试用按钮完整显示，主要操作可交互且位于原生导航栏与 Tab 栏之间，未执行获取或启动。

初次集合 `test_sim_2026-10-17T06-52-59-878Z_pid44279_9ccb31cb.xcresult` 为 **1 通过 / 2 失败 / 0 跳过**：普通触摸通过，两项 VoiceOver 在启用后的首次语音读取中返回 `No speech available`，未开始目标内容朗读，不能计为详情 VoiceOver 通过。两份附件均确认恢复原先关闭的状态。工具在 300 秒停止等待，底层 Xcode 继续跑完；已核对最终结果包与测试进程退出，没有重复启动同一集合。

仅在初始无语音时前进一次焦点的诊断仍失败，返回 `Failed to send moveForward command`（`test_sim_2026-10-17T06-59-04-131Z_pid44279_d68da9bc.xcresult`）。该夹具试验已撤回，未提交自动重试或跳过，继续用原朗读断言检查模拟器运行状态。

用原夹具、相同源码经标准构建 / 启动流程后，最大辅助字号详情专项 **1 通过 / 0 失败 / 0 跳过**：`test_sim_2026-10-17T07-02-05-120Z_pid44279_9dcff119.xcresult`。实际朗读“获取 → 试用”，系统返回后读出原入口的完整名称 / 摘要，截图显示操作完整可见，VoiceOver 恢复为关闭。

随后标准字号专项仍在首次语音读取时报错，**0 通过 / 1 失败 / 0 跳过**：`test_sim_2026-10-17T07-04-30-160Z_pid44279_07ab1fb4.xcresult`，清理状态同样恢复关闭。Apple 将 [`noSpeech`](https://developer.apple.com/documentation/xcuiautomation/xcuivoiceoverservice/error/code/nospeech) 定义为在时限内没有产生语音；当前尚未确定此模拟器状态差异的根因，不能声称标准字号通过或问题已修复。各次结果分别保留，专用小屏模拟器已删除，原有模拟器与用户偏好保留。

## iPad 详情专项 · 2026-10-17

新建 iPad Pro 11-inch（M5）/ iOS 27，竖屏 834 × 1210pt。普通触摸用例按真实图标标识 / 标签选择原生浮动“寻乐”按钮；页面保持原生导航，测试没有把 iPad 改为底部 Tab。详情可见性检查仅在实际存在底部 TabBar 时扣除其区域；iPad 没有底栏时使用窗口下边界，iPhone 仍必须存在原生底部 TabBar。

浅色最大辅助字号 **1 通过 / 0 失败 / 0 跳过**：`test_sim_2026-10-17T07-12-16-296Z_pid44279_e8cdccb5.xcresult`；深色同一旅程另 **1 通过 / 0 失败 / 0 跳过**：`test_sim_2026-10-17T07-13-07-707Z_pid44279_6703d1a7.xcresult`。已复核实际浅深色截图，名称、作者、获取 / 试用完整显示，主要操作位于导航下方，系统返回后原精选入口仍可交互。没有执行获取或启动。

iPad 最大字号 VoiceOver 则 **0 通过 / 1 失败 / 0 跳过**：`test_sim_2026-10-17T07-09-29-326Z_pid44279_f16a4754.xcresult`，首次读取语音报 `No speech available`，未进入详情，清理恢复原先关闭状态。交互工具此前两次创建远程自动化会话超时，改用 XCTest 后普通触摸已完成；不能以触摸、截图或编译结果替代该朗读失败。

标准字号的诊断执行同样 **0 通过 / 1 失败 / 0 跳过**：`test_sim_2026-10-17T07-14-20-055Z_pid44279_a804892e.xcresult`，报 `Lost connection to testmanagerd`。随包崩溃报告的进程是系统 `testmanagerd`，`EXC_BAD_ACCESS` 栈位于 `AXVoiceOverAutomationClient enableVoiceOverWithTimeout:error:` / `XCTDVoiceOverInterface enableWithTimeout:error:`；这是此断连的直接证据，尚不能解释此前所有 `No speech available`。Xcode 重启 runner 后的“0 项通过”不算成功，最终结果仍为失败。

该次未完成正常状态恢复，专用 iPad 的 VoiceOver 偏好仍为开启。已关闭并删除这台临时模拟器及其测试状态；原有 iPhone 模拟器偏好核对为关闭，用户环境保留。额外读取服务描述的诊断未取得输出，已撤回，不加入重试或跳过。iPad 详情朗读矩阵继续未完成。

最终测试适配在原有 iPhone 18 Pro / iOS 27、深色最大辅助字号回归 **2 通过 / 0 失败 / 0 跳过**：`test_sim_2026-10-17T07-16-31-093Z_pid44279_775699bd.xcresult`。普通触摸与 VoiceOver 详情均通过，实际朗读、获取 / 试用相邻顺序和原入口焦点恢复已核对，状态恢复为关闭；随后系统偏好读回同样为关闭。测试工具配置恢复原 `ios-native`，专用小屏 / iPad 已清理，原有模拟器保留。

## iPad 横屏验证 {#ipad-landscape-validation}

2026-10-18 使用 `22fbbfc` 的干净源码及新增 Benchmark 夹具，在新建独占 iPad Pro 11-inch（M5）/ iOS 27 验证实际公开“今天来做菜”详情。只有测试源码变化，未包含并行缓存实现或修改产品页面。每例先建立 `834 × 1210pt` 竖屏起点，确认访客身份，再要求窗口实际变为 `1210 × 834pt`；不能只凭 [`XCUIDevice.orientation`](https://developer.apple.com/documentation/xcuiautomation/xcuidevice/orientation) 的物理方向判断界面方向。

最终带整屏截图的四例 **4 通过 / 0 失败 / 0 跳过**，分别保存在 `light-display.xcresult` 和 `dark-display.xcresult`：

| 外观 | 字号         | 用例时间 | 获取按钮范围（pt）          |
| ---- | ------------ | -------- | --------------------------- |
| 浅色 | 标准         | 33.628s  | x=140，y=262.5，58 × 34.5   |
| 浅色 | 最大辅助字号 | 31.887s  | x=40，y=448.5，144.5 × 77.5 |
| 深色 | 标准         | 33.436s  | x=140，y=262.5，58 × 34.5   |
| 深色 | 最大辅助字号 | 32.081s  | x=40，y=448.5，144.5 × 77.5 |

四例均确认获取 / 试用可交互、主要操作位于导航栏下方，页面没有 WebView；通过系统返回后，原精选入口仍可交互。没有点击获取、试用、分享或评价。XCTest 清理阶段逐例恢复竖屏，四份回读均为 `834 × 1210pt`。整屏截图已逐图核对实际浅深色、完整名称、作者、摘要及两项操作；这不替代触达区域、对比度、VoiceOver 或全部滚动内容的审计。

同一最终测试产物在本任务独占 iPhone 18 Pro / iOS 27 复验原有最大字号详情路径，**1 / 0 / 0**，用例 18.697 秒，保存为 `iphone-regression.xcresult`。没有改变原手机端 TabBar 要求；本轮新建 iPad 已关闭删除，原独占 iPhone 已关闭保留。

保留的前置失败包括一次测试目标名选择错误（未执行用例），以及两项物理方向初始值检查失败（尚未旋转或进入详情）。后者促使夹具明确建立竖屏起点，并把恢复放入 XCTest teardown，而不是依赖测试方法内 `defer`。此前仅带应用截图的浅深色四例也通过，但不与最终四例合并成一次矩阵。

本运行时的 `app.screenshot()` 横屏应用裁图带旋转元数据，查看时出现黑边和截断；同一页面另取 `XCUIScreen.main.screenshot()` 后完整显示。测试保留两种原始截图、完整 AX 和几何记录，没有旋转、裁切或重绘图片来证明布局。证据统一保存于本聊天 `ipad-landscape-22fbbfc/`。原 iPad VoiceOver 的无语音 / 系统服务崩溃、系统全量审计及其他 G4 状态继续未完成。

两条用例为 `ApplicationBenchmarks/testNativeIPadLandscapeDetailAtStandardText` 与 `testNativeIPadLandscapeDetailAtLargestText`，目标是 `YunleFunBenchmarksTests`，Scheme 为 `YunleFunBenchmarks`。执行时显式提供 `TEST_RUNNER_YLF_IPAD_LANDSCAPE_DETAIL=1`、`TEST_RUNNER_YLF_OWNED_BENCHMARK_SIMULATOR_UDID` 及 `TEST_RUNNER_YLF_ACCESSIBILITY_APPEARANCE=light|dark`；只有声明的独占 iPad 模拟器可以进入夹具。
