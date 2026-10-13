# TestFlight 内测上架完整流程

> 当前流程基于 Capacitor 8、Xcode 26 和本机 Apple Distribution 证书。归档、导出、上传分开执行，
> 不在仓库里保存 API Key 或会过期的 provisioning profile 名称。

## 上传记录

| 时间       | 版本      | build  | Delivery UUID                          |
| ---------- | --------- | ------ | -------------------------------------- |
| 2026-06-03 | 1.0       | 1      | 23541d7f-…（首次打通流程，后改版本号） |
| 2026-06-04 | **0.1.0** | **67** | 5a473656-534d-45ad-9ff5-7cd957be673e   |

## 前置条件

- Node.js 24（见根 `.node-version`）、根 manifest 指定的 pnpm、Capacitor 8。
- `/Applications/Xcode.app` 为 Xcode 26+，已安装 iOS Platform。
- Xcode → Settings → Accounts 已登录 Team `QT792GAY4C`。
- Keychain 中有 Apple Distribution 证书，本机已安装 Bundle ID `fun.yunle.apps` 对应的
  App Store provisioning profile。
- App Store Connect API Key 具有 App Manager 或更高权限；`.p8` 只保存在本机或 CI Secret。

如果全局 `xcode-select` 没有指向 Xcode，可只对当前 shell 设置，避免修改系统状态：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

## 版本号管理

`apps/mobile/scripts/sync-ios-version.sh` 负责把 iOS 版本与仓库状态对齐：

- `MARKETING_VERSION` ← `apps/mobile/package.json` 的 `version`
- `CURRENT_PROJECT_VERSION` ← `git rev-list --count HEAD`

`pnpm build:ios` 会先自动执行该同步，再通过 `xcodebuild archive` 生成 archive。也可单独运行：

```bash
pnpm sync:version
```

## 必需环境变量

导出与上传前必须显式提供 profile 和 App Store Connect 凭据：

```bash
export IOS_EXPORT_PROFILE_NAME='iOS Team Store Provisioning Profile: fun.yunle.apps'
export ASC_KEY_ID='<KEY_ID>'
export ASC_ISSUER_ID='<ISSUER_ID>'
export ASC_KEY_P8="$HOME/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8"
```

`IOS_EXPORT_PROFILE_NAME` 必须与本机已安装 profile 的名称完全一致，不要把带时间戳的名称提交到仓库。
API Key 在 App Store Connect → Users and Access → Integrations 中创建，`.p8` 只有一次下载机会。

以下变量有安全默认值，但在其他 Team、target 或输出目录使用时可以覆盖。`IOS_BUNDLE_ID`
是归档前的期望值校验，不会作为全局 Xcode setting 覆盖嵌入 framework；修改 Bundle ID 时应先更新 Xcode App target：

| 变量                             | 默认值                                |
| -------------------------------- | ------------------------------------- |
| `IOS_SCHEME`                     | `App`                                 |
| `IOS_TARGET`                     | `App`                                 |
| `IOS_CONFIGURATION`              | `Release`                             |
| `IOS_TEAM_ID`                    | `QT792GAY4C`                          |
| `IOS_BUNDLE_ID`                  | `fun.yunle.apps`                      |
| `IOS_ARCHIVE_PATH`               | `apps/mobile/ios/App/App.xcarchive`   |
| `IOS_EXPORT_DIR`                 | `apps/mobile/ios/App/output-appstore` |
| `IOS_EXPORT_SIGNING_CERTIFICATE` | `Apple Distribution`                  |

## 完整发布顺序

以下命令从仓库根执行。每次代码或依赖变更后执行：

```bash
# 1. 生成 Web 产物
pnpm build

# 2. 同步 Capacitor 8 插件、Web 资源和 CocoaPods
pnpm sync

# 3. 同步版本号并创建 apps/mobile/ios/App/App.xcarchive
pnpm build:ios

# 4. manual signing 导出、校验签名并上传 TestFlight
bash apps/mobile/scripts/ios-testflight.sh
```

产物位置：

