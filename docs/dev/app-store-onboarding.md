# App Store Connect 上架手册

把 [app/config/index.ts](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/config/index.ts) 里 `appStore.id` 从占位符 `'000000000'` 换成真实 App ID 的全流程。

## 前置条件

- [ ] 已加入 [Apple Developer Program](https://developer.apple.com/programs/)（年费 $99，约 ¥698）
- [ ] Team ID 为 `QT792GAY4C`（`scripts/ios-archive.sh` / `scripts/ios-testflight.sh` 的默认值，可用 `IOS_TEAM_ID` 覆盖）
- [ ] Bundle ID 为 `fun.yunle.apps`（Capacitor、Xcode 和导出脚本保持一致；`IOS_BUNDLE_ID` 只校验期望值）

## 步骤一：注册 Bundle ID（如未注册）

1. 打开 <https://developer.apple.com/account/resources/identifiers/list>
2. 顶部蓝色 ➕ → 选 `App IDs` → Continue
3. 选 `App` → Continue
4. 填写：
   - Description: `云乐坊 / yunle.fun`
   - Bundle ID: 选 **Explicit**，填 `fun.yunle.apps`
5. Capabilities 勾选（按当前 App 实际使用）：
   - ✅ Associated Domains（Universal Link 必需，对应 [public/.well-known/apple-app-site-association](https://github.com/YunYouJun/apps.yunle.fun/blob/main/public/.well-known/apple-app-site-association)）
   - ✅ Push Notifications（如果以后要做推送）
   - ⬜ Sign in with Apple（除非决定上 SIWA）
6. Continue → Register

## 步骤二：在 App Store Connect 创建 App

1. 打开 <https://appstoreconnect.apple.com/apps>（已用 `open` 命令打开）
2. 左上「我的 App」→ 右上 ➕ → 「新建 App」
3. 平台勾选 **iOS**
4. 填写：

| 字段         | 值                                     | 说明                                                                                                                                        |
| ------------ | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| 名称         | `云乐坊`                               | 必须与 [ios/App/App/Info.plist](https://github.com/YunYouJun/apps.yunle.fun/blob/main/ios/App/App/Info.plist) 的 `CFBundleDisplayName` 一致 |
| 主要语言     | 简体中文                               |                                                                                                                                             |
| Bundle ID    | `fun.yunle.apps`                       | 从下拉选已注册的（步骤一）                                                                                                                  |
| SKU          | `fun.yunle.apps` 或 `yunlefun-ios-001` | 自定义唯一标识，不会展示给用户                                                                                                              |
| 用户访问权限 | 完全访问权限                           | 个人开发者保持默认即可                                                                                                                      |

5. 点「创建」

## 步骤三：拿到 Apple ID

1. 创建成功后跳到 App 详情页
2. 左侧栏「**App 信息**」→ 右侧「**一般信息**」区块
3. 找到 **「Apple ID」**字段，是一串 10 位数字（例如 `1234567890`）
4. 复制下来

## 步骤四：回填到代码

```ts
// app/config/index.ts
export const config = {
  // ...
  appStore: {
    id: '1234567890', // ← 替换这里
    get url() {
      return `https://apps.apple.com/app/yunlefun/id${this.id}`
    },
  },
}
```

## Bundle ID 一致性校验

当前以下位置都应保持为同一个 App 标识：

| 来源                                                                                                                                       | 当前值                        |
| ------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------- |
| [capacitor.config.ts](https://github.com/YunYouJun/apps.yunle.fun/blob/main/capacitor.config.ts) `appId`                                   | `fun.yunle.apps`              |
| Xcode 项目 `PRODUCT_BUNDLE_IDENTIFIER`                                                                                                     | `fun.yunle.apps`              |
| [apple-app-site-association](https://github.com/YunYouJun/apps.yunle.fun/blob/main/public/.well-known/apple-app-site-association) `appIDs` | `QT792GAY4C.fun.yunle.apps` ✓ |
| `IOS_BUNDLE_ID` 期望值                                                                                                                     | `fun.yunle.apps`              |

每次修改 Bundle ID 后都要同时更新 Capacitor 配置、Xcode、AASA、provisioning profile 和发布环境变量，
否则 Universal Link、签名或 App Store Connect 匹配会失败。WeChat App ID `wx925d6e320d64f30a`
是独立标识，不应作为 iOS Bundle ID。

## 步骤五：填补 App Store 元数据（不影响 ID 获取，可后做）

App 创建后还要填以下信息才能提交审核，建议提前准备素材：

- **截图**：6.7 寸 (1290×2796) + 6.5 寸 (1242×2688) 各 3-10 张（必填）
- **App 描述**：4000 字以内
- **关键词**：100 字以内，逗号分隔
- **App 图标**：1024×1024 PNG，无圆角无透明
- **隐私政策 URL**：<https://www.yunle.fun/docs/privacy-policy>
- **支持 URL**：建议建一个，例如 <https://www.yunle.fun/support>
- **营销 URL**（可选）：<https://www.yunle.fun>
- **年龄分级**：通过问卷自评，工坊应用聚合类一般 4+ 即可
- **App 隐私问卷（Privacy Nutrition Label）**：必须如实声明收集的数据类别

## 本机环境踩坑

### CocoaPods + Ruby 4 编码 bug

如果跑 `pnpm sync` / `pnpm run:ios` 时 `pod install` 报错：

```
Unicode Normalization not appropriate for ASCII-8BIT (Encoding::CompatibilityError)
```

原因：Ruby 4.0.1 + CocoaPods 1.16.2 不兼容。

**解决**：在 shell 启动文件（`~/.zshrc` / `~/.profile`）加：

```bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```

或一次性：

```bash
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pnpm sync
```

### `pnpm deploy` 需要的环境变量

`@yunlefun/deploy` 通过腾讯云 SDK 推送 Docker 镜像。需要在环境中设置：

```bash
export TENCENT_SECRET_ID=<your-id>
export TENCENT_SECRET_KEY=<your-key>
```

CI 中通过 GitHub Actions Secrets 注入。

## 参考链接

- App Store Connect: <https://appstoreconnect.apple.com>
- Apple Developer Identifiers: <https://developer.apple.com/account/resources/identifiers/list>
- 审核指南: <https://developer.apple.com/cn/app-store/review/guidelines/>
- 中国区备案要求: <https://developer.apple.com/cn/support/app-store-connect/>
