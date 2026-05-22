# App Store Connect 上架手册

把 [app/config/index.ts](https://github.com/YunYouJun/apps.yunle.fun/blob/main/app/config/index.ts) 里 `appStore.id` 从占位符 `'000000000'` 换成真实 App ID 的全流程。

## 前置条件

- [ ] 已加入 [Apple Developer Program](https://developer.apple.com/programs/)（年费 $99，约 ¥698）
- [ ] Team ID 为 `QT792GAY4C`（已写在 [package.json](https://github.com/YunYouJun/apps.yunle.fun/blob/main/package.json) `build:ios` 脚本里）
- [ ] Bundle ID 为 `fun.yunle.apps`（Xcode 项目实际值，**注意与 `capacitor.config.ts` 的 `appId` 不一致，见下文**）

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

## ⚠️ 重要：解决 Bundle ID 不一致问题

**发现的问题**：

| 来源                                                                                                                                       | 当前值                        |
| ------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------- |
| [capacitor.config.ts](https://github.com/YunYouJun/apps.yunle.fun/blob/main/capacitor.config.ts) `appId`                                   | `apps.yunle.fun`              |
| Xcode 项目 `PRODUCT_BUNDLE_IDENTIFIER`                                                                                                     | `fun.yunle.apps`              |
| [apple-app-site-association](https://github.com/YunYouJun/apps.yunle.fun/blob/main/public/.well-known/apple-app-site-association) `appIDs` | `QT792GAY4C.fun.yunle.apps` ✓ |
| WeChat URL Scheme                                                                                                                          | `wx925d6e320d64f30a`          |

`capacitor.config.ts` 与 Xcode 不一致。如果跑 `pnpm sync` 或 `cap sync`，可能会把 Xcode 的 Bundle ID 改成 `apps.yunle.fun`，进而：

- AASA 失效 → Universal Link 不工作
- App Store Connect 找不到匹配的 Bundle ID
- 已签发的开发证书失效

**处理方式**（**在做 cap sync 之前必须先改**）：

```ts
// capacitor.config.ts
const config: CapacitorConfig = {
  appId: 'fun.yunle.apps', // ← 改为反向 DNS，跟 Xcode 实际值对齐
  appName: '云乐坊',
  // ...
}
```

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

## 参考链接

- App Store Connect: <https://appstoreconnect.apple.com>
- Apple Developer Identifiers: <https://developer.apple.com/account/resources/identifiers/list>
- 审核指南: <https://developer.apple.com/cn/app-store/review/guidelines/>
- 中国区备案要求: <https://developer.apple.com/cn/support/app-store-connect/>
