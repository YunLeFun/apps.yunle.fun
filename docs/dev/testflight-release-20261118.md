# 原生 iOS 0.2.0 (7) 内部发布

2026-11-18，发布到既有「云乐坊内测组」，沿用 3 位成员和自动分发。中文测试说明见[本次内测说明](./testflight-notes-0.2.0-7.zh-Hans.md)。本次未更新物理手机。

## 源码与分支

- 归档源码：`fac190db94b32c7faa66624a45a89ccc1542e599`，已推送 main。
- `9cb27c9` 将工坊官方应用集中展示在「云乐坊出品」，编辑精选独立展示。
- 同包包含登录方式和账号记忆、原生微信登录与绑定、紧凑的云居同步失败提示。
- `codex/compact-ios-workshop-sections` 已快进合并；确认提交被 main 包含后，删除本地和远端分支。原工作区的工坊文件改动与该提交补丁完全一致，合并后工作区干净。

## 签名与分发

App `6759859441`，Bundle ID `fun.yunle.apps`，Team `QT792GAY4C`。查询已上传和已处理记录后，构建号从 6 递增为 7。

自动导出遇到云端分发证书权限不足，旧描述文件也缺少当前 App Groups 权限。沿用本机已有的有效 Apple Distribution 证书，为主 App 和分享扩展分别生成 App Store 描述文件，保留 App Groups 和主 App 的 iCloud KVS 授权。仅机器使用的手动签名配置保存在仓库外。

ASC CLI 分别归档、导出。IPA 的正式标识、版本、分发签名、描述文件、`get-task-allow=false`、隐私清单、加密声明与仅内部标记均通过检查，Apple 包校验无错误。上传文件与校验文件的 SHA-256 相同：

`0c56dad254186ead323ca64cb195e40c3c5670a52fa8fc44da5bad6e558a5d22`

唯一上传与最终 Build ID：`e29354f2-1e94-4abe-aed8-c20451aadaca`。

最终 API 验收：`VALID`、`INTERNAL_ONLY`、`IN_BETA_TESTING`，外部状态 `NOT_APPLICABLE`；内部组 `15cca729-b449-4d73-908c-2ee09f0eef68` 已自动关联，3 位既有成员可用。没有重复关联或增加成员。App Store Connect 浏览器会话已失效，本次用 API 回执验收，没有保存网页截图。

## 微信与后端

- Admin 生产部署 `dp6mc9kiddxx` 对应 `910f5e0`，包含「系统设置 → 登录方式」的 iOS 独立开关。
- 按顺序更新 `account-api` 和 `sso-ticket` 代码；下载部署包，分别核对 58 和 64 个源码文件一致。保留既有运行时、环境变量、路由和权限，配置指纹保持一致。私有回滚快照保存在 API 仓库忽略的 `.cloudbase/releases/20261118-ios-wechat/`。
- 创建 `sso_apps_ios_wechat_bindings`，权限为 `ADMINONLY`，为注销清理建立非唯一 `uid` 索引。
- 正式域名的 `appsIOSWeChatAvailability` 返回 `{ "ok": true, "enabled": false }`；网页 `/api/login-options` 仍返回 `weChatLoginVisible=false`。没有开启任一入口。
- AASA 已包含 `QT792GAY4C.fun.yunle.apps` 和 `/auth/wechat/*`。移动应用密钥尚未配置，微信授权尚未完成生产真机验收；开放前按 [iOS 微信接入文档](./ios-wechat-login.md) 完成配置与验收。

发布检查发现 `api.yunle.fun` 证书当天到期。修正已有自动续期证书的 DNS 验证记录，完成签发，并更新该域名现有的 CloudBase 证书绑定。HTTPS 严格校验和实际接口请求已恢复，新证书有效至 2027-02-16；未改变域名路由或关闭证书校验。

## 验证与清理

定向回归共 74 项通过、0 失败：iOS 工坊、账号与微信回调 48 项，后端微信和注销清理 26 项。常规 [CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/44266768074) 已通过；发布验收时，[完整 iOS CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/44266767987) 仍在运行，不能记为完整回归通过。

发行产物与回执保留在 `~/Library/Developer/YunleFunReleases/20261118-0.2.0-7-162505/`：源码归档、Archive / dSYM、IPA、签名配置、Apple 校验与上传回执、最终分发回执，以及测试结果与部署摘要。凭据与包含环境变量的私有快照不进入 Git。

删除本轮独立临时工作树、DerivedData 和包解析副本，回收 1,222,516,736 字节已分配文件（约 1.14 GiB）。复用已有空闲 iPhone 16 Pro / iOS 26.5，结束时为 Shutdown；没有新建或擦除模拟器，其他任务设备保持原状。
