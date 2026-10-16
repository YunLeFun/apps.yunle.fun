# 原生登录键盘布局诊断

> 2026-10-16。iPhone 18 Pro / iOS 27.0（24A434）。告警仍未修复；现有登录 Sheet、键盘完成按钮和表单交互保留。

## 可复现范围

UIKit 以 pageSheet 展示 UIHostingController 时，聚焦 SwiftUI 密码字段可触发 Invalid frame dimension (negative or non-finite)。无需输入密码、提交表单、登录或调用业务服务。

已将场景缩减到仅含 NavigationStack、Form、SecureField 和系统 keyboard toolbar 的 SwiftUI 视图。它不依赖云乐坊账号、WebView 或业务页面，仍会产生同一告警；改为 fullScreen 的对照用例通过。XCTest 捕获的原始调用栈经 LLDB 符号化，告警路径位于 SwiftUI.InputAccessoryBar.body 与 SwiftUI.\_FrameLayout.init。

这证明当前模拟器上存在该系统组件组合的问题，不证明所有系统 / 设备都受影响，也不表示其他布局与无障碍项目已经验收。

| 检查                                                 | 结果                                                         |
| ---------------------------------------------------- | ------------------------------------------------------------ |
| 原生 LoginView / UIKit pageSheet / 密码焦点          | 产生同一告警                                                 |
| 纯 SwiftUI 最小表单 / UIKit pageSheet                | 产生同一告警                                                 |
| 同一最小表单 / fullScreen                            | 通过，无该告警                                               |
| 移除 Spacer、改为单个 keyboard ToolbarItem           | 告警仍在                                                     |
| preferredContentSize / intrinsicContentSize 自动尺寸 | 告警仍在                                                     |
| 用 bottomBar 承载完成操作                            | 告警消失，但完成按钮被数字键盘遮挡，交互验收失败；候选已撤回 |

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

后续在其他系统、真机或更新 SDK 后复测，核对完成按钮、焦点、滚动、大字体与授权连续流程。当前先保留可用交互，继续迁移矩阵中其他原生界面的实施。

## 依据

- [XCTSourceCodeFrame](https://developer.apple.com/documentation/xctest/xctsourcecodeframe)：读取告警的原始栈帧；没有将异步处理告警时的线程栈当成触发栈。
- [UIHostingController](https://developer.apple.com/documentation/swiftui/uihostingcontroller)：使用公开的 UIKit / SwiftUI 承载与尺寸配置。
