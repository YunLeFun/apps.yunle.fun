# 依赖安全（pnpm audit）

记录依赖漏洞的修复策略与剩余风险。最近一次审计：**2026-06-04**。

## 现状

| 等级     | 修复前 | 修复后              |
| -------- | ------ | ------------------- |
| critical | 1      | **0**               |
| high     | 43     | **0**               |
| moderate | 39     | 3（仅部署链，见下） |
| low      | 3      | **0**               |

验证命令：

```bash
pnpm audit --audit-level high   # 应无 critical / high
pnpm audit                      # 查看完整列表
```

## 修复策略：pnpm overrides

绝大多数漏洞来自**传递依赖**（不是我们直接引入的包），无法通过升级直接依赖解决，
因此在 [`pnpm-workspace.yaml`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/pnpm-workspace.yaml) 的
`overrides` 字段把它们钉死到已修复的版本。

> 本仓库使用 pnpm 10.x + workspace，`overrides` 写在 `pnpm-workspace.yaml`（不是 `package.json`）。

主要修复项（完整列表见配置文件注释）：

- `protobufjs ^7.6.2` — critical 任意代码执行（飞书 SDK 带的，仅部署用）
- `axios ^1.17.0` — 多个 SSRF / 原型污染 / MITM
- `tar ^7.5.16` — node-tar 多个路径穿越 / 符号链接（Capacitor CLI、node-pre-gyp）
- `shelljs ^0.8.5`、`@xmldom/xmldom ^0.8.13`、`serialize-javascript ^7.0.5`、
  `flatted ^3.4.2`、`h3 ^1.15.11`、`picomatch`、`lodash ^4.18.1`、`ws ^8.21.0`、
  `defu`、`simple-git`、`basic-ftp`、`fast-uri`、`js-cookie`、`tmp`、
  `@babel/plugin-transform-modules-systemjs` 等。
- moderate 的安全小版本升级：`unhead`、`ip-address`、`qs`、`yaml`、
  `follow-redirects`、`postcss`、`brace-expansion`（分版本段 override）。

改动 override 后务必重新验证：

```bash
pnpm install
pnpm lint && pnpm typecheck && pnpm test:unit && pnpm build
```

## 剩余风险（3 个 moderate，已接受）

剩余 3 项全部位于 **`@yunlefun/deploy`（部署工具，devDependency）** 的依赖链里，
**只在 `pnpm deploy` / `pnpm release` 时、在维护者本机执行**，不进入 App 运行时、
不进入构建产物、也不在 CI 测试路径上。无法在本仓库通过 override 安全修复，需在
`@yunlefun/deploy` 上游升级，故暂时接受：

| 包                 | 链路                                                  | 为何暂不修                                                                                                                   | 实际风险                                                                                  |
| ------------------ | ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `vite <=6.4.1`     | `@yunlefun/deploy > vite-node@2 > vite@5.4.21`        | `vite-node@2` 仅支持 `vite@^5`，补丁在 `vite>=6.4.2`（跨大版本）。`vite@5.4.21` 已在本仓库 `trustPolicyExclude` 中显式接受。 | 漏洞需运行 vite dev server 才可触发；此处 vite-node 仅用于加载配置文件，不起 dev server。 |
| `esbuild <=0.24.2` | `@yunlefun/deploy > vite-node@2 > vite@5 > esbuild`   | 被上面的 vite@5 锁定（vite@5 依赖 `esbuild@^0.21`）。                                                                        | 同上，仅影响 esbuild dev server，部署链不暴露。                                           |
| `uuid <11.1.1`     | `@yunlefun/deploy > tencentcloud-sdk-nodejs > uuid@9` | 补丁仅在 `uuid@11`（ESM-only），会破坏 CJS 的腾讯云 SDK。                                                                    | 仅当向 v3/v5/v6 传入 `buf` 时触发；SDK 生成随机 UUID 不传 `buf`。                         |

**彻底修复方式**：在 `@yunlefun/deploy` 包内将 `vite-node` 升到 `^3`（带 vite 6/7），
并等 `tencentcloud-sdk-nodejs` 升级 `uuid`。届时删除本文「剩余风险」即可。
