# 云乐坊 · yunle.fun

> 云应用聚合平台 —— 在工坊中发现各式各样的云应用，安装到你的云居桌面。

[![CI](https://github.com/YunLeFun/apps.yunle.fun/actions/workflows/ci.yml/badge.svg)](https://github.com/YunLeFun/apps.yunle.fun/actions/workflows/ci.yml)
[![Desktop CI](https://github.com/YunLeFun/apps.yunle.fun/actions/workflows/desktop.yml/badge.svg)](https://github.com/YunLeFun/apps.yunle.fun/actions/workflows/desktop.yml)
[![License](https://img.shields.io/github/license/YunLeFun/apps.yunle.fun)](./LICENSE)

本仓库使用 pnpm workspace。现有 Web、iOS 和 Android 客户端位于 `apps/mobile/`，继续提供 `apps.yunle.fun` 浏览器版本；桌面端使用独立入口 `apps/desktop/`。公共业务与宿主协议按实际复用需求放入 `packages/`，各端独立构建和发布。

## ✨ 特性

- 🏠 **云居（Home）** —— iOS 风格桌面网格，长按编辑、拖拽排序、毛玻璃 Dock
- 🔍 **寻乐（Discovery）** —— 每日编辑推荐 + 每周热门排行
- 🏗️ **工坊（Workshop）** —— 分类浏览、搜索、安装云应用；开发者可发布作品
- 📱 **跨平台** —— Web + iOS / Android 原生（Capacitor），共用移动客户端
- 🔐 **多种登录** —— 微信、手机号 OTP、邮箱、密码、GitHub（仅 Web）
- ☁️ **云端同步** —— 桌面配置实时同步多设备

## 🌐 部署

| 环境       | 地址                     | 触发                            |
| ---------- | ------------------------ | ------------------------------- |
| Production | <https://apps.yunle.fun> | 合并到 `main` 后由 EdgeOne 发布 |

EdgeOne 保留仓库根目录作为安装、构建入口：执行 `pnpm install --frozen-lockfile` 和 `pnpm run build`，静态资源位于 `apps/mobile/.output/public`。生产环境继续使用 Nuxt 全栈适配，包含云端 Nitro API；首次部署迁移后需验证 `/api` 路由与运行依赖。控制台根目录和框架预设仍需与仓库配置保持一致，详见 [仓库迁移与部署](./docs/dev/monorepo.md)。

## 🚀 快速开始

```bash
node --version # 使用 .node-version 指定的 Node.js 24
pnpm i        # 安装依赖
cp -n apps/mobile/.env.example apps/mobile/.env # 按本机环境填写
pnpm dev      # 启动开发服务器（http://localhost:8001）
```

从仓库根执行原有命令即可；应用命令转发到 `apps/mobile`，文档命令仍在 `docs` 中运行。

### 常用命令

| 命令                         | 说明                                             |
| ---------------------------- | ------------------------------------------------ |
| `pnpm dev`                   | 启动开发服务器（端口 8001，`--host` 暴露）       |
| `pnpm build`                 | 构建 Web 生产版本，输出到 `apps/mobile/.output/` |
| `pnpm dev:mobile`            | 显式启动 Web／移动客户端                         |
| `pnpm build:mobile`          | 显式构建 Web／移动客户端                         |
| `pnpm lint`                  | ESLint 检查（@antfu + UnoCSS + formatters）      |
| `pnpm typecheck`             | TypeScript 类型检查                              |
| `pnpm test:unit`             | 运行单元测试（Vitest，单次）                     |
| `pnpm test:watch`            | 单元测试 watch 模式                              |
| `pnpm test:coverage`         | 测试覆盖率报告                                   |
| `pnpm test:e2e`              | Playwright E2E 测试                              |
| `pnpm dev:ios`               | Capacitor iOS 热重载                             |
| `pnpm run:ios`               | 构建并运行 iOS 应用                              |
| `pnpm sync`                  | 同步 web → ios/android                           |
| `pnpm build:android:release` | 构建并验签 Android 发布包                        |
| `pnpm build:ios`             | 同步移动版本号并创建 iOS archive                 |
| `pnpm release`               | 更新移动版本；发布前核对独立移动 Tag，见迁移文档 |

### 桌面开发

```bash
pnpm dev:desktop   # 本地 Nuxt + Electron，独立于移动开发服务
pnpm build:desktop # 生成静态 renderer 和主进程／preload
pnpm test:desktop  # 桌面单元测试
pnpm make:desktop  # 使用 Electron Forge 打包当前平台
```

还可执行 `pnpm typecheck:desktop`、`pnpm test:desktop:e2e`、`pnpm package:desktop` 和 `pnpm verify:desktop`；验证已打包产物时先运行 `make:desktop` 或 `package:desktop`。

桌面端复用升级后的 [vitesse-nuxt-electron](https://github.com/YunLeFun/vitesse-nuxt-electron/pull/6)：独立、安全的 shell／guest preload，`BaseWindow + WebContentsView` 容器和官方 Forge 打包流程。复用 `packages/app-core` 的目录类型、转换和快照，由主进程获取匿名公开目录，打开符合公开、免费和无登录要求的云应用。账号、云居、宿主 SSO 与正式签名／发布按 [桌面架构](./docs/dev/desktop-electron-architecture.md) 分阶段接入。各平台安装包输出到 `apps/desktop/out/make/`。

## 🏗️ 技术栈

| 层级   | 选型                                     |
| ------ | ---------------------------------------- |
| 框架   | Nuxt 4（CSR 模式，`ssr: false`） + Vue 3 |
| UI     | Ionic Vue（ios 模式） + Konsta UI        |
| 样式   | Tailwind CSS 4 + UnoCSS（仅图标） + SCSS |
| 状态   | Pinia                                    |
| 移动端 | Capacitor 8（iOS / Android）             |
| 桌面端 | Electron 44.7.0 + Electron Forge 8.0.1   |
| 后端   | Nitro Server + 腾讯 CloudBase            |
| 认证   | CloudBase Auth + 微信 SDK + GitHub OAuth |
| 部署   | EdgeOne Pages（Git 集成）                |

## 📁 目录结构

```text
apps/
├── mobile/             # Web + Ionic + Capacitor
│   ├── app/            # Nuxt 4 页面、组件、composables、stores、plugins
│   ├── server/         # 云端 Nitro API
│   ├── ios/            # Capacitor iOS 工程
│   ├── android/        # Capacitor Android 工程
│   ├── scripts/        # 移动构建、版本同步与发布脚本
│   ├── test/           # Vitest + Playwright
│   └── package.json    # Web／移动端依赖和版本
└── desktop/            # 独立 Nuxt 界面 + Electron + Forge
packages/               # 私有 workspace 包与原生插件
docs/                   # VitePress 文档站
scripts/                # CloudBase 规则、索引与跨应用工具
package.json            # 私有根包、统一命令和代码质量工具
pnpm-workspace.yaml     # 工作区与依赖安全策略
pnpm-lock.yaml          # 所有工作区共用锁文件
```

移动端环境文件在 `apps/mobile/.env`；iOS / Android 版本从 `apps/mobile/package.json` 读取。各应用的 `.nuxt`、`.output`、测试结果和原生构建产物均留在各自目录。

## 📖 文档

完整文档（产品设计、UI 规范、数据库、开发笔记、上架路线图）见：

- **本地预览**：`pnpm docs:dev`
- **线上**：<https://apps.yunle.fun/docs>

主要章节：

- [产品设计](./docs/product/index.md)
- [UI 规范](./docs/ui/index.md)
- [开发笔记](./docs/dev/index.md)
- [仓库迁移与部署](./docs/dev/monorepo.md)
- [Electron 桌面架构](./docs/dev/desktop-electron-architecture.md)
- [发布路线图](./docs/roadmap.md)
- [App Store 上架手册](./docs/dev/app-store-onboarding.md)

## 🧪 测试

```bash
pnpm test:unit          # 单元测试
pnpm test:e2e           # E2E（Chromium/Firefox/WebKit 三浏览器矩阵）
pnpm test:coverage      # 覆盖率
```

Web／移动 CI 在每次 push / PR 验证 lint、移动类型检查、生产构建、服务端运行依赖、单元及 Nuxt 测试，并单独运行 Chromium smoke。桌面 CI 在 macOS arm64、Windows x64、Linux x64 验证类型、单元、Electron 集成测试、安装包、ASAR／fuses 与打包后启动，上传安装包与失败 trace。移动原生构建使用本机对应 SDK 验证，商店签名和正式发布独立执行。

## 🤝 贡献

1. Fork 本仓库
2. 创建特性分支：`git checkout -b feat/awesome`
3. 提交前确保通过：`pnpm lint && pnpm typecheck && pnpm test:unit`
4. 提交格式参考 [Conventional Commits](https://www.conventionalcommits.org/)
5. 发起 PR 到 `main` 分支

发布前请先阅读 [docs/roadmap.md](./docs/roadmap.md) 了解当前阻塞项。

## 📄 License

[MIT](./LICENSE) © [YunYouJun](https://github.com/YunYouJun)
