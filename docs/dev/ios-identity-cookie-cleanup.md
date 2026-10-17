# 原生身份 Cookie 清理

## 问题与复现

原生运行时在创建时、退出登录和切换账号时清除第一方身份 Cookie。清理完成前，打开应用与后续授权必须继续等待；旧账号页面也不能绕过这个边界。

在 `c11b1e4`、Xcode 27 / iOS 27 模拟器上，连续创建原生首页运行时后，默认 `WKHTTPCookieStore.getAllCookies` 可能迟迟不回调。`HomeLayoutVisualTests.testRemovingLastInstalledApplicationKeepsRunningSessionDiscoverable` 因初次清理超过原有五秒等待而失败。失败发生在读取回调之前，尚未进入删除或 `DispatchGroup.notify`，因此空集合提前 completion 不能修复已观察到的问题。

[完整首页诊断](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39063738602)在四个独立测试进程中执行 44 次：41 通过、3 失败，失败均为上述同一用例。[缩减对照](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39064820916)保留五秒断言，并在每组重新启动测试进程两次：

| 集合                       | 执行次数 | 通过 | 失败 |
| -------------------------- | -------: | ---: | ---: |
| 完整首页 class             |       22 |   20 |    2 |
| 三个首页渲染前序与目标用例 |        8 |    6 |    2 |
| 空态渲染前序与目标用例     |        4 |    4 |    0 |
| 仅目标用例                 |        2 |    2 |    0 |

失败时 App 在前台，主线程上的轮询仍可推进；失败后独立读取 Cookie policy 也没有在观察窗口内回调。WebKit 日志同时记录了 NetworkProcess 挂起 / 恢复，但这不能单独证明框架内部的具体根因，也不能把未回调解释为默认 DataStore 被释放。

[同一构建的生命周期对照](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39065669305)按以下顺序，每组运行完整首页 class、重启测试进程两次：

| 处理方式                         | 执行次数 | 通过 | 失败 |
| -------------------------------- | -------: | ---: | ---: |
| 原实现                           |       22 |   20 |    2 |
| 仅持有默认 DataStore             |       22 |   20 |    2 |
| 持有使用同一存储的 WebKit 上下文 |       22 |   22 |    0 |
| 恢复原实现                       |       22 |   20 |    2 |

六次失败均为原始五秒身份清理超时。上下文组的 24 个读取操作全部收到回调；仅持有 DataStore 没有解决问题，撤回上下文处理后再次复现。因此采用应用侧的上下文生命周期处理，不把它表述为已证明的 WebKit 内部缺陷。

## 修复边界

`HostIdentitySessions` 在主线程创建使用同一 `WKWebsiteDataStore` 的临时 `WKWebView`，并持有到 Cookie 枚举、每一条匹配 Cookie 的删除以及调用方 completion 均完成。上下文不加载页面、不加入可见会话池，操作结束后释放。调用方传入所属 DataStore，避免上下文与 Cookie 存储不一致；Capacitor 入口先调度到主线程。

允许清除的域名与 Cookie 名组合保持不变：`play.yunle.fun/__Host-ylf_play_session`、`cms.yunle.fun/__Host-ylf-cms-session` 和 `cms.yunle.fun/h3`。不放宽超时、不重试清理、不提前释放身份准备状态，保留原生运行时的账号切换代次检查。

## 验证

修复代码 `5d0cf23` 的[无插桩回归](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39066166088)在四个独立测试进程中全部通过：12 个不同用例、48 次执行、48 通过 / 0 失败 / 0 跳过。其中完整首页 class 执行 44 次，真实 Cookie 删除与保留检查执行 4 次。验证分支与修复分支的应用和测试源码完全一致，仅工作流增加重复次数；原始 xcresult 与逐次日志均已核对。

同一修复代码的[完整原生 CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39066160063)终态失败：**416 个不同用例，413 通过 / 3 失败 / 0 跳过**，逐例日志与 xcresult 摘要一致。原 Cookie 超时目标、真实 Cookie 删除 / 保留及原生会话 / 授权测试均通过。仍失败的用例为：

- `SupportViewTests.testCorruptSavedReceiptRendersReadFailureWithoutReplacingEvidence`
- `SupportViewTests.testSignedInFeedbackRendersPreviewEntryWithoutDispatchingHTTP`
- `NativeNavigationUITests.testGuestCanDismissPasswordKeyboardAtStandardTextSize`

前两项保留的截图与 viewport scan 显示：十秒扫描期限结束时尚未滚到所需内容，最终视口距当时列表底部仍分别约 87pt、191pt；截图中没有 Cookie 清理超时或账号状态错误。该夹具直接呈现 `FeedbackView`，不创建原生 Web 运行时；尚未通过独立基线对照证明这两项失败与本改动无关，因此继续按完整 CI 失败记录。键盘用例在未修改的 `c11b1e4` [基线 CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/39061035624)中也失败。

远端 Release 步骤因测试失败而跳过，失败附件上传与模拟器清理成功。下面的本机 Release 编译是独立结果，不能代替远端流水线全绿。PR 保持草稿，未合并。

本机原生 Debug 测试产物、原生 Release 与 Capacitor Debug 模拟器编译均通过。真实 Cookie 集成测试仍逐条验证六条 Cookie 的写入，并确认清理后恰好保留三个无关会话；首页测试保留原来的五秒清理等待和单次打开请求。

诊断 trace、实验环境变量及临时 CI 参数均仅在实验分支使用，不进入修复。测试均在隔离模拟器运行。
