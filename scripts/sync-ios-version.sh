#!/usr/bin/env bash
#
# 把 iOS 版本号与 package.json 自动对齐：
#   - MARKETING_VERSION (CFBundleShortVersionString) ← package.json 的 version
#   - CURRENT_PROJECT_VERSION (CFBundleVersion / build号) ← git commit 总数（全局递增）
#
# 用法：
#   bash scripts/sync-ios-version.sh
#
# 设计：
#   - 版本号只在 package.json 改一处（或 `pnpm release` 用 bumpp 改），iOS 自动跟随
#   - build 号用 `git rev-list --count HEAD`：单调递增、无需记忆上次值、每次提交自动 +1
#     满足 App Store「同一版本号下 build 号必须递增」的要求
#   - 直接改 project.pbxproj 的 build setting（不用 agvtool，避免它把
#     Info.plist 里的 $(MARKETING_VERSION) 引用硬编码掉）
#   - Info.plist 保持 CFBundleShortVersionString=$(MARKETING_VERSION)、
#     CFBundleVersion=$(CURRENT_PROJECT_VERSION)，build setting 是唯一数据源
#
# 已串联进 package.json 的 `build:ios`（`pnpm sync:version && cap build ...`），
# 跑 `pnpm build:ios` 时自动先执行。
# （不用 prebuild 钩子，因为 pnpm 默认 enable-pre-post-scripts=false 不触发 pre/post）

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(node -p "require('./package.json').version")"
BUILD="$(git rev-list --count HEAD)"
PBXPROJ="ios/App/App.xcodeproj/project.pbxproj"

echo "==> 同步 iOS 版本号"
echo "    MARKETING_VERSION       = $VERSION   (来自 package.json)"
echo "    CURRENT_PROJECT_VERSION = $BUILD   (git commit 数)"

# 替换所有出现（Debug + Release 两个 configuration）
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${VERSION};/g" "$PBXPROJ"
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = ${BUILD};/g" "$PBXPROJ"

echo "✅ 已写入 $PBXPROJ"
grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" "$PBXPROJ" | sort -u | sed 's/^/    /'
