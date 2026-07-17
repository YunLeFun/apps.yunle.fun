# 快速开始

## 环境要求

| 工具    | 版本                  |
| ------- | --------------------- |
| Node.js | >= 22                 |
| pnpm    | >= 11                 |
| Xcode   | >= 26（iOS 开发需要） |

## 获取代码

```bash
git clone https://github.com/YunYouJun/apps.yunle.fun.git
cd apps.yunle.fun
```

## 安装依赖

```bash
pnpm i
```

## 启动开发

### Web 开发

```bash
pnpm dev
```

默认运行在 `http://localhost:8001`，自动启用 `--host` 暴露局域网访问。

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

# 部署到腾讯云 SCF
pnpm deploy
```

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
app/                    # Nuxt 4 应用层
├── components/         # 组件（自动导入）
├── composables/        # 组合式函数
├── pages/              # 文件路由
│   └── tabs/           # Tab 页（home, discovery, workshop, me）
├── stores/             # Pinia 状态仓库
├── plugins/            # Nuxt 插件
├── styles/             # 全局样式
├── constants/          # 常量定义
└── types/              # 类型定义
server/                 # Nitro 服务端 API
packages/               # Monorepo 子包
docs/                   # VitePress 产品文档
```
