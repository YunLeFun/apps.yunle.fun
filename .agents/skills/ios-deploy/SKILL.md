---
name: ios-deploy
description: 打包、部署或发布云乐坊原生 iOS 客户端到手机、模拟器与 TestFlight 内部测试。用于“云乐坊打包内测”“更新云乐坊 TestFlight”“装到手机”；旧 Capacitor 客户端仅在明确要求时使用。
---

# 云乐坊 iOS 部署

当前默认对象是 `YunLeFun/apps.yunle.fun/apps/ios` 的原生 SwiftUI 客户端。先读 `apps/ios/README.md`；它不需要打包 Nuxt、Capacitor 同步或 CocoaPods。

## TestFlight 日常更新

读取同级 [ios-testflight](../ios-testflight/SKILL.md) 共用技能，再读仓库 `docs/dev/testflight.md`，执行其中的项目参数和命令。共用技能也可安装在个人 skills 目录，供云生的 `life-testflight` 调用；两边的打包脚本与数据迁移仍归各自项目维护。

- Scheme：`YunleFun`；正式 Bundle ID：`fun.yunle.apps`；App ID：`6759859441`；内部组：云乐坊内测组。
- 版本来源：`apps/ios/project.yml`；此仓库跟踪 `YunleFun.xcodeproj`，版本调整后按项目要求同步并审查生成差异。不要混入个人 `Info.plist` 或签名改动。
- 原生分步脚本：`bash apps/ios/scripts/testflight.sh archive|export|validate|upload`。上传只在本次用户已授权时设置 `YUNLEFUN_CONFIRM_UPLOAD=1`，不因脚本变量再次询问已有授权。
- 发布助手位于 `apps/mobile/scripts/ios-testflight-publish.mjs`，虽然在 mobile 目录，也用于同 App 的原生构建。按文档同时传 `--version` 与 `--build`，先 dry run 再发布；默认沿用现有测试员。

## 手机或模拟器部署

用户要求普通开发安装时，使用原生 Debug 标识 `fun.yunle.apps.native-dev`；指定 TestFlight 更新则走上一节。根据请求选择设备，遵守仓库模拟器归属和清理约定，不能以创建新设备代替核对现有设备。

Debug 的独立标识不迁移正式版数据。用户要求清理重复 App 时，逐个确认标识与数据，先备份，核验最终版本后才卸载重复开发版。正式版同标识更新通过 TestFlight，不先卸载。

## 旧 Capacitor 客户端

只有用户明确要求维护 `apps/mobile/ios` 时，读取 `docs/dev/testflight-capacitor.md` 和对应 mobile 脚本。此时 `pnpm build`、`pnpm sync`、`pnpm build:ios` 才是该旧客户端的构建路径；不能把它作为原生版的前置步骤。Capacitor CLI 与 `devicectl` 的设备 ID 不通用。
