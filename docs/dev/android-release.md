# Android 发布构建

Android Release 必须使用既有的长期 upload key 签名。仓库只保存环境变量接入逻辑，不保存、生成或
轮换 keystore；`.jks` 与 `.keystore` 已加入忽略规则。

## 必需环境变量

```bash
export YUNLEFUN_ANDROID_VERSION_CODE='<integer greater than the published build>'
export YUNLEFUN_ANDROID_RELEASE_STORE_FILE='/absolute/path/to/yunlefun-upload.jks'
export YUNLEFUN_ANDROID_RELEASE_STORE_PASSWORD='<store password>'
export YUNLEFUN_ANDROID_RELEASE_KEY_ALIAS='<key alias>'
export YUNLEFUN_ANDROID_RELEASE_KEY_PASSWORD='<key password>'
export YUNLEFUN_ANDROID_RELEASE_CERT_SHA256='<pinned upload certificate SHA-256 fingerprint>'
```

`versionName` 自动读取根目录 `package.json`；`versionCode` 必须是正整数，并且需要高于应用商店
中已发布的构建。四个签名变量必须同时提供；发布脚本还要求固定的证书 SHA-256 指纹，并在构建前核对
keystore、构建后核对 APK，防止误用另一把 upload key。只设置部分签名变量，或在完全未配置时直接运行
Release 打包任务，Gradle 都会立即失败，避免误产出未签名的候选包。
密码只放在本机安全存储或 CI Secrets 中，不写入 `gradle.properties`、shell history 或仓库文件。

## 构建与验签

```bash
pnpm build:android:release
```

脚本依次构建 Web、仅同步 Android 的 Capacitor 工程、执行 Release 单测与 Lint、生成 APK/AAB，并分别使用
`apksigner` 与 `jarsigner -strict` 验签，并核对固定 upload key 指纹。任一环节失败都不会把产物视为可发布版本。

Android 发布脚本不会运行全平台 `cap sync`，避免 Android 构建被本机 CocoaPods 或 Xcode 工程状态阻断。

验签后的默认产物：

- `android/app/build/outputs/apk/release/app-release.apk`
- `android/app/build/outputs/bundle/release/app-release.aab`

构建完成后仍需在真机安装 APK，覆盖冷启动、后台恢复、授权同意、取消、其他账号与断网场景；
AAB 上传应用商店前还应复核 versionCode、versionName、目标轨道和发布说明。
