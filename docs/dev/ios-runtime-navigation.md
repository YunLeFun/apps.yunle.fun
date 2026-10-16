# 原生云应用导航栏

独立 iOS 客户端使用 `UINavigationController`、`UINavigationItem` 和 `UIBarButtonItem` 承载云应用导航。系统管理标题、按钮分组、材质、安全区和尺寸适配，应用不自行绘制顶栏背景。采用 Apple [标准组件的 Liquid Glass 适配](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)与 [UIKit 新设计指南](https://developer.apple.com/videos/play/wwdc2025/284/)。

## 行为

- 导航标题通过系统标题菜单进入原生应用详情。菜单采用 iOS 16 起可用的 `titleMenuProvider`。
- 返回按钮跟随真实 WebKit 历史更新，网页侧滑返回继续使用 `allowsBackForwardNavigationGestures`。收起与更多操作使用系统导航项。
- 导航面采用系统配色；应用主题色保留在进度条和网页中。旧 Capacitor 宿主继续使用原有主题色标题栏与布局。
- `hideTitleBar` 仍允许网页延伸到屏幕顶部。收起、返回和更多转为 44pt 原生浮动按钮，iOS 26 起使用 `UIButton.Configuration.glass()` 与 `UIGlassContainerEffect`，早期系统使用语义配色的系统按钮回退。
- 浮动容器仅响应按钮区域，按钮之间的网页仍可交互。`showTitleBar` 恢复系统导航栏和网页视口。

## 会话与协议

会话池将 WebView 和导航容器作为一个会话保留。收起后复用同一导航容器及 WebKit 历史；结束、身份重置和内存淘汰同时释放两者。宿主授权页继续由同一个浏览器控制器发起，不向网页传递宿主令牌。授权与延迟菜单动作同时检查导航容器的转场状态；真实 UIKit 转场专项确认容器仍在窗口中、但正在退出时不能开始登录。

`getEnv` 的字段保持原有结构，坐标仍相对 WebView 视口。系统导航栏可见时，`capsuleRect` 返回视口上方的整条导航栏避让区域，避免依赖系统导航按钮内部视图；隐藏后返回实际浮动更多按钮的矩形。显隐调用先同步布局，再回复 JS，调用方可立即重新读取几何。

## 验证

新增 5 项导航专项，连同更新为导航容器承载的 5 项菜单专项共 10 项通过。最终日常回归 218 项（217 单元 / 集成 + 1 UI）通过，无新增告警。实际 WebKit 验证 JSAPI 显隐后的即时安全区与避让区域、按钮间的网页触摸穿透和前进后退历史；浅色、深色辅助字号及长标题截图已导出。

真实云空调的系统标题菜单 / 详情返回、收起恢复结束两项旅程通过，完整更多菜单旅程另 1 项通过，包括 Safari 实际加载、系统分享返回及重载。AI 春联的访客授权登录取消在最终源码另通过 1 项。首次验证发现隐藏的浮动按钮仍出现在无障碍树中，已对整个浮动容器显式控制显隐、交互与 accessibilityElementsHidden；实际旅程断言收起入口唯一。系统标题菜单使用系统附加的操作菜单标签定位。

旧 Capacitor Release 模拟器编译通过，保留既有 3 条 Pods 脚本提示。部署下限仍为 iOS 16；本轮运行证据来自 iPhone 18 Pro / iOS 27。

新导航容器下的真实 SSO 成功路径仍待复验。两次显式尝试分别被模拟器点击连接故障、输入通道改写用户名阻断，均未提交密码或完成登录，最终测试均失败。第一次没有完成交互；第二次进入了原生密码表单并取消。测试进程均已确认终止，一次性 0600 输入文件已被消费删除，本地镜像与临时页面已关闭。不能将工具 300 秒观察超时或已完成的访客取消算作 SSO 成功。

第二次 SSO 尝试在聚焦表单后仍记录 Invalid frame dimension 告警，与[键盘 Sheet 诊断](./ios-keyboard-layout-diagnostics.md)中的告警同文；本轮没有将其修复。此前完整真实 SSO 证据保留在[宿主授权记录](./ios-host-authorization.md)，但不替代导航容器改造后的成功验证。

最终结果目录：日常回归 `test_sim_2026-10-16T06-30-53-800Z_pid92585_52d49361.xcresult`，四条真实页面旅程在同一次 `test_sim_2026-10-16T06-33-23-240Z_pid92585_54e76514.xcresult` 全部通过。仓库外 `ios-native/system-navigation/verification.json` 保留完整路径、源码摘要、失败尝试和清理状态。

成功登录后的保留会话、多层第一方弹层与账号变化、跨应用会话压力，以及完整 VoiceOver、iPad、最低系统、真机和性能验收仍在整体迁移计划中；本页不将构建成功或夹具截图视为完整 UI 验收。
