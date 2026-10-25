# macOS / iOS 共享应用目录图标

2026-10-24：原生两端共用图标映射、来源选择、图片下载 / 解码和异步显示组件。

## 运行时在线清单、本地缓存与内置快照

- 素材预览：<https://icons.yunle.fun/app-assets>
- 在线 JSON：<https://icons.yunle.fun/app-assets/manifest.json>
- 同源仓库文件：<https://github.com/YunLeFun/icons/blob/main/assets/catalog/app-assets.json>

原生两端运行时读取这份清单。启动时先同步读取上次成功的本地清单，立即显示内容；随后后台刷新。应用保持在前台时每小时检查一次，回到前台按同一间隔检查，手动刷新目录立即拉取。并发刷新合并为一次请求，自动失败重试至少间隔 60 秒，切到后台停止定时检查。

站点读取失败、响应异常或清单校验失败时，尝试同一仓库的 GitHub 原始 JSON。两者均失败则保留上次成功清单；首次安装、缓存损坏或系统清理缓存时使用内置快照。成功下载经过验证的清单后原子写入各自应用沙盒的 Caches/应用标识/catalog-icons/manifest.json。旧缓存不会仅因过期而失效。

**更新已采用图标的 URL / 版本摘要后，运行中的客户端即可获得更新，无需重新构建或发版。** 图标视图观察共享清单，应用目录、详情等已打开页面也会更新。相同 URL 的图标摘要变化也会更换图片缓存键；未变化的清单不触发图标重载。

以下命令现在仅用于更新、核对内置兜底快照（Electron 仍消费固定映射），不是原生图标更新的发布步骤：

```sh
pnpm icons:sync --source https://icons.yunle.fun/app-assets/manifest.json
pnpm icons:sync --source https://icons.yunle.fun/app-assets/manifest.json --check
```

也可传入中心仓库路径 `--source /path/to/YunLeFun/icons`。在线站点不可达时，脚本明确报告并尝试同一仓库的 GitHub 原始 JSON；两个地址均失败则不写文件。同步先验证全部输出，再写入 Electron 的 `apps/desktop/shared/app-icons.ts` 和原生共用的 `apps/ios/YunleFun/Services/CatalogIconAssets.generated.swift`，两份记录同一清单 SHA-256。

普通构建不依赖在线清单或兄弟仓库。原生 App 携带固定映射兜底，运行时自动读取在线清单；这里没有修改线上应用数据库。清单缓存保存的是已验证的 URL 与版本信息，图片继续使用现有内存缓存与 HTTPS 加载，不能将清单缓存理解为全量图片已离线下载。

只消费已采用的 `desktopAsset`；正式来源从 `kind: official` 的 `source.url` 读取，其栅格缩略图作为备用。生成图只使用已选定的 `thumbnail`，不提升候选或历史图的采用状态。Saier 保持已确认的画笔稿。

## 选择和失败回退

有运行时清单（包括上次成功的本地缓存）时：

1. 应用明确提供的深色完整图标（深色外观下）。
2. 清单选定的正式来源及其缩略图；它们优先于公共目录中尚未更新的旧图标资料。
3. 应用自己的完整图标、透明主体与旧 Logo。
4. 清单选定的生成缩略图，以及内置快照中的正式资源和缩略图。
5. 所有图片来源均不可用后显示 emoji / 首字。

首次安装且清单尚未获得时，沿用应用完整图标 → 内置正式资源 → 主体 / 旧 Logo → 内置缩略图的顺序。在线清单缺少某个 slug 时，该应用仍可使用内置资源。
加载期间使用中性加载状态，不闪现 emoji。完整图标保留自己的背景，透明主体 / 旧 Logo 使用平台语义底色，两端统一按尺寸的 22% 连续圆角裁切。私有、工坊、所有者和个人市场修订不会因 slug 与公共应用相同而继承公共品牌图标。

两个已知失效地址在原生来源解析中替换为中央清单的正式来源，URL 去重；开发者新提供的其他 URL 保持不变：

