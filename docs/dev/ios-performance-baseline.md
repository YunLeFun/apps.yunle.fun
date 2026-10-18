# iOS 原生迁移：首轮性能与运行证据

> 首轮为 2026-10-16；2026-10-18 干净候选观测见本页末。属于部分基线，不能视为性能验收已完成。完整范围见 [原生改造 Goal](./ios-native-migration.md)。

## 当前结论

在相同 iPhone 16 Pro / iOS 18.6 模拟器上，旧兼容壳与原生主壳都已通过四 Tab 的实际切换检查。原生端真实云空调的打开、收起、恢复、结束旅程通过；网页实际显示“便携小空调”。这些证据只覆盖访客公开流程。

**本轮原生启动测量慢于旧壳，尚未实现性能改善。** 首个可响应帧与首页入口可访问采用不同指标，不能互相替代；也没有把 WebView 首帧当作网页内容就绪。需要继续采集启动调用栈、首次使用、恢复、滚动和真机数据，再制定量化验收目标。

## 测试条件与构建身份

| 项目       | 本轮条件                                                                                       |
| ---------- | ---------------------------------------------------------------------------------------------- |
| 主机       | MacBookPro18,1，32 GiB 内存，10 核 CPU                                                         |
| 工具       | Xcode 27.0，27A266a                                                                            |
| 同一模拟器 | iPhone 16 Pro，iOS 18.6，22G86；独立测试实例，未覆盖用户原有模拟器                             |
| 旧兼容壳   | 当前工作区源码，App Scheme / Release，`fun.yunle.apps`，0.1.0 (194)                            |
| 原生主壳   | YunleFunBenchmarks Scheme / Benchmark，release 优化，`fun.yunle.apps.benchmark-dev`，0.1.0 (1) |
| 数据       | 访客、云居各有一个真实云空调；保留持久缓存，使用实时网络                                       |
| 样本       | 每项 5 次记录值，XCTest 另有不计入结果的预热；同一构建连续测试                                 |
| 源码基点   | `924e131e2d6fd4a8535441a75a5cef5f9b8a0837`，有本次迁移工作区改动                               |

旧壳使用本轮 Nuxt 生产构建并执行 `cap copy ios`，并非 App Store 下载的旧二进制。测量二进制在共享容器补上三个无障碍按钮名称之前生成；该标签改动后的原生旅程及旧壳 Release 编译另行通过。二进制 SHA-256、bundled 页面 SHA-256 与完整条件保存在 `ios-baseline/2026-10-16/provenance.json`，用于区分本轮构建，不能单靠 Git 基点重建有改动的二进制。

没有控制网络延迟、交换测试顺序或做清空缓存的冷安装序列；以下数据用于发现问题，不能直接推算线上用户或真机表现。

## 启动测量

| 指标                   | 旧壳均值 / 中位数 | 原生均值 / 中位数 | 含义                                                                                   |
| ---------------------- | ----------------- | ----------------- | -------------------------------------------------------------------------------------- |
| 首个可响应帧           | 0.688 / 0.684 秒  | 1.156 / 1.164 秒  | `XCTApplicationLaunchMetric(waitUntilResponsive: true)`；不保证目录或网页内容载入      |
| 云居“云空调”入口可访问 | 2.970 / 2.834 秒  | 3.282 / 3.287 秒  | `XCTClockMetric`，从 `app.launch()` 前到入口出现在无障碍树；包含测试驱动与系统等待开销 |

第二项旧壳等待 WebView 内“云空调”文本，原生等待“打开云空调”按钮。它衡量测试工具能观察到入口的端到端时间，**不是生产页面 LCP，也不是纯应用 CPU 时间**。采样停止后才终止应用。

原始样本（秒）如下。样本过少，不报告 P95，也不把均值差异解释为已定位的根因。

- 旧壳首帧：0.683967333，0.683612625，0.714090291，0.678880625，0.681446958。
- 原生首帧：1.174402209，1.142279583，1.191205125，1.110569667，1.163758292。
- 旧壳入口：2.833638125，2.806829537，2.790560245，2.838164607，3.580068176。
- 原生入口：3.287749164，3.223328611，3.287205012，3.270285173，3.342653699。

四份原始 CSV 与 `launch-summary.json` 保存在 `docs/dev/ios-baseline/2026-10-16/`。汇总脚本校验 CSV 均值与迭代值一致，保留原始样本、离散程度和来源，不覆盖原始数据。

## 内存与包体的边界

新增宿主侧 `scripts/ios/process-memory.c` 与 `sample-memory.py`，使用 macOS libproc 对模拟器进程采样，分别保留物理占用、生命周期峰值和 RSS。这些工具不编译到 iOS 应用中。脚本列出的 WebContent / Networking / GPU 是同一模拟器的候选进程；独立确认归属前，不能把它们相加为应用总占用。

