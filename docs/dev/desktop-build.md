# 桌面构建与私有内测

更新日期：2026-10-14。产品仓库现阶段保持私有。此处介绍 Electron 应用的本机构建、产物校验和 CI 内测包，默认未配置分发签名，`desktop.updatesEnabled` 为 `false`；构建和校验命令不上传 Release 或开启更新渠道。

## 本机构建

在仓库根使用 `.node-version` 指定的 Node.js 与根 `package.json` 指定的 pnpm，安装全部 workspace 依赖：

```bash
pnpm install --frozen-lockfile
pnpm dev:desktop
```

构建前执行桌面检查，随后在目标操作系统原生打包：

```bash
pnpm typecheck:desktop
pnpm test:desktop
pnpm test:desktop:e2e
pnpm make:desktop
pnpm verify:desktop
pnpm verify:desktop-artifacts
pnpm verify:desktop-launch
```

`make:desktop` 使用官方 Electron Forge Core API，自动生成静态 renderer、main／preload、原生应用和安装器；可显式传递架构，例如 Apple Silicon 上运行 `pnpm make:desktop --arch=arm64`。各操作系统在对应机器或 CI runner 构建和启动验证，当前 CI 目标为 macOS arm64、Windows x64、Linux x64。

`build:desktop` 只生成静态界面与 Electron JS；`package:desktop` 生成原生应用目录，供 `verify:desktop` 与 `verify:desktop-launch` 检查。需要分发安装包与构建记录时执行 `make:desktop`。

启动后默认进入「探索」。可在侧栏搜索、选择分类或查看最近打开；打开应用后，「返回目录」会保留当前网页，「正在使用」恢复原页面，「关闭应用」销毁当前视图。左下角外观选择支持跟随系统、浅色与深色。macOS 使用原生交通灯和侧栏材质，Windows／Linux 使用各自原生窗口框；最小窗口为 800 × 600，目录列表在窄窗口变为单列。

最近打开是设备本地的成功打开记录，最多 20 个应用 slug。它不等同于移动端云居的安装或云同步；搜索、分类与最近列表仍遵循主进程提供的当前应用访问策略。

## 图标来源

`apps/desktop/build/icons/source.png` 来自移动端现有 1024 × 1024 云乐坊标志。提交的导出文件分别用于 macOS ICNS、Windows ICO、Linux PNG，以及桌面 favicon／PWA 图标。修改主源后在 macOS 执行：

```bash
pnpm icons:desktop
```

该脚本使用系统 `sips` 与 `iconutil`，检查 PNG 尺寸、ICNS 容器和 ICO 各帧；Windows 与 Linux 构建直接使用提交的图标，不重新导出。详细来源记录在 `apps/desktop/build/icons/README.md`。

## 安装包与构建记录

Forge 原生目录位于 `apps/desktop/out/<产品名>-<platform>-<arch>/`，原始 maker 输出位于 `out/make/`。可分发目录为 `apps/desktop/out/artifacts/`：

```text
out/artifacts/
├── build-manifest.json
├── SHA256SUMS
└── <本次 Forge 返回的安装包，保留 maker 相对路径>
```

每次 make 重新整理该目录，只收集本次 Forge 返回的文件；旧 `out/make` 文件不会混入。一次记录仅包含一个产品版本、平台和架构。内测时一起传递安装包、构建记录和 `SHA256SUMS`，便于收件人核对来源与完整性。

| 平台        | 原生应用       | `out/artifacts` 内的文件                 |
| ----------- | -------------- | ---------------------------------------- |
| macOS arm64 | `云乐坊.app`   | DMG、ZIP；ZIP 包含应用，DMG 用于安装     |
| Windows x64 | `YunLeFun.exe` | Squirrel Setup.exe、`.nupkg`、`RELEASES` |
| Linux x64   | `YunLeFun`     | Debian `.deb`                            |

`build-manifest.json` 记录 `productName`、桌面 `version`、`electronVersion`、`platform`、`arch`、`gitCommit`、`gitDirty`、`builtAt`、`signing`，以及每个安装包的相对路径、字节数和 SHA256。

