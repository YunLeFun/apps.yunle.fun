# 原生 iOS 真机验证

独立 SwiftUI 工程位于 `apps/ios`，与 `apps/mobile/ios` 的 Capacitor 工程分别构建。这里的命令不需要打包 Nuxt 或运行 `cap sync`。真机测试使用独立的 `fun.yunle.apps.benchmark-dev`；正式应用的 `fun.yunle.apps` 保留给覆盖升级与候选版本阶段。

## 签名与首次启动 · 2026-10-17

在源码 `e7c27c7`、Xcode 27.0、iPhone 15 Pro / iOS 26.6.1 上验证：

| 项目                               | 结果                                                         |
| ---------------------------------- | ------------------------------------------------------------ |
| 可用开发证书私钥                   | 已可用于签名                                                 |
| Benchmark 真机 `build-for-testing` | 成功                                                         |
| Benchmark 签名与描述文件           | 签名验证通过，描述文件包含本机并支持 Associated Domains      |
| Associated Domains                 | 保留 `applinks:apps.yunle.fun`，没有移除能力绕过签名         |
| 独立 Benchmark 安装                | 首次 CoreDevice 连接失效，一次重试后成功                     |
| 原生应用启动                       | 初次被锁屏拦截；用户解锁后成功，已截图复核云居与四个系统 Tab |
| Release 真机本地归档               | 成功，归档内应用签名验证通过                                 |
| 真机自动化 UI / 系统审计           | 尚未执行到测试用例，见下方连接记录                           |

Release 归档仍为当前原生工程的版本 `0.1.0` / 构建 `1`，最低 iOS 16。这里只证明本地签名与归档链路可用，候选版本的版本号、覆盖升级、功能矩阵、Sandbox 和发布材料仍未验收。该归档未安装、导出或上传；手机上的既有正式应用保留。Associated Domains 的签名有效也不等于 Universal Link 分发已经通过。

首次运行曾显示 iOS 的无线数据访问提示，截图保留在本机。仅看到启动画面不能证明公开目录已经加载，也不算登录、云同步或运行时旅程通过。

后续尝试用系统启动接口将公开应用链接定向交给 Benchmark，但手机已再次锁屏，系统以 `Locked` 拒绝启动；没有取得详情页证据，也没有据此判断链接处理失败。

## 自动化连接记录

手机通过本地网络连接，已配对、开启 Developer Mode，Developer Disk Image 可用。两次 XCTest 均在测试 runner 与 Xcode 建立控制通道时退出：

```text
Connection peer refused channel request for
"dtxproxy:XCTestDriverInterface:XCTestManager_IDEInterface"
Exiting due to IDE disconnection.
The test runner exited with code 74 before establishing connection.
```

首次 `smoke.xcresult` 包含三个明确选取的公开旅程，但没有任何测试用例开始。第二次 `smoke-arm64.xcresult` 只选四 Tab 检查，明确指定 `arch=arm64` 并关闭自动诊断采集，仍在同一阶段退出；两次 `xcodebuild` 均为退出码 65。这不是产品崩溃或测试断言失败，也不是零失败的通过结果。当前请求改用 USB 做对照，根因尚未确定。

结果包、签名资料、设备信息与原始日志保存在仓库外的受限本机目录，不随公开仓库或 CI 上传。首次 Xcode 自动采集了诊断，后续验证使用 `-collect-test-diagnostics never`；如需设备诊断，应单独核对采集范围。

## 复现步骤

在 Xcode 配置可用的开发者账号与证书私钥，并让自动签名为独立应用和测试 runner 生成描述文件。手机保持解锁、开启 Developer Mode；首次 USB 连接按系统提示完成信任。先在 Xcode 的 Devices and Simulators 确认可用设备，再将下面占位符替换为本机值，设备标识不要提交到 Git。

从仓库根目录构建 Benchmark；真机使用开发签名，不沿用模拟器的 `CODE_SIGN_IDENTITY=-`：

```sh
xcodebuild -project apps/ios/YunleFun.xcodeproj \
  -scheme YunleFunBenchmarks -configuration Benchmark \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/yunlefun-ios-device \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  build-for-testing
```

核对产物的 Bundle ID 为 `fun.yunle.apps.benchmark-dev` 后安装。`COREDEVICE_IDENTIFIER` 使用 CoreDevice 标识；后面的 `XCODE_DEVICE_UDID` 使用 Xcode destination 标识，两者不能混用。

```sh
xcrun devicectl device install app --device COREDEVICE_IDENTIFIER \
  /tmp/yunlefun-ios-device/Build/Products/Benchmark-iphoneos/YunleFun.app
xcrun devicectl device process launch --device COREDEVICE_IDENTIFIER \
  fun.yunle.apps.benchmark-dev
```

先只运行四 Tab 用例，确认控制通道与目录加载可用；再分别选择 `testNativeCloudAirCanMinimizeRestoreAndEnd` 和 `testNativeGuestAuthorizationLoginCanBeCancelled`。不要直接运行整个 Benchmark 集合，其中包含需要独立准备数据或显式启用的验证。

```sh
xcodebuild -project apps/ios/YunleFun.xcodeproj \
  -scheme YunleFunBenchmarks -configuration Benchmark \
  -destination 'platform=iOS,id=XCODE_DEVICE_UDID,arch=arm64' \
  -derivedDataPath /tmp/yunlefun-ios-device \
  -resultBundlePath /tmp/yunlefun-device-smoke.xcresult \
  -collect-test-diagnostics never -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 180 \
  -only-testing:YunleFunBenchmarksTests/ApplicationBenchmarks/testPublicScreenInventory \
  test-without-building
```

结果目录每次使用新路径，不覆盖失败证据。首次无线数据提示需要处理后继续；若提示仍覆盖页面或公开目录未就绪，用例应保留失败，不能把空视口当作目录验收。

本地 Release 归档单独执行，不安装产物：

```sh
xcodebuild -project apps/ios/YunleFun.xcodeproj \
  -scheme YunleFun -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/yunlefun-ios-device-archive \
  -archivePath /tmp/YunleFun-native.xcarchive \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  -allowProvisioningUpdates archive
```

归档内正式 Bundle ID、最低系统、版本号、签名与 entitlement 分别核对。此命令不导出或上传构建，发布按后续明确指令执行。

## 无障碍与后续范围

控制通道恢复后，按[系统辅助功能审计](./ios-accessibility-audits.md)分别运行浅色 / 深色、标准 / 最大辅助字号，保留 `.all` 的全部报告。与模拟器逐项比较，不用另一台设备通过来覆盖原失败结果。

这台 iOS 26 真机可以使用 iOS 17 起的系统审计，不能运行需要 iOS 27 VoiceOver Service 的实际朗读测试。初始 VoiceOver 为关闭，本轮未修改；真机的人工阅读、焦点、导航和弹层操作仍待验证。iOS 27 的[模拟器朗读结果](./ios-voiceover-validation.md)单独保留。

后续仍需真实账号与 SSO、跨硬件云同步、权限与相机、前后台 / 锁屏、最低系统、iPad、性能、Sandbox 和旧版覆盖升级。本次签名解除不改变这些验收项的未完成状态，完整 [Goal](./ios-native-migration.md)继续推进。