- archive：`apps/mobile/ios/App/App.xcarchive`
- ExportOptions：`apps/mobile/ios/App/output-appstore/ExportOptions.plist`
- ipa：默认 `apps/mobile/ios/App/output-appstore/App.ipa`（脚本会以导出目录内唯一的 `.ipa` 为准）

`pnpm build:ios` 只负责 archive，不会隐式重建 Web 产物或执行 Capacitor 同步；前两步不能省略。
`apps/mobile/scripts/ios-testflight.sh` 要求 `IOS_EXPORT_PROFILE_NAME`，使用 manual signing 导出，避免依赖机器专属
profile 名称；随后解压 ipa，确认签名 Authority 为 Apple Distribution，再调用 `altool` 上传。

> `pnpm build:ios:adhoc` 使用 `release-testing`，只用于登记设备的内部安装，不能上传 TestFlight。

## Xcode 26 的 symbols 导出问题

本项目曾在 Xcode 26 遇到 `IDEDistributionPackagingStep: Copy failed`。定位结果是
`stripSwiftSymbols=true` / `uploadSymbols=true` 在 packaging 阶段复制 Symbols 目录失败。
`apps/mobile/scripts/ios-testflight.sh` 因此固定为：

```xml
<key>stripSwiftSymbols</key>
<false/>
<key>uploadSymbols</key>
<false/>
```

这不影响 ipa 或 TestFlight 上传，但 dSYM 不会自动随包上传。若需要服务端崩溃符号化，可从
`apps/mobile/ios/App/App.xcarchive/dSYMs` 单独上传或交给 RUM 符号表流程。

## 仅复用已有 archive

如果源码、Web 产物、Pods 和版本号都没有变化，可以跳过前三步，确认 archive 路径后直接运行：

```bash
export IOS_EXPORT_PROFILE_NAME='<已安装的 App Store profile 名称>'
export ASC_KEY_ID='<KEY_ID>'
export ASC_ISSUER_ID='<ISSUER_ID>'
export ASC_KEY_P8='/absolute/path/to/AuthKey_<KEY_ID>.p8'
bash apps/mobile/scripts/ios-testflight.sh
```

如果 archive 在其他位置，同时设置 `IOS_ARCHIVE_PATH=/absolute/path/App.xcarchive`。

## App Store Connect 后续操作

上传后通常需要等待处理，然后：

1. 打开 <https://appstoreconnect.apple.com/apps/6759859441> 的 TestFlight Tab。
2. 选择新 build，完成出口合规问卷；当前 `ITSAppUsesNonExemptEncryption=false`。
3. 关联内部测试群组；外部测试需另行提交 Beta App Review。

## 常见问题

| 现象                                              | 处理方式                                                                   |
| ------------------------------------------------- | -------------------------------------------------------------------------- |
| `xcrun` 找不到 `xcodebuild`                       | 设置上文的 `DEVELOPER_DIR`，或由用户自行修正全局 `xcode-select`            |
| 找不到 archive                                    | 依次执行 `pnpm build`、`pnpm sync`、`pnpm build:ios`                       |
| 缺少 provisioning profile                         | 在 Xcode 下载/创建 App Store profile，并显式设置 `IOS_EXPORT_PROFILE_NAME` |
| `No Apple Distribution certificate`               | Xcode → Settings → Accounts → Manage Certificates 创建/下载证书            |
| `IDEDistributionPackagingStep: Copy failed`       | 保持脚本中的 `stripSwiftSymbols=false` 与 `uploadSymbols=false`            |
| 上传提示缺少权限                                  | 检查 API Key 角色、Issuer ID、Key ID 和 `.p8` 文件路径                     |
| 上传时 `ERROR ITMS-90683: Missing Purpose String` | 检查 `apps/mobile/ios/App/App/Info.plist` 的相机/相册用途描述              |
| TestFlight 显示 `Invalid Binary`                  | 核对 Bundle ID、Distribution 签名、profile 与 arm64 架构                   |

CI 自动上传时使用 macOS runner，把四个必需变量放进 Secrets；不要把 `.p8` 内容、证书私钥或
provisioning profile 提交到 Git。
