# 系统分享反馈的本地验收

只对已确认空闲、使用合成访客数据的模拟器串行执行；需要本机 Support 仓库及其已构建的 `packages/*/dist`。原生工单验收不需要启动 Web；验收显式网页入口时才需要 `apps/web/.output`。不会创建云资源、发送通知或发布构建。

`server.mjs SUPPORT_ROOT TASK_DIRECTORY` 在 `https://127.0.0.1:18473` 启动验收 API，使用 Support 的 `PrivateFeedbackService`、访客 / CSRF / 工单凭证、CloudBase 持久化适配器和既有离线数据库夹具；生产数据库替换为进程内数据。其余页面和静态资源代理到 `127.0.0.1:18474` 上未经修改的 Support Nuxt 构建。代理前拦截所有 `/api/` 请求，不把测试 API 转发到生产。

## 准备

1. 按项目 `AGENTS.md` 和 `~/Library/Developer/SimulatorMaintenance/shared-devices.json` 核对设备归属、旧 UDID 映射与实际 `simctl list`。复用共享池中空闲设备，通过合成数据隔离本轮验收，不为新一轮测试创建同系统同机型副本。任务独占临时目录的 `ownership.json` 记录：

   ```json
   {"simulator":"<本轮 UDID>","purpose":"isolated system share and synthetic guest-ticket acceptance"}
   ```

2. 在该目录生成一天有效、SAN 为 `IP:127.0.0.1` 的本地证书 `local-cert.pem`、私钥 `local-key.pem`。只使用 `simctl keychain <UDID> add-root-cert` 将证书加入本轮模拟器；不关闭证书校验、不更改 Mac 钥匙串。
3. 启动上述验收 API。验收网页入口时另在 Support 根目录设置 `HOST=127.0.0.1 PORT=18474 NUXT_PUBLIC_APP_ORIGIN=https://127.0.0.1:18473 NUXT_PUBLIC_SUPPORT_API_BASE_URL=/api`，运行 `node apps/web/.output/server/index.mjs`。端口被占用时先查归属，不终止其他服务。
4. 使用任务目录的 `DerivedData` 构建 Debug `YunleFun`，额外传入 `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG YUNLE_FEEDBACK_LOCAL_VALIDATION` 和 `build-for-testing`。共享 Swift 源码只有在该显式标记 **同时满足 Debug 和模拟器** 时才使用固定的 loopback HTTPS origin，扩展也只在此模式使用预置渠道。普通 Debug、Benchmark、Release 和真机继续使用正式域名与原收据判定。Release 构建需另行检查不含 loopback origin。
5. 在本轮设备安装并打开 App，让访客身份恢复完成，再导入图片。新设备的 `addmedia` 会同步等待照片库，可能阻塞同设备后续安装；不要在初始化期间并行发起安装与照片导入。仅向本轮照片库导入 Support 的合成 JPEG，以及 `simctl io screenshot` 获得的本轮访客界面 PNG。照片库可能包含 Apple 默认样片，务必选中「最近存储」中的合成图片或系统标识为「截屏」的 PNG。
6. 执行 `python3 preflight.py TASK_DIRECTORY SUPPORT_ROOT`，先检查 Origin、访客 / CSRF、成功后丢失响应的幂等重试、私密链接交换及截图鉴权读取。

## 系统入口与 UI 断言

先从照片的 **Share → 云乐坊 Native** 打开真实扩展。iOS 分享菜单使用主 App 名称，正式版对应「云乐坊」；表单标题为「反馈给云乐坊」。不要通过私有 API 或直接构造扩展控制器代替系统入口。

```sh
python3 run-ui.py TASK_DIRECTORY --name jpeg-full --presented
```

该测试使用扩展自己的 Bundle ID 查询界面，依次检查原生预览和双击缩放、确认取消前零网络请求、服务端提交成功后返回 503、相同幂等键重试、成功回执、App 重启恢复、原生工单详情 / 私密截图读取与预览，以及清除本机记录不删除服务端工单。扩展和工单截图均检查左右横屏、图片比例 / 完整可见 / 居中、横屏放大后旋回竖屏的适配及关闭按钮可达性。工单与截图默认路径断言无 WebView。入口可以在开始前选好，也可在测试的 120 秒等待期间通过 Device Hub 选择；后者保持模拟器辅助功能服务可用。

