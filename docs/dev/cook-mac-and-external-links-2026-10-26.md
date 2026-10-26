# Cook：Mac SSO、能力降级与移动端 B 站外链验收

本记录补充 [Cook #98](https://github.com/YunYouJun/cook/issues/98) 和[前一轮 iOS / Android 登录验收](./cook-host-validation-2026-10-26.md)。宿主基线为 `7b18357ac0f47aeee7a3f99ef2d9e1552de796fa`，本轮只添加显式 live 夹具及记录，没有改变产品权限、注册策略、域名授信或发布客户端。

## 结果与范围

| 平台    | 实际环境                                                                      | 完成的验收                                                                                                 |
| ------- | ----------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Mac     | Apple Silicon / macOS 26.6.2，Testing 宿主与真实 WKWebView                    | 14 项检查通过；原生密码表单、实际授权面板、生产 Cook 换码与取消后重试；能力降级；宿主和消费端退出          |
| iOS     | 独立 iPhone 18 Pro / iOS 27.0 模拟器，实际共享容器                            | 8 项检查通过；真实触摸普通 B 站链接及菜谱按钮，实际 SFSafariViewController 接管，Cook 文档保留，关闭后返回 |
| Android | 独立 Pixel 8 / API 35 模拟器，Chrome 124.0.6367.219，实际 HostWebViewActivity | 两条实际触摸路径通过；前台均为 Chrome CustomTabActivity，地址栏为 B 站域名，Cook 文档保留，返回成功        |

本轮 runID 为 `c2f4d551-bea9-476a-8cfd-376e19090f7e`。Mac XCTest 完整旅程 1 通过 / 0 失败 / 0 跳过，另一个独立进程的清理测试通过；iOS XCTest 完整旅程 1 通过 / 0 失败 / 0 跳过；Android instrumentation 最终完整旅程 1 通过 / 0 失败。

## Mac：真实账号与能力降级

- 从生产目录读取 Cook，入口仍为 `https://cook.yunle.fun/home`。实际 `getEnv()` 为 `macos`、`trusted=true`、`titlebar`、`capsuleVisible=false`，没有 `capsuleRect`；Cook 胶囊避让为 `0px`，未发生布局脚本错误。
- 实际 `canIUse()` 返回 `authorize=true`、`haptic=false`、`setClipboard=false`。直接调用两个不支持接口会拒绝并返回 `HOST_API_UNSUPPORTED`，系统剪贴板 changeCount 保持原值；未读取或改写剪贴板内容。
- 实际点击食材后选择状态改变，未产生未处理异常；随后还原选择。这验证了 Cook 对无触感宿主的降级。
- 点击 Cook 登录入口，原生登录面板显示正确应用上下文。AppKit 控件事件填入固定受管测试账号；原生 UI 驱动实际点击登录与授权按钮，密码未进入消费端 JavaScript。
- 实际原生授权确认 → 生产签码 → Cook SDK 换码 → Cook 显示与宿主相同的账号，消费端仍为同一 WKWebView 和 Origin。
- Cook 退出后宿主仍登录；再次请求后实际取消，Cook 留在原页面并显示取消状态；重试确认后再次成功登录。
- 消费端退出控件、宿主远端 sign-out、独立 Keychain 清除均通过。只删除本轮清单记录的 WebKit profile；AppKit 测试进程退出后，在独立清理测试中确认删除完成，最终报告 `profileCleanupComplete=true`。没有清理用户日常客户端的账号或资料。

## iOS / Android：实际外跳

两端均使用生产页面的现有控件，覆盖不同实现：

1. `https://cook.yunle.fun/about/me` 的「哔哩哔哩」来源链接，目标 `https://space.bilibili.com/1579790`。
2. `https://cook.yunle.fun/library` 的第一条菜谱「电饭煲版广式腊肠煲饭」，按钮调用 Cook 正常 `openRecipe()` / `window.open()`。

使用原生触摸事件而非 DOM `.click()` 验收外跳，保留 WebKit / Chromium 的实际用户手势与弹窗策略。iOS 观察真实 `SFSafariViewController` 类型、展示完成及返回后同一 Cook 文档；系统面板保留 15 秒供 UI 驱动补充观察。Android 观察真实前台 Activity `com.android.chrome/org.chromium.chrome.browser.customtabs.CustomTabActivity`，实际地址栏分别为 `space.bilibili.com` / `bilibili.com`，并验证返回后 Cook URL 未改变；没有拦截或伪造 Intent。

Android 新模拟器的首次启动停在 Chrome FirstRunActivity，属于测试环境前置条件。仅在专用模拟器将 Chrome 设为调试应用并使用 `_ --disable-fre`，随后完整复跑通过；没有登录 Google 或 B 站。该开关来自 [Chromium Android 调试流程](https://chromium.googlesource.com/chromium/src/+/main/docs/android_debugging_instructions.md)，只用于独立自动化环境，结束后撤销调试应用和临时开关并回收设备。

Android 视频地址在实际 Custom Tab 中返回 **B 站 412 风控页面**。这条结果证明外跳与返回成功，不能据此声称视频播放成功；本轮没有绕过该风控。

## 显式夹具与复跑

普通 CI 不启用下列 live 入口；跳过不能记为生产验收通过。

- Mac：`MacCookHostLiveTests/testCookSSOAndUnsupportedCapabilities`，`YunleFunMacLiveValidation` Scheme / `Testing` 配置。设置 `YLF_MAC_COOK_HOST=1` 和 `YLF_MAC_COOK_RUN_ID`。一次性 0600 输入为测试宿主缓存下 `MacCookHost-<大写 UUID>/input.json`，结构为 `runID` 和单元素 `accounts`；仅允许既有 `production-zero-balance` production 测试账号。输入读完立即删除，凭据在原生内存和独立 Keychain 中使用。
- Mac 驱动：读取同目录 `progress.json`，按 `await-native-submit`、`await-consent`、`await-cancel`、再次 `await-consent` 操作实际面板。驱动只点击按钮，不读取或传入密码。最终按同一 UUID 设置 `YLF_MAC_COOK_CLEANUP=1`，仅运行 `testRemoveRecordedCookProfiles`；清理模式要求本轮 Keychain 已清空。
- iOS：`CookExternalLinkLiveTests/testBilibiliAnchorAndWindowOpenUseSystemSafari`，`YunleFunLiveValidation` Scheme。设置 `YLF_COOK_EXTERNAL_LINKS=1`、`YLF_COOK_EXTERNAL_RUN_ID` 和绑定当前专用设备的 `YLF_COOK_EXTERNAL_SIMULATOR`。读取 App 缓存 `CookExternalAcceptance/progress.json`，在 `await-tap-anchor` / `await-tap-window-open` 阶段用原生 UI 驱动点击现有控件。报告为同目录 `report.json`，截图与报告也在 xcresult 附件中。
- Android：`CookExternalLinkLiveTest`，instrumentation 参数 `cookExternalLive=1` / `cookExternalRunId=<UUID>`，仅允许模拟器硬件。直接启动真实 HostWebViewActivity，打开从生产目录读取的 Cook 入口；通过实际 WebView 几何计算触摸位置，发送原生触屏输入。报告为 App external files 下 `cook-external-report.json`，同目录保存两张 Custom Tabs 截图。
- 构建与依赖：Mac 使用仓库 `script/build_and_run.sh` 构建后选择专用 live Scheme；iOS 复用锁定的 Swift 包；Android 使用 JDK 21、现有 Capacitor 同步流程，再构建 `:app:assembleDebug :app:assembleDebugAndroidTest`。本轮 Android 主壳使用任务独占占位资源，外链夹具仅打开实际原生容器和生产 Cook；未把测试资源、绝对依赖路径或生成配置加入 PR。

前置失败均保留阶段结果后修正：Mac 驱动识别 SwiftUI 控件与人工驱动等待超时；iOS 定位器最初只读 HTML 属性、没有读取 Ionic 的 `href` 属性，以及把旧占位 `/recipes` 误作当前菜谱页；Android 的 Chrome 首次启动流程。修正后分别完整复跑通过，本轮未发现需要修改产品代码的新缺陷。

## 仍未覆盖

实体设备震感、完整 OS / 安全区 / 弱网矩阵、已安装 B 站 App 时 Universal Links / App Links 的接管、B 站账号与视频播放、非默认外链偏好及其他来源域名仍需独立验收。本轮也不代表 CloudBase 跨设备数据同步或新的宿主发布已完成。
