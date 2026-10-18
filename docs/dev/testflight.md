# 云乐坊原生 iOS TestFlight 内部测试

日常更新发布 `apps/ios` 下的原生客户端，顺序为：**确认源码与版本 → archive → export → 核验 IPA → validate → upload → 内测组验收 → 按需更新手机**。每个阶段单独执行和留回执。

旧 Capacitor 客户端的命令保存在[历史流程](./testflight-capacitor.md)，不作为当前原生发布的前置步骤。`pnpm build:ios` 目前仍转发旧 mobile 脚本；原生版使用本页的 `apps/ios/scripts/testflight.sh`，不需要打包 Nuxt 或同步 CocoaPods。

## 与云生共用

[共用 ios-testflight skill](https://github.com/YunLeFun/apps.yunle.fun/blob/main/.agents/skills/ios-testflight/SKILL.md) 负责源码与授权、版本检查、仅内部导出、签名和 Apple 校验、精确构建选择、分发验收、凭据与交付规则。`ios-deploy` 和云生的 `life-testflight` 只负责路由到各自文档与项目参数。

共用技能维护在本仓库 `.agents/skills/ios-testflight/`，安装到个人 skills 目录后可在两个仓库直接调用；仓库内 `ios-deploy` 也能直接读取同级共用技能。更新共用技能源后同步本机安装副本。项目命令、导出配置及迁移实现仍归各仓库维护，无需让两个应用的打包脚本跨仓库互相导入。

| 项目              | 云乐坊                                       | 云生                                                                                     |
| ----------------- | -------------------------------------------- | ---------------------------------------------------------------------------------------- |
| 仓库              | `YunLeFun/apps.yunle.fun`                    | `YunYouJun/life`                                                                         |
| 原生工程 / Scheme | `apps/ios` / YunleFun                        | `apps/ios` / Life                                                                        |
| 正式 Bundle ID    | `fun.yunle.apps`                             | `cn.yunyoujun.life`                                                                      |
| 内部组            | 云乐坊内测组                                 | 云生内测组                                                                               |
| 版本来源          | `apps/ios/project.yml`                       | `apps/ios/project.yml`                                                                   |
| 工程跟踪          | 跟踪 YunleFun.xcodeproj                      | Life.xcodeproj 生成后忽略                                                                |
| 首次切换          | 旧壳与原生共用标识，保留容器后显式导入旧数据 | `.dev` 与正式版容器独立，先迁移再清理                                                    |
| 项目命令          | 本页                                         | [云生发布文档](https://github.com/YunYouJun/life/blob/main/docs/guide/ios-testflight.md) |

同团队可以使用同一把已有授权的 API Key；App ID、Bundle ID、版本、组、测试说明和回执仍分别核对。切换项目时显式设置本次 App 参数，不能继承上个应用的元数据或跨 App 复用 betaTester ID。

## 已验证基线与版本来源

2026-10-19 已从 main `f7e172834fa2b4b8ca3d07b0f824e3f80b1f5564` 发布 **0.2.0 (1)**，完成归档、导出、Apple 校验、上传和内部组验收：`VALID`、`INTERNAL_ONLY`、`IN_BETA_TESTING`、外部状态 `NOT_APPLICABLE`。该次使用已有内部组成员，未新增邀请；手机已从 TestFlight 安装并确认只有一份云乐坊。这是该版本的发布基线，不替代后续版本各自的验收。

| 参数                     | 当前项目配置                                                              |
| ------------------------ | ------------------------------------------------------------------------- |
| App Store Connect App ID | `6759859441`                                                              |
| 正式 / Debug 标识        | `fun.yunle.apps` / `fun.yunle.apps.native-dev`                            |
| Scheme / Configuration   | `YunleFun` / `Release`                                                    |
| Team                     | `QT792GAY4C`                                                              |
| 版本 / 构建              | `apps/ios/project.yml` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` |
| 分步脚本                 | `apps/ios/scripts/testflight.sh`                                          |
| 内部组                   | 云乐坊内测组                                                              |

构建 `0.2.0 (1)` 已占用。每次先查询已上传记录，再递增原生构建号；不要用旧 mobile 包版本或 Git 提交次数计算它。修改 `project.yml` 后用 XcodeGen 同步当前仓库跟踪的 Xcode 工程，审查并提交相关差异，不混入个人 `Info.plist`、本地签名设置或其他任务改动。

## 准备源码和环境

使用最新 main 或用户指定的已提交版本。先 fetch、检查工作树和当前设备归属；存在其他任务改动时用独立工作树，不 stash、reset 或提交别人的文件。完成适合源码改动的检查并提交后，再归档。

需要符合项目配置的 Xcode、XcodeGen、锁定的 Swift 包，以及本机签名证书或有权限的 App Store Connect API Key。先检查 `xcodebuild -version` 与 `xcrun altool --help`。如需选择 Xcode，只对当前进程设置 `DEVELOPER_DIR`，避免修改全局状态。

以下从仓库根、同一个 Bash 会话执行。版本和构建号示例需替换为本次已确认且提交的值：

```bash
set -euo pipefail

export IOS_VERSION='0.2.0'
export IOS_BUILD='2'
export ASC_KEY_ID='<Key ID>'
export ASC_ISSUER_ID='<团队 Issuer ID>'
export ASC_KEY_P8="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
export API_PRIVATE_KEYS_DIR="$(dirname "$ASC_KEY_P8")"
export ASC_BUNDLE_ID='fun.yunle.apps'
export ASC_INTERNAL_GROUP='云乐坊内测组'

test -f "$ASC_KEY_P8"
chmod 600 "$ASC_KEY_P8"

ylf_commit="$(git rev-parse HEAD)"
export IOS_TESTFLIGHT_DIR="${CODEX_HOME:-$HOME/.codex}/artifacts/yunlefun/testflight-${IOS_VERSION}-${IOS_BUILD}-${ylf_commit:0:7}"
test ! -e "$IOS_TESTFLIGHT_DIR"
mkdir -p "$IOS_TESTFLIGHT_DIR"
chmod 700 "$IOS_TESTFLIGHT_DIR"
git rev-parse HEAD > "$IOS_TESTFLIGHT_DIR/source-commit.txt"
git archive HEAD -o "$IOS_TESTFLIGHT_DIR/source.tar"
```

Issuer ID 来自 App Store Connect“用户和访问 → 集成 → App Store Connect API”；Key ID 与当前使用的 `AuthKey_<Key ID>.p8` 文件匹配。`.p8` 权限保持 600，不把私钥、JWT、完整测试员邮箱或个人设备标识写入仓库与共享日志，不启用 `set -x`。默认自动签名，不需要把本机 provisioning profile 名称写进仓库；确需 manual signing 时再设置匹配的 `IOS_EXPORT_PROFILE_NAME`。

## 归档、导出与包检查

```bash
bash apps/ios/scripts/testflight.sh archive > "$IOS_TESTFLIGHT_DIR/archive.log" 2>&1
bash apps/ios/scripts/testflight.sh export > "$IOS_TESTFLIGHT_DIR/export.log" 2>&1
```

产物为 `$IOS_TESTFLIGHT_DIR/YunleFun.xcarchive`、`export/ExportOptions.plist` 和唯一的 `export/*.ipa`。脚本检查 Release 标识、版本、隐私清单、加密声明，并拒绝携带本地 StoreKit 测试配置；导出后检查签名和 App Store 描述文件。`.xcarchive` 内 `.app` 可能仍是开发签名，不能用它替代导出 IPA 的签名核验。

导出固定 `destination = export`、`method = app-store-connect`、`testFlightInternalTestingOnly = true`、`manageAppVersionAndBuildNumber = false`。validate 和 upload 还会重新读取包内标识与 `TFInternalTestingOnly`，拒绝旧导出或另一个 App 的 IPA。Swift 符号选项沿用原生脚本的配置；归档内 dSYM 保留，是否上传符号单独记录。

再核对本次期望版本和哈希：

```bash
python3 - <<'PY'
import os
import pathlib
import plistlib
import zipfile

root = pathlib.Path(os.environ['IOS_TESTFLIGHT_DIR'])
ipas = list((root / 'export').glob('*.ipa'))
assert len(ipas) == 1
with zipfile.ZipFile(ipas[0]) as archive:
    names = [name for name in archive.namelist()
             if name.startswith('Payload/') and name.count('/') == 2
             and name.endswith('.app/Info.plist')]
    assert len(names) == 1
    info = plistlib.loads(archive.read(names[0]))
    assert info['CFBundleIdentifier'] == 'fun.yunle.apps'
    assert info['CFBundleShortVersionString'] == os.environ['IOS_VERSION']
    assert info['CFBundleVersion'] == os.environ['IOS_BUILD']
    assert info['TFInternalTestingOnly'] is True
print('IPA app, version, build and internal-only flag verified')
PY

shasum -a 256 "$IOS_TESTFLIGHT_DIR"/export/*.ipa > "$IOS_TESTFLIGHT_DIR/ipa.sha256"
```

只要求打包时可继续完成 validate，保留结果后交付，不进入 upload。源码、版本或依赖有变更就重新归档；仅重试网络或 Apple 状态查询时先核对原产物和回执，不覆盖已有发布目录。

## Apple 校验与上传

```bash
bash apps/ios/scripts/testflight.sh validate > "$IOS_TESTFLIGHT_DIR/validate.log" 2>&1
```

确认退出码为 0、Apple 校验无错误后，且本次请求已明确授权上传，再执行：

```bash
YUNLEFUN_CONFIRM_UPLOAD=1 bash apps/ios/scripts/testflight.sh upload \
  > "$IOS_TESTFLIGHT_DIR/upload.log" 2>&1
```

`YUNLEFUN_CONFIRM_UPLOAD` 是脚本的显式上传开关；用户已明确要求上传/更新 TestFlight 时直接设置，不重复确认。保存 delivery UUID，上传后仍需等待 Apple 处理。状态不明确时先查询 delivery/构建记录，不直接重传。[Apple 上传说明](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)

## 内部测试分发与验收

处理完成后，精确匹配本次 iOS 营销版本和构建号。现有发布助手可用于原生同标识的构建；同时传入两个参数，不只传 `--build`：

```bash
export ASC_WHATS_NEW='<本次实际改动与需要验证的行为>'
pnpm publish:ios:testflight -- --version "$IOS_VERSION" --build "$IOS_BUILD" --dry-run \
  > "$IOS_TESTFLIGHT_DIR/publish-dry-run.log" 2>&1
```

核对 dry run 的 Bundle ID、版本、构建号、Build ID、内部组和拟变更，再发布：

```bash
pnpm publish:ios:testflight -- --version "$IOS_VERSION" --build "$IOS_BUILD" \
  > "$IOS_TESTFLIGHT_DIR/publish.log" 2>&1
```

助手只接受 `VALID`、未过期且 `INTERNAL_ONLY` 的目标，按 `preReleaseVersion` 同时限定 iOS 营销版本；同构建号有多个候选且未指定版本时会拒绝。复用“云乐坊内测组”，开启自动分发与反馈，更新测试说明和当前加密声明。默认不新增测试员，日常更新沿用已有成员。

最终必须确认构建已关联、有可用内部成员、`IN_BETA_TESTING` 且外部状态为 `NOT_APPLICABLE`。在 [App Store Connect TestFlight](https://appstoreconnect.apple.com/apps/6759859441/testflight) 保存显示对应版本“正在测试”和内部组的截图，隐藏无关账户信息。先验收自动分发结果，已经关联时不重复建组或邀请。

首次建组或明确要求增加成员时，从具备该 App 权限的已有 ASC 内部用户中选择；跨 App 的 betaTester ID 不直接通用。首次关联优先通过网页核对，不启用外部组、公开链接或提交 Beta App Review。[Apple 内部测试说明](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)

## 手机更新、数据与交付

用户要求更新手机时，从 TestFlight 更新“云乐坊”，核对本次版本、“打开”、正常启动、原有云居和账号状态，以及自动更新设置。正式标识沿用 `fun.yunle.apps`，不先卸载旧 App。覆盖安装保留容器不代表 Capacitor localStorage 已完成原生导入，按[旧版数据导入](./ios-upgrade-migration.md)和[云居备份](./ios-home-backups.md)核验，保留已有待验边界。

独立开发 / Benchmark 标识不会自动迁移正式数据。清理重复 App 前逐一确认标识、数据与归属，先备份，验证最终 TestFlight 版本后再删除对应测试 App；不能按显示名称批量删除。用户只要求服务器发布时不自动操作手机，设备阻塞时分别报告已发布与未安装的状态。

在仓库外保留源码提交与副本、版本/构建、归档和 dSYM、导出配置、IPA 与 SHA-256、校验/上传/发布回执、delivery/Build ID、内部组截图和手机验证结果。安装包、归档、DerivedData、私钥、个人配置和手机数据不进 Git。模拟器按仓库归属与清理约定使用，本流程无需模拟器时不创建。