`gitDirty: true` 表示打包时仓库存在已修改或未跟踪文件，`gitCommit` 只标识当时 HEAD，不能完整代表这些本地变化；`false` 表示当时工作区干净。忽略的构建产物不计入 dirty 状态。

`signing.scope` 为 `distribution-identity`。`unsigned` 表示未配置分发身份，Electron／macOS 仍可能包含 ad-hoc 签名；`configured-unverified` 表示配置了签名，记录本身没有完成签名／公证验收。`signing.verified` 当前始终为 `false`，安装包校验成功不代表签名已验证。私有内测与正式签名发布分别验收。

## 三项产物校验

| 根命令                          | 检查内容                                                                                     | 需要先生成                          |
| ------------------------------- | -------------------------------------------------------------------------------------------- | ----------------------------------- |
| `pnpm verify:desktop`           | ASAR 内完整生产依赖、禁止外部软链接、Electron fuses                                          | `package:desktop` 或 `make:desktop` |
| `pnpm verify:desktop-artifacts` | 构建记录格式、文件大小／SHA256、`SHA256SUMS` 和文件清单一致，目录不含未列出的文件            | `make:desktop`                      |
| `pnpm verify:desktop-launch`    | 启动本机平台／架构原生应用，确认 `app://shell` 静态界面就绪，使用临时 profile 并在检查后退出 | `package:desktop` 或 `make:desktop` |

Linux 在无桌面环境中为 Electron E2E 和启动校验使用 Xvfb，例如：

```bash
xvfb-run --auto-servernum pnpm verify:desktop-launch
```

`SHA256SUMS` 使用标准 `<hex> *<relative-path>` 格式，包含所有安装包和 `build-manifest.json`。收到内测目录后在该目录运行标准工具：

```bash
# macOS
shasum -a 256 -c SHA256SUMS

# Linux
sha256sum -c SHA256SUMS
```

Windows PowerShell 可使用系统 `Get-FileHash` 检查相同清单：

```powershell
Get-Content -LiteralPath SHA256SUMS -Encoding UTF8 | ForEach-Object {
  $expected, $file = $_ -split ' \*', 2
  $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $expected) { throw "SHA256 mismatch: $file" }
  Write-Output "OK: $file"
}
```

SHA256 核对传输前后的文件是否相同；来源真实性仍由可信内测渠道和后续签名验证确认。

## 三平台 CI

`Desktop CI` 根据桌面源码、共享 `app-core` 和构建配置路径触发，纯文档修改不启动桌面构建。目标为 macOS arm64、Windows x64、Ubuntu 24.04 x64；每个平台执行 lint、类型、单元、Electron E2E、make 和三项产物校验。CI 从 `out/artifacts` 上传完整安装包与构建记录，保留 3 天；失败 trace／报告保留 7 天。工作流不创建或发布 GitHub Release。

workflow 的 `workflow_dispatch` 配置进入默认分支后，具有仓库写权限的成员可在 Actions → Desktop CI → Run workflow 选择分支和 `target`：`all`、`macos`、`windows`、`linux`。默认分支要求来自 [GitHub 手动运行工作流文档](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)。

默认分支已包含工作流时，也可从仓库目录使用 GitHub CLI 选择一个平台：

```bash
gh workflow run desktop.yml --ref main -f target=macos
gh run watch
```

将 `target` 改为 `windows` 或 `linux` 可单独验证对应平台；`all` 会启动三平台矩阵。当前组织 Actions 预算阻止 runner 启动，手动触发入口不能绕过这一限制；恢复预算或接入可用 runner 后才可完成远端验收。本机结果与实际远端记录见 [迁移验收](./monorepo.md#验证迁移)。

## 更新策略校验

根 `pnpm check:desktop-release` 是只读配置检查，需要 `RELEASE_TAG` 与 `GITHUB_REPOSITORY`：Tag 必须是稳定 `v<apps/desktop/package.json version>`，仓库必须等于 `desktop.updateRepository`。该检查不上传文件。

当前自动更新关闭，允许保持私有仓库及 draft 分发配置。只有开启公共 Electron 更新服务时，检查还要求 `GITHUB_REPOSITORY_VISIBILITY=public`；本轮没有修改仓库可见性、执行发布或开启自动更新。
