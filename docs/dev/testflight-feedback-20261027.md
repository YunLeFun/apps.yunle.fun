# TestFlight 用户反馈核对 · 2026-10-27

## 查询方式

本机已有 ASC CLI 5.14.3 和 System Keychain 认证，可直接使用 App Store Connect API，无需浏览器登录或新增 MCP。以下均为只读命令，`--paginate` 会拉取全部分页：

```sh
# 文字与截图反馈；附带构建信息
asc --read-only testflight feedback list \
  --app 6759859441 --include build --paginate --output json

# 拉取截图下载地址；链接有有效期
asc --read-only testflight feedback list \
  --app 6759859441 --include-screenshots --paginate --output json

# 查看单条反馈详情
asc --read-only testflight feedback view \
  --submission-id ADHXHNjwvH2Te4xRVTRBg-g --output json

# 崩溃反馈
asc --read-only testflight crashes list \
  --app 6759859441 --paginate --output json

# 有崩溃反馈时，以对应 submission ID 拉取日志
asc --read-only testflight crashes log --submission-id SUBMISSION_ID
```

命令输出可能包含测试者邮箱及临时截图链接，原始响应和截图不提交仓库；共享记录时移除这些字段。命令与认证沿用现有 [TestFlight 发布配置](./testflight.md)。

## 本次反馈

全量分页查询得到 **1 条文字 / 截图反馈、0 条崩溃反馈**。

| 字段     | 内容                                                                            |
| -------- | ------------------------------------------------------------------------------- |
| App      | 云乐坊 · `6759859441` / `fun.yunle.apps`                                        |
| 反馈 ID  | `ADHXHNjwvH2Te4xRVTRBg-g`                                                       |
| 提交时间 | 2026-10-27 20:02:43（Asia/Shanghai）                                            |
| 构建     | `4` / `db510ccf-f118-46d2-9330-b5e05daf6ec5`                                    |
| 系统     | iOS 27.0.1                                                                      |
| 用户原文 | 显示暂不支持下载，需要支持                                                      |
| 截图     | 「应用下载缓存」页面中的「云乐坊 · 管理后台」显示「暂不支持下载」，没有下载按钮 |

已通过 API 取得并实际查看该截图，核对其反馈对象为管理后台的云应用资源下载，并非网页文件导出。

## 修复对应关系

构建 4 的缓存策略仅允许 `canOpenAsGuest && runtimeScope == "public"` 的应用保存首页归档；管理后台需要登录或来自工坊，因此被归入不支持下载。

