# 客户端工作区与部署

更新日期：2026-10-24。仓库根目录管理 pnpm workspace、统一命令、锁文件和依赖安全策略。现有 Nuxt / Ionic / Capacitor 工程迁入 `apps/mobile/`，该入口继续提供 Web、iOS 和 Android 客户端；桌面端在 `apps/desktop/` 接入独立 Nuxt 界面和 Electron Host。迁移在 [产品 PR #41](https://github.com/YunLeFun/apps.yunle.fun/pull/41) 中 review。

## 目录与命令

| 内容                | 路径                                                        | 说明                                                    |
| ------------------- | ----------------------------------------------------------- | ------------------------------------------------------- |
| Web／移动源码和 API | `apps/mobile/app/`、`apps/mobile/server/`                   | 保留原有页面、Ionic 导航和云端 API                      |
| 移动配置与环境文件  | `apps/mobile/nuxt.config.ts`、`capacitor.config.ts`、`.env` | 私有环境值只保存在本机或 CI Secret                      |
| 原生工程            | `apps/mobile/ios/`、`apps/mobile/android/`                  | Capacitor 在移动应用目录执行                            |
| 移动脚本与测试      | `apps/mobile/scripts/`、`apps/mobile/test/`                 | 脚本自行定位移动应用根目录                              |
| 桌面入口            | `apps/desktop/`                                             | 独立 renderer、Electron main／preload、Forge 配置和测试 |
| 公共包              | `packages/`                                                 | 按实际消费者提取协议和业务，移动原生插件不引入桌面      |
| 文档                | `docs/`                                                     | 保留现有 VitePress workspace                            |
| 运营工具            | `scripts/`                                                  | CloudBase 集合初始化、规则和索引保留在仓库根            |

所有依赖在仓库根安装，使用 `.node-version` 指定的 Node.js 和根 `package.json` 指定的 pnpm：

```bash
pnpm install --frozen-lockfile
cp -n apps/mobile/.env.example apps/mobile/.env
pnpm dev
```

原有根命令 `dev`、`build`、`generate`、`typecheck`、`test:*`、`sync`、`build:ios` 和 `build:android:release` 继续转发到移动应用。也可显式执行：

```bash
pnpm --dir apps/mobile run dev
pnpm --dir apps/mobile run build
pnpm --dir apps/mobile run sync
pnpm --dir apps/mobile exec playwright test --project=chromium
```

根 `pnpm lint` 检查全仓库；`pnpm docs:dev` 等文档命令在 `docs` 中执行。移动端版本来自 `apps/mobile/package.json`，桌面端版本来自 `apps/desktop/package.json`，根包不承担客户端版本号。

桌面命令独立转发到 `apps/desktop`：

```bash
pnpm dev:desktop
pnpm build:desktop
pnpm test:desktop
pnpm make:desktop
```

根目录还提供 `typecheck:desktop`、`test:desktop:e2e` 与 `package:desktop`，分别对应桌面类型、Electron 集成测试和原生应用打包。构建后运行 `verify:desktop` 检查 ASAR／生产依赖／fuses，`verify:desktop-artifacts` 检查安装包／构建记录／SHA256，`verify:desktop-launch` 实际启动原生包。Forge 的原始安装包保留在 `apps/desktop/out/make`；本次构建的可分发目录是 `apps/desktop/out/artifacts`，包含安装包、`build-manifest.json` 和 `SHA256SUMS`，不会混入旧产物。

产品仓库现阶段保持私有，`desktop.updatesEnabled` 为 `false`，CI 不发布 Release，默认产物未配置分发签名。`check:desktop-release` 只校验稳定 Tag、桌面版本与目标仓库；启用公共 Electron 更新服务还要求明确确认目标仓库可见性为 public。图标从移动端既有标志导出，macOS 可用 `icons:desktop` 更新 ICNS／ICO／PNG，其它平台使用提交的导出文件。完整命令与产物字段见 [桌面构建与私有内测](./desktop-build.md)。

桌面接入继续使用 Electron 44.7.0 和 Forge 8.0.1。当前移动与桌面统一到 Nuxt 4.6.2、Vue 3.5.44 和 Vite 8.3.5，TypeScript 为 5.9.3，pnpm 为 11.13.1；主进程通过 `vite-electron` 别名也使用 Vite 8.3.5。文档保留稳定版 VitePress 1.6.4，并将其 Vite 单独覆盖到兼容的 6.4.5。各构建日志与锁文件记录实际版本，安全补丁及精确例外见[依赖安全](./dependency-security.md)。

实际接入来源为 `vitesse-nuxt-electron` 的 `3821916`，包含开发重建队列和退出治理；产品进一步监听 `shared` 与 `packages/app-core`，保留各应用开发进程的退出清理。

公共包 `packages/app-core` 复用应用记录类型、记录转换、域名与图标处理和内置目录快照，移动原路径通过 re-export 保持兼容。桌面主进程从固定匿名公开 API 获取目录，按公开、审核与发布状态及无需登录／会员／付费的条件决定能否打开应用；离线仅提供显式允许的免费快照应用。目录刷新时，相同 slug 与规范化后的完整 URL 保留正在运行的视图、历史及会话，并同步变化的文档 ID；应用下架、访问门槛或目标 URL 改变才关闭。完整账号、云居同步与宿主 SSO 后续接入。

迁移前位于根目录的 `.env` 已随应用移入 `apps/mobile/.env`。根运营脚本使用该文件时应显式设置 `--env-file=apps/mobile/.env`，避免把私有环境复制到多个应用。

## 应用目录的生成来源

内置应用快照的 producer 位于相邻 `admin` 仓库：`admin/scripts/gen-app-snapshot.ts` 输出本仓库的 `packages/app-core/src/catalog/generated.ts`，Web／移动与桌面从公共包消费。生成文件应通过 producer 更新，避免两端分别维护目录副本。

`admin/scripts/migrate-builtin-apps.ts` 的既有源码读取路径同步为 `apps/mobile/app/constants/apps/index.ts`。配套 [admin PR #41](https://github.com/YunLeFun/admin/pull/41) 优先使用迁移后的目录，并保留对旧布局的兼容，可先于产品迁移合并。本次改造只更新跨仓库路径，没有运行数据库迁移或重新生成线上快照；后台工具执行和数据发布仍按各自原有流程验收。

## EdgeOne 生产部署

生产站点使用 EdgeOne 官方 Nuxt 自动适配器，浏览器资源、页面 fallback 和 Nitro API 一起验收。控制台的构建目录必须指向实际 Nuxt 工程；仓库根包只负责命令转发，不能让平台正确检测移动 Nuxt 应用。

| 构建设置     | 值                                           |
| ------------ | -------------------------------------------- |
| 框架预设     | `Nuxt`                                       |
| 构建根目录   | `apps/mobile`                                |
| 安装命令     | `pnpm --dir ../.. install --frozen-lockfile` |
| 构建命令     | `pnpm run build:edgeone`                     |
| 静态资源目录 | `.edgeone/assets`                            |
| Node.js      | `24.18.0`，与根 `.node-version` 保持一致     |

根目录由控制台管理；进入 `apps/mobile` 后，平台读取该目录的 `edgeone.json`，其构建、安装和输出目录设置优先于控制台同名配置。应用配置保留 AASA 与工坊 API 的响应头。根 `edgeone.json` 也转发到专用构建入口；如果误用仓库根目录导致自动适配器未启用，构建检查会失败，避免再次发布只有静态资源的版本。

当前 Nuxt 4.6.2 锁定 Nitro 2.13.5；EdgeOne 部署继续采用平台官方适配器生成 `.edgeone`，不在产品工作区新增适配器 beta 依赖。客户端保持 `ssr: false`；生产仍保留运行 Nitro API 的 Node 服务。

官方适配器先在 Nuxt 配置中注入临时模块，再运行 `build:edgeone`；该命令只执行 Nuxt 构建并检查本阶段的静态资源、Nitro 入口、chunk 和 CloudBase 运行依赖。命令返回后，适配器才生成 `handler.js`、版本 3 的 `config.json`，恢复 Nuxt 配置，并由平台补齐函数启动入口。完成适配后可从仓库根执行 `pnpm check:edgeone-output`，校验函数路由覆盖 `/login`、`/tabs/home` 和应用 API。直接运行普通 Nuxt 构建不会完成平台适配；无适配器预处理的 `build:edgeone` 会报错。

完整部署产物位于 `apps/mobile/.edgeone`：`assets/` 包含浏览器资源，`cloud-functions/ssr-node/` 包含函数 handler、路由配置、Nitro chunk 和运行依赖。`outputDirectory` 只选择静态资源；发布必须同时收集函数目录，不能只上传 `.output/public` 或 `.edgeone/assets`。

专用入口清理旧 `.edgeone`，使用空 dotenv 文件构建，并拒绝应用目录或函数产物中的 `.env`、`.env.production`、`.env.local` 和 `.env.production.local`。请在干净检出中部署，服务端变量通过 EdgeOne 环境设置提供；该限制不影响日常移动／Web 构建和 Capacitor 的 `.output` 流程。

Nuxt 生产服务器不自动读取 `.env`；运行时覆盖需要匹配已声明的 `NUXT_*` 配置，例如 `NUXT_TENCENT_API_SECRET_ID`、`NUXT_TENCENT_API_SECRET_KEY` 和 `NUXT_WX_OPEN_APP_SECRET`。私密值不能放入 `runtimeConfig.public`。平台普通 Node 函数的 `context.env` 契约不能直接证明 Nuxt 函数中的 `process.env` 已传入，必须通过实际页面／只读 API 验证变量可用性，不输出变量值。

每次发布均应核对以下项目，构建成功不能替代实际请求验收：

1. 控制台使用表中设置，日志确认启用 Nuxt 官方适配器，应用目录中的文件配置生效。
2. 完整 `.edgeone` 包含静态资源、函数 handler、版本 3 路由和 CloudBase 服务端依赖，产物没有私有环境文件。
3. `/`、`/tabs/home`、`/login` 可直接打开和刷新，Nuxt JavaScript／CSS 可加载；`/.well-known/apple-app-site-association` 保持 JSON 响应头。
4. 只读 `/api/apps/public` 返回 JSON，匿名 `/api/apps/access`、`/api/workshops/mine` 和 `/api/workshops/joined` 返回预期鉴权 JSON；工坊 API 保持 `private, no-store`。`/api/workshops` 根路由仅定义 POST，不用该路径的 GET 响应判断服务端是否部署成功。
5. 云端 Secret、CloudBase 环境和允许的 Origin 在运行时可用，响应及浏览器资源不暴露服务端配置。登录回调与原生关联域另行验证。

参考官方 [Nuxt 支持](https://pages.edgeone.ai/document/framework-nuxt)、[文件配置](https://pages.edgeone.ai/document/edgeone-json)、[构建设置](https://pages.edgeone.ai/document/build-guide)、[构建产物协议](https://pages.edgeone.ai/document/building-output-configuration) 与 [Nuxt 运行时配置](https://nuxt.com/docs/4.x/guide/going-further/runtime-config)。

`netlify.toml` 作为历史备选配置更新 Node.js 和资源目录；启用 Netlify 时仍需验证它的 Nuxt 服务端适配与 monorepo package directory。`cloudbaserc.json` 没有源码路径，继续保留现有环境与 CloudRun 名称。参考 [Netlify monorepo 设置](https://docs.netlify.com/build/configure-builds/monorepos/)。

## Capacitor 兼容工程与发布

云乐坊原生 iOS 位于 `apps/ios`，日常 TestFlight 更新使用[原生发布流程](./testflight.md)。下列命令用于 `apps/mobile` 的旧 Capacitor 兼容客户端，不作为原生发布前置步骤。

Capacitor 的 `webDir` 仍相对 `apps/mobile` 指向 `.output/public`。构建和同步命令保持原有行为：

```bash
pnpm build
pnpm sync
pnpm build:ios
```

iOS Podfile、Android Gradle 与本地 StoreKit 插件需解析工作区中的依赖，不能依赖迁移前的根 `ios`／`android` 目录。iOS archive 和 Android APK／AAB 留在各自原生工程下，上传、签名和真机验证仍是独立发布步骤。

从仓库根手动执行移动脚本时使用完整路径，例如：

```bash
bash apps/mobile/scripts/ios-testflight.sh
```

详见 [TestFlight 发布](./testflight.md) 和 [Android 发布](./android-release.md)。桌面客户端使用自己的构建、安装包、签名及更新渠道，接入范围见 [桌面架构](./desktop-electron-architecture.md)。

移动与桌面的 Git Tag 需要区分。建议移动使用 `mobile-vX.Y.Z`；桌面若使用官方公共 GitHub 更新服务，可保留 `vX.Y.Z` 的有效 SemVer Tag。当前移动 `release` 命令发布前需核对标签命名，桌面接入不自动上传发布、签名或开启产品更新渠道。

## Forge 与 pnpm 11 的打包兼容

桌面 `package`、`make` 和 `publish` 通过 `scripts/forge.mjs` 调用官方 `@electron-forge/core@8.0.1` programmatic API。Forge 8 CLI 的旧式连字符配置检查不能识别 pnpm 11 workspace 中的 camelCase 设置；API 入口保留原 makers、hooks、重建和 fuses 流程，工作区依赖安全策略保持不变。

macOS 的 `preMake` hook 检查 DMG maker 声明的 `macos-alias`／`fs-xattr` 原生绑定；缺失时只在对应依赖目录执行 `npm rebuild`，为本机 Node 构建辅助模块。该步骤不安装新依赖，辅助模块不进入 Electron 运行时。Linux deb maker 显式使用包名 `yunlefun` 和可执行文件 `YunLeFun`，避免 scoped workspace 包名 `@yunlefun/desktop` 与实际程序名混用。

## 验证迁移

根 CI 使用工作区锁文件安装，固定读取 `.node-version`，通过根转发命令验证 Web／移动类型、生产构建、服务端运行依赖、单元与 Nuxt 测试。Chromium 在 `apps/mobile` 执行，失败时上传该应用的截图和 trace。

独立 Desktop CI 配置在 macOS arm64、Windows x64 和 Ubuntu 24.04 x64 执行桌面 lint、类型、单元、Electron 集成测试、Forge make、ASAR／fuse、安装包／构建记录／SHA256 检查与 `verify:launch` 打包后启动。Linux 使用 Xvfb，仅修改文档不触发桌面构建。workflow 进入默认分支后可手动选择 `all`、`macos`、`windows` 或 `linux`；安装包从 `out/artifacts` 上传并保留 3 天，失败 trace 保留 7 天。该流程不发布 GitHub Release，手动入口见 [构建说明](./desktop-build.md#三平台-ci)。

2026-10-14 的独立 PR 工作区验收结果：

- PR 在最新 `main` 上整理迁移变更，排除原工作区尚未提交的其它功能。根 lint、Web／移动类型检查、475 个单元测试、59 个 Nuxt 测试、5 个 Chromium smoke、生产构建与服务端运行依赖检查通过。
- 桌面 lint、类型检查、75 个单元测试和 3 个真实 Electron E2E 通过；另实测确认失败时可以保存 Electron trace。macOS arm64 的 Forge make 成功生成带云乐坊品牌图标的 `.app`、DMG 和 ZIP，实际应用 ICNS 与提交的图标一致。最新产物通过三项根校验：ASAR 完整生产依赖树／fuses、安装包／构建记录／SHA256、原生打包启动；标准 `shasum` 也通过全部安装包与 manifest 校验。关闭自动更新时的私有 release 配置检查通过，没有执行发布。
- [三平台 Desktop CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38426634680) 已触发，但 GitHub 提示“Actions budget is preventing further use”；所有 job 均未进入步骤，runner 没有启动。因此该轮失败不能作为代码执行结果，macOS／Windows／Linux 的远端验收仍待恢复 Actions 预算或接入可用 runner 后运行。

2026-10-13 在原本机工作区的迁移阶段记录如下。该工作区包含其它尚未提交的功能，这些记录不替代当前 PR 的验收；当时的 534 个单元测试和 62 个 Nuxt 测试不作为本 PR 的测试数量：

- Web／移动：5 个 Chromium smoke、生产构建与服务端依赖检查通过；iOS Simulator 未签名编译、Android Debug 构建和 12 个原生 JUnit 测试通过。
- Web 全栈产物：本地生产 Node server 的 `/`、`/tabs/home`、`/login` 均返回 200；只读 `/api/apps/public` 返回 200 JSON，包含 25 个公开应用。
- 桌面：macOS arm64 的 `.app`、DMG、ZIP、ASAR 完整生产依赖树、fuses、原生启动及开发进程启动／退出清理通过。
- 打包后的桌面 UI：实际 ASAR `.app` 从 `app://shell/` 加载，Electron 为 44.7.0；线上目录显示 `online` 和 25 项，无目录错误；`cook.yunle.fun` 在 WebContentsView 中加载“食用手册”，guest 的 `require` 和 `window.desktop` 均为 `undefined`。
- 根 lint 与文档构建通过。当前 PR 的原生工程构建、生产部署、签名、公证、真机登录与跨版本更新另行验收。

2026-10-24 依赖整理将根 esbuild 更新到 0.28.2，并移除误缩窄通用 peer 范围的旧 Vite／esbuild 覆盖。当前仍有 `@stencil/vue-output-target` 声明 `vue-router ^4.5.0`、项目使用 5.1.0 的既有 peer 提示；安全审计未处理项为 0，另有 2 项已应用补丁并精确忽略的 high，详见[依赖安全](./dependency-security.md)。此轮构建与测试结果以依赖升级 PR 的验证记录为准，不沿用上述迁移验收数量。

本机验证应覆盖：

- 现有 Web 路由、登录页面、API 返回和静态资源。
- Capacitor 同步后的插件路径、配置和资源。
- 对应 SDK 下的 iOS／Android 编译与既有原生协议测试。
- 桌面接入后的类型、Electron 集成测试、原生安装包与 ASAR 校验。

CI 配置不代表真机登录、商店签名或生产部署已经通过；这些结果按实际执行记录验收。
