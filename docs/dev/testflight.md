# TestFlight 内测上架完整流程

> 本文记录从代码到 TestFlight 内测的完整链路，含本机环境踩坑。

## ✅ 上传成功记录

| 时间       | 版本      | build  | Delivery UUID                          |
| ---------- | --------- | ------ | -------------------------------------- |
| 2026-06-03 | 1.0       | 1      | 23541d7f-…（首次打通流程，后改版本号） |
| 2026-06-04 | **0.1.0** | **67** | 5a473656-534d-45ad-9ff5-7cd957be673e   |

> 当前以 **0.1.0 (build 67)** 为准（pre-release 语义）。1.0 那个 build 可在
> ASC TestFlight 里手动 expire/删除（非必须，TestFlight 允许多版本号共存）。

## 版本号管理（自动对齐）

iOS 版本号与 `package.json` 自动对齐，**只需改 `package.json` 一处**：

- `MARKETING_VERSION` (CFBundleShortVersionString) ← `package.json` 的 `version`
- `CURRENT_PROJECT_VERSION` (CFBundleVersion / build 号) ← `git rev-list --count HEAD`（单调递增）

```bash
pnpm sync:version   # 手动同步一次
pnpm build:ios      # build:ios 已串联 sync:version，自动先同步版本号
```

实现：`scripts/sync-ios-version.sh` 用 `sed` 改 `project.pbxproj`
的 build setting，`Info.plist` 保持 `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` 引用（单一数据源）。

发新版只需：

```bash
pnpm release        # bumpp 改 package.json version + tag
# 或手动改 package.json version，然后：
pnpm build:ios      # 自动同步版本号 + 出 archive
bash scripts/ios-testflight.sh   # 导出 .ipa + 上传
```

---

完整通路（每一步实测）：

- ✅ webapp build + `cap sync`
- ✅ iOS 26.5 SDK，`xcodebuild archive` → `ios/App/App.xcarchive`
- ✅ PLA 协议同意
- ✅ Apple Distribution 证书（cloud-managed）：签名 `Apple Distribution: Lan Yang (QT792GAY4C)`
- ✅ App Store profile：`iOS Team Store Provisioning Profile: fun.yunle.apps`
- ✅ Admin 级 ASC API Key 认证
- ✅ `xcrun altool --upload-app` 上传成功

### ⚠️ 关键踩坑：`IDEDistributionPackagingStep: "Copy failed"`

**根因**（实测定位，**不是** Xcode bug，也不是代码问题）：

> ExportOptions 里 `uploadSymbols=true`（含 `stripSwiftSymbols`），在 Xcode 26 的
> packaging 阶段收集 dSYM 符号时触发 `Copy failed`。
> **把这两个改成 `false` 后 export 立刻成功。**

铁证（`IDEDistributionPipeline.log`）：

```
Running /usr/bin/rsync '-8aPhhE' '…/XcodeDistPipeline.~~~/Symbols' '--link-dest' …
Step "IDEDistributionCreateIPAStep" failed with error "Copy failed"
```

失败步骤是 `IDEDistributionCreateIPAStep` 用 **rsync 复制 `Symbols` 目录**（`--link-dest` 硬链接）时失败 —— `Symbols` 目录正是 `uploadSymbols=true` 收集的 dSYM。关掉它就不生成该目录，自然不触发。

排查路径（供未来参考）：

- `ditto` 复制整个 `App.app` 成功 → 排除 app bundle 文件问题
- 10 个 framework + 11 个 dSYM 完整、无坏符号链接、无残留 Headers/Modules → 排除结构问题
- 磁盘空间充足、PLA/证书/profile/API Key 全部就绪 → 排除账号问题
- 唯一变量是符号处理选项 → 关掉后通过 ✅

**代价**：dSYM 不随包上传，App Store Connect / RUM 的崩溃日志不会自动符号化。
影响很小，且可后续单独补传：

