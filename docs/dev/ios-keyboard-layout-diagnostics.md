# 原生登录键盘布局诊断

> 2026-10-17 更新。iPhone 18 Pro / iOS 27.0（24A434）。原生登录已改用系统导航栏收起键盘，避开原 keyboard toolbar 组合的告警；原始最小对照仍失败，系统问题未被宣布修复。

## 可复现范围

UIKit 以 pageSheet 展示 UIHostingController 时，聚焦 SwiftUI 密码字段可触发 Invalid frame dimension (negative or non-finite)。无需输入密码、提交表单、登录或调用业务服务。

已将场景缩减到仅含 NavigationStack、Form、SecureField 和系统 keyboard toolbar 的 SwiftUI 视图。它不依赖云乐坊账号、WebView 或业务页面，仍会产生同一告警；改为 fullScreen 的对照用例通过。XCTest 捕获的原始调用栈经 LLDB 符号化，告警路径位于 SwiftUI.InputAccessoryBar.body 与 SwiftUI.\_FrameLayout.init。

这证明当前模拟器上存在该系统组件组合的问题，不证明所有系统 / 设备都受影响，也不表示其他布局与无障碍项目已经验收。

| 检查                                                       | 结果                                                         |
| ---------------------------------------------------------- | ------------------------------------------------------------ |
| 原 LoginView keyboard toolbar / UIKit pageSheet / 密码焦点 | 产生同一告警                                                 |
| 纯 SwiftUI 最小表单 / UIKit pageSheet                      | 产生同一告警                                                 |
| 同一最小表单 / fullScreen                                  | 通过，无该告警                                               |
| 移除 Spacer、改为单个 keyboard ToolbarItem                 | 告警仍在                                                     |
| preferredContentSize / intrinsicContentSize 自动尺寸       | 告警仍在                                                     |
| 用 bottomBar 承载完成操作                                  | 告警消失，但完成按钮被数字键盘遮挡，交互验收失败；候选已撤回 |

bottomBar 候选的真实 AI 春联登录 / 授权 / 退出旅程通过，不能证明键盘操作可用。该次工具观察在 300 秒超时后，通过同一进程与日志确认执行已终止，读取原 xcresult 核实 1 项通过及测试会话清理，没有因此重新启动测试。

## 独立诊断入口

三个检查保存在 LiveValidation/KeyboardLayoutDiagnostics.swift，属于独立 YunleFunLiveValidation Scheme。默认跳过，需要显式 YUNLEFUN_UI_LAYOUT_DIAGNOSTICS=1 和空闲的专用模拟器；不读取测试账号文件，不向外部发送凭据。该诊断保留失败断言，用于后续 SDK / 系统变化的复核。

从仓库根运行，将 SIMULATOR_UUID 换成本机可用设备：

```sh
TEST_RUNNER_YUNLEFUN_UI_LAYOUT_DIAGNOSTICS=1 xcodebuild \
  -project apps/ios/YunleFun.xcodeproj \
  -scheme YunleFunLiveValidation -configuration Debug \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -parallel-testing-enabled NO \
  -only-testing:YunleFunLiveTests/KeyboardLayoutDiagnostics test
```

在上述环境的实际结果为 1 项通过、2 项失败，失败分别对应纯 SwiftUI Sheet 和原生登录 Sheet 的同一告警。未启用时的跳过不代表问题已修复，不计为 UI 验收通过。聊天附件 ios-native/keyboard-layout 保存实验、原始结果引用和调用栈；生产源文件未保留候选布局或调试插桩。

后续仍需在其他系统、真机或更新 SDK 后复测，核对焦点、滚动、大字体与授权连续流程。上述表格与早期三例结果保留为原方案的诊断证据。

## 原生表单调整 · 2026-10-17

