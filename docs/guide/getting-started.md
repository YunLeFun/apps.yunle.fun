# 快速开始

## 环境要求

| 工具    | 版本                                    |
| ------- | --------------------------------------- |
| Node.js | 24，见根 `.node-version`                |
| pnpm    | 见根 `package.json` 的 `packageManager` |
| Xcode   | >= 26（iOS 开发需要）                   |

## 获取代码

```bash
git clone https://github.com/YunLeFun/apps.yunle.fun.git
cd apps.yunle.fun
```

## 安装依赖

```bash
pnpm i
cp -n apps/mobile/.env.example apps/mobile/.env
```

## 启动开发

### Web 开发

```bash
pnpm dev
```

默认运行在 `http://localhost:8001`，自动启用 `--host` 暴露局域网访问。

从仓库根执行命令即可，`pnpm dev` 转发到 `apps/mobile`。该应用继续提供 Web、iOS 和 Android 客户端；桌面使用独立 `apps/desktop` 入口。

### iOS 开发

```bash
# 热重载开发
pnpm dev:ios

# 构建并运行
pnpm run:ios
```

::: tip
iOS 开发需要 macOS + Xcode 环境，首次运行前需执行 `pnpm sync` 同步 Capacitor 配置。
:::

## 构建 & 部署

```bash
# 构建生产版本
pnpm build

# 运行生产构建
pnpm start

# Web 生产发布
# 将验证通过的改动合并到 main，EdgeOne 会自动构建并发布
```

Web 产物位于 `apps/mobile/.output/`。部署保留仓库根作为安装和构建入口，静态资源目录为 `apps/mobile/.output/public`，服务端继续使用 Nuxt 全栈适配。首次迁移部署需要核对控制台配置及 `/api` 路由，详见 [客户端工作区与部署](../dev/monorepo.md)。

## 代码质量

```bash
# ESLint 检查
pnpm lint

# TypeScript 类型检查
pnpm typecheck

# 运行全部测试
pnpm test

# E2E 测试
pnpm test:e2e
```

## 文档开发

```bash
# 启动文档开发服务器
pnpm docs:dev

# 构建文档
pnpm docs:build
```

## 项目结构

```text
apps/
├── mobile/             # 现有 Web／移动工程
│   ├── app/            # Nuxt 页面、组件、状态和插件
│   ├── server/         # 云端 Nitro API
│   ├── ios/            # Capacitor iOS
│   ├── android/        # Capacitor Android
│   ├── scripts/        # 移动构建和发布
│   └── test/           # Vitest 与 Playwright
└── desktop/            # 独立 Nuxt + Electron + Forge
packages/               # 共享包与移动原生插件
docs/                   # VitePress 产品文档
scripts/                # CloudBase 运营工具
pnpm-workspace.yaml     # 工作区及安全策略
pnpm-lock.yaml          # 统一依赖锁文件
```
