---
name: ios-deploy
description: 打包并部署云乐坊 iOS App 到真机或模拟器，归档并上传 App Store Connect，或将有效构建发布到 TestFlight 内部测试组。当用户要求“打包到 iOS”“装到手机”“部署真机”“上传或发布 TestFlight”“配置内部测试员”或运行 Capacitor iOS 流程时使用。
---

# iOS 打包部署（Nuxt + Capacitor）

Nuxt 4（`ssr: false`）+ Capacitor 8，web 产物在 `.output/public`。

## 部署到真机（默认行为）

用户未指定目标时直接部署真机，不要询问：

```bash
pnpm build
pnpm sync
LANG=en_US.UTF-8 npx cap run ios --list
pnpm run:ios --target '<上一步列出的真机 Target ID>'
```

输出 `Deploying App.app to <UDID>` 即成功，app 自动启动。

- 报 `Invalid target ID` 说明设备变了：重新列出设备并取非 simulator 行的 Target ID，不要把个人设备标识写入仓库。
- 不要用 `xcrun devicectl list devices` 的 UDID —— 那是另一套体系，`cap run` 不认。
- agent 场景必须显式传 `--target`，否则 `cap run` 会交互式选设备卡住。

## 归档并上传

TestFlight / App Store 使用以下顺序：

```bash
pnpm build:ios

export IOS_EXPORT_PROFILE_NAME='<App Store profile 名称>'
export ASC_KEY_ID='<Key ID>'
export ASC_ISSUER_ID='<Issuer ID>'
export ASC_KEY_P8="$HOME/.appstoreconnect/private_keys/AuthKey_<Key ID>.p8"
bash scripts/ios-testflight.sh
```

Ad-hoc 使用 `pnpm build:ios:adhoc`。这些命令都会自动同步版本号。

## 发布 TestFlight 内测

上传处理完成后，调用幂等发布脚本。先 dry run，再执行：

```bash
pnpm publish:ios:testflight -- --build <build-number> --dry-run
pnpm publish:ios:testflight -- --build <build-number>
```

脚本会：

1. 只选择 `VALID` 且未过期的构建；省略 `--build` 时选择最新构建。
2. 复用或创建“云乐坊内测组”，并开启自动分发与 TestFlight 反馈。
3. 关联构建，设置当前 App 的出口合规为“不使用非豁免加密”。
4. 创建或更新简体中文的 App 说明、反馈邮箱、隐私政策和测试重点。
5. 验收构建状态必须为 `IN_BETA_TESTING`。

默认不新增测试员。首次配置或明确要求发邀请时，使用以下任一方式：

```bash
pnpm publish:ios:testflight -- --build <build-number> --tester-email '<现有 ASC 用户邮箱>'
pnpm publish:ios:testflight -- --build <build-number> --invite-all-internal-users
```

也可用逗号分隔的 `ASC_INTERNAL_TESTER_EMAILS`，并用 `ASC_WHATS_NEW` 覆盖本次测试重点。脚本只接受已有 App Store Connect 内部用户，不创建外部测试员；外部 TestFlight 需要单独的测试组和 Beta App Review。

## 凭据安全

- 只记录凭据文件路径和环境变量名，不记录 `.p8` 内容、私钥、JWT 或完整测试员邮箱。
- `.p8` 保持本机权限 `600`，不得提交到 Git。
- App Store Connect API Key 至少需要 App Manager 权限。
- 发布输出只报告测试员数量；错误中的邮箱必须脱敏。

## 注意事项

1. **优先用 pnpm 脚本**：cap 相关脚本已内置 `LANG=en_US.UTF-8`（CocoaPods 必需）；直接 `npx cap ...` 需手动加，否则报 `Encoding::CompatibilityError`。
2. **`@capacitor/cli` 当前锁定为 8.4.2，且不得低于 7.5.0**：tar 被安全 override 钉到 v7，旧 CLI 用 v6 API 会报 `undefined (reading 'extract')`，详见 docs/dev/dependency-security.md。
3. **server/ 代码不要顶层 require CJS 包**：nitro prerender 以虚拟入口执行，顶层 `createRequire` 会崩，须函数内惰性加载（参考 `server/utils/cloudbase-admin.ts`）。
4. cordova-plugin-wechat 的 `NSAppTransportSecurity` warning 可忽略。
