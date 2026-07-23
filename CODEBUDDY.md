# CODEBUDDY.md This file provides guidance to CodeBuddy when working with code in this repository.

## 常用命令

| 命令 | 说明 |
|------|------|
| `pnpm i` | 安装依赖 |
| `pnpm dev` | 启动开发服务器（端口 8001，`--host` 暴露网络访问） |
| `pnpm build` | 构建生产版本，输出到 `.output/` |
| `pnpm start` | 运行生产构建 (`node .output/server/index.mjs`) |
| `pnpm lint` | ESLint 检查（@antfu/eslint-config + UnoCSS） |
| `pnpm typecheck` | TypeScript 类型检查 |
| `pnpm test` | 运行全部测试（Vitest） |
| `pnpm test:unit` | 运行单元测试（单次执行） |
| `pnpm test:watch` | 监听模式运行测试 |
| `pnpm test:coverage` | 生成测试覆盖率报告 |
| `pnpm test:e2e` | 运行 Playwright E2E 测试（Chromium/Firefox/WebKit） |
| `pnpm test:e2e:ui` | Playwright UI 模式调试 E2E |
| `pnpm dev:ios` | Capacitor iOS 热重载开发 |
| `pnpm run:ios` | 构建并运行 iOS 应用 |
| `pnpm deploy` | 通过 `@yunlefun/deploy` 部署到腾讯云 SCF |

## 架构概览

### 项目定位

云乐坊 (yunle.fun) —— 一个「应用聚合平台」，用户可以浏览、搜索和使用各种小应用。项目采用 **Nuxt 4 (CSR 模式)** 构建 Web 端，同时通过 **Capacitor 8** 打包为 iOS 原生应用。

### 技术栈组合

- **框架**: Nuxt 4 (`ssr: false`，纯客户端渲染)，兼容版本 4
- **UI**: Ionic Vue (`ios` 模式) + Konsta UI —— 双 UI 框架协同，Ionic 提供原生级路由和组件，Konsta 提供 iOS 风格的表单和列表组件
- **样式**: Tailwind CSS 4 + UnoCSS（仅用 `presetIcons` 做图标方案）+ SCSS 自定义变量
- **状态**: Pinia
- **移动端**: Capacitor 8 (iOS)，集成微信 SDK（`cordova-plugin-wechat`）
- **后端**: Nitro Server API + 腾讯 CloudBase (`@cloudbase/js-sdk`)
- **认证**: CloudBase Auth + 微信登录 + `nuxt-auth-utils`
- **部署**: Docker 容器 → 腾讯云 SCF (云函数)，通过 TCR 镜像仓库分发

### 目录结构要点

```
app/                    # Nuxt 4 应用层（所有前端代码）
├── components/         # 组件（pathPrefix: false，无需路径前缀即可自动导入）
│   ├── app/            # 应用级通用组件（ActionSheet, Grid, Icon 等）
│   ├── auth/           # 登录相关组件
│   ├── house/          # 应用卡片展示
│   ├── wx/             # 微信相关组件
│   └── ui/             # 基础 UI 组件
├── composables/        # 组合式函数（自动导入）
│   ├── auth/           # 认证逻辑（CloudBase Auth、手机登录、微信登录）
│   └── wx/             # 微信 JSSDK、扫码
├── pages/              # 文件路由
│   ├── tabs/           # Tab 页（home, apps, settings）
│   ├── login/          # 登录页
│   ├── app/[code].vue  # 应用详情动态路由
│   └── mobile/         # 移动端专属页面
├── plugins/            # Nuxt 插件
│   ├── api.ts          # $api：带 JWT 自动注入和 401 刷新重试的 fetch 客户端
│   └── temp/cloudbase.client.ts  # CloudBase SDK 初始化
├── stores/             # Pinia 状态仓库
│   ├── user.ts         # 用户认证状态（JWT 存 Cookie，31 天有效）
│   └── app.ts          # 应用状态（最近使用列表，localStorage 持久化）
├── styles/             # 全局样式
│   ├── ionic.css       # Ionic 自定义样式
│   ├── konsta.css      # Konsta 自定义样式
│   └── scss/           # SCSS 变量和覆盖
├── constants/apps/     # 应用列表数据和分类定义
└── types/              # 前端类型定义

server/                 # Nitro 服务端 API
├── api/login.ts        # 登录 API
├── api/wx/             # 微信相关 API（auth、user、login check/ticket）
└── api/app/search.ts   # 应用搜索 API

packages/               # Monorepo 子包
├── auth/               # @yunlefun/auth — 认证工具库
│   └── src/
│       ├── shared/     # 验证器、倒计时 hook、通用类型
│       └── wx/         # 微信登录、验证逻辑
└── types/              # 共享类型（YlfAppInfo 接口）
```

