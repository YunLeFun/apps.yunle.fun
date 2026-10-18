# 原生 iOS 真机验证

> 当前范围 · 2026-10-17：用户随后要求后续全部在 iOS 模拟器测试，不再使用真机。本页保留已经取得的历史证据与复现命令，后续不自动执行设备命令、不等待手机连接或解锁。当前推进以[原生 Goal](./ios-native-migration.md)的模拟器矩阵为准。

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
| 真机自动化 UI                      | USB 四 Tab、访客授权取消与截图就绪会话均通过，分次执行       |
| 真机系统审计                       | 浅色 1 通过 / 7 失败，深色 2 通过 / 6 失败，均无跳过         |

Release 归档仍为当前原生工程的版本 `0.1.0` / 构建 `1`，最低 iOS 16。这里只证明本地签名与归档链路可用，候选版本的版本号、覆盖升级、功能矩阵、Sandbox 和发布材料仍未验收。该归档未安装、导出或上传；手机上的既有正式应用保留。Associated Domains 的签名有效也不等于 Universal Link 分发已经通过。

首次运行曾显示 iOS 的无线数据访问提示，截图保留在本机。仅看到启动画面不能证明公开目录已经加载；随后 USB 用例的工坊截图已确认真实公开目录载入 25 项。这不算真实账号登录或云同步通过。

后续尝试用系统启动接口将公开应用链接定向交给 Benchmark，但手机已再次锁屏，系统以 `Locked` 拒绝启动；没有取得详情页证据，也没有据此判断链接处理失败。

## 自动化连接记录

手机通过本地网络连接，已配对、开启 Developer Mode，Developer Disk Image 可用。两次 XCTest 均在测试 runner 与 Xcode 建立控制通道时退出：

```text
Connection peer refused channel request for
"dtxproxy:XCTestDriverInterface:XCTestManager_IDEInterface"
Exiting due to IDE disconnection.
The test runner exited with code 74 before establishing connection.
```

首次 `smoke.xcresult` 包含三个明确选取的公开旅程，但没有任何测试用例开始。第二次 `smoke-arm64.xcresult` 只选四 Tab 检查，明确指定 `arch=arm64` 并关闭自动诊断采集，仍在同一阶段退出；两次 `xcodebuild` 均为退出码 65。这不是产品崩溃或测试断言失败，也不是零失败的通过结果。

用户通过 USB 连接并解锁后，只读确认传输为 `wired`、配对及通道正常；`smoke-usb.xcresult` 的四 Tab 用例 **1 通过 / 0 失败 / 0 跳过**。同一签名产物在 USB 上开始执行并通过，因此无线控制连接是当前已观察到的区别，尚未证明其内部根因或修复无线通道。

`journey-usb.xcresult` 的云空调会话与 AI 春联访客登录取消为 **2 通过 / 0 失败 / 0 跳过**。云空调实际完成收起 / 恢复 / 结束；AI 春联进入原生表单、取消回网页、再次进入并取消，没有输入凭据或发送验证码。此处仍是产品源码 `e7c27c7` 的首轮签名构建，不是真实账号 SSO 成功路径。

复核附件发现，云空调的首次打开截图仍是白屏，恢复截图才显示完整网页。原测试只等待辅助功能树中的文字存在，不能证明首次绘制完成。后续增加系统 Vision 对实际截图中“便携小空调”的识别，首次打开与恢复分别在原有用例时限内等待；只保存真实识别到标题的画面或失败时最后一张画面，不根据节点存在直接记作页面已显示。收紧后的构建复验另行记录，不改写原始截图。

收紧后的 `painted-usb.xcresult` 为 **2 通过 / 0 失败 / 0 跳过**：首次打开与恢复的截图均识别到网页标题，AI 春联的取消 / 再进入同次通过。这次产物包含本轮[详情页动态字号调整](./ios-detail-accessibility.md)，开发签名构建成功；没有把测试更早等待截图改记为产品性能提升。真实账号登录与授权成功仍未在真机验证。

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

控制通道恢复后，原签名构建已按[系统辅助功能审计](./ios-accessibility-audits.md)分别运行四个 Tab、浅色 / 深色、标准 / 最大辅助字号，保留 `.all` 的全部报告。浅色 `audit-light.xcresult` 为 **1 通过 / 7 失败 / 0 跳过**，共 13 条对比度；深色 `audit-dark.xcresult` 为 **2 通过 / 6 失败 / 0 跳过**，共 14 条对比度。两种外观均无裁切 / 动态字号报告，但完整集合仍失败。

| 页面 | 浅色标准字号 | 浅色最大辅助字号 | 深色标准字号 | 深色最大辅助字号 |
| ---- | ------------ | ---------------- | ------------ | ---------------- |
| 云居 | 1 条对比度   | 通过             | 2 条对比度   | 通过             |
| 寻乐 | 3 条对比度   | 1 条对比度       | 3 条对比度   | 1 条对比度       |
| 工坊 | 3 条对比度   | 1 条对比度       | 4 条对比度   | 通过             |
| 我   | 2 条对比度   | 2 条对比度       | 2 条对比度   | 2 条对比度       |

云居使用这次访客旅程取得的云空调 / AI 春联，本机内容与模拟器不同。部分报告没有提供元素；寻乐最大字号的一条指向伸入底栏区域的精选摘要。没有证据可以忽略这些报告或直接认定系统误报。iOS 26 真机没有报告 iOS 27 模拟器中的寻乐裁切，也不能据此关闭后者。

这台 iOS 26 真机可以使用 iOS 17 起的系统审计，不能运行需要 iOS 27 VoiceOver Service 的实际朗读测试。初始 VoiceOver 为关闭，本轮未修改；真机的人工阅读、焦点、导航和弹层操作仍待验证。iOS 27 的[模拟器朗读结果](./ios-voiceover-validation.md)单独保留。

后续仍需真实账号与 SSO、跨硬件云同步、权限与相机、前后台 / 锁屏、最低系统、iPad、性能、Sandbox 和旧版覆盖升级。本次签名解除不改变这些验收项的未完成状态，完整 [Goal](./ios-native-migration.md)继续推进。