登录仍使用原生 Form、TextField、SecureField 和 Sheet。收起键盘移至系统导航栏尾端，仅在字段聚焦时显示；iOS 17 起使用 `topBarTrailing`，iOS 16 使用系统导航项回退。按钮明确标为“收起键盘”，保持取消和登录操作各自的含义。手机号、邮箱、用户名、密码、验证码补齐独立无障碍名称与稳定标识，字段有内容时仍能辨认用途。

原生密码焦点诊断已通过；同轮 fullScreen 最小对照通过，原 pageSheet / keyboard toolbar 对照仍失败，整组三例为 **2 通过 / 1 失败**，不是整组通过。结果为 `test_sim_2026-10-16T16-31-16-316Z_pid44279_f62dd416.xcresult`。

新增真实 XCUITest 检查标准字号的手机号 / 密码输入及最大辅助字号的数字键盘。测试输入一次性字符，不提交登录；要求键盘在屏幕内、按键可交互、收起按钮可点击且位于键盘上方，点击后键盘与按钮消失。兼容系统将按键暴露为 Key 或 Button 的两种角色。软件键盘模式下两例通过，无新增告警：`test_sim_2026-10-16T16-44-33-694Z_pid44279_1088846b.xcresult`，全屏截图已复核。

初轮仅检查键盘元素存在，截图未覆盖软件键盘，证据不足；补齐可见性后保留了失败。另一次因只查询 Key 角色而漏掉字母键，独立实际操作确认后修正查询，保留可见性断言。原有模拟器恢复硬件键盘模拟后，完整日常结果为 **264 通过 / 2 失败**，两项均因软件键盘处于屏幕外失败；不合并为完整通过。隔离环境验证与 CI 按各自终态另外记录。

新建独立 iPhone 18 Pro / iOS 27 模拟器，不连接 Device Hub 的桌面硬件键盘，等待首次系统迁移完成后运行完整日常 Scheme，最终 **266 通过 / 0 失败 / 0 跳过**（260 单元 / 集成 + 6 UI）：`test_sim_2026-10-16T16-51-41-396Z_pid44279_53e18db2.xcresult`。保留键盘全部可见性 / 可操作性断言；没有改变全局偏好或注入线上账号。专用模拟器在验证后删除，原有设备与设置保留。此通过与前述硬件键盘模式失败分开记录，后续远端 CI 以新提交自身结果为准。

