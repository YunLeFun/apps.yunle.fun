# 依赖安全（pnpm audit）

记录依赖漏洞的修复策略与剩余风险。最近一次审计：**2026-10-31**。

## 现状

本轮修复 Web CI 新报告的 19 项未处理公告，优先升级到已发布的安全版本。没有新增 GHSA 忽略项或降低审计等级。

| 等级     | 修复前未处理公告 | 当前未处理 | 已补丁并精确忽略（见下） |
| -------- | ---------------- | ---------- | ------------------------ |
| critical | 0                | **0**      | 0                        |
| high     | 6                | **0**      | 1                        |
| moderate | 10               | **0**      | 0                        |
| low      | 3                | **0**      | 1                        |
| 合计     | 19               | **0**      | 2                        |

`pnpm audit` 通过，`pnpm audit --json` 的 `advisories` 为空；metadata 仍记录 1 项 high 和 1 项 low。
两项均已应用仓库补丁；pnpm 根据包版本匹配公告，不能识别补丁是否已修复问题，所以在
`auditConfig.ignoreGhsas` 中精确忽略。这表示没有未处理告警，不表示这些旧版本已被审计服务认定为无漏洞。

```bash
pnpm audit --audit-level high
pnpm audit --json
```

## 修复策略

1. 优先升级直接依赖及其构建工具，并同步提交 `pnpm-lock.yaml`。移动与桌面当前统一为 Nuxt `4.6.3`、
   Vue `3.5.44` 和 Vite `8.3.5`；根构建工具使用 esbuild `0.28.2`，其余依赖在声明的 semver 范围内刷新。
