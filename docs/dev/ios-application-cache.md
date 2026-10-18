# 原生 iOS 云应用下载缓存

原生 iOS 在应用详情、云应用的“更多操作”以及“我 → 设置 → 应用下载缓存”提供本地下载管理。用户可以下载、取消、重新下载更新、清理单个应用或清理全部下载缓存，并查看资源大小与更新时间。

新建应用会话优先使用匹配的下载缓存；没有缓存、文件已被系统回收或校验失败时走原有在线加载。应用网址变化不会命中旧地址的缓存。更新与清理不打断已经运行的应用，结束该应用后重新打开生效。原“重新载入”仍使用 WebKit 的网页刷新操作。

## 缓存范围

下载采用 Apple 的 [createWebArchiveData](https://developer.apple.com/documentation/webkit/wkwebview/createwebarchivedata(completionhandler:))，保存首页与加载完成时已经取得的网页资源，使用 [WKWebView.load 数据接口](https://developer.apple.com/documentation/webkit/wkwebview/load(_:mimetype:characterencodingname:baseurl:)) 在原网站来源下重新载入。这里是网页资源缓存，不是完整站点打包；动态请求、懒加载、视频、跨页面导航和登录仍可能依赖网络。未承诺任意第三方应用都能完整离线运行。

本次支持云乐坊市场中可公开免费打开的版本。工坊、所有者预览、个人作品来源以及需要登录、会员或购买的应用暂不支持下载；运行时原有访问校验仍先于缓存读取。下载使用新建的非持久 WebKit 会话，不复制正在运行的页面、Cookie、网站存储或宿主凭据，也不注入宿主 JS bridge。主文档必须为成功的 HTML 响应，限制为同一 HTTPS 来源，拒绝 `Cache-Control: private` / `no-store` 的主文档。应用实际使用时仍在原 WebView 中读取它自己的登录和使用数据。

“清理下载缓存”只清除本功能持有的资源文件。不会移除云居应用、最近使用、账号或网站登录，也不会批量清空共享 WKWebsiteDataStore 的 Cookie、localStorage、IndexedDB 或浏览器自动 HTTP 缓存。用户界面沿用这个明确名称，避免误认为清理下载资源等于重置网站数据。

## 保存、更新与并发

- 文件位于 `Library/Caches/CloudApplicationDownloads`，不进入云居同步和备份；系统可能按存储压力回收。
- key 是应用 ID、来源 scope、完整启动 URL 的 SHA-256，不使用外部输入直接拼接路径。
- 每个文件包含版本、应用资料、来源、下载时间、资源数据和摘要。单文件原子替换，失败更新保留旧文件。
- 单个归档最多 25 MiB，总文件预算 200 MiB；容量不足不自动删除用户选定的其他缓存。界面字节格式使用系统格式化。
- 同时只进行一个下载。网页引擎准备预算为 90 秒；首次主框架实际开始 provisional navigation 后，加载和归档共用独立的 45 秒期限，两个阶段预算合计 135 秒。获准导航不能提前消耗加载期限。重定向及重复回调不能续期，HTTP 请求仍设置 40 秒超时。大小上限在归档生成后验证，不代表下载网络流量的硬上限。
- 清理先取消并等待正在进行的保存，再删除文件，迟到的下载响应不能把清理后的缓存重新写回。
- 运行时异步读取核对身份代次和会话对象，结束或账号切换后的旧读取不能载入到替换会话。
- 损坏条目不阻止其他条目管理；“清理全部”也可以移除不可列出的损坏文件。

## 验证

以下保留分阶段排查记录；较早记录中的待验项和下载期限，以文末的最新修正与验收结果为准。

定向测试包含磁盘重建、地址与应用隔离、原子更新、损坏文件、容量限制、单个 / 全部清理、取消和迟到响应，以及菜单与运行时会话回归。

WebKit 测试使用不存在的 `.invalid` 来源，从归档读取外部脚本、模块脚本及其依赖、CSS 和 SVG，并验证交互和原始来源。它避免已有网络缓存掩盖资源缺失。

真实公开网站验证需显式启用 `YLF_CACHE_LIVE_TEST=1`；UI 旅程需在空下载缓存的访客模拟器启用 `YLF_CACHE_UI_TEST=1`。两者不会登录、获取付费权益或修改服务端数据。UI 旅程访问真实云空调，检查下载 / 更新 / 从缓存打开 / 取消清理 / 全部清理，并保存截图。日常测试不启用这两个网络专项。

最低部署版本仍为 iOS 16。本轮运行设备与实际结果在功能验证完成后记录；iPad、最低版本与完整辅助功能审计不由单台模拟器的通过结果代替。

### 串行完整验收

使用 `build_sim(buildForTesting: true)` 生成最新 `.xctestproducts`，在已安装 Debug 构建、缓存为空且自动更新关闭的专用访客模拟器上运行：

```sh
python3 apps/ios/scripts/validate-cache-ui.py \
  --simulator SIMULATOR_UUID \
  --test-products /path/to/build.xctestproducts \
  --output /path/to/empty-results-directory \
  --repeat 2
```

脚本串行执行独立新进程冷启动、26 项缓存定向测试、独立进程的 2 项真实网站测试，再执行两轮“下载 / 手动更新 / 缓存启动 / 清理”“运行中自动更新 / 下次会话生效 / 单项清理”和“单项及全部清理的取消 / 确认”，合计 35 项。真实联网测试与可控 WebKit 替身分进程运行，隔离异步进程创建 / 回收。每组从实际 `.xcresult` 读取计数，要求全部通过且零跳过；输出日志、结果包、每组 JSON 以及 `validation-summary.json`。脚本只操作显式指定的设备，拒绝非空结果目录，保留失败证据。夹具写入之前先结束测试应用，下载缓存仍通过用户界面清理。

长会话验证应省略全部重启选项。结果记录每组前后的设备 `launchd_sim` PID 与启动时间，以及 SpringBoard、RunningBoard、XCTest 控制服务 PID；模拟器共享宿主内核，不能用 `kern.boottime` 代替设备会话标识。未指定设备重启选项时，脚本要求所有组保持初始 `launchd_sim` 标识，发生设备重启即失败。进程信息只读采集，不停止服务；每组同时记录实际命令耗时。

定向重跑可用 `--phase core`（28 项底层与联网测试）、`--phase ui`（三个 UI 流程）或 `download` / `automatic` / `clear` 单个流程。单组命令超过 1200 秒或被中断时，脚本先通知 Xcode 取消并等待结果落盘，再限时终止本命令的进程组，避免留下重叠测试命令；失败不会自动重试并覆盖原证据。

遇到本机模拟器服务会话退化时，可增加 `--restart-between-groups`：它只在组间重启显式指定的专用测试设备，保留该设备磁盘里的缓存和设置。默认保留设备运行状态，避免反复触发系统冷启动；新应用进程冷启动仍单独运行。Xcode 用例执行预算为 900 秒、单组命令上限为 1200 秒；网页内容首次呈现预算为 120 秒，以容纳模拟器 WebContent / Network 扩展启动。下载结果等待为 140 秒，自动更新就绪等待为 145 秒，均覆盖生产下载器两个有上限的阶段及保存后的 UI 更新。

若设备能正常运行、但 Xcode 卡在 XCTest 控制会话初始化，可用 `--restart-test-service` 在每组之前仅重启指定设备的 `com.apple.testmanagerd`，避免重启整个设备。它只适用于没有其他测试使用的专用设备，不会操作其他模拟器或宿主的测试服务。

### 可控的清理 UI 夹具

在已安装 Native Debug 的空缓存访客模拟器中运行：

```sh
python3 apps/ios/scripts/seed-cache-ui-fixtures.py SIMULATOR_UUID
```

脚本拒绝覆盖任何现有下载，只写入两个 `.invalid` 来源的合成缓存条目。用 `YLF_CACHE_UI_FIXTURES=1` 启用 `ApplicationCacheUITests/testClearConfirmationsWithLocalFixtures`，通过实际界面验证单应用 / 全部清理各自的取消与确认，并在成功后删除这两个条目。该专项不依赖真实网站下载。

### 真实自动更新 UI 夹具

在宿主应用已结束、缓存为空、自动更新关闭的专用访客模拟器中运行：

```sh
python3 apps/ios/scripts/seed-cache-ui-fixtures.py SIMULATOR_UUID --automatic
```

脚本查询当前公开目录，只为固定的云空调应用写入两天前的合成旧缓存，页面显示“自动更新旧版本”。它不会修改产品的 24 小时间隔、网络判断或下载实现。用 `YLF_CACHE_UI_AUTOMATIC=1` 启用 `ApplicationCacheUITests/testAutomaticUpdateKeepsRunningCacheUntilReopened`：先打开旧缓存，再通过设置开启仅 Wi-Fi 自动更新，等待真实下载完成，检查原会话仍显示旧页面；结束并重开后核对真实云空调控件，最后通过运行菜单清理缓存。此专项和普通下载旅程、清理夹具专项分开运行，各自需要满足前置数据条件。

### 2026-10-18 本机验证记录

设备为 iPhone 18 Pro / iOS 27 模拟器，Debug 模拟器构建通过；未进行真机或最低系统验收。

- 31 项缓存存储、竞态、WebKit、菜单和会话定向测试通过（结果 `test_sim_2026-10-17T18-05-07-923Z_pid28871_38f2b1e5.xcresult`）。随后增加的模块依赖离线断言也通过。
- 完整原生运行时使用 `.invalid` 来源读取本地缓存、执行交互、保留当前会话、结束后读取更新版本通过（`test_sim_2026-10-17T18-23-23-574Z_pid28871_03cb800b.xcresult`）。此测试显式准备默认 WebKit 存储，并先等待原有身份清理完成；更早的尝试记录了身份清理未就绪和加载超时，不代表冷启动问题已经解决。
- 真实云空调匿名下载与新 WebView 重放通过（`test_sim_2026-10-17T18-09-23-402Z_pid28871_8b82d372.xcresult` 中的 Live 测试）。UI 已观察到约 797 KB / 13 项资源，以及真实网页控件。联网保持可用，不能据此声称云空调所有功能完全离线。
- 同一批完整 UI 旅程最初在运行菜单的清理确认处失败，改用带明确取消操作的系统 alert。后续完整旅程分别在网页启动、下载阶段超时，最后一轮为 `test_sim_2026-10-17T18-24-45-242Z_pid28871_e6aaeac6.xcresult`。完整联网 UI 旅程仍未标记通过；不以底层测试替代这项结果。

结果包位于本机 XcodeBuildMCP 的工作区 `result-bundles` 目录，未提交二进制测试产物。

可控本地夹具的清理 UI 旅程 **1 通过 / 0 失败 / 0 跳过**：实际点击单应用清理的取消 / 确认、返回列表核对剩余一项、全部清理的取消 / 确认，最终显示 0 个应用。结果为 `test_sim_2026-10-17T18-30-50-350Z_pid28871_7ca182a4.xcresult`，保留确认框和清理完成截图；两条合成缓存由界面清理完毕。此项确认设置页面清理流程，不替代尚未完整通过的真实网站与运行菜单联网旅程。

### 联网超时继续排查 · 2026-10-18

本轮发现了独立的测试环境阻塞，不能据此把先前所有网页超时都归因为环境：

- 原来的 iPhone 18 Pro 同时被另一套应用的测试占用，因此改用 `YunleFun Cache Validation` 专用模拟器。
- 主机负载多次超过 600；新模拟器一次系统初始化耗时 4 分 51 秒。进程采样显示 Xcode 等待 `SimDevice.installApplication`，应用安装、截图和容器查询均出现无响应，测试代码尚未执行。工具的 300 秒超时属于测试调度层，不是下载器的 45 秒超时。
- 经用户允许仅关闭空闲实例，关闭了无活动测试或控制任务的 Showcase；有日志监听的 Native Preview 和其他在用实例保留。停止本任务挂起的测试，未重启全局 CoreSimulator 服务。
- 独立 macOS WebKit 诊断程序复用同一下载器代码，连续两次取得真实云空调归档，分别为 808469 / 808471 字节，首轮约 15 秒、第二轮约 4 秒。回调顺序为响应 → 加载结束 → 归档完成 → 释放下载器；未复现提前释放。此结果只帮助缩小排查范围，不能代替 iOS 原生运行时及 UI 验收。临时产品日志与诊断程序已移除。

新增 `ApplicationCacheLiveTests/testStoreDownloadsUpdatesAndClearsCloudAir`，在临时目录里通过真实 store 下载、更新、校验更新时间和资源、清理并确认文件消失。另加 `ApplicationCacheRuntimeTests/testColdRuntimeClearsIdentityWithoutAnExistingWebView`；检查冷启动时应单独选择此用例在新进程运行，避免先运行其他 WebKit 测试预热。两条测试已编译，因安装阶段阻塞尚未取得本轮执行结果。

UI 旅程现在对首次下载和更新都等待操作结束，再核对成功消息和“更新缓存”按钮；出错会显示实际失败消息，避免只等按钮直到 UI 超时。没有增加下载期限、提前保存未完成资源或跳过原有失败断言。

移除临时诊断后的最终编译通过记录：`build_sim_2026-10-17T19-06-03-833Z_pid28871_ecde46f7.xctestproducts`（0 warnings / 0 errors）。安装阶段阻塞记录：`test_sim_2026-10-17T19-01-56-174Z_pid28871_add0af58.xcresult`（由本任务主动停止，不算产品测试通过或失败）。环境恢复后仍须执行独立冷启动用例、Live 测试、完整 UI 旅程，再重复完整旅程验证稳定性；目前不能宣称完整联网流程已修复并稳定通过。

## 可选自动更新

“我 → 设置 → 应用下载缓存”提供“自动更新已下载应用”和“仅在 Wi-Fi 下下载”。自动更新默认关闭，Wi-Fi 限制默认开启，两项偏好持久化在本机。开启后只更新已下载、仍在当前目录中公开免费、启动 URL 与 scope 未变化的应用，不替用户下载新应用。

- 宿主处于活跃状态、网络可用时调度；每个应用距上次保存至少 24 小时。仅 Wi-Fi 时排除蜂窝和昂贵连接（包括个人热点），低数据模式一律暂停。请求同时设置 cellular / expensive / constrained 限制；网络路径变化会取消正在进行的自动下载。
- 手动关闭 Wi-Fi 限制后才允许蜂窝。退出活跃状态、关闭自动更新或目录撤销下载资格，都会取消自动下载；手动下载仍由用户主动发起。
- 下载和手动操作共用单一队列，沿用归档验证和原子替换。失败保留旧文件，依次等待 1、2、4、8、16、24 小时重试，退避记录可跨进程保留；手动更新可立即重试。用户主动取消自动下载后至少等待 1 小时。
- 清理先取消下载与检查任务，再等正在进行的写入结束；没有缓存的应用不再进入自动队列。清理不会关闭用户的自动更新偏好。
- 这里没有注册 iOS BackgroundTasks，也不保证宿主被挂起或终止后继续下载。静默指使用云乐坊期间不弹窗、不强制刷新当前页面。

自动更新采用静默下载，当前会话保持原版本。运行时记录实际读到的归档时间；有更新时，更多菜单及缓存页显示“更新已就绪，下次重新打开生效”，结束后重开读取新归档。首次下载、手动更新和清理仍明确展示进度、结果与确认。此方案不包含宿主 iOS App 自身的版本更新。


### 自动更新与超时边界验证 · 2026-10-18

新增 `ApplicationCacheAutomaticUpdateTests` 覆盖默认值和偏好恢复、Wi-Fi / 热点 / 蜂窝 / 低数据模式、24 小时间隔、当前目录资格、失败与退避、切后台 / 断网 / 撤销资格后的迟到结果、清理后不回填、单队列和下次会话提示。

`ApplicationCacheDownloaderTests` 用不完成加载/归档的 WebView 验证期限、取消和再次下载。回归测试复现了旧归档回调把重试错误地完成为旧内容，以及旧导航错误结束新请求；新增 WebView 身份校验后 3 项通过。生产下载上限保持 45 秒，未放宽时间或保存不完整页面。该缺陷不等同于已证明此前 iOS 完整旅程超时的唯一原因。

本机 iOS 27 模拟器出现独立系统阻塞：测试命令等待安装后又等待 `SimDevice.launchApplication`，普通进程派发也超时，测试代码尚未执行。主机一次采样为负载约 704、508 个运行进程、83 个阻塞进程和约 12 GB 压缩内存。确认 Native Preview 对应任务空闲且没有控制命令后关闭该实例，仅重启本任务专用模拟器；没有停止其他正在使用的模拟器，也没有重启全局 CoreSimulator 服务。随后只重启专用模拟器的 SpringBoard，普通应用启动仍无响应；系统主页仍显示大面积未加载的图标。已停止本任务的挂起测试与启动命令，关闭专用模拟器以释放资源。

为继续验证产品逻辑，临时 macOS SwiftPM 工程直接链接本仓库的缓存服务、应用模型和测试文件，只有不涉及缓存的深链解析依赖使用编译辅助实现。该辅助验证不是 iOS UI 验收，结果和后续待验项见下方记录。

- 最终 iOS Debug 编译（包含自动更新、UI 偏好测试和下载器超时回归）通过，0 warnings / 0 errors：`build_sim_2026-10-17T19-34-42-766Z_pid28871_bd67ff04.xctestproducts`。
- macOS 辅助验证共 **24 项通过，0 失败**：9 项自动更新、3 项下载器、5 项磁盘仓库、3 项 store 并发、2 项真实网站、2 项 WebKit 回放。最后补充操作代次检查后，相关 12 项再度通过。
- 真实 store 流程从磁盘取出每次下载 / 更新后的归档，在全新非持久 WKWebView 中验证云空调控件，然后清理并确认文件消失；修复后连续两轮约 6.6 秒和 12.5 秒通过。网络仍保持可用，不代表所有动态功能离线可用。
- 辅助日志位于本机 `/tmp/ylf-cache-all-tests.log`、`/tmp/ylf-cache-live-repeat.log`、`/tmp/ylf-cache-final-regression.log`；回归修复前后分别为 `/tmp/ylf-cache-downloader-red.log` / `/tmp/ylf-cache-downloader-green.log`。临时工程未进入产品或发布流程。
- 本轮 iOS 定向测试 `test_sim_2026-10-17T19-23-53-052Z_pid28871_3118faee.xcresult` 在等待安装 / 启动超过 12 分钟后停止。不能把工具返回、编译成功或 macOS 通过等同于 iOS 完整旅程通过。

仍需在可正常启动应用的独立 iOS 模拟器完成：新进程冷启动、上述缓存定向测试、启用 `YLF_CACHE_UI_TEST=1` 的完整旅程（含自动更新偏好持久化）、可控单项 / 全部清理确认，再重复联网旅程验证稳定性。

### 专用设备恢复排查 · 2026-10-18 03:47–04:10

- 旧专用设备再次启动失败，返回 `launchd failed to respond` / `could not bind to session`。没有重启全局 CoreSimulator 或中断其他正在使用的模拟器。
- 新建 `YunleFun Cache UI Recovery` 后，安装约 11 秒、普通启动约 6 秒成功，首页可见。首次 UI 用例运行到设置开关：SwiftUI 将整行暴露为 switch，默认中心点击没有改变开关值。测试改为点击右侧控件并等待值变化，保留开关默认值及重启持久化断言。修正后的完整旅程尚未通过，不能把该定位修改记为已完成运行复验。
- 新增真实自动更新 UI 专项和 `--automatic` 过期夹具，覆盖运行中保留旧版本、Wi-Fi 静默下载、下次会话使用更新及运行菜单清理。夹具编码与标记检查通过；此 UI 专项尚未执行成功。
- 最新测试包编译通过，0 warnings / 0 errors：`build_sim_2026-10-17T19-54-55-835Z_pid28871_436a73ca.xctestproducts`。
- 同设备后续测试卡在 `SimDevice.launchApplication`；仅重启本设备 bridge 后结束等待，但重新启动设备也出现会话绑定失败。第二台独立设备 `YunleFun Cache UI Isolated 2` 初始化耗时 5 分 28 秒，工具 300 秒超时后底层 Xcode 继续运行，最终进入用例，但应用启动停在运行库加载阶段。
- 系统进程 `xpcproxy_sim` 和应用 `YunleFun` 的独立采样均位于 `dyld3::mapSplitCachePrivate → __mmap`。应用采样时 footprint 约 336 KB，尚未进入业务代码。同期交换内存约 24 GB、数据盘剩余约 34 GB；这支持存在宿主/运行时阻塞，但尚不能断言内存压力是唯一根因。
- 首次开关断言失败结果：`test_sim_2026-10-17T19-49-47-079Z_pid28871_870e1b56.xcresult`。后续启动阻塞结果：`test_sim_2026-10-17T19-55-36-269Z_pid28871_1a2f2465.xcresult`；第二台设备的未完成旅程：`test_sim_2026-10-17T20-00-37-960Z_pid28871_7b6fbdf5.xcresult`。它们都不是完整 UI 通过记录。
- 采样文件保留于 `/tmp/ylf-cache-recovery-xcode-sample.txt`、`/tmp/ylf-cache-recovery-bridge-sample.txt`、`/tmp/ylf-cache-isolated-xcode-sample.txt`、`/tmp/ylf-cache-xpcproxy-sample.txt`、`/tmp/ylf-cache-ui-app-sample.txt`。停止本任务挂起测试并关闭专用设备，避免继续增加负载；其他仍在使用或用途未确认的模拟器保留。

### 设备恢复与超时阶段修正 · 2026-10-18

- 经用户明确允许，关闭空闲的 Life 预览，并向另一原生任务协调串行模拟器测试。该任务自行关闭其设备并保留登录检查点；缓存测试仅使用 `YunleFun Cache UI Isolated 2`（`49FB90E5-FF24-4113-AD2F-57A68A98CF62`）。本轮曾在确认所有设备关闭、没有活动安装或测试命令后重启用户级 CoreSimulator 服务；没有中断正在使用的设备。已删除本任务两台废弃设备和过期测试产品，保留结果与日志。
- 临时目录权限核对为 `1777`，`simctl runtime dyld_shared_cache update` 确认当前运行库缓存可用，未强制重建。`DYLD_SHARED_REGION=avoid` 的隔离实验被运行库明确拒绝，已移除该变量并正常启动设备。
- 主机仍出现约 638 的负载和 CPU 无空闲。Xcode 可卡在 XCTest 控制会话建立阶段；仅重启专用设备的 `testmanagerd` 后可继续执行。脚本将可控 WebKit 替身与真实联网测试分进程运行，并保留每次失败，不自动重试覆盖证据。这些结果不证明宿主系统的所有延迟已消除。
- 一次真实 UI 下载的时间线显示：14:44:47 请求启动，14:45:26 才启动 WebContent / Network / GPU，14:45:28 才获准主框架导航；旧下载器在 14:45:35 终止。启动约 39 秒耗尽原来的单一预算，实际网页加载只获得几秒。这属于下载期限边界问题，不能把系统准备耗时完全算作联网耗时。
- 下载器先改为两个有上限的阶段：引擎准备 45 秒，首次主框架导航获准后加载与归档另 45 秒，两个阶段预算合计 90 秒（该切换边界随后继续修正，见下文）；HTTP 请求仍为 40 秒。重复导航和重定向不能续期。每个阶段使用独立期限标识和操作代次，已取消的旧计时器不能结束新阶段或重试。取消和清理仍立即取消当前操作，更新失败保留旧文件。
- 新增回归先复现“导航尚有时间却被启动阶段期限终止”：`test_sim_2026-10-18T06-52-01-362Z_pid58326_4f85227b.xcresult`。修复后下载器 **5 通过 / 0 失败 / 0 跳过**：`test_sim_2026-10-18T06-53-52-849Z_pid58326_0133a549.xcresult`，包含两个阶段、重复回调不得续期、旧归档与导航回调、网络限制。测试替身隔离真实 WebKit 初始化回调，使期限边界可控。
- UI 测试等待真实标签按钮出现、可点击及标签页已选中，处理运行页面结束后的动画；保留下载成功消息、旧会话、新版本和清理的全部断言。最新构建 `build_sim_2026-10-18T06-53-19-791Z_pid58326_b07c4904.xctestproducts` 通过，0 warnings / 0 errors。
- 同构建首先通过 28 项冷启动 / 缓存 / 联网测试、第一轮全部 3 个 UI 流程及第二轮手动流程；无设备重启的第二轮自动更新在旧缓存首载时失败，自动下载尚未开启。失败记录保留于 `phase-budget-acceptance/automatic-update-2.xcresult`。采样显示主线程处于 run loop，系统扩展启动线程等待 `RBSLaunchRequest` 的同步回复及 FrontBoard bootstrap 锁，失败快照收集也被延迟。随后只重启专用设备，按组间重启方式重新执行 UI 专项；网站数据和偏好保留，失败用例留下的单条合成旧缓存在严格核对标记与摘要后移入本机 `failed-ui-fixtures`，未覆盖失败结果。

### 实际导航边界回归 · 2026-10-18 15:40

第一版两阶段期限仍在导航获准时提前切换。用真实 WebKit 回调取得的导航资料构建受控回归，复现其在实际导航开始前消耗加载预算：`test_sim_2026-10-18T07-35-56-038Z_pid58326_feaee2c7.xcresult`。实时阶段日志记录获准后约 0.027 秒就开始计时、实际导航在 0.695 秒才开始，1.05 秒即被终止。

最终在 `didStartProvisionalNavigation` 才启动加载 / 归档的 45 秒期限；准备阶段给多进程初始化独立的 90 秒预算。新增无导航时引擎本身也必须超时的断言；重复导航不得续期、旧回调和旧计时器不得结束当前操作。下载器 **6 通过 / 0 失败 / 0 跳过**：`test_sim_2026-10-18T07-40-45-030Z_pid58326_e35a669a.xcresult`。最新构建为 `build_sim_2026-10-18T07-40-25-769Z_pid58326_f3a5126f.xctestproducts`，0 warnings / 0 errors。

阶段日志只记录随机操作标识、阶段、耗时及错误域 / 代码，不记录网站地址、归档内容或凭据。`--restart-ui-groups` 只在 UI 组之前重启专用设备，底层与联网组保留独立应用进程；可配合 `--restart-test-service` 使用。此前失败用例的合成缓存及缓存测试偏好已在专用设备关闭时备份重置，其他网站资料、偏好和设备保留。

### 最终完整验收 · 2026-10-18

同一最终构建 `build_sim_2026-10-18T07-40-25-769Z_pid58326_f3a5126f.xctestproducts` 在 iPhone 18 Pro / iOS 27 专用模拟器完成 **35 通过 / 0 失败 / 0 跳过**。验收结束时已核对原生 Swift 源码与项目文件与该构建一致；`git diff --check` 和两个验证脚本的语法检查通过。

| 验收组 | 通过数量 |
| --- | ---: |
| 新进程冷启动身份清理 | 1 |
| 存储、并发、自动更新策略、下载器期限、WebKit 与运行时 | 26 |
| 真实云空调下载 / 更新 / 全新 WebView 回放 / 清理 | 2 |
| 下载 / 手动更新 / 缓存启动 / 取消及全部清理 UI，两轮 | 2 |
| Wi-Fi 静默更新 / 旧会话保留 / 重开使用新缓存 / 运行菜单单项清理 UI，两轮 | 2 |
| 单项与全部清理各自取消 / 确认 UI，两轮 | 2 |

实际调用使用 `--repeat 2 --restart-ui-groups --restart-test-service`，共 9 个串行测试组。UI 组之间仅重启本任务专用设备，保留网站资料和偏好；这项隔离恢复不代表宿主长会话的 RunningBoard / CoreSimulator 延迟已全面修复。测试中的下载、页面内容、新旧会话、偏好持久化及清理断言全部保留，失败尝试也保留在先前结果目录中。

本机结果目录为 `~/.codex/artifacts/ios-cache-ui-20261018-01a14b01/navigation-boundary-acceptance/`，包含各组 `.xcresult`、日志、原始 JSON、`validation-summary.json` 和额外核对的 `verified-acceptance.json`。最终截图位于同级 `final-evidence/`，包含旧缓存、更新就绪、重开后的新页面、单项清理确认和清空列表。实时阶段日志保留于同级 `boundary-red-host.log`。

通过后再次检查真实容器：剩余下载缓存文件为 0，自动更新关闭、仅 Wi-Fi 开启。已结束全部测试与日志监听，关闭缓存专用模拟器，并通知协调任务恢复其测试；Life 预览保持关闭，其他设备及私有检查点保留。二进制结果未加入仓库；本轮没有进行真机、iPad 或最低 iOS 16 验收，也不据联网成功声称任意网站可完整离线运行。

### 无组间重启的连续 UI 验收 · 2026-10-18 16:26

沿用上述最终构建，专用设备启动一次后执行 `--phase ui --repeat 2`，省略所有重启选项，连续两轮完整 UI **6 通过 / 0 失败 / 0 跳过**。下载、手动更新、缓存页面、新旧会话、偏好持久化及单项 / 全部清理的断言全部保留。各组实际命令耗时如下（包含 Xcode 会话建立和收尾）：

| UI 流程 | 第一轮 / 秒 | 第二轮 / 秒 |
| --- | ---: | ---: |
| 下载、手动更新、缓存启动和全部清理 | 140.8 | 104.9 |
| Wi-Fi 自动更新、旧会话保留、重开新版本和单项清理 | 111.7 | 95.7 |
| 单项 / 全部清理的取消及确认 | 42.7 | 40.7 |

每组前后 `launchd_sim` 均为 `72095`（16:15:55 启动），SpringBoard 为 `72101`，RunningBoard 为 `72106`。XCTest 控制服务首次按需启动为 `93716` 后也保持不变；未重启设备、上述服务或宿主 CoreSimulator。另一原生任务按既有授权自行结束测试并暂停新测试，本任务只操作 `49FB90E5-FF24-4113-AD2F-57A68A98CF62`，没有操作其他设备。

结果位于本机 `~/.codex/artifacts/ios-cache-ui-20261018-01a14b01/continuous-session/ui-two-rounds/`，`validation-summary.json` 保存全部计数、耗时、重启选项和服务会话信息。第二轮的旧缓存、新页面、更新就绪和清理截图已导出到同级 `ui-evidence/`。

本轮没有复现先前采样中的扩展启动阻塞。串行窗口初始主机负载约 85，期间一次采样约 199，低于此前 600 以上的负载；这与资源争用假设相符，但不能证明它是唯一根因，也不能将一次窗口内通过等同于所有高负载条件下均无阻塞。本轮只增强验收的会话核对和证据记录，没有调整生产下载期限或改动 WebView 生命周期。

### 同一会话的组合复验 · 2026-10-18 16:36

上述两轮 UI 通过后，保持同一设备及服务会话，再执行默认完整验收 `--repeat 2`，同样省略全部重启选项，取得 **35 通过 / 0 失败 / 0 跳过**：独立进程冷启动 1 项、缓存定向 26 项、真实网站 2 项，以及两轮完整 UI 共 6 项。该顺序覆盖先运行底层 WebKit 组、再运行 UI 的原失败场景。

两次调用累计 **41 次测试执行、35 项不同测试、四轮完整 UI（12 次 UI 执行）**，没有失败或跳过。16:16:48 至 16:36:02 的全部 15 组均保持同一 `launchd_sim 72095`，SpringBoard `72101`、RunningBoard `72106` 及首次启动后的 XCTest 控制服务 `93716` 也未变化。三个重启选项均为 `false`，验收期间没有重启设备或服务，也没有自动重跑失败组。

完整组合结果位于 `continuous-session/integrated-two-rounds/`，与前述 `ui-two-rounds/` 同属本机 `~/.codex/artifacts/ios-cache-ui-20261018-01a14b01/` 下的连续验收目录。汇总核对文件为 `continuous-session/verified-continuous-acceptance.json`；最终组合第二轮的截图位于 `continuous-session/integrated-ui-evidence/`。`cache-host.log` 保存本次阶段日志，`host-during-integrated.json` 记录主机采样，`native-source-audit.json` 保存原生源码摘要并核对其与上述测试构建一致。

最终再次核对容器：下载缓存文件 0，自动更新关闭、仅 Wi-Fi 开启。测试命令和日志监听均已结束，专用设备确认关闭，并已通知协调任务恢复测试。其他设备、网站资料和私有检查点保留。本轮实现了无需组间重启的连续验收目标；先前高负载下系统扩展启动阻塞的唯一根因仍未证实。

### 高负载启动定位与专项回归 · 2026-10-18

最初阶段保留其他任务正在使用的设备，在专用设备 `49FB90E5-FF24-4113-AD2F-57A68A98CF62` 做自然负载下的有界探测；该阶段没有人为施压，后续独立的有界资源对照见下文。主机为 10 核、32 GiB，采样负载曾达约 383；负载超过 100 时也观察到约一半 CPU 空闲，`pmset -g therm` 未记录热限制告警，因此不能只凭负载平均值判定 CPU 持续饱和。

新增 `apps/ios/scripts/probe-native-startup.py`，要求显式指定 UUID、匹配的设备名称、已启动的专用访客设备及空结果目录。它每轮结束本任务应用并通过普通 `simctl launch` 启动，不连接 LLDB；等待既有诊断中的固定 `app.launched` 标记，只导出该标记的时间，不导出其他诊断消息或账号分区。该标记表示应用初始化已到达，不替代首屏 / WebKit / 交互验收。准备超过阈值时，只对指定设备的应用、RunningBoard、SpringBoard 和 `launchd_sim` 做有界采样，并记录主机换页计数。结果保留失败，脚本不重启设备、服务或自动重试。

```sh
python3 apps/ios/scripts/probe-native-startup.py \
  --simulator SIMULATOR_UUID \
  --expected-device-name 'DEDICATED_SIMULATOR_NAME' \
  --output /path/to/empty-results-directory \
  --repeat 8 --timeout 20 --sample-after 10
```

普通启动的四组对照均为新应用进程，保留设备会话和应用数据：

| 构建 / 顺序 | 次数 | 中位耗时 / 秒 | 最长耗时 / 秒 |
| --- | ---: | ---: | ---: |
| 原 Debug，首次探测 | 8 | 2.587 | 16.726 |
| 原 Debug，10 秒探测上限 | 8 | 2.515 | 3.153 |
| 仅临时设置 `ENABLE_DEBUG_DYLIB=NO` | 8 | 2.424 | 4.506 |
| 装回原 Debug | 8 | 3.860 | 4.230 |

首次组的两次慢启动约 16.7 / 16.4 秒。第一次的应用采样仍在 `dyld_sim → JustInTimeLoader::loadDependents → matchesPath / Mach-O load command`，footprint 约 2 MiB，尚未进入应用业务代码，距进程出生约 13.4 秒。第七次的应用采样已进入主 RunLoop（2026-10-18 18:00 复核更正）；其 RunningBoard 工作队列同时经历提交 launchd 启动请求与解析进程属性，不能归为持续的 pre-main 阻塞。两次均没有采到服务端循环等待。这定位了**该次复现慢启动的直接耗时点：模拟器动态链接器的预加载依赖解析**；普通启动未接调试器，故该次延迟不要求 LLDB 存在。首次探测的统计可能包含诊断采集开销，随后已将采集与就绪轮询分开；不能把这些样本当作严格受控的性能基准。

各组自然负载不同，Debug 动态库对照不能证明是修复，仓库构建设置没有修改，已装回原构建并恢复原 DerivedData 配置。全局解压缩、换页计数在慢启动期间增加，但其他工作也在运行，不能据此唯一归因于内存、磁盘或 CPU 调度。先前 WebKit 空白页的客户端 `RBSLaunchRequest` 等待栈也不能单独证明 RunningBoard 死锁；仍缺该异常时刻的服务端采样。

另核对当前 runtime 的预构建缓存位于 RuntimeRoot 的 `System/Library/Caches/com.apple.dyld/`，两个主体文件约 3.8 GB。旧 `simctl runtime dyld_shared_cache update` 工具在本版本会提示 obsolete；旧目录只有工具日志不代表运行库缓存缺失。没有强制重建缓存或变更正在使用的运行库。Apple 关于 [启动的动态链接阶段](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time) 和 [调试器启动延迟的区分方法](https://developer.apple.com/forums/thread/800067) 仅用作排查依据，不把论坛案例视为本机根因证明。

专项回归增加两项，均须显式启用 `YLF_CACHE_STARTUP_PROBE=1`，联网项另须 `YLF_CACHE_LIVE_TEST=1`：

- 连续 8 次打开 `.invalid` 来源的本地缓存会话，验证页面标题，并检查结束后浏览器和 WKWebView 的弱引用均释放。首次执行 1 通过 / 0 失败 / 0 跳过，各次打开约 1.7–2.9 秒。
- 连续 8 次生产匿名下载，逐次校验真实归档资源及下载引擎释放。首次执行 1 通过 / 0 失败 / 0 跳过；各次总耗时约 2.8–28.0 秒。首次约 17.2 秒中准备占约 14.1 秒；第七次约 28.0 秒中准备占约 10.0 秒，加载 / 归档占其余时间，不能把全程都归为引擎启动。原有生产准备、导航及 HTTP 期限保持不变。

这两项没有观察到会话或下载 WebView 对象积累，不据此声称所有生命周期路径均无泄漏。验收脚本增加 `--phase startup`，在两个独立测试进程执行上述专项；完整验收可加 `--include-startup-probes`，总计 37 项。默认完整验收仍为 35 项，普通测试不自动进行连续联网探测。

### CPU、I/O 与内存对照结果 · 2026-10-18 17:30

在原 Debug 构建和同一设备会话中做三组有界对照，没有改动生产逻辑或系统缓存：

| 对照 | 实际资源条件 | 施压中启动次数 | 中位 / 最长启动耗时（秒） |
| --- | --- | ---: | ---: |
| CPU | 4 个自有计算进程；一次采样约 88% CPU 忙碌 | 8 | 2.540 / 4.474 |
| 读 I/O | 2 个进程只读自有 128 MiB 临时文件，FD 使用 `F_NOCACHE`；一次采样约 849 MB/s | 8 | 2.744 / 3.659 |
| 内存 | 其他任务自然结束测试并自行关闭设备后，分配至 1.25 GiB 即达到 warn，停止增加；保持并周期访问数据 | 4 | 2.389 / 2.489 |

CPU 对照包含施压前 4 次、施压中 8 次、释放后 4 次；计算进程约 30 秒后回收，均有 60 秒自限。I/O 对照包含 2 / 8 / 2 次，两个读取进程约 28 秒退出，128 MiB 文件已删除。内存对照包含 2 / 4 / 2 次：配置上限为 4 GiB / 30 秒，实际到 1.25 GiB、指标进入 warn 后不再增长；约 18.3 秒全部释放，未进入 critical。内存对照的启动探测期间每秒检查其他设备状态；出现其他设备启动或 critical 会立即释放测试内存。三组各自的全部探测均在配置的 20 秒期限内完成。

在其他任务仍运行时，还记录到自然 warn 现场，8 次普通启动约 2.3–3.5 秒，指标在每次前后均为 2。`kern.memorystatus_vm_pressure_level` 的输出按 dispatch 压力级别转换：1 为 normal、2 为 warn、4 为 critical，解释依据是 [Apple XNU 的只读 sysctl 实现](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c) 及 SDK `dispatch/source.h`，没有写入内核压力触发接口。

上述结果表明，在本轮测到的资源强度内，单独的 CPU、I/O 和 warn 级内存压力均不足以稳定复现旧故障，不能将其任一项写成唯一根因。没有继续增加内存至 critical 或复刻此前整机 600–900 的极端负载。已确认的是首次慢启动采样停在 pre-main 动态库依赖解析；另一次慢探测采样已到主 RunLoop；旧空白页的系统服务端等待链尚未再次捕获，未宣称宿主阻塞已经根治。

原构建的最新测试包 `build_sim_2026-10-18T08-59-15-454Z_pid58326_319fe27b.xctestproducts` 在原会话继续通过两轮完整 UI **6 / 0 / 0**（通过 / 失败 / 跳过），再通过 `--phase startup` 的两个专项 **2 / 0 / 0**。此前两个专项各自也已独立通过一次。76 次普通启动探测包含上述 A/B、自然压力和三个资源对照；各组有自己的阈值和采样条件，不将其混算为同一 SLA 的 76 项产品测试。

本机证据目录为 `~/.codex/artifacts/ios-cache-ui-20261018-01a14b01/high-load-startup/`：

- `native-launch-1/` 保留两次慢启动的成对采样；后续 `native-strict-a/`、`native-direct-b/`、`native-restored-a/` 保留构建对照。
- `bounded-cpu-comparison.json`、`bounded-io-comparison.json`、`bounded-memory-comparison.json` 与对应子目录保留资源采样、工作进程、实际期限和逐次启动结果。
- `native-pressure-natural/` 保留自然 warn 下的逐次指标；`ui-two-rounds/`、`startup-regressions/` 保留实际 `.xcresult` 计数和服务会话记录。
- `debug/` 中的有界资源对照程序和设备范围日志观察器仅作诊断原型；正式重复启动探测和专项验收入口在 `apps/ios/scripts/`。观察器在本轮 UI 及专项重跑期间没有触发新的超过阈值引擎采样，不能用零采样证明故障消失。

UI 与专项组之间未重启设备或服务：`launchd_sim 49579`（16:45:17 启动）、SpringBoard `49588`、RunningBoard `49591`、XCTest 服务 `50562` 均保持不变。最终核对缓存文件为 0、自动更新关闭、仅 Wi-Fi 开启。本任务所有测试工作进程和日志监听均已结束，专用设备已确认关闭，并已通知协调任务恢复测试；网站资料与其他设备的私有检查点保留。

### 系统服务端同步采样 · 2026-10-18

`simulator_startup_diagnostics.py` 将正常启动探测、连续缓存会话、匿名下载和缓存 UI 页面的等待接到同一套采样器。验收时显式添加 `--capture-slow-startup --expected-device-name 'YunleFun Cache UI Isolated 2'`；默认验收不启动采样器。下载引擎准备、缓存测试打开至渲染的进度事件超过 8 秒，或 XCTest 首个用例开始前超过 30 秒，会触发采样。后者单独标为 `xctest-bootstrap`，不能当成应用或 WebKit 的耗时。UI 标记在解析、点击启动按钮之前发出，覆盖 XCTest 等待界面空闲的阶段。进度以日志被观察到的时间计，日志生产或传输延迟仍可能影响触发时间。

采样器先验证设备 UUID、名称、Booted 状态和 SpringBoard 的 `launchd_sim` 父进程，并保存进程出生时间和可执行文件 UUID。之后直接使用主机公开 libproc 接口枚举这一个 launchd 的子进程，不在异常时向 RunningBoard 或 launchd 发采集 RPC。每个时间点最多并发采样 12 个进程，包含应用、RunningBoard、launchd、SpringBoard、所选设备的测试 / 启动服务以及最近创建的 WebKit / xpcproxy 进程；超出上限的扩展 PID 单独记为 omitted。保留两个时间点的栈和期间的逐 PID CPU 原始计数、pageins、驻留量、footprint 与磁盘读写字节。字段布局已与当前 macOS SDK 的 C 结构体编译结果核对，不再把 `ps` 不支持的缺页列当作零。进程身份变化会拒绝后续采样；其他设备的子进程不进入采样列表。

每组最多触发 3 次，单个 `sample` 为 1 秒 / 20 毫秒间隔，命令最多等 20 秒。采样与页面就绪轮询分开；符号化和进程启动也可能受主机调度影响，报告保留采集启动与完成时间。全局 VM 计数最多等待 1 秒，缺失时记录错误并继续抓栈。采样器不终止、安装、擦除应用，不重启系统服务，也不读取进程参数、环境变量或账号数据。OSLog 仅监听所选设备的固定下载诊断事件，不导出原始任意日志。失败、取消和重复到达的日志事件不会重新打开已结束的等待。

也可在所选设备正常运行时直接获取两波现场（输出目录必须为空）：

```sh
python3 apps/ios/scripts/capture-simulator-startup.py \
  --simulator 49FB90E5-FF24-4113-AD2F-57A68A98CF62 \
  --expected-device-name 'YunleFun Cache UI Isolated 2' \
  --output /tmp/ylf-startup-capture-new
```

该独立入口初始化时仍需一次所选设备的 `launchctl list`；持续异常可能令这一步失败。连续验收在运行测试前建立服务身份，后续异常采集无需该 RPC。可用 `--watch-log <测试日志> --duration 600` 监听已启动的测试；独立监听不控制测试生命周期。每次采样的 `capture.json`、栈文件以及组内 `summary.json` 留在新目录，采样错误与测试结果分别记录。用 `python3 -m unittest discover -s apps/ios/scripts -p test_simulator_startup_diagnostics.py` 验证设备排除、PID 复用、真实导航边界及日志重排回归，无需启动模拟器。

本轮第一版采样器在全机 `ps` 前置枚举时超过 8 秒，还没有开始应用启动探测。失败保留为 `server-wait-chain/native-probe/preflight-error.json`；改成限定父进程的 libproc 后，设备和资源快照实测约 0.77 秒完成。随后 8 次普通启动均通过（约 2.3–3.6 秒，未达 4 秒采样阈值）。这修复的是诊断工具的采集阻塞，不将其写成原有应用启动延迟的根因或修复。

#### 本轮连续验收与等待链

构建 `d85b8876.xctestproducts`（2026-10-18 17:58，0 警告 / 错误）以 `--phase all --repeat 2 --include-startup-probes --capture-slow-startup` 连续运行，实际 `.xcresult` 汇总为 **37 通过 / 0 失败 / 0 跳过**：冷启动 1、缓存核心 26、真实联网 2、启动专项 2、两轮 UI 各 3。这里是 37 次用例执行，包含第二轮重复执行的 UI 用例。两个启动专项各自覆盖 8 次缓存会话或匿名引擎创建及释放。

采样触发及观察到的等待如下；这些阈值用于采集现场，不是产品失败期限：

| 现场 | 等待至阶段结束（秒） | 成功栈文件 |
| --- | ---: | ---: |
| 第一轮手动下载后打开缓存页 | 14.744 | 24 |
| 第一轮打开自动更新旧缓存页 | 10.573 | 23 |
| 第二轮首次下载引擎准备 | 9.633 | 24 |
| 第二轮打开自动更新旧缓存页 | 8.567 | 21 |

共 4 个现场、92 份成功栈，均包括同一设备的客户端、RunningBoard 与 launchd；没有采样超时。第一轮两个页面现场的 WebContent 已进入扩展主循环。具体看到 `unblockServicesRequiredByAccessibility → AXWebProcessLoader → dlopen → notifyMonitor… → RemoteNotificationResponder::blockOnSynchronousEvent`；另一份中 WebContent 的 AX 主线程和 AXBinaryMonitorQueue 等待 `withLoadersReadLock`，同进程 AXBundleLoadQueue 停在动态库加载后的同步通知。对应 RunningBoard 主线程和工作线程空闲，launchd 未见持续启动处理堵塞；不能把这次等待解释成 RunningBoard 死锁。

这把**本轮部分页面等待的直接栈位置**缩小到 WebKit 辅助功能加载、dyld 锁与外部映像通知。Apple 开放源中的[映像通知路径](https://github.com/apple-oss-distributions/dyld/blob/main/dyld/ExternallyViewableState.cpp)及[监控端回执](https://github.com/apple-oss-distributions/dyld/blob/main/libdyld/dyld_process_info_notify.cpp)支持同步通知的含义解释；它们不证明本机通知接收者的身份、哪一端欠回执或唯一根因。本轮没有追到确切的外部接收进程，也没有排除 `sample` 挂接和符号化对通知的影响。等待在采样触发前已超过阈值，但不能将全段 8–15 秒都归给采到的某个函数。第二轮下载准备的采样没有捕获同样的持续等待栈，不能把它与页面辅助功能等待合并归因。

两波之间测试仍继续推进，部分操作结束后已出现新子进程；报告保留 PID、出生时间、事件观察时间和计数，不将新 PID 当作同一个卡死进程。首次页面样本期间 WebContent 的 pageins 和读字节继续增加，全局处于 warn；这些是资源观测，不是内存或磁盘故障的因果证明。旧数分钟 `RBSLaunchRequest.executeRequest` 阻塞本轮没有重现，其上游原因仍待确认。没有据此改动生产逻辑、下载期限或构建设置。

另将普通启动采样阈值主动设为 1 秒做一次控制验证，3.350 秒观察到应用初始化标记（标记时间约 3.305 秒），两波 14 份栈成功；第一波还在 pre-main `loadDependents`，第二波已进入应用主循环，显示该栈也会出现在正常启动的过渡阶段。确认异步采样、等待第二波和应用退出都能收尾。它是人为触发的采样控制，不计入上述 4 个真实延迟现场。工具的 7 项主机回归、Python 编译检查与 `git diff --check` 均通过；验收前后 120 个源文件摘要一致。

完整验收保持 `launchd_sim 52383`（18:02:06 启动）、SpringBoard `52392`、RunningBoard `52396`；XCTest 服务首次按需启动为 `57768`，随后各组保持一致。三个组间重启开关均为 false。最终缓存 0、自动更新关闭、仅 Wi-Fi 开启，工作进程和监听已结束，专用设备确认 Shutdown 后已让出串行窗口。其他在用模拟器未操作。

本机证据在 `~/.codex/artifacts/ios-cache-ui-20261018-01a14b01/server-wait-chain/`：`continuous-acceptance/` 保存 11 组实际结果及采样，`episode-analysis.json` 保存四次现场与逐 PID 计数变化；`native-probe-libproc/`、`native-capture-smoke/` 保存普通启动和控制验证，`prior-evidence-correction.json` 明确更正上一轮第七次采样已进主循环的解读，原始证据保留。