```bash
# 可选：单独上传 dSYM 做崩溃符号化
xcrun altool --upload-symbols --type ios \
  --file ios/App/App.xcarchive/dSYMs \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

### 命令行一键脚本

`scripts/ios-testflight.sh` 已固化上述修复（symbols=false），后续重新发版直接：

```bash
# 0. 先出 archive（首次或代码变更后）
LANG=en_US.UTF-8 pnpm build:ios   # 若 Copy failed 见上文，脚本里已 symbols=false
# 或仅复用已有 archive，跳到下面

export ASC_KEY_ID=<Admin Key ID>
export ASC_ISSUER_ID=<Issuer ID>
export ASC_KEY_P8=~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
bash scripts/ios-testflight.sh   # 导出 .ipa → 校验签名 → altool 上传
```

> ⚠️ cloud signing 需 **Admin** 级 API Key（App Manager 会报 `Cloud signing permission error`）。

> 注：`pnpm build:ios`（cap build）内部仍可能用默认 symbols=true 而 Copy failed。
> 当前 archive 已存在，推荐直接跑 `scripts/ios-testflight.sh` 复用 archive 导出上传。
> 若要让 `cap build` 也不踩坑，需在 Xcode scheme 或 cap 的 ExportOptions 模板里关 symbols。

## 一、构建 .ipa（本地）

### 1.1 前置环境

```bash
# 修 CocoaPods Ruby 4 编码 bug（一次性，写到 ~/.zshrc）
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 验证 Xcode 命令行工具
xcode-select -p   # 应输出 /Applications/Xcode.app/Contents/Developer
xcrun altool --help | head -1
```

### 1.2 Xcode 内必须做的事（**只能在 Xcode GUI 里操作**）

打开 Xcode → Settings (⌘,) → 检查：

- [ ] **Components / Platforms** Tab：下载与你的测试 iPhone 系统版本匹配的 **iOS Platform**（例：iOS 26.5）。这是 xcodebuild 跑 archive 的硬依赖。
- [ ] **Accounts** Tab：登录 Apple ID，确认能看到 Team `QT792GAY4C`，且 Manage Certificates 里有 **Apple Distribution** 证书（若无，点 ➕ 创建）
- [ ] **Components**：若提示 CoreSimulator 版本不一致，先 SoftwareUpdate 跑系统更新，再 `sudo xcodebuild -runFirstLaunch`

### 1.3 三步出 .ipa

```bash
pnpm build           # webapp 出包到 .output/public
pnpm sync            # capacitor 同步到 ios/
pnpm build:ios       # cap build ios --xcode-export-method app-store-connect ...
```

`pnpm build:ios` 完成后产物在 `ios/App/output/App.ipa`。

> ⚠️ **不要用 `pnpm build:ios:adhoc`** —— 那是 `release-testing` 方法（内部 ad-hoc 100 台设备），**不能上 TestFlight**。

### 1.4 验证 .ipa

```bash
# 确认是 app-store distribution 签名
codesign -dv --verbose=4 ios/App/output/App.ipa 2>&1 | grep -E "Identifier|TeamId|Authority"
```

预期看到 `Authority=Apple Distribution: <your-team>`（不是 Apple Development）。

## 二、上传到 App Store Connect

### 2.1 推荐：App Store Connect API Key（自动化友好）

#### 创建 Key（**一次性**）

1. 打开 <https://appstoreconnect.apple.com/access/api>
2. 「Keys」Tab → ➕ → 名称 `yunlefun-deploy`、Access 选 **Developer**（最小权限可上传）
3. 下载 `.p8` 文件（**只有一次下载机会**），保存到 `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`
4. 记下 **Key ID**（10 字符）和 **Issuer ID**（页面顶部 UUID）

#### 设置环境变量（写到 `~/.zshrc`）

```bash
export APP_STORE_CONNECT_API_KEY_ID="<KEY_ID>"
export APP_STORE_CONNECT_API_KEY_ISSUER_ID="<ISSUER_ID>"
# 不需要 export key 内容，xcrun altool 会从 ~/.appstoreconnect/private_keys/ 自动读
```

#### 上传

```bash
xcrun altool --upload-app \
  --type ios \
  --file ios/App/output/App.ipa \
  --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
  --apiIssuer "$APP_STORE_CONNECT_API_KEY_ISSUER_ID"
