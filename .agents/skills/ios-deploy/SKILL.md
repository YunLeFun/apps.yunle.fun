---
name: ios-deploy
description: 打包、部署或发布云乐坊原生 iOS 客户端到手机、模拟器与 TestFlight 内部测试。用于“云乐坊打包内测”“更新云乐坊 TestFlight”“装到手机”；旧 Capacitor 客户端仅在明确要求时使用。
---

# 云乐坊 iOS 部署

当前默认对象是 `YunLeFun/apps.yunle.fun/apps/ios` 的原生 SwiftUI 客户端。先读 `apps/ios/README.md`；它不需要打包 Nuxt、Capacitor 同步或 CocoaPods。

## TestFlight 日常更新

先读取已安装的 `ios-testflight`，再读 `docs/dev/testflight.md` 的项目参数。共用技能唯一维护源是 [YunYouJun/ai](https://github.com/YunYouJun/ai/blob/main/skills/ios-testflight/SKILL.md)，安装命令为 `npx skills add YunYouJun/ai --skill=ios-testflight`。未安装时可读取已有 ai checkout 的 `skills/ios-testflight/`，或取得该可信仓库的技能及引用文件；不再维护本仓库的同名副本。

- Scheme：`YunleFun`；正式 Bundle ID：`fun.yunle.apps`；App ID：`6759859441`；内部组：云乐坊内测组。
- 版本来源：`apps/ios/project.yml`；此仓库跟踪 `YunleFun.xcodeproj`，版本调整后按项目要求同步并审查生成差异。不要混入个人 `Info.plist` 或签名改动。
- 默认按共用技能的 ASC CLI 路径执行：归档、导出、精确版本查询、上传和内部组验收；Apple IPA 校验保留 altool。导出配置为 `apps/ios/ExportOptions-TestFlight.plist`。
- `apps/ios/scripts/testflight.sh` 和 `apps/mobile/scripts/ios-testflight-publish.mjs` 只作已确认兼容问题的回退，详见 `docs/dev/testflight-fallback.md`。上传仍要求本次授权；已有明确授权不重复确认。默认不新增测试员。

## 手机或模拟器部署

用户要求普通开发安装时，使用原生 Debug 标识 `fun.yunle.apps.native-dev`；指定 TestFlight 更新则走上一节。根据请求选择设备，遵守仓库模拟器归属和清理约定，不能以创建新设备代替核对现有设备。

Debug 的独立标识不迁移正式版数据。用户要求清理重复 App 时，逐个确认标识与数据，先备份，核验最终版本后才卸载重复开发版。正式版同标识更新通过 TestFlight，不先卸载。

## 旧 Capacitor 客户端

只有用户明确要求维护 `apps/mobile/ios` 时，读取 `docs/dev/testflight-capacitor.md` 和对应 mobile 脚本。此时 `pnpm build`、`pnpm sync`、`pnpm build:ios` 才是该旧客户端的构建路径；不能把它作为原生版的前置步骤。Capacitor CLI 与 `devicectl` 的设备 ID 不通用。
