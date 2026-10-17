# 原生资料与会话边界验证

更新于 2026-10-18。本轮仅使用独占 iOS 模拟器，资料写入限既有零余额合成账号。没有修改认证提供方、手机号、邮箱、密码或付费权益。

## 迟到保存与身份代次

`AccountSession.updateProfile` 原先在请求返回后只检查当前 UID。A → B → A 或同 UID 重新登录后，这个检查仍会放行旧保存结果，继续读取并覆盖新会话的资料投影，也会向调用方报告旧操作成功。

现在在取得授权前记录 `selectionGeneration`，授权返回和实际写入返回后均通过既有 `requireCurrent` 检查代次、当前 UID 与 access token，再继续读取资料。它阻止旧结果进入新会话；已经发出的服务端写入仍可能完成，不能宣称远端操作已撤销。

三项确定性测试在旧源码为 **1 通过 / 2 失败**，分别复现账号往返与同账号重新登录的迟到回调；正常保存、服务端回读和 Keychain 重建为对照。修复后认证交互、账号 Session 与 CloudBase 契约专项共 **52 通过 / 0 失败 / 0 跳过**。结果为 `profile-identity-before.xcresult`、`profile-identity-after.xcresult`，失败记录保留。

## 真实表单夹具

`LiveValidation/ManagedAccountLiveTests.swift` 的 `ManagedProfileLiveTests` 默认跳过，要求 `YUNLEFUN_LIVE_PROFILE=validate`、新的大写 `YUNLEFUN_LIVE_PROFILE_RUN` UUID，以及与实际 `SIMULATOR_UDID` 相等的 `YUNLEFUN_OWNED_SIMULATOR_UDID`。只允许模拟器。使用 `YunleFunLiveValidation` 的 Debug app-hosted 目标，Xcode 串行执行。

认证是私有夹具准备：从宿主缓存的 `iOSNativeValidation/profile-native-input.json` 消费固定账号的一次性凭据，使用实际 CloudBase 服务和私有 Keychain。密码不进入 UI、工具参数、环境变量或日志；这不算登录表单验证。reader 复用既有 no-follow、所有者、单链接、目录 0700、文件 0600 和大小限制，仅允许两个固定输入文件名。

夹具承载实际 `AccountProfileView` 与原生编辑表单。外部 UI 驱动点击编辑、聚焦、两次保存和账号退出；公开 UIKit 输入只提供合成昵称及多行 emoji 简介。生产改动只添加三个无障碍标识，未增加假成功入口或替换网络响应。

成功标准包括：昵称首尾空白裁剪；实际 POST 后另行 GET 回读 UID、昵称和简介；用户名、邮箱和手机号保持；同 UID 的资料更新不改变身份代次；重新创建 Session 从 Keychain 读到新资料；再次通过 UI 恢复原昵称与简介并独立回读；实际账号管理退出、远端 signout 成功及 Keychain 无账号。

## 恢复与证据边界

写入前将 run、owner、原昵称和简介保存为私有 0600 基线文件，存在未处理基线时拒绝新验证。失败时先读服务端，只有当前值仍是本轮精确合成内容才恢复；遇到其他修改保留基线，不覆盖。只有服务端原资料核对通过后才删除基线。`recover` 模式须携带同一 run 并验证基线 owner，直接恢复单独标记，不能计作 UI 旅程成功。

首轮 `profile-live.xcresult` 的界面控制连接超时，夹具等待聚焦 180 秒后失败；写入尝试和成功均为 0，独立回读确认原资料，signout 成功一次，Keychain、基线及一次性输入已清理。测试结束后，Xcode 卡在 `simCtlDiagnose` 超过 5 分钟；保留进程采样后仅结束该诊断子进程，测试进程未被中断，结果包正常落盘为失败。后续运行关闭额外 sysdiagnose 收集，仍保留 XCTest 结果与附件。

第二轮 `profile-live-v2.xcresult` 保存后回读昵称的内部空格消失，与夹具的精确预期不符，故仍为 **0 通过 / 1 失败**。外部 UI 恢复原资料：首次 `setValue` 更新了简介画面却没有更新 SwiftUI 绑定，再通过实际原生编辑事件提交后恢复成功，本轮共 3 次实际写入。失败后的独立 GET 确认原昵称和简介，远端注销及私有数据清理均成功。未扩大成功断言，也没有改写旧报告。

这一轮恢复曾尝试输入和粘贴非敏感的原合成简介，Mac changeCount 为 1259→1261，不能宣称该轮未操作剪贴板；密码从未进入 UI 或粘贴通道。第三轮只使用已聚焦的公开 UIKit 输入，昵称改为无内部空格的 `iOS校验<run 前 8 位>`，另记录并断言交给实际认证服务的昵称已去除首尾空白。内部空格的变化来源尚未做请求抓包定位，不把它描述为已修复的产品缺陷。

## 第三轮完整闭环

`profile-live-v3.xcresult`：**1 通过 / 0 失败 / 0 跳过，81.577 秒**，结果包无运行时警告。run 为 `891FA965-2858-44D4-A775-9179A8507D95`，全部成功标记来自同一次编译和真实服务执行：

- 实际 UI 两次保存，转发认证服务观察到 2 次尝试、2 次成功；第一次提交值验证首尾裁剪，昵称与多行 emoji 简介通过另行 GET 精确回读。
- 同账号资料更新的身份代次不变，重新创建 Session 读取 Keychain 得到新资料；用户名、邮箱、手机号与最初一致。
- 第二次实际保存恢复原昵称与简介，独立 GET 核对通过；没有走直接恢复路径。
- 实际账号管理“退出当前账号”及“退出并移除”，远端 signout 成功一次；重新读取私有 Keychain 无账号和当前身份。缓存内一次性输入与基线为空，外部恢复备份在回读确认后删除。
- 保存与恢复页面的实际截图、外部 AX、结果报告、日志、activity 及来源摘要均保留。包含三个真实旅程、反事实测试和编译记录的 3,755 个原始文件，扫描完整密码及 12 字符前缀未命中；检查 UTF-8 / UTF-16 字节及可解析 plist，不等于完整内存或网络抓包审计。第三轮 Mac 103.213 秒计数保持 1261→1261，监测只读计数。

证据保存在 `/Users/yunyou/.codex/artifacts/ios-native-goal-20261018/` 的 `profile-*` 文件。构建含工作区并行缓存改动，来源哈希另存，不能视作纯净提交 CI。当前结果不覆盖资料错误状态、VoiceOver、其他系统 / 尺寸或完整业务页面验收。