2. 上游依赖范围仍保留易受影响版本时，在 [`pnpm-workspace.yaml`](https://github.com/YunLeFun/apps.yunle.fun/blob/main/pnpm-workspace.yaml)
   使用与调用方 API 兼容的安全覆盖。跨主版本覆盖需验证实际调用链，并尽量限定到对应父依赖。
3. 上游尚无已发布修复版时，回移最小补丁并测试恶意输入与合法行为；只有此类已修复且有证据的告警才按 GHSA 精确忽略。
   上游发布修复版或移除依赖后，删除补丁和对应忽略项。

本仓库使用 pnpm `11.13.1` + workspace，`overrides`、`patchedDependencies` 与安装脚本策略写在
`pnpm-workspace.yaml`。`allowBuilds` 显式放行 `@parcel/watcher`、`core-js`、`core-js-pure`、
`electron`、`electron-winstaller`、`esbuild`、`fs-xattr`、`macos-alias`、`protobufjs`、`unrs-resolver`；
没有通配符，新增带安装脚本的包仍需单独审查。

## 本轮传递依赖与兼容处理

- Web 和桌面升级到 [Nuxt 4.6.3](https://github.com/nuxt/nuxt/releases/tag/v4.6.3)，同步修复 Nuxt、Vite builder 和 Nitro server 的新公告。
- `follow-redirects` 升级到 `1.16.2`；`node-forge` 升级到已发布的 [1.4.1](https://github.com/digitalbazaar/forge/releases/tag/v1.4.1)，
  移除旧 RSA 回移补丁与对应 GHSA 忽略。五项 RSA 恶意结构及合法签名回归继续验证上游版本。
- `glob >=9 <14.0.2` 限定覆盖到 `14.0.3`，修复中止后继续遍历的问题；保留 Electron 所需的 glob 7 callback API。
  `minimatch <11.0.1` 升级到 `11.0.3`，阻断 optimizationLevel 2 的 globParts 放大。
  两个兼容补丁只适配 `glob@7.2.3` 和 `@electron/asar@3.4.1` 对 minimatch 的旧调用：使用命名导出及 Matcher.test，
  并保留旧正则对象的路径。`glob-security-compatibility.test.ts` 从实际 Electron 和 archiver 依赖解析消费者，
  验证 callback、同步遍历、隐藏文件、花括号、globstar、ASAR unpack/unpackDir、Promise API 和模式放大上限。
- 文档保留稳定版 VitePress `1.6.4`，只对其 Vite 覆盖到 `6.4.5`，满足 `@vitejs/plugin-vue@5` 的 peer 范围。
  原 Vite 5 的三个 GHSA 忽略项与发布信任例外已移除，无需为修复漏洞迁移到 VitePress 预发布版。
- `get-uri@6.0.5 > basic-ftp` 限定覆盖到 `6.2.3`，保留 `Client` API；已使用本地 FTP fixture 验证连接和完整下载。
- `appdmg@0.6.6 > image-size` 限定覆盖到 `2.0.4`，并通过 `patches/appdmg@0.6.6.patch`
  将旧 callback 调用适配到 `image-size/fromFile` 的 Promise API。独立 fixture 已验证图片尺寸、缺文件、坏图片与无背景跳过分支。
- 继续保留按版本段限定的 esbuild、form-data、picomatch、undici 等安全覆盖，避免改写兼容的新版本声明。
  删除会误缩窄通用 peer 范围的旧 Vite／esbuild 覆盖；Vue runtime、compiler-sfc 与 server-renderer 同步到 `3.5.44`。
- H3 安全覆盖只命中旧 1.x 范围，保留新 devframe 所需的 H3 2，避免全局覆盖导致缺少 `H3` 导出。
- 两端 `@playwright/test` 精确固定为 `1.61.1`，保持既有 Electron `44.7.0` 的测试驱动基线；
  后续升级需通过完整跨平台集成测试。
- 其他覆盖包含 protobufjs、axios、tar、brace-expansion、fast-uri、js-yaml、katex、tinypool、ws 等；
  完整版本与适用依赖链以 workspace 注释和锁文件为准。

当前安装仍有 `@stencil/vue-output-target` 声明 `vue-router ^4.5.0`、项目使用 `5.1.0` 的既有 peer 提示。
这与安全告警分开跟踪，不能用忽略 peer 检查来宣称所有声明均兼容。

## 发布信任策略

保持 `trustPolicy: no-downgrade`。Workbox `7.4.1` 引入的
`@trickfilm400/rollup-plugin-off-main-thread@3.0.0-pre1` 缺少 provenance，
本轮在 Workbox 链内限定使用具备 provenance 的 `2.5.0`；已比对两者发布包中的生产代码逐字相同，未新增信任例外。

`@capacitor/haptics` 仍固定在 `8.0.1`：`8.0.2` 缺少前一稳定版具备的 provenance。
Vue `3.5.40` 的旧 `minimumReleaseAgeExclude` 已移除。当前仍保留的精确发布信任例外为
`@octokit/endpoint@9.0.6`、`rollup@2.80.0` 与 `chokidar@4.0.3`；没有新增包名通配例外。

## 已补丁的精确忽略项（1 high、1 low）

| 包 / GHSA                                                                                       | 依赖链与补丁证据                                                                                                                                                                                                                                     | 退出条件                                                             |
| ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `lodash.set@4.3.2` / [`GHSA-p6mc-m468-83gw`](https://github.com/advisories/GHSA-p6mc-m468-83gw) | `@cloudbase/node-sdk > @cloudbase/database > lodash.set`。公告声称的 `4.3.3` 尚未发布；`patches/lodash.set@4.3.2.patch` 回移 `__proto__` / `constructor` / `prototype` 路径拦截，`apps/mobile/test/unit/lodash-set-patch.test.ts` 覆盖三条污染路径。 | CloudBase 移除该依赖或上游发布真实修复版后，删除补丁与 GHSA 忽略项。 |

### 2026-10-28：deepmerge 原型键补丁

`deepmerge` 的真实最新发布仍为 `4.3.1`，`4.3.2` 尚未发布，不能通过升级到该版本消除告警。
[GHSA-gcqx-w48m-w2h4](https://github.com/advisories/GHSA-gcqx-w48m-w2h4) 当前也没有已发布修复版本。
遵循上述已验证补丁策略，`patches/deepmerge@4.3.1.patch` 在目标复制和源合并之前统一拒绝字符串
`__proto__`，覆盖 npm 包的源码、CommonJS 主入口和浏览器 UMD 入口。其余原型检查与合并规则保留。

`apps/mobile/test/unit/deepmerge-patch.test.ts` 从 Nitro 的实际 Rollup 依赖解析已安装包，验证 CJS 与 UMD
均能拦截无原型目标、空值/原始值占位、目标自有原型键和嵌套输入；同时验证普通对象、数组拼接、Symbol
及输入不可变性。精确忽略此 low 告警仅针对已应用并验证的版本补丁；当前仅保留 lodash.set 的 high 补丁；2026-10-31 已升级 node-forge 并移除其旧补丁和忽略项。

上游发布真实安全版本后，应升级消费者并移除本补丁与这条 GHSA 精确忽略，不扩大忽略范围或降低审计等级。

## 验证命令

依赖变更需同时验证移动／Web、桌面和文档消费者。以下命令用于本轮回归，实际通过结果以对应提交的 CI 验证记录为准：

```bash
pnpm install --frozen-lockfile
pnpm audit --audit-level high
pnpm lint
pnpm typecheck
pnpm test:unit
pnpm test:nuxt
pnpm build
pnpm check:server-runtime-deps
pnpm --dir apps/mobile exec playwright test --project=chromium
pnpm typecheck:desktop
pnpm test:desktop
pnpm test:desktop:e2e
pnpm make:desktop
pnpm verify:desktop
pnpm verify:desktop-artifacts
pnpm verify:desktop-launch
pnpm docs:build
```
