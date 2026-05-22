# 云乐坊 · yunle.fun

> 云应用聚合平台 —— 在工坊中发现各式各样的云应用，安装到你的云居桌面。

[![CI](https://github.com/YunYouJun/apps.yunle.fun/actions/workflows/ci.yml/badge.svg)](https://github.com/YunYouJun/apps.yunle.fun/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/YunYouJun/apps.yunle.fun)](./LICENSE)

## ✨ 特性

- 🏠 **云居（Home）** —— iOS 风格桌面网格，长按编辑、拖拽排序、毛玻璃 Dock
- 🔍 **寻乐（Discovery）** —— 每日编辑推荐 + 每周热门排行
- 🏗️ **工坊（Workshop）** —— 分类浏览、搜索、安装云应用；开发者可发布作品
- 📱 **跨平台** —— Web + iOS 原生（Capacitor），同源代码
- 🔐 **多种登录** —— 微信、手机号 OTP、邮箱、密码、GitHub（仅 Web）
- ☁️ **云端同步** —— 桌面配置实时同步多设备

## 🌐 部署

| 环境       | 地址                    | 触发                     |
| ---------- | ----------------------- | ------------------------ |
| Production | <https://yunle.fun>     | 手动 `pnpm release`      |
| Canary     | <https://dev.yunle.fun> | 每次合并到 main 自动部署 |

## 🚀 快速开始

```bash
pnpm i        # 安装依赖
pnpm dev      # 启动开发服务器（http://localhost:8001）
```

### 常用命令

| 命令                 | 说明                                        |
| -------------------- | ------------------------------------------- |
| `pnpm dev`           | 启动开发服务器（端口 8001，`--host` 暴露）  |
| `pnpm build`         | 构建生产版本，输出到 `.output/`             |
| `pnpm lint`          | ESLint 检查（@antfu + UnoCSS + formatters） |
| `pnpm typecheck`     | TypeScript 类型检查                         |
| `pnpm test:unit`     | 运行单元测试（Vitest，单次）                |
| `pnpm test:watch`    | 单元测试 watch 模式                         |
| `pnpm test:coverage` | 测试覆盖率报告                              |
| `pnpm test:e2e`      | Playwright E2E 测试                         |
| `pnpm dev:ios`       | Capacitor iOS 热重载                        |
| `pnpm run:ios`       | 构建并运行 iOS 应用                         |
| `pnpm sync`          | 同步 web → ios/android                      |
| `pnpm deploy`        | 通过 `@yunlefun/deploy` 部署到腾讯云 SCF    |

## 🏗️ 技术栈

| 层级   | 选型                                     |
| ------ | ---------------------------------------- |
| 框架   | Nuxt 4（CSR 模式，`ssr: false`） + Vue 3 |
| UI     | Ionic Vue（ios 模式） + Konsta UI        |
| 样式   | Tailwind CSS 4 + UnoCSS（仅图标） + SCSS |
| 状态   | Pinia                                    |
| 移动端 | Capacitor 7（iOS）                       |
| 后端   | Nitro Server + 腾讯 CloudBase            |
| 认证   | CloudBase Auth + 微信 SDK + GitHub OAuth |
| 部署   | Docker → 腾讯云 SCF（云函数）            |

## 📁 目录结构

```text
app/                    # Nuxt 4 应用层
├── components/         # 组件（pathPrefix: false 自动导入）
│   ├── app/            # 应用级通用组件
│   ├── auth/           # 登录相关
│   ├── house/          # 应用卡片展示
│   ├── scanner/        # 扫码组件
│   └── wx/             # 微信相关
├── composables/        # 组合式函数（自动导入）
├── pages/              # 文件路由
│   ├── tabs/           # 三大 Tab：home / discovery / apps / me
│   ├── workshop/       # 我的应用 CRUD
│   ├── app/[id].vue    # 应用详情
│   └── login/          # 登录
├── plugins/            # api.ts、cloudbase.client.ts、deeplink.client.ts
├── stores/             # Pinia 仓库
└── styles/             # 全局样式（含 iOS 系统色变量）

server/                 # Nitro 服务端 API
packages/               # Monorepo 子包（auth, types）
ios/                    # Capacitor iOS 工程
docs/                   # VitePress 文档站
test/                   # Vitest + Playwright 测试
```

## 📖 文档

完整文档（产品设计、UI 规范、数据库、开发笔记、上架路线图）见：

- **本地预览**：`pnpm docs:dev`
- **线上**：<https://yunle.fun/docs>

主要章节：

- [产品设计](./docs/product/index.md)
- [UI 规范](./docs/ui/index.md)
- [开发笔记](./docs/dev/index.md)
- [发布路线图](./docs/roadmap.md)
- [App Store 上架手册](./docs/dev/app-store-onboarding.md)

## 🧪 测试

```bash
pnpm test:unit          # 单元测试
pnpm test:e2e           # E2E（Chromium/Firefox/WebKit 三浏览器矩阵）
pnpm test:coverage      # 覆盖率
```

CI 在每次 push / PR 自动跑 lint + typecheck + unit test 三个 job。

## 🤝 贡献

1. Fork 本仓库
2. 创建特性分支：`git checkout -b feat/awesome`
3. 提交前确保通过：`pnpm lint && pnpm typecheck && pnpm test:unit`
4. 提交格式参考 [Conventional Commits](https://www.conventionalcommits.org/)
5. 发起 PR 到 `main` 分支

发布前请先阅读 [docs/roadmap.md](./docs/roadmap.md) 了解当前阻塞项。

## 📄 License

[MIT](./LICENSE) © [YunYouJun](https://github.com/YunYouJun)
