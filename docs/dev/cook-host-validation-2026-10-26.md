# Cook 宿主真实链路验收 · 2026-10-26

Cook 的 [#98](https://github.com/YunYouJun/cook/issues/98) 跟踪宿主集成与原生客户端迁移。本轮在隔离模拟器运行真实宿主容器、生产 Cook 页面和既有 SSO 服务；没有 mock `window.ylf`、授权响应或换码结果。

## 版本与结果

宿主源码基线为 `22b839b4ae9a29d39a6542dbc1557c0d3ed33684`，叠加本 PR 的显式 live 测试。线上公开目录入口为 `https://cook.yunle.fun/home`，`trustedHosts` 仍为 `cook.yunle.fun`，默认形态为 `titlebar`。没有改动白名单、注册策略、账号权限或云函数。

| 项目       | iOS                                                                         | Android                                                                          |
| ---------- | --------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| 环境       | iPhone 18 Pro / iOS 27.0 模拟器，真实 WKWebView                             | Pixel 8 / API 35 隔离模拟器，真实 WebView                                        |
| 原生运行时 | SwiftUI 客户端的 `NativeWebRuntime`、共享 `WebViewController`、原生账号服务 | `MainActivity`、`HostRuntimePlugin`、`HostWebViewActivity`、生产宿主网页账号服务 |
| 测试结果   | 1 通过 / 0 失败 / 0 跳过，方法 30.149 秒                                    | 1 通过 / 0 失败，最终完整旅程 48.388 秒                                          |
| 报告       | 10 个布尔检查全部为 true                                                    | 10 个布尔检查全部为 true                                                         |
| runID      | `c48d791e-9b7b-4e27-b0b4-8e783376b8f7`                                      | `0b85ae1b-1bd7-4c29-88f9-7744bf48eaea`                                           |

Android 验收包仅在隔离 Debug 副本中设置 Capacitor `server.url=https://apps.yunle.fun`，使实际生产宿主网页驱动原生桥。未提交该配置，也未生成或发布新的正式客户端。iOS 夹具在真实进程中挂载实际运行时，用隔离 Keychain 和 WebProfile 元数据承载测试会话。

## 实际走过的流程

1. 从生产公开目录读取 Cook 并打开兼容入口，确认真实 `getEnv()` 返回当前平台、`trusted=true` 和 `titlebar`。
2. 实际调用 `canIUse('authorize')`、`canIUse('haptic')`、`canIUse('setClipboard')`，三项均为 true。
3. 调用真实 `haptic('light')` 和 `haptic('success')` 并等待原生回应。写入带 runID 的合成剪贴板文本，由原生剪贴板 API 读回核对，然后恢复原内容。
4. 点击 Cook「我的」→「使用云乐坊账号登录」。iOS 经实际 UIKit 密码表单登录；Android 经实际第一方宿主密码表单登录。仅使用受管 `production-zero-balance` 测试账号，密码没有进入 Cook 消费端。
5. 操作实际原生授权面板。生产服务签发 code，由 Cook 正常 SDK 换码并登录；Cook 显示与原生授权面板相同的账号名称，保留同一消费端网页和 Origin。
6. 退出 Cook 后再次授权、取消；确认消费端仍显示登录入口且未回落到网页跳转。随后重新请求、确认授权，再次成功登录并退出。iOS 另核对 Cook 退出后宿主仍登录；Android 再次展示同一宿主账号并完成授权。
7. 通过实际账号服务 / 宿主退出控件退出测试会话。iOS 远端 sign-out 获得回应；Android 宿主资料页回到「请先登录查看个人资料」。消费端退出控件及宿主本机退出状态已核对，未独立探测消费端服务端会话撤销。

首次 Android 核心旅程已完成，但夹具清理误用了不存在的 `ylf.close()`；修正为实际的 `closeBrowser()` 后，按原 runID 绑定的清理模式完成宿主退出。随后从已退出状态重跑完整旅程，10 项全部通过。该问题属于测试夹具，没有因此修改产品接口。

## 可重复运行的夹具

- iOS：`apps/ios/LiveValidation/CookHostLiveTests.swift`，属于 `YunleFunLiveValidation` Scheme；仅在 `YUNLEFUN_LIVE_COOK_HOST=1` 时运行。`YUNLEFUN_LIVE_COOK_RUN_ID` 必须与一次性输入一致，输入中的 `simulatorID` 必须等于当前 `SIMULATOR_UDID`。
- Android：`apps/mobile/android/app/src/androidTest/java/fun/yunle/apps/CookHostLiveTest.kt`；仅在 instrumentation 参数 `cookHostLive=1` 时运行，`cookRunId` 必须与输入一致，并限制到模拟器硬件。普通测试调用会跳过，不能将跳过记成功能通过。
- 输入仅来自仓库外受管账号池；只暂存固定测试账号，不能复制整个池。iOS 路径为 App 的 `Library/Caches/CookHostAcceptance/input.json`，Android 为 App 私有 `files/cook-host-input.json`。两端检查私有文件权限，读完立即删除；文件不得加入源码、命令参数、日志或报告。
- 输入结构为 `runID` 和单元素 `accounts`；iOS 另含 `simulatorID`。账号字段为既有受管池的 `id`、`environment`、`username`、`password`，值必须匹配固定 production 测试账号。
- iOS 只运行 `CookHostLiveTests/testManagedCookLoginClipboardAndHaptics`，导出 xcresult 中 JSON 与签入截图；App 缓存另写 `CookHostAcceptance/report.json`。
- Android 使用 JDK 21，先执行 `:app:assembleDebug :app:assembleDebugAndroidTest`，安装两份 APK 后以显式参数运行 `fun.yunle.apps.CookHostLiveTest`。应限定 `:app:`，不要给生成的 Cordova 库模块构建无关的 instrumentation APK。
- Android 报告与截图位于 App 的 external files 目录。失败后如报告确认本轮已完成受管账号登录，可在相同 `cookRunId` 下显式加 `cookHostCleanup=1` 重试宿主退出；该模式不会重复登录或读取账号池。
- 两端报告只保存 runID、阶段、布尔检查与测试范围，不保存密码、token、code、UID 或账号资料。先核对退出结果、导出必要证据，再删除本轮专用模拟器与可重建产物。

## Cook 原生 iOS CI

Cook 布局修复 #168 的 [PR 工作流](https://github.com/YunYouJun/cook/actions/runs/40224423806) 和合并提交 `ca75ea84066aee0d80af5176f019913f71587b07` 的 [main 工作流](https://github.com/YunYouJun/cook/actions/runs/40224836685) 均已成功。两次原生 iOS 作业中的 Build and test 步骤均实际完成，没有以排队或跳过充当成功。

## 范围边界

本轮证实当前源码容器与生产服务的登录、取消 / 重试、原生触感调用回应和剪贴板读回。模拟器无法证明实体震感；也未验收 macOS 登录与能力降级、B 站外链、最低 OS、弱网 / 前后台矩阵或已发布宿主包的完整设备覆盖。没有由此认定 CloudBase 跨设备数据同步、App Store 上架或新的宿主发布已完成。