相同最终表单源码的实际 AI 春联 SSO UI 与原生密码焦点诊断随后同次运行，**2 通过 / 0 失败 / 0 跳过，无新增告警**：`test_sim_2026-10-16T16-57-33-952Z_pid44279_65b772f5.xcresult`。完成真实密码登录、原生授权、网页身份与退出，测试会话和一次性输入已清理，见[SSO 复验](./ios-runtime-navigation.md#新导航容器真实-sso-复验-·-2026-10-17)。这不改写原 pageSheet / keyboard toolbar 最小对照的失败。

该调整不代表完整 VoiceOver、所有登录方式、最低系统或真机验收完成。标准字号“我”页的裁切 / 动态字号 / 对比度审计仍失败，见[辅助功能审计](./ios-accessibility-audits.md)。

## 托管执行中的按键查询

`6051799` 的托管 CI 在标准字号手机号键盘处失败，截图实际显示键盘和已输入的字符；日志记录测试先反复查询不存在的 Key 角色，耗尽 5 秒等待，未能完成后续 Button 查询。现改为按已知按键名称跨角色定位，先核对屏幕范围，再检查该按键可点击；就绪等待为 10 秒，失败时额外保存完整树。键盘不能在屏幕外、按键必须可操作、收起按钮必须在其上方并实际完成收起等断言保留。

新查询下的两条键盘 UI 在独立模拟器分别通过，首轮集合因旧版导入另有失败，不能合并为整组通过。该托管运行共 264 通过 / 2 失败，另一项为旧版导入读取失败，Release 编译未执行；完整 CI 与修正后的终态见[执行记录](./ios-ci-and-open-source.md)和 PR #48。

下一轮 `842cef1` 为 267 通过 / 1 失败：标准字号方法在进入登录表单前的组合文字入口查询卡住，触及 120 秒用例限制，并未执行到键盘；其余五条 UI 和全部 262 项单元 / 集成通过。登录入口现按 `me.login` 直接定位，并等待“我”页导航就绪，保留可访问文字断言。新建模拟器完整 6 UI 通过，`test_sim_2026-10-16T18-34-51-200Z_pid44279_82a73a01.xcresult`。该变化用于稳定自动化入口定位，不改写剩余页面辅助功能审计或系统最小对照的失败。

`096f076` 的六条 UI 在远端均通过，组合标准字号手机号 / 密码用例用时 114 秒，接近 120 秒用例时限。两种登录方式现拆为独立旅程，各自从访客页面进入并执行实际输入 / 可访问名称 / 软件键盘 / 收起检查；每项时限保持 120 秒。连同原有最大字号及其他导航，完整七条 UI 在新建模拟器通过，`test_sim_2026-10-16T20-13-59-437Z_pid44279_eba5992b.xcresult`。完整日常现为 269 项，远端完整终态单独记录。

## 最新日常 CI 失败核对 · 2026-10-18

PR48 头 `c11b1e4` 的 [39061035624](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39061035624) 原 xcresult 为 **415 通过 / 1 失败 / 0 跳过**。全部 406 项单元 / 集成通过；失败是标准字号密码键盘用例的收起等待，Release 编译跳过。这次不是 Cookie 初次清理失败。

原收起后截图中键盘与导航栏收起按钮均已消失，AX 树也不存在 `Keyboard` 或 `login.dismiss-keyboard`；密码字段仅保留测试字符的安全掩码。活动记录显示收起后仍重查原先 `x=0, y=590, width=402, height=226` 的键盘元素并发生内部 retry，随后查询已经移除的按钮；五秒 predicate 预算在这些查询中耗尽。该证据指向已移除元素的测试查询开销，不足以证明产品未收起键盘。

改为查询当前按钮数量与 `keyboards.allElementsBoundByIndex`：仍要求收起操作不存在，所有残留键盘与全部目标输入按键都不可交互。保持原五秒时限、显示时的屏幕范围 / 按键可点击 / 收起按钮位置断言，不添加点击重试、不改 LoginView、不过滤告警。此修正在专用 iOS 27 模拟器的三条键盘 UI 中全部通过：标准字号密码、标准字号手机号和最大辅助字号手机号均执行实际输入与收起，原五秒时限保持。结果为 `source-and-keyboard-tests.xcresult`（同包另有 60 项云居回归，总计 63 通过 / 0 失败 / 0 跳过），位于 `/Users/yunyou/.codex/artifacts/ios-native-goal-20261018/`。随后提交 `e7ea1cd` 的 [Native CI 39067045605](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39067045605) 中三条键盘用例及全部 10 条 UI 均通过；完整执行仍为 431 通过 / 2 失败 / 0 跳过，失败是首页初次 Cookie 清理和反馈页扫描，Release 跳过。键盘本次通过不改写先前失败，也不把整轮 CI 记为成功。

Apple 对 [allElementsBoundByIndex](https://developer.apple.com/documentation/xcuiautomation/xcuielementquery/allelementsboundbyindex) 的定义为立即执行当前查询并返回按索引绑定的结果；这里用空匹配集表达元素已经消失，避免重复解析旧节点。

## 参考资料

- [XCTSourceCodeFrame](https://developer.apple.com/documentation/xctest/xctsourcecodeframe)：读取告警的原始栈帧；没有将异步处理告警时的线程栈当成触发栈。
- [UIHostingController](https://developer.apple.com/documentation/swiftui/uihostingcontroller)：使用公开的 UIKit / SwiftUI 承载与尺寸配置。
- [topBarTrailing](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/topbartrailing)：由系统管理导航栏尾端的辅助操作。