- 星纸：`https://play.yunle.fun/games/paper-star/icon.png` → `https://assets.play.yunle.fun/games/paper-star/runtime/v2/icon.png`
- SMAP：`https://smap.yunle.fun/smap-logo.svg` → `https://smap.yunle.fun/smap-app-icon.svg`

## 共享实现与验证入口

macOS 直接编译 iOS 目录下的 `ApplicationIconSource`、`CatalogIconAssets.generated`、`CatalogIconStore`、`ApplicationImagePipeline`、`SVGIconDecoder` 和 `ApplicationIconImage`，没有第二套加载逻辑。两端固定 SwiftDraw 0.29.0 并打包许可证。HTTPS 限制、SVG 资源策略、32 MB 内存缓存、请求合并、4 项并发与失败退避沿用同一实现；所有候选均有机会被尝试。

共享的 `CatalogIconStoreTests` 另外覆盖在线主站 / 镜像失败、缓存重开 / 损坏、原子缓存保留、并发合并、刷新间隔和响应式更新。下载响应以流式读取限制为 2 MB，验证 schema、唯一 slug、已采用状态、图片元数据、HTTPS 地址与摘要格式后才能替换当前清单。

共享的 `ApplicationIconTests` 与 `CatalogIconAssetsTests` 覆盖正式图优先、深色选择、失效 URL 修正、私有修订隔离、SVG 解码 / 拒绝、请求合并、失败退避及超过 10 个来源后的最终回退。iOS 另外保留上传标准化与浅深色渲染测试。

`PublicIconLiveTests` 同时编入两端独立的 LiveValidation scheme，读取真实运行时清单、验证缓存落盘及重开，逐项读取线上公开目录并实际解码，要求所有目录应用都有图片候选。它不属于离线日常测试，也不读取测试账号。

## 运行时刷新验证

- macOS：25 项图标 / 清单 / 缓存测试通过；最后新增的无内置快照应用场景与缓存测试另复测 9 项通过。
- iOS：应用与测试目标编译通过，27 项图标 / 清单 / 缓存测试全部通过。复用设备首次启动遇到 launchd 服务错误，重试后成功完成；结束后恢复 Shutdown，没有创建或遗留临时设备。
- 真实线上验收：2 项通过，在线清单下载、缓存落盘与重开成功，25 个公开应用图标全部成功解码。
- macOS 正常应用启动自动下载并缓存 28 项清单；实际点击刷新目录后，缓存写入时间更新，已查看界面并保存截图。
- 同步脚本 / 桌面图标 10 项通过，ESLint、内置快照一致性与 `git diff --check` 通过。

本轮摘要和截图保存在 `apps/macos/build/validation/runtime-icons/`；清单源 SHA-256 为 `607b3965012b879afd8bf04ec2b4757c7e92ab3efb1eafe58edb0aff7e5ffcf4`。用于回归运行时清单机制，下次同范围验收通过后可回收本轮原始 xcresult，保留必要摘要。构建 / 测试临时日志目录已回收，继续复用依赖和增量缓存。

客户端需先安装包含本机制的版本；此后同一清单协议内的图标新增、地址 / 版本更新无需重新发版。未发布 iOS 分发包，未写入线上应用数据库或中央素材仓库。

## 首轮固定快照接入验证（历史）

- 同步脚本 / 桌面图标：10 项通过；相关脚本 ESLint 与 `git diff --check` 通过；在线源与本地快照一致。
- macOS：13 项图标单元测试、2 项线上测试通过。线上 25 个应用全部成功解码，包括星纸与 SMAP，以及做菜、云栈、云乐坊间的 SVG。
- iOS：应用及测试目标编译通过，15 项图标测试通过，包括上传标准化、浅深色渲染和共享来源回退。
- macOS 已重新构建、启动并查看真实目录；截图与测试摘要保存在 `apps/macos/build/validation/icons/`。
- iOS 复用已有空闲的 `iPhone 18 Pro`（`4502D5E9-9630-4AF0-9050-3C9109139FD0`），完成后恢复 Shutdown；未新建模拟器，未操作其他任务的 Cook iPad。构建日志使用任务独占临时目录并自动回收，依赖与增量缓存继续复用。

这次是客户端修复，未发布新的 iOS 分发包，也未改写线上应用记录。
