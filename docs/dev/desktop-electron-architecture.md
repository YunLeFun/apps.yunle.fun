# 云乐坊 Electron 桌面端架构与模板接入方案

更新日期：2026-10-14。状态：现有 Web／Capacitor 工程已迁入 `apps/mobile`，桌面入口在 `apps/desktop` 接入，改造在 [产品 PR #41](https://github.com/YunLeFun/apps.yunle.fun/pull/41) 中 review。通用模板已在 [PR #6](https://github.com/YunLeFun/vitesse-nuxt-electron/pull/6) 升级并通过三平台 CI；本文的多标签、产品登录与宿主授权等完整桌面能力仍分阶段实现。模板验证与产品验证分别验收。

当前独立 PR 工作区已基于最新 `main` 整理，排除了原本机工作区未提交的其它功能；根 lint、Web／移动类型检查、475 个单元测试、59 个 Nuxt 测试、5 个 Chromium smoke、生产构建与服务端运行依赖检查通过。桌面 lint、类型、70 个单元测试与 2 个真实 Electron E2E 通过，失败 trace 保存已实测；macOS arm64 的品牌 `.app`、DMG、ZIP 以及包内运行时、构建记录／SHA256 与真实启动校验均通过。迁移阶段的原生工程编译和生产 API 记录见[验收说明](./monorepo.md#验证迁移)，不替代当前 PR 的原生工程验收。产品三平台 CI 已触发，但 GitHub Actions 预算阻止 runner 启动，远端跨平台执行尚未验收；签名、正式发布和跨版本更新另行验收。

本次桌面接入提供匿名公开目录及允许开放的云应用容器，复用 `packages/app-core` 的 AppRecord、记录转换、域名／图标和目录快照。主进程从固定公开 API 获取和缓存目录，校验审核、公开和发布状态；应用无需登录、会员或付费才允许打开。离线只显示显式免费 slug 白名单，在线成功结果完整替换缓存，目录为空也不自动回退旧列表。目录刷新时，相同 slug 与规范化后的完整 URL 保留正在运行的视图、历史及会话，并同步变化的文档 ID；应用下架、访问门槛或目标 URL 改变才关闭。本次不建立账号、云币、云居、PKCE 或宿主 SSO，guest 不接收账户 token；下文这些能力属于后续架构目标。

推荐移动端与桌面端继续在 `apps.yunle.fun` 产品仓库协作，首版保留 Nuxt/Vue 业务代码。桌面容器使用 `BaseWindow + WebContentsView`，构建采用 Nuxt 静态客户端、独立 Vite 主进程/预加载构建、Electron Forge 打包。产品仓库现阶段保持私有，客户端自动更新关闭；后续更新接入使用官方 `update-electron-app`。移动与桌面分别管理构建产物、平台配置和发布。`vitesse-nuxt-electron` 保持为独立的通用模板，云乐坊业务留在产品仓库。

当前桌面界面采用 macOS App Store 的精选内容与应用列表，以及紧凑的侧栏和工作区。侧栏提供探索、全部应用、最近打开、真实目录分类及正在使用的应用；搜索结果在主区域显示。精选和最近列表都从当前允许打开的目录中匹配，不会恢复下架或需要付费的应用。最近打开仅在本地保存最多 20 个 slug，不保存账户、URL 或 token。应用成功加载后才记录，目录文档 ID 更新不影响匹配。

精选横幅作为在线装饰媒体发布到 COS 的公开 HTTPS 对象，二进制不进入 Git 或桌面安装包；原生品牌图标仍在仓库中维护。固定对象地址位于 `apps/desktop/shared/editorial-media.ts`，只有它的 Origin 获得 shell `img-src` 许可，不扩展脚本、API 或 frame 来源。图片请求使用 `no-referrer`；地址留空、无效或加载失败时只隐藏插画，保留橙色背景、文案和真实应用打开入口。替换同一 COS 对象可以更新媒体，变更路径或 CDN Origin 时需更新配置并重新验证。媒体维护说明位于 `apps/desktop/public/images/README.md`。

应用目录的 28 个固定图标同样存于 COS，覆盖在线与离线目录。新设计强调简洁主体、居中留白和小尺寸辨识；正式品牌标志按来源复用。256px WebP 合计 135,562 字节，PNG 源图与素材不进入 Git 或安装包。加载失败或未知应用保留同尺寸 emoji 回退，旧图片节点的迟到错误不能影响新图；固定清单不会接受远端任意 URL。完整设计与维护方式见[目录图标](./desktop-app-icons.md)。

首版保持一个 guest：返回目录或进入关于页时隐藏原生视图，继续使用时恢复同一网页；明确关闭或访问策略撤回才销毁。macOS 使用原生 `hiddenInset` 交通灯和侧栏 vibrancy，Windows／Linux 保留原生窗口框。工具栏高 52 CSS px，主进程另外保留至少 52 DIP 的顶部安全区域；shell 整页刷新或崩溃会清除旧 viewport。浅色、深色和跟随系统外观同时同步 Nuxt 界面与 Electron `nativeTheme`。布局常量位于 `apps/desktop/shared/window-layout.ts`。

本方案依据产品源码与后续能力设计，不能据此认定所有能力已在生产发布。实际模板接入来源为 PR #6 分支的 `3821916`，包含开发重建队列和退出治理；此前模板运行基线 `267ac2ca55c0ab7ba68b0b40cae9def5d656eccb` 的 [CI](https://github.com/YunLeFun/vitesse-nuxt-electron/actions/runs/38390155087) 已验证 macOS arm64、Windows x64、Linux x64。以下版本是模板基线，产品依赖以各应用 manifest 和工作区锁文件为准。

## 1. 产品与代码复用

首版面向 macOS 和 Windows，提供云居、寻乐、工坊、账户与多应用标签页。Linux 保留架构兼容，待桌面环境、系统密钥存储和发布包验证后再支持。独立应用窗口、多账号网页配置和分屏放在后续阶段。

| 现有实现                                                       | 桌面处理                                                                                            |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `app/stores/homeScreen.ts`、`app/composables/useHomeScreen.ts` | 复用安装、排序、最近使用与云同步；网页 Cookie 和浏览器工作区不进入云居同步                          |
| 应用目录、详情、评价、工坊、寻乐的数据与业务逻辑               | 复用；逐步把业务内容从 Ionic 页面包装中提取为共享 Vue 组件                                          |
| `app/composables/useBrowser.ts`                                | 保留调用入口，改为调用平台 Adapter，不再把 Electron 判为普通浏览器                                  |
| `app/host-runtime/index.ts`                                    | 抽出无 Capacitor 依赖的协议类型，增加 Electron Adapter                                              |
| `app/utils/host-identity-broker.ts`                            | 复用请求校验、可信展示信息解析和一次性授权码解析                                                    |
| `identity-broker`、`session-policy`、`inappbrowser` 插件       | 用能力探测选择实现，替换散落的 `Capacitor.isNativePlatform()` 判断                                  |
| `app/plugins/api.ts`、`server/`                                | 复用 HTTPS API、Bearer 与刷新逻辑，增加桌面基址和 Origin 适配；服务端继续部署在云端                 |
| `app/app.vue`、`app/pages/tabs.vue`                            | 保留在移动入口；桌面使用独立 `app.vue`、侧栏、标签栏和键盘操作，共享页面内容逐步从 Ionic 包装中提取 |
| 微信 SDK、StoreKit、状态栏、震动、扫码等移动能力               | 按能力探测禁用或替换；桌面支付使用服务端支持的网页渠道                                              |

现有工程已迁入 `apps/mobile/`，以上现有业务路径均相对该应用目录。再从实际被桌面复用的模块抽取共享代码；共享包可作为私有 workspace 包使用，不要求发布到 npm。产品工作区与部署入口见 [客户端工作区与部署](./monorepo.md)。

## 2. 进程与模块

```text
Electron main
  ├─ DesktopWorkspace：窗口、标签、视图布局与生命周期
  ├─ GuestSessionManager：持久化 Session 与账户配置
  ├─ NavigationPolicy：导航、弹窗、外链与认证窗口
  ├─ HostIdentityCoordinator：来源证明、授权交互与请求生命周期
  ├─ PermissionBroker：网页权限与云乐坊 JSAPI
  └─ Protocol / Settings / Downloads / Updates
       │
       ├─ shell preload → 本地 Nuxt 主界面（独立宿主 Session）
       └─ guest preload → 云应用 WebContentsView（独立应用 Session）

本地 Nuxt 主界面 → 现有 CloudBase / HTTPS API / SSO 服务
云应用页面       → 该应用自己的 HTTPS API / BFF
```

主进程负责 Electron 对象、窗口位置、网页来源验证与原生能力。Nuxt 主界面负责目录、业务数据、云居、账户展示和桌面交互。云应用页面只控制自己的网页。

`DesktopWorkspace` 对外提供小接口：打开应用、执行会话操作、订阅快照。导航历史、窗口归属、布局、失效回收和崩溃恢复留在模块内部，不把 Electron 对象或通用 `ipcRenderer` 暴露给 Vue。

现有 `HostRuntime` 方法和事件尽量保持兼容。桌面新增的激活、前进、后退、刷新等工作区操作独立于移动授权协议，避免所有平台被迫实现桌面专属能力。

建议目录如下，新增目录是计划，并非当前已有代码：

```text
packages/host-contracts/           # 无 Capacitor / Electron 依赖的协议与能力类型
apps/mobile/app/host-runtime/      # Web / Capacitor 实现与能力探测
apps/desktop/
  app/
    app.vue                       # 独立桌面入口
    host-runtime/                 # Electron Adapter 与能力探测
    components/workspace/         # DesktopFrame、Sidebar、TabStrip、AppViewport
    composables/useDesktopWorkspace.ts
    plugins/platform.client.ts
  electron/
    main/
      index.ts
      workspace/                  # 视图、窗口、布局、生命周期
      sessions/                   # profile、partition、数据清理
      identity/                   # pending request、来源校验、授权窗口
      policies/                   # 导航、外链、权限
      protocol.ts
      downloads.ts
      updates.ts
    preload/
      shell.ts                    # 只向本地主界面开放宿主控制接口
      guest.ts                    # window.ylf 协议，默认仅主文档
  vite.electron.config.ts
  forge.config.cjs
  scripts/
    dev-desktop.mjs
    build-desktop.mjs
```

公共协议用普通可取消监听句柄替换对 `PluginListenerHandle` 的类型依赖。Adapter 选择通过应用入口与预加载提供的版本化能力完成，不伪造 Capacitor 的平台状态。

## 3. 内嵌 Web 应用与布局

每个窗口使用一个 `BaseWindow`。本地 shell `WebContentsView` 绘制侧栏、标签栏、导航条和站内内容；打开云应用时，主进程把另一个 guest `WebContentsView` 放入内容区域。首版同一窗口一次显示一个云应用，其他标签按会话策略保活。

`WebContentsView` 由 Electron 原生 View 管理，不属于 Vue DOM。Vue 的 `z-index` 和 Teleport 不能直接覆盖 guest 页面。统一由 `DesktopWorkspace` 管理视图顺序：授权采用本地、受限的模态 `BrowserWindow`；跨页面菜单与遮罩使用原生菜单、受限覆盖视图或暂时隐藏 guest。隐藏 guest 保留页面，不表示销毁。

`AppViewport` 只报告指定内容槽的矩形，主进程校验并限制在窗口内部，按窗口大小、页面缩放转换为 DIP。不能简单乘 `devicePixelRatio`。移动窗口、缩放、全屏、侧栏折叠和多显示器切换均重新计算；guest 永远不能覆盖宿主的地址/来源和退出入口。

`displayMode: immersive` 在桌面只影响应用内容区域和可选工具栏，页面不能隐藏云乐坊工作区的退出入口。`window.ylf.getEnv()` 扩展桌面平台标识与能力描述；震动等不存在的能力由 `canIUse()` 返回 false，不返回虚假的成功。

具体窗口模型参考 [WebContentsView](https://www.electronjs.org/docs/latest/api/web-contents-view)。选用 `BaseWindow` 后必须显式释放关联 WebContents，参见 [资源管理说明](https://www.electronjs.org/docs/latest/api/base-window#resource-management)。

## 4. 会话、账号与内存

Electron 的 Session 是 Cookie/存储/权限空间，云乐坊的 HostSession 是打开的页面；二者不是一一对应。一个应用的多个标签可共享一个 Electron Session，每个标签拥有独立 WebContents。网页认证弹窗按需要继承发起应用的 Session。

| 对象           | 建议配置                                                                  |
| -------------- | ------------------------------------------------------------------------- |
| 本地主界面     | 独立 `persist:ylf-shell`，仅本地打包代码                                  |
| 云应用         | `persist:ylf-app-<appKey>-<profileKey>`；key 使用稳定、不含凭据的本地标识 |
| 访客临时页     | 无 `persist:` 的 Session，关闭后不作为持久化配置恢复                      |
| 外部浏览器认证 | 系统浏览器拥有自己的 Cookie，结果通过绑定请求的回调传回                   |

`profileKey` 隔离宿主账号和未来的网页多账号配置。多个第一方应用也不默认共享宿主 Session，它们通过 SSO 获取各自的登录态。持久化 partition 名必须跨版本稳定，并有数据版本迁移方案。

标签状态为 `loading → active ↔ background → discarded / closed`。后台保活保留页面状态，但仍占内存；`discarded` 释放 WebContents，之后只能重新加载 URL，不能承诺恢复任意网页的未提交表单、DOM 或播放器状态。默认采用有限保活数量，结合内存压力回收最近未使用的后台页；音视频、捕获、进行中的认证和明确要求保留的任务避免自动回收。

工作区落盘只记录标签顺序、应用 id、窗口位置与可安全恢复的 URL。拒绝保存 OAuth 回调、授权码、token、支付回调等敏感 URL；启动时延迟加载后台标签。崩溃只影响对应页面，显示恢复入口。首版不承诺网页离线可用。

账号切换先停止旧配置的页面与授权请求，再选择新配置的 partition，最后刷新云居数据。退出时清理宿主凭据与宿主派生的第一方身份会话。第三方网站会话只能按明确的数据保留策略保留在旧配置中，不能自动交给新宿主账号。下载到用户指定目录的文件不随会话清理删除。

## 5. 导航与弹窗

导航信任与 JSAPI 授信分开：网站能被打开，不代表能调用宿主能力。

- 应用 id、目录入口和能力策略由可信目录解析。shell 传来的标题、URL 和 `trustedHosts` 仅作输入，主进程不把这些字段本身当授信证据；来源无法验证时只作为普通网页运行。
- 普通 HTTPS 页面可在应用容器导航，跨 Origin 时重新评估授权；已发出的授权请求绑定原文档，导航后失效。
- 普通 `target=_blank` 进入该应用拥有的新标签或窗口；对认证弹窗保留合法的 opener、Session 与 `postMessage` 语义，不能一律转换后破坏登录。
- OAuth 有明确提供方限制时使用系统浏览器与认证 Adapter。跨站导航不直接复制任何 Cookie 或宿主 token。
- `file:`、本地 shell scheme 和任意系统协议不向 guest 开放。外部协议只在明确允许的操作中经校验交给系统。
- 首版不实现通用浏览器扩展、DRM 保证或任意网页的兼容承诺。需用真实云应用验证输入法、剪贴板、下载、弹窗、音视频和屏幕共享。

新窗口策略由主进程的 `setWindowOpenHandler` 和导航事件统一控制，参考 [webContents](https://www.electronjs.org/docs/latest/api/web-contents)。

## 6. 宿主登录与内嵌应用 SSO

两个流程分开设计：云乐坊主界面登录自己的账号；guest 应用通过 `window.ylf.authorize()` 获取自己的登录态。

内嵌应用沿用已有 `identity:bootstrap + nonce + PKCE S256` 协议：

```text
guest window.ylf.authorize(request)
  → guest preload 的固定通道
  → main 验证真实发送 frame / Origin / 应用归属，建立 pending request
  → 可信 shell 复用 /api/auth/sso/resolve 解析 Registry 策略
  → 宿主展示注册表提供的应用、来源、账号与权限
  → shell 复用 sso-ticket / issueSsoCode 签发短时一次性 code
  → main 再验证 pending request 和原文档仍有效，仅向发起页面返回
  → guest 在自己的 Origin / BFF 用 PKCE 兑换自己的会话
```

继续复用 `host-identity-broker.ts` 与身份插件中的纯逻辑，替换 Capacitor 事件和原生确认的 Adapter。`prompt: consent` 使用宿主可信弹窗；`select_account` 和 `openAuthSession` 使用外部认证实现。取消必须作为取消返回，不能静默切换登录路径。

主进程每次调用都检查 `sender`、`senderFrame.origin`、主 frame、主进程维护的应用映射和协议参数。`sourceOrigin` 由 Electron 提供，不能相信页面传来的值或仅检查地址栏 URL。pending request 还绑定会话 id、文档 generation、nonce、超时和一次性消费状态；页面导航、关闭、登出或账户切换立即取消，异步结果回来时再次检查。

普通第三方网页没有第一方身份授权能力。`trustedHosts` 可以用于审核后的某项 JSAPI 授信，但不代替 SSO Registry 的精确 client、Origin、redirect URI 和 scope 校验。

主界面登录初期复用现有手机号、邮箱与 CloudBase 状态管理。OAuth 通过桌面认证 Adapter 打开系统浏览器。已有 `yunlefun://` 移动协议不能直接照搬为桌面实现：需验证 desktop 安装注册、冷启动和 Windows second-instance，并避免与 Android/macOS 运行的其他客户端争抢 scheme；必要时使用独立桌面 scheme 或经 Registry 校验的 loopback 返回方案。

现有 `desktop-auth` 的设备会员 entitlement 不等于全功能 Apps 登录。不能把该 token 当 CloudBase access token 或把 Skykeeper 客户端登记直接复用给桌面云乐坊。

现有 SDK 使用本地持久化，用户 store 还有 Cookie/localStorage 镜像，不能声称加一个加密文件就已保护所有凭据。验证阶段可以在独立、可信 shell partition 中复用 SDK；生产凭据方案须先验证 SDK 是否支持受控存储，再决定系统安全存储 Adapter 或凭据代理，并清除旧镜像。系统加密需检查实际后端，Linux 的弱回退不能被当成可靠密钥库。参考 [safeStorage](https://www.electronjs.org/docs/latest/api/safe-storage)。

## 7. 预加载与权限

shell 和 guest 使用两个独立 preload，均采用 `contextIsolation: true`、`sandbox: true`、`nodeIntegration: false` 和 `webSecurity: true`。sandbox preload 构建成独立、无运行时代码拆分的 CJS 文件，避免不受支持的 Node/ESM 导入。

shell preload 只暴露带 schema 校验的宿主操作、事件和取消订阅。guest preload 兼容 `window.ylf` 的版本化协议，只暴露固定方法，不暴露 `ipcRenderer`、任意通道、文件路径、主进程 fetch 或 Electron 对象。

权限模块区分三种判断：页面是否可导航、页面是否获准调用某项云乐坊 JSAPI、用户是否授权某项 Chromium 设备能力。摄像头、麦克风、通知、剪贴板和屏幕捕获按实际请求 Origin 展示，默认不自动允许。检查权限与请求权限的 handler 都要实现；授权记录按应用、profile 和精确 Origin 存储。

身份弹窗来自可信本地页面，应用名与权限文案由 Registry 解析；guest 不能创建伪装为宿主的授权窗口或选择自己的可信展示文本。保留现有 `canIUse` 降级路径。

参考 [上下文隔离](https://www.electronjs.org/docs/latest/tutorial/context-isolation)、[IPC 发送方验证](https://www.electronjs.org/docs/latest/tutorial/security#17-validate-the-sender-of-all-ipc-messages) 和 [Session 权限](https://www.electronjs.org/docs/latest/api/session)。

## 8. Nuxt 构建、网络与开发

移动与桌面使用各自的 Nuxt 配置和 package.json，桌面入口固定为 desktop，并通过跨平台脚本设置需要的环境值。每个应用在自己的目录生成 `.nuxt`、`.output/public`、Electron 产物与安装包；`apps/mobile` 的 Web 部署和 Capacitor 静态构建也应使用独立构建任务与缓存。目标值和 API 地址烧入构建，第三方页面不能通过 URL 参数改变环境。

移动入口保留 Ionic 路由；桌面入口使用独立导航、容器尺寸与交互。逐页抽取共享 feature 组件，移动页面和桌面页面作为薄组合层。Nuxt Layer 只放可复用的插件、composables 和组件，不整体继承移动入口的 Ionic 配置、原生插件或 `app.vue`；项目文件优先级更高。

当前主界面从固定的自定义 Origin `app://shell` 加载本地静态产物，已通过打包后的真实页面验证。提前注册 standard/secure/fetch 等所需能力，不开启 CSP bypass；只在 shell Session 注册静态资源 handler，不在 guest Session 注册。handler 限制 host 和资源根目录，阻止路径穿越，正确处理 SPA 路由、MIME 和缺失资源。

静态桌面包不启动 Nitro，不打包 `server/` 运行时。`$api` 显式指向 `https://apps.yunle.fun` 或 development 地址；继续使用 Bearer，不向任意 guest 请求注入宿主 Authorization。桌面 Origin 必须在 development 验证现有 CORS 与 CloudBase 登录/域名策略，当前 `origin-rules.ts` 仅接受 HTTP/HTTPS，不能直接配置自定义 scheme 字符串期待生效。服务端可按验证结果增加精确 native Origin 规则。不能通过关闭 `webSecurity` 或放行 `Origin: null` 解决问题。

开发脚本启动 Nuxt、等待健康响应和 preload 构建完成后再启动 Electron，并负责退出、端口冲突、超时与主进程重启。guest 的已打开页面不会因为 shell HMR 无条件重建。正式包不包含开发地址、Nitro 服务端 Secret 或开发调试开关。

参考 [Electron 自定义协议](https://www.electronjs.org/docs/latest/api/protocol) 与 [Nuxt Layer 优先级](https://nuxt.com/docs/4.x/guide/going-further/layers)。

## 9. 当前模板与框架选择

`vitesse-nuxt-electron` 现在可作为 Nuxt + Electron 的通用起点。模板已具备静态界面、安全 preload、受限 IPC、WebContentsView 示例和 Forge 发布流程；产品匿名目录和共享应用数据已接入，账号和宿主 SSO 继续分阶段建设。

| 核对项   | 模板当前实现                                                                                     | 产品接入或后续完善                                                                                                                        |
| -------- | ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| 依赖基线 | Nuxt 4.6.1、Vue 3.5.44、Vite 8.3.4、Electron 44.7.0、Forge 8.0.1、pnpm 12.11.2，构建使用 Node 24 | 产品先采用 Nuxt 4.4.8、Vue 3.5.40、TypeScript 5.9.3、pnpm 11.13.1；renderer Vite 7.3.6，主进程别名 Vite 8.3.4，Electron／Forge 沿模板基线 |
| 渲染隔离 | shell／guest 独立 sandbox preload，固定接口及发送者／主 frame／Origin 校验                       | 增加云乐坊宿主协议和授权生命周期，保留原生能力授信检查                                                                                    |
| 本地加载 | `app://shell` 服务 `.output/public`，CSP 使用内联脚本哈希，已验证路由刷新                        | 验证产品自定义 Origin、API、登录和最终 Nuxt／Ionic 产物                                                                                   |
| 内嵌应用 | 两个文档站示例、按应用持久化 Session，一次保留一个 guest                                         | AppManifest、ViewManager、多标签与账号配置隔离；登录弹窗、下载和请求权限                                                                  |
| 开发编排 | 端口和健康检查、主进程／preload 构建、重建队列、变更重启与退出治理                               | 已扩展 `shared/` 与 `app-core` 监听并验证启动／退出清理；窗口状态、原生菜单和故障诊断后续建设                                             |
| 打包     | Forge，静态客户端和运行时依赖进入 ASAR；生产二进制 fuse 校验                                     | 产品通过官方 Forge Core API 兼容 pnpm 11，物化完整生产依赖树；macOS arm64 `.app`／DMG／ZIP、ASAR 与 fuses 已验证                          |
| 发布更新 | macOS DMG／ZIP、Windows Squirrel、Linux deb；草稿发布和 `update-electron-app`                    | 配置证书、验证签名／公证及真实跨版本更新；按产品需求选择更新分发源                                                                        |
| CI       | 模板三平台 CI 通过，macOS x64 另配置发布任务                                                     | 产品三平台 CI 已触发，但 Actions 预算阻止 runner 启动；远端三平台尚未验收，产品 macOS x64 与真实安装发布测试仍需补充                      |
| 依赖维护 | 人工升级，Dependabot 自动 PR 已停用；精确发布信任例外和 DevTools 兼容补丁已记录                  | 清理过期例外，跟进上游修复；运行时和开发工具链审计分别跟踪                                                                                |

首版继续 Nuxt 的理由是复用现有业务：请求插件、运行时配置、路由和账户逻辑已经使用 Nuxt 接口。桌面只生成静态 SPA，服务端留在云端。移动导航和 Capacitor 判断需要平台适配；更换界面框架不会替代这些工作。

| 方案                                              | 适用情形                                                                       |
| ------------------------------------------------- | ------------------------------------------------------------------------------ |
| Nuxt 静态界面 + 独立 Vite 主进程／preload + Forge | 当前推荐。复用现有 Nuxt 业务，Electron 对象和生命周期由独立宿主模块管理        |
| Vue + Vite 界面 + Electron + Forge                | 从零开发、主要承载标签和远程网页的独立容器；迁移现有 Nuxt 业务前需明确适配成本 |

当前实现直接调用 Vite 构建主进程和 preload，由 Forge 执行打包，未采用 Forge 的 Vite 插件或 `nuxt-electron`。宿主接口尽量独立于界面框架，后续调整 renderer 时可继续复用窗口、会话和权限实现。

产品 `scripts/forge.mjs` 调用官方 `@electron-forge/core@8.0.1` 的 programmatic API 执行 package／make／publish，保留 makers、hooks、重建和 fuses；Forge CLI 的旧连字符配置检测无法识别 pnpm 11 workspace 的 camelCase 设置，根依赖策略保持不变。macOS DMG 的 `preMake` hook 只为声明依赖中缺失的 `macos-alias`／`fs-xattr` 绑定执行本机 Node rebuild，不安装新依赖或加入 Electron 运行时；Linux deb maker 显式指定 `name: yunlefun` 与 `bin: YunLeFun`，避免 scoped 包名和程序名不匹配。

构建使用移动端既有云乐坊标志导出的 ICNS／ICO／PNG，并同步桌面 favicon／PWA 图标。Forge make 结束后只收集本次返回的安装器，在 `out/artifacts` 写入产品／Electron 版本、平台／架构、Git commit／dirty、分发签名配置与 SHA256 构建记录。根 `verify:desktop`、`verify:desktop-artifacts` 和 `verify:desktop-launch` 分别检查包内运行时、分发文件和真实启动；步骤与各平台格式见 [桌面构建与私有内测](./desktop-build.md)。

发布入口执行 `check:desktop-release` 的相同检查，要求稳定 `v<桌面版本>` Tag 与配置仓库一致；Forge 8 的 platform／arch 通过 `makeOptions` 传递。关闭自动更新时允许私有 draft 分发的配置，开启公共更新源时要求 `GITHUB_REPOSITORY_VISIBILITY=public`。当前只提供构建和校验脚本，没有执行发布。

模板只维护通用运行、构建、隔离、打包与演示，业务留在产品仓库。通用修复回流模板；接口稳定且有多个实际消费者时再抽宿主包。参考 [模板接入指南](https://github.com/YunLeFun/vitesse-nuxt-electron/blob/codex/upgrade-nuxt-electron/docs/adoption.zh-CN.md)、[Electron 官方打包教程](https://www.electronjs.org/docs/latest/tutorial/tutorial-packaging) 和 [Forge 更新指南](https://www.electronforge.io/advanced/auto-update)。

## 10. 发布与验证顺序

2026-10-14 的独立 PR 工作区通过根 lint、Web／移动类型、475 个单元测试、59 个 Nuxt 测试、5 个 Chromium smoke、生产构建与服务端运行依赖检查，桌面 lint／类型、70 个单元测试、2 个 Electron E2E 和失败 trace 保存验证。macOS arm64 的 Forge make 成功生成品牌 `.app`、DMG、ZIP，实际应用 ICNS 与提交的图标一致；`verify:desktop`、`verify:desktop-artifacts`、`verify:desktop-launch` 和标准 `shasum` 均通过，安装包与 manifest 完整性已验证。关闭自动更新时的私有 release 配置检查通过，没有执行发布。[三平台 Desktop CI](https://github.com/YunLeFun/apps.yunle.fun/actions/runs/38426634680) 已触发，GitHub 注释为“Actions budget is preventing further use”，所有 job 均没有进入步骤。恢复预算或接入可用 runner 后仍需实际运行并验收三平台，不能将此轮失败归因于代码。

2026-10-13 在原本机工作区的迁移阶段已验证本地生产 Node server 的 `/`、`/tabs/home` 和 `/login` 返回 200，匿名 `/api/apps/public` 返回 200 JSON 与 25 个公开应用。打包后的 macOS ASAR `.app` 从 `app://shell/` 启动，线上目录为 `online`、25 项且无错误；实际 `cook.yunle.fun` 在 WebContentsView 加载“食用手册”，guest 的 `require` 和 `window.desktop` 均为 `undefined`。当时的 Chromium、iOS Simulator、Android、macOS 打包、ASAR／fuses、原生启动与开发退出清理记录保留在[迁移验收说明](./monorepo.md#验证迁移)。该工作区包含其它未提交功能，当前 PR 的原生工程与正式部署仍需独立验收。

当前保留 Nitro 安全覆盖的 esbuild 0.28.1；旧 unplugin 的 `^0.25` 声明产生两项 optional peer 提示，实际构建和测试通过。

1. **通用模板基础已完成**：静态 Nuxt renderer、隔离 preload、自定义协议、单 guest 示例、健康检查和三平台 CI。继续完善统一配置、AppManifest 与 ViewManager，形成可供产品接入的小接口。
2. **产品接入验证**：`apps/mobile` 结构迁移和本机原有功能验证已完成，`apps/desktop` 接入安全容器并从 `packages/app-core` 复用公共模块。完整云居／工坊、Electron HostRuntime Adapter、自定义 Origin 下 CloudBase 登录刷新和数据同步继续逐项接入；凭据持久化和认证回调单独验收。
3. **桌面工作区**：侧栏、标签、导航历史、会话隔离、权限、下载、崩溃恢复和有限后台保活；桌面授权接入既有 PKCE 身份代理。
4. **发布就绪**：macOS 签名/公证、Windows 签名、更新渠道和旧版本升级迁移。macOS 生成 DMG 与更新用 ZIP；Windows 生成 Squirrel Setup.exe、full.nupkg 与 RELEASES。验证真实安装和跨版本更新后再面向用户发布。
5. **后续能力**：独立窗口、网页多账号配置、分屏、产品的 Linux 支持与共享包抽取。模板已能构建 Linux deb，产品登录与系统集成仍需单独验证。

产品自动更新当前关闭。后续方案使用官方 `update-electron-app` 与 Electron `autoUpdater`，默认来源是面向公共 GitHub 仓库的 `update.electronjs.org`；草稿版本不会进入用户更新渠道。私有仓库或对象存储分发需要一起调整发布和更新源。Linux 使用包管理器更新。更新源由主进程固定配置；应用名称、Bundle ID、Squirrel 包名、用户数据目录、partition key 和数据版本在首个公开版本前固定。参考 [Forge 更新指南](https://www.electronforge.io/advanced/auto-update) 和 [Squirrel.Windows 产物](https://www.electronforge.io/config/makers/squirrel.windows)。

模板现有测试覆盖来源隔离、iframe 无 guest bridge、受限导航、会话存储、前进后退和关闭回收。产品接入需要补充以下验证：

- 单元测试覆盖导航/权限决策、partition 归属、授权状态机和路径解析，测试对外行为，不镜像实现。
- Electron 集成测试覆盖 shell 与 guest 来源隔离、iframe 调用拒绝、跨源导航后的授权失效、过期请求不回送和账号切换。
- macOS/Windows 安装包 smoke 覆盖 SPA 路由、暗色模式、输入法、弹窗登录、下载、权限、窗口关闭资源释放和更新后登录态。
- 选取几个现有第一方应用及不同开发者的第三方网页验证真实兼容性；跨平台 UI/音视频/系统浏览器回调不能只用开发服务器测试替代。

首个产品实现需要验证 CloudBase 与自定义 Origin 的兼容、SDK 凭据存储接点、桌面认证回调、原生 View 上方的可信弹窗，以及包含业务页面的 Nuxt／Ionic 静态产物。模板的简单静态路由已验证；产品需要按自己的页面和登录流程验收。

## 11. 移动端与 PC 端的仓库组织

推荐一个产品仓库，保留独立的平台入口、工程和发布。云乐坊移动端与桌面端共享账号、应用目录、云居、同步规则和宿主协议，同仓库更便于在一个 PR 中修改并验证这些模块。

采用 `apps/mobile/` 和 `apps/desktop/` 两个应用入口，先迁移已有工程并保持行为，再接入独立桌面界面与共享模块。移动入口已迁入工作区；以下目录中的公共包按实际复用需求建设，详细的桌面业务模块仍是后续目标：

```text
apps.yunle.fun/
  apps/
    mobile/               # 现有 Nuxt 工程；初期也提供 apps.yunle.fun Web 版本
      app/                # 移动页面、Ionic 布局、Web / Capacitor Adapter
      server/             # 现有 Nitro API，只部署云端
      ios/
      android/
      scripts/            # 移动打包、同步、版本与应用内购脚本
      test/               # 现有应用测试与测试配置
      nuxt.config.ts
      capacitor.config.ts
      package.json
    desktop/              # Nuxt 桌面界面、Electron、Forge、桌面测试与脚本
  packages/
    auth/                 # 保留现有包，补齐 workspace 导出与类型
    capacitor-storekit/   # 保留现有移动专属包，桌面入口不引用
    app-core/             # 按实际需求抽取共享业务模块
    host-contracts/       # 后续公共宿主协议及能力定义
  docs/                   # 保留现有文档工作区
  scripts/                # 跨应用校验与仓库工具
  package.json            # 私有 workspace 根，提供统一命令
  pnpm-workspace.yaml
  pnpm-lock.yaml
```

`mobile` 表示当前以移动体验为主的客户端，并不取消浏览器版本。现有 Web 与移动共用 Nuxt 工程，首阶段继续从 `apps/mobile` 构建 Web 部署；等浏览器入口有独立布局或发布需求时再增加 `apps/web/`。现有 `server/` 暂随原工程迁移，Electron 和 Capacitor 安装包都不包含服务端运行时或私密配置；以后需要独立后端发布时再考虑 `apps/api/`。不为尚无独立消费者的代码预建大量包。

迁移核对项：

- workspace 增加 `apps/*`、`packages/*` 并保留 `docs`；保留既有依赖安全策略，重新生成锁文件的 importer，应用依赖归对应 package.json，根目录保留公共工具。
- 当前 `@yunlefun/auth` 和 StoreKit 通过源码 alias 引用，转为 `workspace:*` 前先补齐包的导出与构建；iOS Podfile 的本地插件相对路径、Capacitor 插件发现与 `webDir` 一并验证。
- 移动脚本与对应原生工程一起迁移，修正工作目录、版本读取、资源与测试路径；根 `dev`、`build`、`sync` 等常用命令先提供转发，降低迁移影响。
- CI 按应用执行构建与测试；EdgeOne 保留仓库根安装与构建入口，静态资源目录更新为 `apps/mobile/.output/public`，保持 Nuxt 全栈适配并验证云端 API 运行依赖。外部控制台设置需按 [迁移部署指南](./monorepo.md) 核对。
- 第一轮只验证原 Web 构建与路由、服务端 API、现有测试、Capacitor 同步与 iOS / Android 构建；迁移通过后再接入桌面，便于定位回归来源。

仓库内的共享包使用 `workspace:*`，统一 Node、pnpm 和锁文件管理。Nuxt Layer 用于复用 Nuxt 特有代码；每个应用管理自己的布局和页面组合，项目文件优先于 Layer。共享代码不直接导入 Electron、Capacitor 或移动导航，平台能力通过 Web、Capacitor、Electron 的具体实现提供。

构建缓存和产物按目标隔离。移动商店发布与桌面签名／安装包／更新分开，版本号可以独立推进。平台目录变化验证对应应用；公共协议和业务模块变化验证所有消费者。迁入 workspace 后核对 Forge 项目根目录、运行时依赖收集和 ASAR，不能让安装包依赖仓库外源码或软链接。

独立版本由各应用的 manifest 管理，发布脚本与版本校验按对应应用执行。模板目前使用单应用根 package.json 和 `vX.Y.Z` 校验，迁入 workspace 时需调整工作目录与 manifest 路径。公共 GitHub 更新服务只收集有效 SemVer 标签的正式版本，桌面可保留 `vX.Y.Z`，移动端使用如 `mobile-vX.Y.Z` 的标签；若桌面改用 `desktop-vX.Y.Z`，同步调整 Forge publisher 的 `tagPrefix`、工作流和校验，并更换能识别该命名方案的更新源。参考 [官方更新服务规则](https://github.com/electron/update-electron-app/blob/main/README.md#how-does-this-module-handle-github-release-states)。

`vitesse-nuxt-electron` 继续保持独立通用模板仓库。将经过验证的宿主代码和构建方式接入产品，产品维护自己的依赖与业务，通用改进回流模板。只有产品或团队权限已经独立、共享业务很少时，再考虑客户端分仓；当前无需合并云乐坊所有站点和后台仓库。

参考 [pnpm Workspace](https://pnpm.io/workspaces) 与 [Nuxt Layers](https://nuxt.com/docs/4.x/guide/going-further/layers)。