本次检查开始时，工作区已存在针对管理后台与支持中心的未提交修复，详见 [公共资源缓存](./ios-application-cache.md#管理后台与支持中心的公共资源缓存)。本次保留这些改动并重新验证，不重复实现或提交其他任务的代码：

- iOS 17 及以上允许这两个站点预下载公开脚本、样式、字体和图片；工坊来源不再导致公共资源下载入口不可用。
- 页面、登录检查与接口仍使用在线请求，不保存登录页面和账号内容，也不改变应用访问权限。
- 缓存管理页提供下载、更新和删除操作；删除资源缓存保留 Cookie 与网站本地存储。
- iOS 16 继续在线打开，并提示公共资源缓存的系统版本要求。

相关实现位于 `ApplicationStaticResourceCache.swift`、`ApplicationCacheRepository.swift`、`ApplicationCacheStore.swift`、`ApplicationCacheView.swift` 与 `NativeWebRuntime.swift`。

## 本次验证与交付边界

首次核对时已有 iPhone 18 Pro / iOS 27 未运行测试命令，但随后另一任务也在该设备启动测试。本次取消自己的首轮命令；该轮已有 17 项通过，不计为完整验收。没有终止另一任务的命令，也未擦除或关闭其设备。

为避免并行测试互相干扰，本次创建临时设备 `YunLeFun TestFlight Feedback 20261027`（`3F2157B4-629A-408D-A528-E391993ECAE7`），复用已编译的测试产物，在独立环境完成重跑。Xcode 27.1 / iOS 27.0 的实际 `.xcresult` 结构化汇总为 **22 通过、0 失败、0 跳过**：

| 测试类                                 | 通过数 |
| -------------------------------------- | -----: |
| `ApplicationCacheAutomaticUpdateTests` |      9 |
| `ApplicationCacheRepositoryTests`      |      5 |
| `ApplicationCacheStoreTests`           |      3 |
| `ApplicationStaticResourcePolicyTests` |      4 |
| `ApplicationStaticResourceLiveTests`   |      1 |

最后一项同时访问两个真实站点，验证下载后在新 WebView 中读取实时页面、复用公共资源，以及清理后 Cookie / localStorage 保留且已下载资源不能再以 `only-if-cached` 读取：

| 站点     | 下载资源 | 资源总字节 | 新页面复用资源数 |
| -------- | -------: | ---------: | ---------------: |
| 管理后台 |      228 |  7,131,030 |               27 |
| 支持中心 |       69 |  1,577,779 |               15 |

缓存相关的 6 个实现与测试文件，在编译前、首轮停止后和隔离验证完成后的 SHA-256 均一致。当前源码基线为 `ba5c08b` 加已有工作区改动。本次只新增本反馈记录，未覆盖、提交已有修复或其他任务的修改。

复现时先选择空闲的当前项目模拟器，使用同一组 `-only-testing` 参数执行 `xcodebuild test`，并设置 `TEST_RUNNER_YLF_CACHE_LIVE_TEST=1`。本次使用既有 `apps/ios/build` 增量缓存；隔离重跑使用 `test-without-building`，没有复制依赖或重建第二份产物。此结果不代替真机、iOS 16 或完整 UI 回归。

测试脚本已在 `finally` 中关闭并删除临时设备，两步均返回 0；任务结束前重新核对设备列表，确认该 UDID 不存在。删除前 `simctl` 记录设备数据为 789,028,864 字节。导出的结论保存在本记录，临时截图、原始测试日志与结果包已回收，实测回收 250,191,872 字节（du 分配空间）；共享增量构建缓存继续保留。

App Store Connect 中的原始反馈予以保留。本次未上传新版 TestFlight，构建 4 上的旧行为需通过后续新构建交付修复。

## 真机体验安装 · 2026-10-27

按用户后续要求，先安装到 iPhone 15 Pro 体验，TestFlight 发布留待体验后继续。本次以 `ba5c08b` 加上述下载修复生成独立源码快照，只覆盖 7 个缓存实现 / 测试文件，不包含其他并行任务中的登录、支持中心或 App Group 改动。使用 Debug 开发签名构建 **0.2.0 (4)** / `fun.yunle.apps.native-dev`，显示名称「云乐坊 Native」。

真机编译、严格签名检查、开发描述文件设备匹配和安装均成功；已启动开发版，并再次查询确认进程仍在运行。原 `fun.yunle.apps` 的版本和安装位置未变化；开发版原有数据未卸载或清除。用户已解锁手机供安装与启动，不进行自动账号或页面操作，具体体验由用户在手机上完成。

可执行文件 SHA-256：`9d1ad8bfbcecc5733c1fc2232567734b91b8aa4ce4a2479fb906b32de1c40263`。精确源码覆盖文件及哈希、编译产物核验和脱敏安装结论保存在本机 `/Users/yunyou/.codex/artifacts/yunlefun/device-preview-20261027-203802`；其中 `cache-fix-inputs.tar.gz` 仅保留 7 个复现输入，主基线可由 Git 恢复。这些小型记录在同组修复发布并完成设备体验后可回收。临时源码、完整构建产物、结果包和日志随后删除，回收分配空间 370,872,320 字节；既有 Swift Package 缓存继续复用。