原生首页本轮有一组完成截图核对、调试器附加前的宿主样本：PID 2559，三次物理占用均为 27,855,632 字节，约 26.57 MiB。这只是单个进程的一组观察，不能据此完成内存验收。先前未核对画面状态的首页记录不用于正式对比；云空调打开时采样与调试器附加可能重叠的一组记录已排除。LLDB 导入运行时会改变目标进程内存，不得混入基线。

模拟器应用包逻辑文件大小：旧壳 18,059,860 字节，原生 3,338,766 字节。原生功能尚未齐全，也尚未归档 / 压缩为同等条件的 IPA；这些数值只用于识别构建，不能宣称最终包体缩减比例。

宿主与已归属 WebKit 进程的同步采样、重复打开 / 收起 / 结束后的稳定范围、内存压力和真实设备仍待完成。

## 复现入口

性能与公开旅程位于 `apps/ios/Benchmarks/ApplicationBenchmarks.swift`，单独使用 `YunleFunBenchmarks` Scheme；默认单元测试 Scheme 不包含性能测试。Benchmark 使用独立开发 Bundle ID，不改变正式 Release 标识。

在一次性访客测试模拟器安装旧兼容 Release。先运行 `testPublicScreenInventory`；原生另运行 `testPrepareNativeHomeWithCloudAir`，从真实目录获取应用，确保两端云居各有一个相同入口。`testNativeCloudAirCanMinimizeRestoreAndEnd` 在缺少入口时也会先走真实获取流程，不依赖测试执行顺序。

授权旅程 `testNativeGuestAuthorizationLoginCanBeCancelled` 会另行获取 AI 春联，改变该测试实例的安装列表。之后重新进行“仅一个云空调”的启动比较时，必须另行准备符合条件的一次性测试实例，不能直接复用改变后的数据集。本页时间样本仍对应记录中的原始构建和单应用数据集。

Xcode 的 Test Scheme 环境变量中，`YLF_BENCHMARK_TARGET=legacy` 选择已安装的旧壳，缺省选择原生；`YLF_BENCHMARK_METRICS=1` 才启用两个测量方法。XcodeBuildMCP 的 `test_sim` 使用相同名称的 `testRunnerEnv`；它会添加 `TEST_RUNNER_` 前缀。使用 `-parallel-testing-enabled NO`，分别用 `-only-testing` 运行对应方法，避免其他测试改变测量状态。

导出结果并汇总，以下路径均由执行者替换，不读取账号或令牌：

```sh
xcrun xcresulttool export metrics --path RESULT.xcresult --output-path METRICS_DIRECTORY
python3 scripts/ios/benchmark-report.py \
  --metrics legacy-frame=LEGACY_FRAME_DIRECTORY \
  --metrics native-frame=NATIVE_FRAME_DIRECTORY \
  --metrics legacy-content=LEGACY_CONTENT_DIRECTORY \
  --metrics native-content=NATIVE_CONTENT_DIRECTORY \
  --out SUMMARY.json
```

内存采样前先核对真实画面、Bundle ID 和宿主 PID，等待采样命令完全结束，再进行任何调试器附加。以下脚本只验证 PID 属于指定模拟器，画面与 WebKit 归属需要另有证据。

```sh
xcrun clang -Wall -Wextra -O2 scripts/ios/process-memory.c -o /tmp/yunlefun-process-memory
python3 scripts/ios/sample-memory.py \
  --simulator SIMULATOR_UUID --host-pid HOST_PID \
  --sampler /tmp/yunlefun-process-memory --out MEMORY.json
```

## 已有证据与下一步

- 旧壳与原生四 Tab 检查均通过，断言选中状态后导出四页截图；原生从真实目录获取云空调通过。
- 原生云空调“打开 → 收起 → 恢复 → 结束”通过，检查真实网页标题、运行中入口及结束后 WebView 移除。不能替代 SSO、受保护应用、多会话、进程回收或泄漏验证。
- 原生 41 项单元测试、共享容器 / 身份边界 26 项测试通过；共享容器按钮补无障碍名称后，原生实际旅程与旧兼容 Release 编译通过。
- 旧壳在 iOS 27 模拟器因 Scene 生命周期要求崩溃，未把该结果用于性能比较。iOS 18.6 首次手工启动曾出现白屏；测试驱动启动与独立测试实例重新安装后可正常显示，尚未定位原因，不能写成已修复。
- 先定位原生首帧额外开销，再补首次打开 / 恢复 / 滚动、可归属的 WebKit 内存、真机与旧版覆盖升级。真实账号及生产云居接口未联调，M0 / M2 / M4 对应项保持未完成。

本次聊天附件的 `ios-native` 目录保存 `.xcresult` 导出截图、无障碍树、内存诊断及构建来源记录；仓库只保留不含账号的时间序列与复现代码。

