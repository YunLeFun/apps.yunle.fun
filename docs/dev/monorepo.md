# 客户端工作区与部署

更新日期：2026-10-13。仓库根目录管理 pnpm workspace、统一命令、锁文件和依赖安全策略。现有 Nuxt / Ionic / Capacitor 工程迁入 `apps/mobile/`，该入口继续提供 Web、iOS 和 Android 客户端；桌面端在 `apps/desktop/` 接入独立 Nuxt 界面和 Electron Host。

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

根目录还提供 `typecheck:desktop`、`test:desktop:e2e`、`package:desktop` 与 `verify:desktop`，分别对应桌面类型、Electron 集成测试、原生应用打包和已有包校验。安装包位于 `apps/desktop/out/make`。

桌面接入复用模板的 Electron 44.7.0、Forge 8.0.1 与 Vite 8.3.4 主进程构建；Nuxt、Vue、TypeScript 和 pnpm 先与原产品工作区保持兼容，分别采用 Nuxt 4.4.8、Vue 3.5.40、TypeScript 5.9.3 和 pnpm 11.13.1。renderer 使用对应 Nuxt builder 的 Vite 7.3.6；主进程通过 `vite-electron` 别名单独使用 Vite 8.3.4，各构建日志与锁文件记录实际版本。

实际接入来源为 `vitesse-nuxt-electron` 的 `3821916`，包含开发重建队列和退出治理；产品进一步监听 `shared` 与 `packages/app-core`，保留各应用开发进程的退出清理。

公共包 `packages/app-core` 复用应用记录类型、记录转换、域名与图标处理和内置目录快照，移动原路径通过 re-export 保持兼容。桌面主进程从固定匿名公开 API 获取目录，按公开、审核与发布状态及无需登录／会员／付费的条件决定能否打开应用；离线仅提供显式允许的免费快照应用。目录刷新时，相同 slug 与规范化后的完整 URL 保留正在运行的视图、历史及会话，并同步变化的文档 ID；应用下架、访问门槛或目标 URL 改变才关闭。完整账号、云居同步与宿主 SSO 后续接入。

迁移前位于根目录的 `.env` 已随应用移入 `apps/mobile/.env`。根运营脚本使用该文件时应显式设置 `--env-file=apps/mobile/.env`，避免把私有环境复制到多个应用。

## 应用目录的生成来源

内置应用快照的 producer 位于相邻 `admin` 仓库：`admin/scripts/gen-app-snapshot.ts` 输出本仓库的 `packages/app-core/src/catalog/generated.ts`，Web／移动与桌面从公共包消费。生成文件应通过 producer 更新，避免两端分别维护目录副本。

`admin/scripts/migrate-builtin-apps.ts` 的既有源码读取路径同步为 `apps/mobile/app/constants/apps/index.ts`。本次改造只更新跨仓库路径，没有运行数据库迁移或重新生成线上快照；后台工具执行和数据发布仍按各自原有流程验收。

## EdgeOne 生产部署

生产站点继续使用现有 Nuxt 全栈适配：浏览器静态资源和 Nitro API 一起验收。根 `edgeone.json` 保留原有响应头，并记录迁移后的构建命令与静态资源路径。

| 构建设置     | 值                                 |
| ------------ | ---------------------------------- |
| 仓库根目录   | `./`                               |
| 安装命令     | `pnpm install --frozen-lockfile`   |
| 构建命令     | `pnpm run build`                   |
| 静态资源目录 | `apps/mobile/.output/public`       |
| Node.js      | 与根 `.node-version` 保持一致      |
| 框架适配     | 保留当前 Nuxt 全栈预设／服务端适配 |

`outputDirectory` 指静态资源目录，不能据此省略 Nitro API。平台的 Nuxt 适配需要定位迁移后的应用和服务端产物；如果既有适配从根 `.output/server` 收集运行时，需同步使用 `apps/mobile/.output/server`，或按平台的 Nuxt 输出规范收集。仓库改造没有修改外部控制台设置。

第一次迁移部署需核对：

1. 控制台根目录仍为 `./`，不要切换到 `apps/mobile` 后再使用根工作区命令。
2. 构建日志运行的是移动 Nuxt 工程，静态资源和服务端依赖都进入平台产物。
3. `/tabs/home` 与登录回调可打开并刷新；`/.well-known/apple-app-site-association` 保持 JSON 响应头。
4. `/api` 请求进入 Nitro；`/api/workshops` 及子路由仍返回 `private, no-store` 响应头。
5. 云端 Secret、CloudBase 环境及允许的 Origin 保持原有部署策略，原生安装包不包含服务端配置。

文件配置支持覆盖构建、安装和输出目录，根目录仍由控制台管理。参考 [EdgeOne 配置](https://edgeone.ai/document/162316940299157504) 与 [构建设置](https://pages.edgeone.ai/document/build-guide)。

`netlify.toml` 作为历史备选配置更新 Node.js 和资源目录；启用 Netlify 时仍需验证它的 Nuxt 服务端适配与 monorepo package directory。`cloudbaserc.json` 没有源码路径，继续保留现有环境与 CloudRun 名称。参考 [Netlify monorepo 设置](https://docs.netlify.com/build/configure-builds/monorepos/)。

## 原生工程与发布

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

独立 Desktop CI 在 macOS arm64、Windows x64 和 Linux x64 执行桌面 lint、类型、单元、Electron 集成测试、Forge make、ASAR／fuse 检查与 `verify:launch` 打包后启动。Linux 使用 Xvfb，失败 trace 与安装包按平台上传；该流程不发布 GitHub Release。

2026-10-13 的本机验收结果：

- Web／移动：共享模块抽取后，类型检查、534 个单元测试、62 个 Nuxt 测试、5 个 Chromium smoke、生产构建与服务端依赖检查通过；iOS Simulator 未签名编译、Android Debug 构建和 12 个原生 JUnit 测试通过。
- Web 全栈产物：本地生产 Node server 的 `/`、`/tabs/home`、`/login` 均返回 200；只读 `/api/apps/public` 返回 200 JSON，包含 25 个公开应用。
- 桌面：lint、类型检查、27 个单元测试和 2 个真实 Electron E2E 通过；macOS arm64 的 `.app`、DMG、ZIP、ASAR 完整生产依赖树、fuses、原生启动及开发进程启动／退出清理通过。
- 打包后的桌面 UI：实际 ASAR `.app` 从 `app://shell/` 加载，Electron 为 44.7.0；线上目录显示 `online` 和 25 项，无目录错误；`cook.yunle.fun` 在 WebContentsView 中加载“食用手册”，guest 的 `require` 和 `window.desktop` 均为 `undefined`。
- 根 lint 与文档构建通过。Windows／Linux 的新三平台 CI 尚待实际运行；生产部署、签名、公证、真机登录与跨版本更新另行验收。

依赖安装仍有 Nitro 安全覆盖的 esbuild 0.28.1 与旧 unplugin 声明 `^0.25` 的两项 optional peer 提示；实际构建和测试通过，保留安全覆盖。

本机验证应覆盖：

- 现有 Web 路由、登录页面、API 返回和静态资源。
- Capacitor 同步后的插件路径、配置和资源。
- 对应 SDK 下的 iOS／Android 编译与既有原生协议测试。
- 桌面接入后的类型、Electron 集成测试、原生安装包与 ASAR 校验。

CI 配置不代表真机登录、商店签名或生产部署已经通过；这些结果按实际执行记录验收。