iOS 26 视觉验收需要在 26.x 实际运行；分别设置本轮设备的 `simctl ui <UDID> appearance light` / `dark`，重新从系统菜单进入并保存表单、确认、原生工单及预览截图。检查标准导航操作的系统玻璃材质、内容对比度、图片比例和缩放。预览采用深色内容背景；浅色 / 深色主要比较表单与工单界面，不通过 CSS 仿造系统材质。

旋转验收应等待实际 `app.windows.firstMatch.frame` 的宽高关系完成改变，并检查图片框是否保持比例、完整位于窗口内和居中。使用 **`XCUIScreen.main.screenshot()`** 导出整屏证据，保留方向元数据，并同时导出窗口 / 图片框几何信息。不要用 `app.screenshot().image.size` 或 PNG 编码像素的宽高判断界面方向：2026-10-28 的 A/B 诊断确认 App 范围截图在横屏下可能出现裁剪与方向元数据异常，而实际窗口和整屏预览已横屏。初轮“横屏未通过”的截图结论已由后续实际窗口验收取代。

仅验证主 App 草稿横屏时，不需要启动本地 API 或导入证书：使用普通 Debug 构建和已准备的合成照片库，执行 `python3 run-ui.py TASK_DIRECTORY --name draft-rotation --rotation`。该用例还验证关闭后保留描述 / 图片、移除图片，并在未显式开启 `SCREENSHOT_ROTATION_QA` 时跳过。横屏方法由草稿用例与完整系统分享用例共用，避免三处验收逻辑分叉。

主 App 草稿可另运行 `python3 run-ui.py TASK_DIRECTORY --name draft --presented --draft`：通过 iOS 26 的系统图片选择器导入截图，验证原生预览、双击缩放、关闭后描述与图片保留、移除图片及全程无提交。系统图片选择器属于 `com.apple.mobileslideshow.photospicker` ExtensionKit 进程，需查询它的辅助功能树，不能查询被遮挡的主 App。

这里的系统入口由实际 UI 操作选择，XCTest 验证进入后的整个流程，不宣称是一条完全无人操作的 Photos 自动化。测试框架不能把底层照片 / 分享服务的辅助功能树当成扩展自己的树。

渠道分支使用本轮 App Group 中的记忆渠道，不伪造 App Store 收据。App 保持后台时执行：

```sh
python3 set-channel.py TASK_DIRECTORY testFlight
# 每条测试开始前或等待期间，从真实系统菜单重新打开扩展。
python3 run-ui.py TASK_DIRECTORY --name beta-official --presented --beta-close
python3 run-ui.py TASK_DIRECTORY --name beta-general --presented --beta
python3 set-channel.py TASK_DIRECTORY standard
```

分别断言优先显示官方反馈说明、关闭说明不提交；以及明确选择通用反馈后才显示截图，移除和取消不提交。真实 TestFlight 安装的收据识别仍需后续候选构建验证。

`server-control.json` 仅包含本地夹具控制密钥，留在任务临时目录；报告 `server-report.json` 仅保存合成描述、截图元数据、请求次数和幂等键，不保存图片或访客访问凭证。各次 UI 结果使用不同名称，导出摘要和必要截图后回收原始结果包。

## 收尾

停止本轮 Web / API / 测试进程，导出测试摘要、合成截图、后端元数据及源文件摘要；删除任务构建目录、证书和密钥，保留共享依赖缓存。再次核对共享池：本轮设备若已被维护流程指定为保留设备，必须保留，不能按过期的临时设备记录删除；只清理本轮 QA App、合成草稿与本轮证书。不要为清理一张证书重置整台设备的钥匙串。恢复设备时也需遵循最新映射，不能重建已被维护流程淘汰的设备或运行时。

若安装和启动连 Apple 自带 App 也持续卡住，先采样本轮设备进程。2026-10-28 曾确认本轮自动 `simctl log stream` 使 runningboardd 阻塞在 `_os_activity_stream_reflect`；只停止该任务的日志流后，启动立即恢复。不要据此关闭其他设备或重置全局模拟器服务。
