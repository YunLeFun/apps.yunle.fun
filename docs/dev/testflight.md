# 云乐坊原生 iOS TestFlight 内部测试

> 2026-10-26：已提交 **0.2.0 (3)**，完成标准 iPhone 候选验证（Duo 专项仍失败）、iCloud capability / 新 profile、Release Archive、仅内部 IPA 导出、共用脚本及 Apple 零错误校验。**未上传或分发**。完整来源、摘要、支付限制和失败记录见[本轮验收](./testflight-preflight-20261026.md)，[中文测试说明](./testflight-notes-0.2.0-3.zh-Hans.md)已准备。已处理最高号为 2；Xcode 导出准备另产生本次构建 3 的 `AWAITING_UPLOAD` 记录及分析元数据（没有 IPA），当前新建下一号为 4；实际上传前先核对并恢复本次记录。

本轮本机自动导出缺少云托管分发证书权限，已使用现有本机 Distribution 私钥及含 iCloud KVS 的新 profile 手动导出。机器专用 ExportOptions 留在仓库外；局部 export、仅内部、不改版本号等限制保留，仓库通用模板不写个人签名设置。

默认发布 `apps/ios` 原生客户端，通过 **ASC CLI 归档和导出 → IPA 核验 → Apple 校验 → 上传 → 现有内部组验收**。共用步骤唯一维护在 [YunYouJun/ai 的 ios-testflight](https://github.com/YunYouJun/ai/blob/main/skills/ios-testflight/SKILL.md)，本页维护项目参数和资源准备；入口为 `ios-deploy`。

旧 Capacitor 命令在[历史流程](./testflight-capacitor.md)，不作为原生发布前置步骤。`pnpm build:ios` 仍指向旧 mobile 路径。

## 安装共用工具

```bash
npx skills add YunYouJun/ai --skill=ios-testflight
brew install asc
asc version
xcodebuild -version
```

共用技能可供两个项目直接安装使用，不再在云乐坊维护通用副本。未安装时可以读取已有 ai checkout 的 `skills/ios-testflight/` 或获取该可信仓库的技能和引用文件。`SKILL_DIR` 指向本次实际读取的技能目录，不假定本机路径。当前命令按 ASC CLI 5.14.3 核对；升级后先读对应 `--help`。

## 项目参数与已发布基线

| 参数                   | 本项目                                                                    |
| ---------------------- | ------------------------------------------------------------------------- |
| App ID                 | `6759859441`                                                              |
| 正式 / Debug Bundle ID | `fun.yunle.apps` / `fun.yunle.apps.native-dev`                            |
| 工程 / Scheme          | `apps/ios/YunleFun.xcodeproj` / `YunleFun`                                |
| Team / Configuration   | `QT792GAY4C` / `Release`                                                  |
| 版本来源               | `apps/ios/project.yml` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` |
| 内部组 / ID            | 云乐坊内测组 / `15cca729-b449-4d73-908c-2ee09f0eef68`                     |
| 导出配置               | `apps/ios/ExportOptions-TestFlight.plist`                                 |
| 隐私声明               | `apps/ios/YunleFun/PrivacyInfo.xcprivacy`                                 |

2026-10-19 已从 main 发布 **0.2.0 (2)**，完成 Apple 校验和 `VALID / INTERNAL_ONLY / IN_BETA_TESTING` 验收，外部 `NOT_APPLICABLE`。构建号 2 已占用。下次先查询服务器（包含上传中的构建），再更新并提交版本，不能照抄示例 3。本仓库跟踪 `YunleFun.xcodeproj`，修改 `project.yml` 后同步并审查生成差异；不混入个人 Info.plist 或本地签名配置。

## 准备工作树与项目变量

使用最新远端 main 或用户指定的提交。主工作区被其他任务使用时新建独立工作树，不 stash、reset、切换或提交别人的文件。先完成相应检查，再归档；若从候选提交归档、随后合并，应确认合并后源码与归档来源完全一致并记录 main 提交。

以下在目标仓库根目录的同一个 Bash 会话设置；凭据占位符和 `SKILL_DIR` 需替换为本次实际值。先创建仓库外的新产物目录，避免覆盖上次回执：

```bash
set -euo pipefail

export APP_ID='6759859441'
export BUNDLE_ID='fun.yunle.apps'
export TEAM_ID='QT792GAY4C'
export GROUP_ID='15cca729-b449-4d73-908c-2ee09f0eef68'
export IOS_PROJECT='apps/ios/YunleFun.xcodeproj'
export IOS_SCHEME='YunleFun'
export IOS_VERSION='0.2.0'
export IOS_BUILD='3' # 仅示例；先查询，再改 project.yml 并提交
export EXPORT_OPTIONS='apps/ios/ExportOptions-TestFlight.plist'
export PRIVACY_MANIFEST='apps/ios/YunleFun/PrivacyInfo.xcprivacy'
export ENCRYPTION='false'
export SKILL_DIR='/path/to/installed/ios-testflight'

export ASC_KEY_ID='<Key ID>'
export ASC_ISSUER_ID='<团队 Issuer ID>'
export ASC_KEY_P8="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
test -f "$ASC_KEY_P8"
chmod 600 "$ASC_KEY_P8"

export RELEASE_DIR="${CODEX_HOME:-$HOME/.codex}/artifacts/yunlefun/testflight-$(date +%Y%m%d-%H%M%S)"
test ! -e "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR/export"
chmod 700 "$RELEASE_DIR"
export ARCHIVE="$RELEASE_DIR/YunleFun.xcarchive"
export IPA="$RELEASE_DIR/export/YunleFun.ipa"
export WHATS_NEW='<本次实际改动与测试重点>'
```

按共用技能的[认证与版本查询](https://github.com/YunYouJun/ai/blob/main/skills/ios-testflight/references/asc-cli.md#变量与准备)将 `ASC_KEY_P8` 映射到 ASC CLI 的 `ASC_PRIVATE_KEY_PATH`，查询新构建号并提交版本。Issuer ID 从 App Store Connect“用户和访问 → 集成 → App Store Connect API”取得，Key ID 与本机 `.p8` 文件名对应；不写入仓库，不输出私钥、JWT、完整测试员邮箱或个人设备标识。

版本提交后准备本项目资源和工程：

```bash
xcodegen generate --spec apps/ios/project.yml
git diff --check
git rev-parse HEAD > "$RELEASE_DIR/source-commit.txt"
git archive HEAD -o "$RELEASE_DIR/source.tar"
```

确认待发布源码已提交。生成工程或资源如产生了应跟踪的差异，先审查、提交并重新记录源码；不以 `ALLOW_DIRTY` 绕过归档来源核验。

## 执行共用流程

读取并执行共用技能的 [ASC CLI 命令](https://github.com/YunYouJun/ai/blob/main/skills/ios-testflight/references/asc-cli.md)。上述变量直接供它使用，无需导入另一个应用的脚本或配置。

- 导出配置固定仅内部测试、局部导出及保留源码版本，Swift 符号选项沿用本项目已验证值；归档及 dSYM 保留。
- 用共用 `verify_release.py ipa` 检查正式标识、版本、构建号、隐私清单、Apple Distribution 签名和 App Store 描述文件；再用 `altool --validate-app` 做 Apple 包校验。
- 用户明确要求上传/更新 TestFlight 后，用 ASC CLI 上传同一个 SHA-256 的 IPA。保存上传回执，按 App、营销版本、iOS 平台和构建号等待处理，不能用 `--latest` 或盲目重传。
- 先用只读服务器核验和 `add-groups --dry-run` 检查已有内部组，再执行必要关联及测试说明更新；自动分发已关联则不重复关联。日常更新沿用现有组、自动分发、反馈与成员，不新增邀请。
- 最终 `verify_release.py server --phase published` 必须通过：仅内部、有效未过期、正确版本和组、有成员、`IN_BETA_TESTING`，外部 `NOT_APPLICABLE` 且未关联外测组。保存回执及可核对的页面截图；网页会话失效时可以 API 回执验收并记录原因。

ASC CLI 的 `builds upload --dry-run` 会预留上传操作，不是只读预检；`asc validate` 也不替代 Apple IPA 校验。精确旗标与恢复规则以共用参考为准。

## 手机、兼容回退与交付

仅在用户要求时从 TestFlight 更新正式标识，确认版本、“打开”、正常启动、原有数据及自动更新；不先卸载正式 App。旧 Capacitor 与原生正式版共用标识；覆盖安装保留容器不代表 WebKit 数据已导入。按[旧版导入](./ios-upgrade-migration.md)和[云居备份](./ios-home-backups.md)验证。开发/Benchmark 标识须分别确认容器，不能按显示名称批量删除。

ASC CLI 不可用或存在已确认的兼容问题时，使用 [Xcode/altool 回退](./testflight-fallback.md)，保留全部仅内部与校验条件并记录原因。一次命令失败不自动授权扩大分发范围或重传。首次建档、登录或协议需要人工处理时明确待办，不伪报完成。

产物、源码副本、归档和 dSYM、导出配置、IPA 哈希及校验/上传/发布回执放在仓库外，分别报告服务器发布和手机验证结果。无需模拟器时不创建；使用时遵守归属、复用和本次临时设备清理约定。
