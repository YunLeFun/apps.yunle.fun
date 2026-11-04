# Capacitor 使用边界与退役准备

2026-11-05 按当前源码核对。结论：可以分阶段准备迁移，Android 主壳及旧 iOS 兼容工程仍依赖 Capacitor，当前不能全仓删除。

## 各端现状

| 消费者                | 当前实现                                                           | Capacitor 处理                                                |
| --------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------- |
| `apps/ios`            | SwiftUI + `NativeWebRuntime`，直接调用原生服务和 `NativeStoreKit`  | 工程不依赖 Capacitor；旧壳退役仍需升级与数据迁移验收          |
| `apps/macos`          | SwiftUI / AppKit + WKWebView，共用部分原生 iOS 服务                | 不依赖 Capacitor                                              |
| `apps/desktop`        | Electron 主进程与独立 preload / IPC                                | 不依赖 Capacitor                                              |
| `apps/mobile/android` | `MainActivity : BridgeActivity`，注册 `HostRuntimePlugin : Plugin` | 仍是 Android 主壳，保留                                       |
| `apps/mobile/ios`     | Capacitor 兼容工程、旧内购适配器与 Cordova 插件                    | 可优先安排退役，尚未在本次依赖清理中删除                      |
| `apps/mobile/app`     | 浏览器与旧移动壳共用的 Nuxt / Ionic 界面                           | 仍直接引用 Capacitor 平台判断、插件及宿主事件，需先收拢适配层 |

`apps/mobile` 也提供 `apps.yunle.fun` 的浏览器页面与服务端 API，删除旧原生壳不代表删除该应用。
Ionic、Konsta 是界面依赖，Capacitor 是原生宿主与桥接依赖，可以分别迁移。

## 仍在使用的能力

- 宿主网页容器：打开 / 收起 / 恢复、会话列表与上限、账号切换清理，以及网页授权、登录后返回原页面。
- App 生命周期与深链：`deeplink.client.ts`、`identity-broker.client.ts` 及 OAuth 回调使用原生 App / Browser 插件。
- 扫码与相册：`Barcode.vue` 调用原生扫码，`useScanner.ts` 调用 Camera 选择二维码图片；Web 使用摄像头与 jsQR。
- 触感、键盘和状态栏：界面直接使用 Haptics，原生配置仍启用 Keyboard / StatusBar。
- 旧 iOS 支付：`useIap.ts`、`iap.client.ts` 经 `packages/capacitor-storekit` 处理交易、补单和完成交易；新 iOS 使用独立 `NativeStoreKit`。
- 旧壳微信配置：Android / 旧 iOS 仍注册 `cordova-plugin-wechat`，移除前需核对实际启用入口及替代能力。

`app/host-runtime/index.ts` 同时声明宿主契约并调用 `registerPlugin`，事件句柄也使用 Capacitor 类型。
仅删除 package.json 声明会直接破坏这些调用。

还有一条传递依赖：`@nuxtjs/ionic@1.0.2` 自身依赖 Capacitor core / CLI 7，当前通过 workspace overrides 统一到 8.6。
退出 Capacitor 时也要替换这一 Nuxt 集成入口；只移除显式的 `@capacitor/*` 仍会重新安装传递依赖。

## 迁移顺序与退出条件

1. **先收拢 Web 适配层。** 将宿主协议类型与 Capacitor 注册分离，页面经明确的宿主能力接口访问平台、浏览器、触感、扫码和生命周期。保留浏览器实现及现有 Android 适配器，避免在业务页面继续增加平台判断。
2. **优先退役旧 iOS 主壳。** 按[旧版升级迁移](./ios-upgrade-migration.md)和[原生迁移验收](./ios-native-migration.md)验证同 Bundle ID 升级、本地未同步数据、账号隔离、已购恢复 / 未完成交易、链接与授权回跳。通过后独立删除 `apps/mobile/ios`、旧 StoreKit 包和仅服务旧 iOS 的 Web 插件 / alias，并调整根脚本与测试夹具。
3. **替换 Android 壳和桥接。** 可先保留现有 Nuxt 界面，复用独立的 Kotlin WebView、导航与会话服务，替换 `BridgeActivity` 和 `HostRuntimePlugin` 的 Capacitor 适配层。扫码 / 相册、触感、外部浏览器、生命周期和深链逐项接入。是否进一步原生化 Android 界面另行决定，不作为替换桥接的隐含前提。
4. **最后移除依赖与兼容配置。** 替换 `@nuxtjs/ionic` 的初始化方式后，验证 Ionic 路由、页面栈和返回行为，再移除剩余 Capacitor / Cordova 包、overrides、安装脚本与原生构建入口。按实际消费者清理安全补丁，保留 Web、原生 iOS / macOS 和 Electron 所需依赖。

Android 新壳需要验证旧版覆盖安装、现有签名身份、账号与未同步本地数据、授权来源 / 主 frame 校验、后台恢复、扫码权限拒绝及断网场景。
支付继续保留服务端验单、账号归属、幂等与完成交易的顺序；宿主令牌不得进入云应用页面。

## 本次范围

本次依赖清理将仍使用的 Capacitor 统一到 8.6，验证 Android Debug 与旧 iOS 模拟器架构编译，并未实施上述主壳迁移。
构建成功不能替代旧用户升级、支付和真实宿主交互验收；具体功能进度继续记录在各原生迁移文档中。
