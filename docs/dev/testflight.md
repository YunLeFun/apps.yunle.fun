# TestFlight 内测上架完整流程

> 本文记录从代码到 TestFlight 内测的完整链路，含本机环境踩坑。

## 当前进度（2026-06-03）

- ✅ webapp build + `cap sync` 通过
- ✅ iOS 26.5 SDK 已安装，`xcodebuild archive` 成功 → 产出 `ios/App/App.xcarchive`
- ✅ **PLA 协议已同意**（否则 export 不会成功）
- ✅ **Apple Distribution 证书已可用**：实测签名为 `Apple Distribution: Lan Yang (QT792GAY4C)`
  - 注：`security find-identity -v -p codesigning` 可能列不出它，因为 Xcode automatic signing 把它放在单独 keychain，但导出时实际可用。
- ⏳ **最后一步：app-store-connect 导出 + 上传 —— 需要 ASC API Key**
  - 直接跑 automatic signing 的 app-store 导出会报
    `No provider associated with App Store Connect user`（Xcode 账号 session 无法认证到 ASC 拉 App Store provisioning profile）
  - **解法**：用 App Store Connect API Key 认证导出 + 上传，一步到位。

### 一键脚本（拿到 API Key 后）

```bash
# 1. 到 https://appstoreconnect.apple.com/access/api 创建 Key（Access 选 App Manager）
#    下载 .p8 到 ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
# 2. 设置三个变量
export ASC_KEY_ID=<10位 Key ID>
export ASC_ISSUER_ID=<UUID Issuer ID>
export ASC_KEY_P8=~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
# 3. 一键导出 + 上传（脚本会复用已有 App.xcarchive）
bash scripts/ios-testflight.sh
```

脚本 [`scripts/ios-testflight.sh`](../../scripts/ios-testflight.sh) 会：生成带 API Key 认证的 ExportOptions → 导出 app-store .ipa → 校验是 Distribution 签名 → `xcrun altool` 上传到 TestFlight。

> ⚠️ Access 级别要 **App Manager** 或更高（Developer 级别能 export 但上传可能权限不足）。

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
