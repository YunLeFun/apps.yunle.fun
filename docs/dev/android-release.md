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

`versionName` 自动读取 `apps/android/version.properties`；`versionCode` 必须是正整数，并且需要高于应用商店
中已发布的构建。四个签名变量必须同时提供；发布脚本还要求固定的证书 SHA-256 指纹，并在构建前核对
keystore、构建后核对 APK，防止误用另一把 upload key。只设置部分签名变量，或在完全未配置时直接运行
Release 打包任务，Gradle 都会立即失败，避免误产出未签名的候选包。
密码只放在本机安全存储或 CI Secrets 中，不写入 `gradle.properties`、shell history 或仓库文件。

## 构建与验签

```bash
# 从仓库根执行
pnpm build:android:release
```

脚本直接执行独立 Gradle 工程的 Release 单测、Lint 和 APK/AAB 构建，再分别验签并核对 upload key 指纹。需要 JDK 21 和 Android SDK 36，不需要 Node、Nuxt 或生成的网页资源。未配置签名时可运行 Debug 验证，Debug 包名为 `fun.yunle.apps.debug`。

首次正式分发或替换旧包前，先核对旧分发渠道、版本号和本地数据，并用正式签名包验收登录、云居同步、购买、扫码和覆盖安装。Debug 覆盖验证可在隔离模拟器上使用同包名、同 debug 签名的新旧包，核对旧壳数据、账号切换和回退；它不替代正式包验收。

新版保留旧壳的默认 WebView 存储供回退。云应用使用按账号和应用隔离的存储，不会自动导入旧壳数据。如果设备的 WebView 不支持隔离，或无法打开相应存储，应用内会停止加载，用户可更新 Android System WebView 或返回目录。

验签后的默认产物：

- `apps/android/app/build/outputs/apk/release/app-release.apk`
- `apps/android/app/build/outputs/bundle/release/app-release.aab`

构建完成后仍需在真机安装 APK，覆盖冷启动、后台恢复、授权同意、取消、其他账号与断网场景；
AAB 上传应用商店前还应复核 versionCode、versionName、目标轨道和发布说明。
