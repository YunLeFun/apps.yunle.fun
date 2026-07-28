# CloudBase 集成

本项目使用腾讯云开发 (CloudBase) 作为后端服务。

## 能力

- **认证**: CloudBase Auth（手机号、微信登录）
- **数据库**: NoSQL 文档数据库
- **云函数**: 事件型/HTTP 型
- **云存储**: 文件上传下载
- **AI**: 混元/DeepSeek 大模型调用

## 参考链接

- [CloudBase 官方文档](https://docs.cloudbase.net/)
- [CloudBase AI Toolkit](https://docs.cloudbase.net/ai/cloudbase-ai-toolkit/getting-started)
- [CloudBase JS SDK](https://docs.cloudbase.net/api-reference/webv3/introduction)

## 开发说明

- CloudBase Skills 已通过 CodeBuddy 全局安装，无需项目内单独配置
- 环境 ID 通过 `nuxt.config.ts` 的 `runtimeConfig.public.tcbEnvId` 配置
- SDK 初始化见 `app/plugins/temp/cloudbase.client.ts`
- 认证逻辑见 `app/composables/auth/`

## 存储边界

生产环境约定：

- CloudBase 默认云存储只放公开内容，例如身份认证头像的 `avatars/` 对象。
  当前权限是「所有用户可读、管理员可写」。用户资料保存 CloudBase 返回的
  稳定 `cloud://` 文件 ID，展示层通过
  `NUXT_PUBLIC_CLOUDBASE_STORAGE_PUBLIC_ORIGIN` 映射到已验证的公共源站；
  不保存或重复生成短期签名 URL。
- 用户项目、画笔库等私有内容放在独立 COS 桶
  `yunlefun-private-1325586649`。该桶保持私有 ACL，客户端不得持有永久密钥；
  后续通过服务端校验用户身份后签发短期 STS 凭证或短期签名 URL。
- 公共和私有对象不要混用同一个桶，避免公开头像时意外放开用户文件。

### 2026-07-28 迁移状态

- 已把 CloudBase 中现存的 2 个 `user-storage/` 私有对象复制到独立私有 COS
  桶，并逐个校验大小和 ETag；确认迁移后已删除 CloudBase 中的两个源对象。
- CloudBase 默认桶当前只剩 `avatars/` 下的公开头像，权限已切换为
  `ADMINWRITE`（所有用户可读、管理员写）。
- App 与 `www.yunle.fun` 共用同一解析约定：兼容 `cloud://` 文件 ID，并会
  清除用户资料中遗留的短期签名查询参数；客户端不再为公开头像调用签名接口。