```

成功输出：`No errors uploading 'ios/App/output/App.ipa'.`

### 2.2 备选：Apple ID + 应用专用密码（不推荐，但能用）

#### 生成 App-Specific Password

1. <https://account.apple.com/account/manage> → Sign-In and Security
2. App-Specific Passwords → ➕ → 名称 `yunlefun-altool`
3. 复制生成的 19 字符密码（格式 `xxxx-xxxx-xxxx-xxxx`）

#### 上传

```bash
xcrun altool --upload-app \
  --type ios \
  --file ios/App/output/App.ipa \
  --username "<你的 Apple ID 邮箱>" \
  --password "<app-specific-password>"
```

## 三、App Store Connect 配置 TestFlight 内测

上传后约 **10-30 分钟**苹果完成处理（Email 通知），然后：

1. 打开 <https://appstoreconnect.apple.com/apps/6759859441>（你的 App）
2. 顶部「TestFlight」Tab
3. 左侧「iOS Build」可以看到刚上传的版本（状态先是 Processing，再变 Ready to Submit）
4. **填合规问卷**：点击版本 → 出口合规问题 → 选「不包含加密」（与 Info.plist `ITSAppUsesNonExemptEncryption=false` 对齐）
5. **内部测试**（无需 Apple 审核，2 分钟生效）：
   - 左侧「Internal Testing」→ 新建群组（如 `dev-team`）
   - 把构建版本关联到群组
   - 添加测试员（最多 100，需是 App Store Connect 团队成员）
6. **外部测试**（需 Apple 审核 24-48h）：
   - 左侧「External Testing」→ 新建群组
   - 关联版本 → 「提交进行审核」
   - 填测试备注（向 Apple 解释 App 用途）

### 测试员安装

测试员手机装 [TestFlight App](https://apps.apple.com/app/testflight/id899247664) → 邮件收到邀请链接 → 一键安装。

## 四、常见坑

| 现象                                              | 原因                             | 解决                                                                   |
| ------------------------------------------------- | -------------------------------- | ---------------------------------------------------------------------- |
| `iOS xx.x is not installed`                       | Xcode 没装匹配的 iOS Platform    | Xcode → Settings → Components 下载                                     |
| `CoreSimulator is out of date`                    | Xcode 和 macOS 子组件失步        | SoftwareUpdate + `sudo xcodebuild -runFirstLaunch`                     |
| `No Apple Distribution certificate`               | Keychain 里只有 Development 证书 | Xcode → Settings → Accounts → Manage Certs → ➕ Apple Distribution     |
| 上传时 `ERROR ITMS-90683: Missing Purpose String` | Info.plist 没声明权限用途        | 已在 `ios/App/App/Info.plist` 添加 NSCameraUsage / NSPhotoLibraryUsage |
| 上传时 `ITMS-90713: Missing Info.plist value`     | 缺 ITSAppUsesNonExemptEncryption | 已在 Info.plist 中设为 false                                           |
| TestFlight 显示 `Invalid Binary`                  | bitcode / 架构问题               | 当前已用 arm64 only，无 bitcode（Xcode 15+ 已默认关闭）                |

## 五、CI 自动上传（可选，1.x 再做）

未来想做 main 分支自动推 TestFlight，可加 GitHub Actions：

```yaml
- name: Upload to TestFlight
  env:
    APP_STORE_CONNECT_API_KEY_ID: ${{ secrets.ASC_KEY_ID }}
    APP_STORE_CONNECT_API_KEY_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
    APP_STORE_CONNECT_API_KEY: ${{ secrets.ASC_KEY_P8 }}
  run: |
    mkdir -p ~/.appstoreconnect/private_keys
    echo "$APP_STORE_CONNECT_API_KEY" > ~/.appstoreconnect/private_keys/AuthKey_$APP_STORE_CONNECT_API_KEY_ID.p8
    xcrun altool --upload-app --type ios --file ios/App/output/App.ipa \
      --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
      --apiIssuer "$APP_STORE_CONNECT_API_KEY_ISSUER_ID"
```

但 macOS runner 比较贵，建议先手动跑稳定后再上 CI。
