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