## 官方指标定义

- [XCTApplicationLaunchMetric](https://developer.apple.com/documentation/xctest/xctapplicationlaunchmetric)
- [等待可响应帧的初始化参数](https://developer.apple.com/documentation/xctest/xctapplicationlaunchmetric/init%28waituntilresponsive%3A%29)
- [手动停止测量](https://developer.apple.com/documentation/xctest/xctmeasureoptions/invocationoptions-swift.struct/manuallystop)

## 干净候选的启动与分进程观测 · 2026-10-18

来源为 `a8b16f7` 干净归档的 Benchmark / arm64，`fun.yunle.apps.benchmark-dev` 0.1.0 (1)。与[新候选包](./ios-simulator-preview.md#含隐私声明的新候选-·-2026-10-18)为同一二进制，文件摘要在 `ios-baseline/2026-10-18/provenance.json`。同一个自有 iPhone 18 Pro / iOS 27.0 (24A434) 在测试时仍名为 Candidate c8d43bc，交付前才改名为 Candidate a8b16f7；不能由设备名称推断所装源码。

先通过真实工坊准备唯一云空调入口，再检查四 Tab；两条均通过。两项测量分别运行，各 **5 次记录值**，XCTest 另有预热；没有夹杂业务测试、清空缓存或调试器附加。测量后独立回读访客安装列表仍只有云空调，常用为空。

| 指标                 | 均值 / 中位数    | 五个原始样本（秒）                                              |
| -------------------- | ---------------- | --------------------------------------------------------------- |
| 首个可响应帧         | 5.661 / 5.602 秒 | 5.492266625、5.568539625、5.602269875、5.661422500、5.978063000 |
| 首页云空调入口可访问 | 7.569 / 7.577 秒 | 7.539119073、7.473305463、7.580419111、7.675234932、7.576948379 |

两个测试均通过且无结果包运行时警告，表示测量与入口断言执行完成，**不表示性能达标**。原始 CSV 未改，汇总脚本核对均值并保留离散值；不从五个样本报告 P95。

主机为 macOS 26.6.2 / Xcode 27.0 (27A266a)、10 核，测量前负载为 153.75 / 120.53 / 106.58，结束后为 85.53 / 106.42 / 103.13。共享开发机没有达到受控空闲条件，实时网络也未控制；旧壳在当前唯一 iOS 27 运行时无法启动。该观测明显偏慢，但不能与 10 月 16 日不同源码 / iOS 18.6 的数值直接判定回归、改善或根因，仍需空闲主机上的同条件对照与启动调用栈。

### 内存状态与进程归属

另行手动启动同一 App，先确认真实画面，再逐阶段做三次间隔约一秒的 libproc 采样。全程未附加调试器；下面是各进程物理占用均值（MiB），并非 RSS 或应用总内存。RunningBoard 原始日志明确包含宿主 Bundle ID / PID 2738，以及对应 WebKit extension 身份、PID 和宿主发出的断言，独立于采样脚本完成归属。

| 状态               | 宿主 2738 | 启动时 WebContent 2831 | Networking 2832 | 云空调 WebContent 6223 | 云空调 GPU 6225 |
| ------------------ | --------- | ---------------------- | --------------- | ---------------------- | --------------- |
| 单入口首页         | 67.49     | 15.34                  | 9.60            | 未出现                 | 未出现          |
| 云空调实际绘制     | 73.50     | 15.08                  | 11.21           | 68.17                  | 23.61           |
| 收起并显示运行中 1 | 74.80     | 15.11                  | 11.60           | 65.57                  | 25.70           |
| 恢复并实际绘制     | 74.60     | 15.11                  | 11.53           | 64.85                  | 25.75           |
| 结束后回到首页     | 80.03     | 15.14                  | 11.49           | 已退出                 | 已退出          |

初始 GPU 2833 在首个首页样本前约 34 秒已退出。实际打开时发现采样脚本原先漏列 `GPUExtension.appex`，已补充为未归属候选；修正后确实采到 GPU 6225，再由系统日志确认归属。没有因为同属模拟器就直接把候选算作 App 进程，也没有把不同进程占用相加宣称系统实际释放量。

这里只完成一次打开 / 收起 / 恢复 / 结束循环。结束后新 WebContent / GPU 退出，宿主却仍高于最初首页；有限样本不能判断泄漏、长期稳定范围、峰值或实际压力表现。原始日志、五组采样、各阶段截图与归属摘录在本机 `candidate-a8b16f7-verification`，仓库的 `memory-summary.json` 保留样本、来源摘要与归属证据。正式内存验收仍待重复循环、Instruments 与可用设备条件。

测试后停止 App，精确恢复预先保存的空安装列表访客快照，并通过候选脚本重新安装启动、核对空云居。这是隔离夹具清理，不计作产品升级或回退验证。
