# 依赖安全（pnpm audit）

记录依赖漏洞的修复策略与剩余风险。最近一次审计：**2026-07-16**。

## 现状

| 等级     | 修复前 | 未忽略 | 精确接受（见下） |
| -------- | ------ | ------ | ---------------- |
| critical | 1      | **0**  | 0                |
| high     | 8      | **0**  | 2                |
| moderate | 11     | **0**  | 2                |
| low      | 4      | **0**  | 0                |

`pnpm audit` 会显示 `4 vulnerabilities found`，随后明确标注 `2 moderate (2 ignored) | 2 high (2 ignored)`；
`pnpm audit --json` 的 `advisories` 为空，表示没有未处理告警。

验证命令：

```bash
pnpm audit --audit-level high   # 应无未忽略的 critical / high
pnpm audit                      # 查看完整列表
```

## 修复策略：pnpm overrides

绝大多数漏洞来自**传递依赖**（不是我们直接引入的包），无法通过升级直接依赖解决，
因此在 [`pnpm-workspace.yaml`](https://github.com/YunYouJun/apps.yunle.fun/blob/main/pnpm-workspace.yaml) 的
`overrides` 字段把它们钉死到已修复的版本。

> 本仓库使用 pnpm 11.x + workspace，`overrides` 写在 `pnpm-workspace.yaml`（不是 `package.json`）。

`allowBuilds` 只显式放行当前锁文件中确实需要安装脚本的 6 个构建/原生依赖：
`@parcel/watcher`、`core-js`、`core-js-pure`、`esbuild`、`protobufjs`、`unrs-resolver`；
没有通配符，新增带安装脚本的包仍会被 pnpm 拦截并要求单独审查。

主要修复项（完整列表见配置文件注释）：

- `protobufjs ^7.6.5` — critical 任意代码执行（飞书 SDK 带的，仅部署用）
- `axios ^1.18.1` — 多个 SSRF / 原型污染 / MITM
- `tar ^7.5.19` — node-tar 多个路径穿越 / 符号链接（Capacitor CLI、node-pre-gyp）。
  注意：`@capacitor/cli` < 7.5.0 按 tar v6 API 调用，在此 override 下 `cap sync` 会报
  `Cannot read properties of undefined (reading 'extract')`，需保持 `@capacitor/cli >= 7.5.0`
  （其 tar 依赖已升至 ^7.5.3）。
- `shelljs ^0.8.5`、`shell-quote ^1.8.4`、`@xmldom/xmldom ^0.8.13`、`serialize-javascript ^7.0.7`、
  `flatted ^3.4.2`、`h3 ^1.15.11`、`picomatch`、`lodash ^4.18.1`、`ws ^8.21.0`、
  `defu`、`simple-git`、`basic-ftp`、`fast-uri`、`js-cookie`、`tmp`、
  `@babel/plugin-transform-modules-systemjs` 等。
- 2026-07-16 新增：`@babel/core ^7.29.1`、`esbuild`（分版本段）、`form-data`（v3/v4 分段）、
  `js-yaml ^4.1.2`、`launch-editor ^2.14.1`、`lodash.unset ^4.18.0`、`undici ^7.28.0`、
  `uuid ^11.1.1`、`vite ^7.3.5`。
- 其他 moderate 的安全小版本升级：`unhead`、`ip-address`、`qs`、`yaml`、
  `follow-redirects`、`postcss`、`brace-expansion`（分版本段 override）。
- `@capacitor/haptics` 固定在 `8.0.1`：`8.0.2` 缺少前一稳定版具备的 provenance，
  会触发 `trustPolicy: no-downgrade`；未通过 `trustPolicyExclude` 放宽供应链策略。

改动 override 后务必重新验证：

```bash
pnpm install
pnpm lint && pnpm typecheck && pnpm test:unit && pnpm build
```

## 精确接受项（2 high + 2 moderate）

只在 `auditConfig.ignoreGhsas` 中按 GHSA 编号接受，不按包名或等级做宽泛忽略：

| 包 / GHSA                                                                                               | 链路                                                     | 接受依据                                                                                                                                                                                                                                                | 退出条件                                                           |
| ------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `vite@5.4.21` / `GHSA-fx2h-pf6j-xcff`（high）、`GHSA-4w7w-66w2-5vf9`、`GHSA-v6wh-96g9-6wx3`（moderate） | `docs > vitepress@1.6.4 > vite@5.4.21`                   | VitePress 1.6.4 的依赖范围仍是 Vite 5，修复版在 Vite 6；问题都需要启动开发服务器，文档 CI 只做静态构建，线上不运行该服务器。                                                                                                                            | VitePress 2 发布稳定版并完成迁移后，移除 3 个 GHSA 例外。          |
| `lodash.set@4.3.2` / `GHSA-p6mc-m468-83gw`（high）                                                      | `@cloudbase/node-sdk > @cloudbase/database > lodash.set` | 审计声称的 `4.3.3` 从未发布，npm 最新仍为 `4.3.2`。仓库通过 `patchedDependencies` 应用 `patches/lodash.set@4.3.2.patch`，回移 Lodash 的 `__proto__` / `constructor` / `prototype` 路径拦截；`test/unit/lodash-set-patch.test.ts` 持续验证三条污染路径。 | CloudBase 移除该依赖或上游发布真实修复版后，删除补丁与 GHSA 例外。 |

`esbuild` 已从 VitePress 链升级到可用修复线 `0.25.x`，`uuid` 已覆盖到 `11.1.1`，不再属于接受项。
