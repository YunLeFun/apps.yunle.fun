# 负一屏 AI Agent 会员功能方案

> 状态: 已落地 v1 + v1.1 手势入口
> 关联: [Home Screen 拖拽排序](./home-screen-drag) · [认证](./auth) · [CloudBase 安全规则](./cloudbase-rules)

## 1. 概述

云居首页增加 AI 负一屏,会员可通过对话检索应用,Agent 返回文本和结构化应用卡片。非会员可进入 AI 屏查看示例,发送真实消息时跳转会员页。

- 首页 Header 左上角提供 `aria-label="进入 AI 助手"` 的 AI 图标入口。
- 首页第 0 页支持右滑进入 AI 屏,AI 屏左滑返回首页;搜索态、编辑态、拖拽态禁用外层手势。
- 客户端调用 CloudBase Web SDK: `useCloudbase().app.ai().bot.sendMessage()`。
- Agent Bot ID: `agent-yunlefun-1g1ef4a470aefe98`。

## 2. 当前架构

v1 不使用 Nitro SSE 代理,也不以 `@ag-ui/client` 作为主调用路径。浏览器端复用现有 `useCloudbase()` 初始化出的 `@cloudbase/js-sdk` 实例,调用官方 Web 集成方式:

```ts
const result = await app.ai().bot.sendMessage({
  botId,
  threadId,
  runId,
  messages,
  tools,
  context: [],
  state: {},
  forwardedProps: { source: 'apps.yunle.fun' },
})
```

客户端仍兼容两类流事件:

- CloudBase 官方示例流: `content`、`reasoning_content`
- AG-UI 事件: `TEXT_MESSAGE_*`、`TOOL_CALL_*`、`TOOL_CALL_RESULT`、`RUN_ERROR`、`RUN_FINISHED`

`reasoning_content` 只用于状态提示,不在正式 UI 中逐字展示。

## 3. 运行时配置

Nuxt public runtime config 映射如下:

```env
NUXT_PUBLIC_TCB_ENV_ID=yunlefun-8g7ybcxc7345c490
NUXT_PUBLIC_CLOUDBASE_REGION=ap-shanghai
NUXT_PUBLIC_CLOUDBASE_ACCESS_KEY=
NUXT_PUBLIC_AGENT_BOT_ID=agent-yunlefun-1g1ef4a470aefe98
NUXT_PUBLIC_AGENT_REQUEST_TIMEOUT_MS=60000
```

Publishable Key 可放 public env,但不要提交真实值。当前本地 `.env` 可用于开发和真实 Agent smoke。

## 4. 访问控制

客户端发送前做 UX 拦截:

1. 未登录: 跳 `/login`
2. 已登录但非会员: 跳 `/membership`
3. 会员: 调用 CloudBase Agent

服务端是最终权威。`agents/app-discovery` 已部署到 CloudBase Agent 入口,在 SSE 建立前完成:

- Bearer token 校验: 调用 CloudBase `/auth/v1/user/me`,拒绝匿名 publishable key 与伪造 token。
- 会员校验: 查询 `user_memberships.userId`,以 `expireAt > now` 为有效会员。
- 每日限额: 写入 `agent_usage` 集合,`_id = {uid}_{yyyy-mm-dd}`,默认每日 50 次。

客户端 `useCoin().isMember` 仍只做 UX 拦截。

## 5. AI 屏体验

`AgentScreen` 支持:

- 空态、会员锁定态、配置缺失态
- 示例 prompt 与真实公开应用示例卡片
- 流式文本输出
- Markdown 流式预览,使用 `markstream-vue`,HTML 默认 escape,禁用图片,链接只允许安全协议
- 停止生成、重试、新对话
- 错误条与工具状态提示
- 应用卡片展示

`MessageBubble` 对 assistant 内容启用 Markdown,用户输入仍按纯文本展示。

## 6. 负一屏手势

`HomeAgentPager` 是首页外层 pager:

```text
[ AI 负一屏 ] <-> [ 云居首页(内层 HomeScreenGrid) ]
```

设计约束:

- 不改 `HomeScreenGrid` 内层分页和拖拽逻辑。
- 仅首页第 0 页允许右滑进入 AI 屏。
- AI 屏打开后左滑返回首页。
- 输入框、链接、按钮、搜索、编辑和拖拽场景不抢手势。

## 7. 工具 `search_apps`

Agent 请求会声明 `search_apps({ query, category?, limit? })` 工具,最多返回 6 张卡片。

本仓实现:

- 云端 Agent 服务包: `agents/app-discovery`
- 工具声明: `app/utils/agentTools.ts`
- 本地登录保护 API: `server/api/agent/search-apps.post.ts`
- 检索与打分: `server/utils/agent-search-apps.ts`
- 前端兜底调用: `app/composables/useAgentSearchApps.ts`

云端 Agent 会服务端执行 `search_apps`,并发出 AG-UI `TOOL_CALL_RESULT`;前端本地 API 只作为兜底。

查询只返回 `apps` 集合中:

```ts
isPublic === true && status === 'approved'
```

已通过 CloudBase MCP 抽样核实当前环境存在该字段组合,公开已审核应用总数为 22。

## 8. 卡片契约

卡片只使用公开 `YlfAppInfo` 子集加 `reason`:

```ts
slug
name
description
logo
emoji
themeColor
category
rating
ratingCount
coinCost
requiresMembership
websiteUrl
trustedHosts
reason
```

Agent 不自动打开或安装应用。用户显式点击后复用现有业务:

- 打开: `useOpenApp()`
- 安装: `useHomeScreen().installApp()`
- 详情: `/app/[id]`

## 9. 真实接入核实

CloudBase MCP 已核实:

- 当前环境: `yunlefun-8g7ybcxc7345c490`,状态 ready
- Agent: `agent-yunlefun-1g1ef4a470aefe98`
- 名称: `YunLeFun`
- 类型: `scf`
- `isReady: true`

本地真实流式调用已能返回内容。若 Agent 未返回工具卡片,客户端会通过本地 `search_apps` API 做一次卡片兜底,保证会员检索应用时仍可看到结构化卡片。

2026-06-25 云端修复后已核实:

- 匿名 Web SDK 调用返回 `UNAUTHENTICATED / 请先登录`。
- 伪造 Bearer token 返回 `INVALID_CREDENTIALS`。
- `agent_usage` 集合已创建。
- CORS 预检通过: `http://localhost:3000`、`https://apps.yunle.fun`。
- `search_apps` 工具 schema 已改为 CloudBase LangGraph adapter 可接受的最小 JSON Schema。

## 10. 测试覆盖

- Unit: `useAgentChat` 合并 CloudBase/AG-UI 文本流、工具结果、错误事件、会员拦截、本地卡片兜底。
- Unit: `search_apps` 不返回私有/未审核应用,排序稳定,输出符合卡片 schema。
- Component: `AgentScreen` 锁定跳转、发送、错误重试、应用卡片渲染。
- Component: `HomeAgentPager` 右滑打开、禁用态阻断、左滑关闭。
- Markdown: `AgentMarkdownPreview` 渲染常见 Markdown、escape HTML、拦截不安全链接。

常规验证:

```bash
pnpm lint
pnpm typecheck
pnpm test:unit
pnpm test:nuxt
git diff --check
```

## 11. 剩余验收项

P0/P1 客户端功能已补齐,云端强制门控和服务端工具执行已部署。仍需一次正式会员账号端到端验收:

- 登录正式会员账号。
- 输入"找一个开发工具"。
- 看到流式 Markdown、`TOOL_CALL_RESULT` 应用卡片。
- `agent_usage` 写入当天用量记录。
