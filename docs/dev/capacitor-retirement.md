# Capacitor 使用边界与退役记录

2026-11-05：用户确认旧 Capacitor iOS 客户端没有对外或通过 TestFlight 分发，按未发布客户端退役。历史上传 / 编译记录不作为已分发证明，也不把历史覆盖升级或 Sandbox 未通过项改写为通过。

## 当前边界

| 消费者                | 当前实现                                           | Capacitor 状态                                |
| --------------------- | -------------------------------------------------- | --------------------------------------------- |
| `apps/ios`            | SwiftUI、原生 WebView / 授权服务、`NativeStoreKit` | 不依赖 Capacitor，公共代码已迁入本工程        |
| `apps/macos`          | SwiftUI / AppKit + WKWebView                       | 不依赖 Capacitor，从原生 iOS 目录复用授权协议 |
| `apps/desktop`        | Electron + 独立 preload / IPC                      | 不依赖 Capacitor                              |
| `apps/mobile/android` | `BridgeActivity` + `HostRuntimePlugin`             | 继续维护                                      |
| `apps/mobile/app`     | 浏览器与 Android 共用 Nuxt / Ionic 界面            | 仅宿主适配器直接访问 Capacitor                |
| 旧 `apps/mobile/ios`  | 未分发的兼容主壳                                   | 工程、旧 StoreKit 插件与专用构建脚本已移除    |

`apps/mobile` 继续提供 `apps.yunle.fun` 的页面与服务端 API。Ionic / Konsta 是界面依赖，保留与退出 Capacitor 可以分别处理。

## 已收拢的宿主层

- `app/host-runtime/contracts.ts`：宿主协议、授权请求、会话与可移除的事件订阅，不引用 Capacitor 类型。
- `app/host-runtime/capabilities.ts`：平台事实、应用生命周期、系统浏览器、触感和扫码结果的公共契约。
- `app/host-runtime/adapters/capacitor.ts`：集中注册 Android 宿主插件、映射插件枚举与调用媒体能力；扫码 / 相册插件按需加载。
- `app/host-runtime/index.ts`：只提供公共导出。页面、组合式函数、插件、状态与遥测使用该入口，不再直接引用 Capacitor 包。
- ESLint 同时限制静态 import 与动态 import，只有 `host-runtime/adapters` 可以加载原生插件，避免重新分散到业务代码。

授权协议仍保留来源、主 frame、nonce、PKCE、一次性授权码及账号切换隔离；该重构不向云应用暴露宿主令牌。

## 旧 iOS 退役范围

删除 `apps/mobile/ios` 中受版本控制的工程、`packages/capacitor-storekit`、Web `useIap` / 交易监听、钱包和会员页的旧 IAP 分支，以及旧归档、版本同步和导出脚本。
移除 `@capacitor/ios` 与旧 StoreKit alias。`pnpm sync` 现在仅执行 `cap sync android`；旧 `open:ios` / `dev:ios` / `run:ios` / `build:ios` / `sync:version` 入口已退出。

原生 iOS / macOS 原来从旧目录编译的文件先迁移，再删除主壳：

- `apps/ios/YunleFun/WebRuntime/WebViewController.swift`：保留现有原生行为和原有未提交改动，仅删除失去消费者的 Capacitor 条件分支。
- `HostAuthorizationProtocol.swift`：源码原样迁移，iOS 与 macOS 共用。
- `HostWebViewSupport.swift`：保留图片、授权展示、会话策略与身份清理等共享支持代码，删除 `CAPPlugin` 实现。
- `Resources/BrandAssets.xcassets`：保留原生 App 正在使用的图标和品牌资源。

新原生客户端的 `NativeStoreKit`、验单 / 账本服务、已购恢复及原生本地 StoreKit 测试配置保持独立。Web / Android 只保留在线支付，并在用户返回后执行对账与账户刷新。
旧本地数据读取工具仍可用于个人数据恢复；未执行卸载、擦除或删除本机旧 App 数据。旧目录里的本地归档 / 导出产物没有随 Git 工程删除，已加入明确忽略规则，避免误提交。
原先未提交的旧 WebView 源码在去除条件分支前另有本机副本与摘要，原有其他原生任务改动继续保留。

原生发布使用[SwiftUI TestFlight 流程](./testflight.md)。兼容的 App Store Connect 发布辅助脚本仍保留供原生流程回退，不依赖已退役工程。

## 验收范围

本轮验证通过：734 项移动单测、78 项 Nuxt 测试、5 项 Chromium 登录回归、72 项原生授权 / 会话 / 钱包专项、12 项分享卡回归及 1 项独立进程回收测试。
Web 类型检查、生产构建、Android 同步与 Debug 整包构建、iOS / macOS 编译、文档构建、冻结锁文件安装与安全审计均通过。

首轮直接执行原生专项为 71 通过 / 1 失败：测试结束时 WebKit 仍占用命名测试存储，失败证据保留。
随后按仓库既有 CI 的 collect / verify 流程复验，72 项专项与独立回收测试通过；核对 32 项归属记录，剩余存储为空、目录已删除，验证进程与创建进程不同。
没有更改原生测试断言或增加跳过来隐藏首轮失败。
未分发旧壳无需作为产品升级来源继续维护；这不代表原生客户端整体的支付 Sandbox、硬件、性能或辅助功能矩阵已经完成。

## 下一阶段：Android

Android 仍需要宿主容器、会话池、SSO 授权、扫码 / 相册、触感、生命周期与深链。
可以先复用现有 Kotlin WebView、导航与会话服务，替换 `BridgeActivity` 和 `HostRuntimePlugin` 的 Capacitor 适配层，同时保留现有 Nuxt 界面。

`@nuxtjs/ionic@1.0.2` 还会传递引入 Capacitor core / CLI，当前通过 overrides 统一到 8.6。
最终退出时，需替换该 Nuxt 集成入口并验证 Ionic 页面栈 / 返回行为，再删除剩余 Capacitor / Cordova 包、兼容配置及原生构建入口；不影响 Web、原生 iOS / macOS 或 Electron。
