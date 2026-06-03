# TestFlight 内测上架完整流程

> 本文记录从代码到 TestFlight 内测的完整链路，含本机环境踩坑。

## 当前进度（2026-06-03）

所有签名 / 账号 / 证书障碍**已全部清除**，只剩最后一步打包上传：

- ✅ webapp build + `cap sync` 通过
- ✅ iOS 26.5 SDK 已安装，`xcodebuild archive` 成功 → 产出 `ios/App/App.xcarchive`
- ✅ **PLA 协议已同意**
- ✅ **Apple Distribution 证书可用**（cloud-managed，实测签名 `Apple Distribution: Lan Yang (QT792GAY4C)`）
- ✅ **App Store provisioning profile 存在**：`iOS Team Store Provisioning Profile: fun.yunle.apps`（UUID `c0add50e-…`）
- ✅ **Admin 级 ASC API Key 认证通过**：能连 ASC 拉到 app（6759859441 / fun.yunle.apps / 云乐坊 / v1.0），所有 framework 证书评估 `errors: (null)`
- ⛔ **命令行 `xcodebuild -exportArchive` 卡在 `IDEDistributionPackagingStep: "Copy failed"`**
  - 这是 **Xcode 26 命令行导出的已知 bug**，发生在签名全部通过之后的打包步骤，与代码 / 证书 / 账号无关
  - 对比：ad-hoc（`release-testing` method）导出走不同打包路径，**不触发**此 bug；但 ad-hoc 包不能上 TestFlight
  - 磁盘空间、权限均已排除

### ✅ 绕过方案：Xcode Organizer GUI 上传（已为你打开）

Organizer 的打包实现与命令行不同，能绕过 `Copy failed`。archive 已复制到标准目录并在 Organizer 打开：

1. Xcode → **Window → Organizer**（⌥⌘O），左侧选 **Archives**
2. 选中最新的 **「云乐坊」** archive（2026-06-03）
3. 右侧点 **「Distribute App」**
4. 选 **「App Store Connect」** → Next
5. 选 **「Upload」** → Next
6. 签名选 **「Automatically manage signing」** → Next
7. 确认信息 → **「Upload」**
8. 等进度条走完，提示 **「Upload Successful」**

> GUI 会用已登录的 Apple ID session + cloud signing 自动处理证书/profile，全程几乎不用做选择。

### 命令行一键脚本（留作 Xcode bug 修复后/CI 用）

[`scripts/ios-testflight.sh`](../../scripts/ios-testflight.sh)：

```bash
export ASC_KEY_ID=<Admin Key ID>
export ASC_ISSUER_ID=<Issuer ID>
export ASC_KEY_P8=~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
bash scripts/ios-testflight.sh
```

> ⚠️ cloud signing 需 **Admin** 级 API Key（App Manager 会报 `Cloud signing permission error`）。
> ⚠️ 当前 Xcode 26 下此脚本会撞 `Copy failed`，待 Apple 修复后可用；现阶段用上面的 Organizer GUI。

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

| 现象                                              | 原因                             | 解决                                                                                                   |
| ------------------------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `iOS xx.x is not installed`                       | Xcode 没装匹配的 iOS Platform    | Xcode → Settings → Components 下载                                                                     |
| `CoreSimulator is out of date`                    | Xcode 和 macOS 子组件失步        | SoftwareUpdate + `sudo xcodebuild -runFirstLaunch`                                                     |
| `No Apple Distribution certificate`               | Keychain 里只有 Development 证书 | Xcode → Settings → Accounts → Manage Certs → ➕ Apple Distribution                                     |
| 上传时 `ERROR ITMS-90683: Missing Purpose String` | Info.plist 没声明权限用途        | 已在 [`ios/App/App/Info.plist`](../../ios/App/App/Info.plist) 添加 NSCameraUsage / NSPhotoLibraryUsage |
| 上传时 `ITMS-90713: Missing Info.plist value`     | 缺 ITSAppUsesNonExemptEncryption | 已在 Info.plist 中设为 false                                                                           |
| TestFlight 显示 `Invalid Binary`                  | bitcode / 架构问题               | 当前已用 arm64 only，无 bitcode（Xcode 15+ 已默认关闭）                                                |

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
