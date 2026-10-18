# 原生云应用菜单

独立 iOS 客户端的云应用“更多操作”使用 SwiftUI `NavigationStack`、`List`、`Section`、`NavigationLink` 和系统工具栏，由 `UIHostingController` 承载在系统 `pageSheet` 中。系统负责圆角、材质、返回、滚动、浅深色与动态字号；不自行绘制玻璃背景或菜单卡片。部署下限仍为 iOS 16，新系统采用对应的系统组件外观。

设计依据见 Apple [List](https://developer.apple.com/documentation/swiftui/list) 和 [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)。

## 页面与操作

- 应用信息复用原生图标加载管线；网址只显示 scheme、host 和 port，不显示用户信息、路径、查询或片段。
- 详情、评分与评价、作者公开作品在同一原生导航栈内打开。私有工坊和所有者预览不显示公开评价入口；作者展示名和作品查询标识分别使用 `author` 与 `ownerLogin`。
- 从当前应用的详情可“返回应用”；菜单及其详情、评价和作者页面提供系统“完成”入口。
- 分享、复制链接、浏览器打开、重新载入及结束仍调用宿主已有行为。分享使用 `UIActivityViewController`；结束使用系统 destructive 角色并说明会话会释放。
- 菜单默认 large，允许收拢到 medium。长内容及辅助字号可继续滚动，不使用固定内容高度或固定圆角。

## 宿主边界

共享 `WebViewController` 只接收原生宿主提供的菜单页面与动作回调。旧 Capacitor 宿主未安装此工厂，继续使用既有菜单。

动作在 UIKit 弹层关闭完成后执行，避免分享弹层与菜单同时呈现。菜单 ID、重复点击保护、可见宿主、当前控制器、账号 generation 与运行时 identity reset 在执行前后校验；退出、切换账号或关闭旧会话后，保留的旧回调不得结束或操作新会话。

标题进入详情的原生工厂同时修正了 reviews 目标，并读取当前会话元数据。标题入口已进一步接入[系统导航栏](./ios-runtime-navigation.md)，显隐与几何也有专项验证；沉浸胶囊、多层弹层与账号变化等完整运行时行为继续按迁移计划验证。

## 验证记录

新增 5 项专项通过：网址显示不泄漏导航参数、重复结束只执行一次、弹层关闭期间身份变化丢弃动作，以及浅色和深色辅助字号截图。真实目录中的云空调另有实际收起 / 恢复 / 结束旅程通过。

完整菜单 XCUITest 在 iPhone 18 Pro / iOS 27 通过 1 项，实际点击详情“返回应用”、评价、作者和“完成”，复制链接后回到原网页，Safari 加载真实云空调，再回原生应用调出系统分享、关闭分享、重载及结束。详情前后的 WebView 节点数量保持一致。

初次测试发现 medium 初始高度隐藏结束入口、工具栏在子页面未配置，以及测试误以为系统分享面板有 Close 按钮。菜单改为默认 large，各原生目的页面通过共享环境上下文显示系统工具栏，分享测试使用当前系统实际提供的外部关闭区域。失败结果保留，不计入通过数量。

本菜单阶段的原生日常回归 213 项（212 单元 / 集成 + 1 UI）全部通过，无新增运行时告警。菜单旅程结果为 `test_sim_2026-10-16T05-35-40-626Z_pid92585_e928e167.xcresult`，日常回归结果为 `test_sim_2026-10-16T05-37-00-722Z_pid92585_5d6ff6c7.xcresult`。截图导出到仓库外 `ios-native/native-menu/journey-27` 与 `daily-27`；完整路径见本轮 `verification.json`。

复测入口：日常 Scheme 为 `YunleFun`，专项类为 `YunleFunTests/NativeApplicationMenuTests`；真实界面 Scheme 为 `YunleFunBenchmarks`，选择 `ApplicationBenchmarks/testNativeCloudApplicationMenuRoutesAndCommands` 和 `ApplicationBenchmarks/testNativeCloudAirCanMinimizeRestoreAndEnd`。真实界面测试依赖公开目录与云空调网站，不登录、不购买、不提交分享目标。

共享容器还通过旧 Capacitor 工程的 Release 模拟器编译，保留既有 3 条 Pods 构建脚本提示。本地 Manifest 与仓库锁文件原先仅生成器版本不同，已用隔离安装的 CocoaPods 1.16.2 执行 deployment 安装后重建；仓库的依赖、锁文件及旧工程没有额外改动。

本轮不代表全量 UI、VoiceOver、iPad、真机、最低系统或发布验收完成。已有键盘工具栏告警单独跟踪于[键盘布局诊断](./ios-keyboard-layout-diagnostics.md)。