### 关键架构决策

**双 UI 框架方案**: Ionic Vue 负责页面级路由（`IonPage`, `IonRouterOutlet`, Tab 导航）和原生级交互，Konsta UI 用于表单、列表等 iOS 风格组件。两者通过 `app.vue` 中的 `KonstaApp` 包裹 `IonApp` 协同工作。暗黑模式通过 `@nuxtjs/color-mode` 管理，同时驱动 Ionic 的 `ion-palette-dark` 和 Konsta 的 `dark` class。

**认证体系**: 以腾讯 CloudBase Auth 为核心，支持多种登录方式。`useCloudbaseAuth()` 是认证统一入口 composable，组合了 Core（基础认证）+ OTP（短信/邮件验证码）+ OAuth（第三方登录）三个模块。JWT token 存储在 Cookie 中（31 天有效期），`api.ts` 插件拦截 401 响应自动刷新 token 并重试请求。

**Monorepo 结构**: 使用 pnpm workspace，但 `@yunlefun/auth` 包通过 `nuxt.config.ts` 的 `alias` 直接映射到源码路径，开发时无需构建子包。`@yunlefun/deploy` 和 `@yunlefun/toolkit` 为外部 npm 包。

**部署流水线**: Docker 多阶段构建（node:22-alpine），生产镜像推送到腾讯 TCR，部署为腾讯云 SCF 云函数（端口 80）。Canary 环境 (dev.yunle.fun) 在每次 main 分支提交时自动部署。

### 样式约定

- Tailwind CSS 4 通过 Vite 插件加载，用于通用工具类
- UnoCSS 仅启用 `presetIcons`，用于图标（`i-carbon-*`、`i-ri-*`、`i-twemoji-*`）
- SCSS 变量定义在 `styles/scss/vars.scss`，CSS 变量在 `styles/css/css-vars.css`
- Ionic 和 Konsta 各有独立的样式覆盖文件

### 测试配置

- **单元测试**: Vitest，测试文件放在 `test/unit/*.{test,spec}.ts`，Node 环境
- **Nuxt 测试**: Vitest + `@nuxt/test-utils`，测试文件放在 `test/nuxt/*.{test,spec}.ts`，Nuxt 环境
- **E2E 测试**: Playwright，测试文件放在 `test/e2e/`，三浏览器矩阵（Chromium/Firefox/WebKit）

### ESLint 配置

使用 `@antfu/eslint-config`，启用 UnoCSS 和 formatters 插件。关闭了 `vue/no-multiple-template-root` 和 `vue/no-deprecated-slot-attribute` 规则（Ionic 需要）。忽略 `ios`、`android`、`.codebuddy` 目录。

### 运行时配置

通过 `nuxt.config.ts` 的 `runtimeConfig.public` 管理：`tcbEnvId`（CloudBase 环境 ID）、`cloudbaseRegion`、`cloudbaseAccessKey`、`wxOpenAppId`（微信开放平台）、`wxOpenRedirectUri`。
