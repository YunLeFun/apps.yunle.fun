#!/usr/bin/env bash
#
# 一键：从已有 archive 导出 app-store .ipa 并上传到 TestFlight
#
# 用法：
#   export IOS_EXPORT_PROFILE_NAME='iOS Team Store Provisioning Profile: fun.yunle.apps'
#   export ASC_KEY_ID=xxxxxxxxxx
#   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   export ASC_KEY_P8=~/.appstoreconnect/private_keys/AuthKey_xxxxxxxxxx.p8
#   bash scripts/ios-testflight.sh
#
# 前提：
#   - 已跑过 pnpm build / pnpm sync，且 ios/App/App.xcarchive 存在
#     （或先跑 `LANG=en_US.UTF-8 pnpm build:ios` 重新 archive）
#   - 已创建 App Store Connect API Key（Access ≥ App Manager，上传需要）
#
# 文档：docs/dev/testflight.md

set -euo pipefail
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../ios/App" && pwd)"
SCHEME="${IOS_SCHEME:-App}"
TEAM_ID="${IOS_TEAM_ID:-QT792GAY4C}"
BUNDLE_ID="${IOS_BUNDLE_ID:-fun.yunle.apps}"
ARCHIVE="${IOS_ARCHIVE_PATH:-$IOS_DIR/$SCHEME.xcarchive}"
EXPORT_DIR="${IOS_EXPORT_DIR:-$IOS_DIR/output-appstore}"
SIGNING_CERTIFICATE="${IOS_EXPORT_SIGNING_CERTIFICATE:-Apple Distribution}"
TMP=""

cleanup() {
  if [ -n "$TMP" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}
trap 'status=$?; cleanup; exit "$status"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -z "${ASC_KEY_ID:-}" ]; then
  echo "❌ 需要设置 ASC_KEY_ID" >&2
  exit 1
fi
if [ -z "${ASC_ISSUER_ID:-}" ]; then
  echo "❌ 需要设置 ASC_ISSUER_ID" >&2
  exit 1
fi
if [ -z "${ASC_KEY_P8:-}" ]; then
  echo "❌ 需要设置 ASC_KEY_P8（.p8 文件绝对路径）" >&2
  exit 1
fi
if [ -z "${IOS_EXPORT_PROFILE_NAME:-}" ]; then
  echo "❌ 需要设置 IOS_EXPORT_PROFILE_NAME（App Store provisioning profile 名称）" >&2
  exit 1
fi
PROFILE_NAME="$IOS_EXPORT_PROFILE_NAME"

# 展开 ~ 路径
ASC_KEY_P8="${ASC_KEY_P8/#\~/$HOME}"

if [ ! -d "$ARCHIVE" ]; then
  echo "❌ 找不到 $ARCHIVE"
  echo "   请先跑：LANG=en_US.UTF-8 pnpm build:ios"
  exit 1
fi
if [ ! -f "$ASC_KEY_P8" ]; then
  echo "❌ 找不到 API Key 文件：$ASC_KEY_P8"
  exit 1
fi

echo "==> 生成 ExportOptions.plist（app-store-connect，manual signing）"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/ExportOptions.plist"
shopt -s nullglob
old_ipas=("$EXPORT_DIR"/*.ipa)
shopt -u nullglob
if [ "${#old_ipas[@]}" -gt 0 ]; then
  rm -f "${old_ipas[@]}"
fi
cat > "$EXPORT_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>export</string>
	<key>method</key>
	<string>app-store-connect</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>$SIGNING_CERTIFICATE</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>$BUNDLE_ID</key>
		<string>$PROFILE_NAME</string>
	</dict>
	<!--
	  关键：Xcode 26 下 stripSwiftSymbols/uploadSymbols=true 会在 packaging
	  阶段触发 "IDEDistributionPackagingStep: Copy failed"。
	  关掉后 export 正常。代价：dSYM 不随包上传，崩溃日志符号化缺失，
	  可后续用 `xcrun altool --upload-symbols` 或 RUM 单独补传，不影响上架。
	-->
	<key>stripSwiftSymbols</key>
	<false/>
	<key>uploadSymbols</key>
	<false/>
	<key>teamID</key>
	<string>$TEAM_ID</string>
</dict>
</plist>
EOF

echo "==> 导出 .ipa（本机 Distribution 证书 + App Store profile）"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_P8" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

shopt -s nullglob
ipa_files=("$EXPORT_DIR"/*.ipa)
shopt -u nullglob
if [ "${#ipa_files[@]}" -ne 1 ]; then
  echo "❌ 导出目录应产出一个 .ipa，实际为 ${#ipa_files[@]} 个：$EXPORT_DIR"
  exit 1
fi
IPA="${ipa_files[0]}"
echo "✅ 导出成功：$IPA"

echo "==> 校验 .ipa 签名"
TMP="$(mktemp -d)"
unzip -q "$IPA" -d "$TMP"
APP_BUNDLE="$(find "$TMP/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [ -z "$APP_BUNDLE" ]; then
  echo "❌ .ipa 中未找到 Payload/*.app"
  exit 1
fi
codesign -dvv "$APP_BUNDLE" 2>&1 | grep -F "Authority=$SIGNING_CERTIFICATE" || {
  echo "⚠️ 签名不是 Apple Distribution，TestFlight 会拒绝"; exit 1;
}
cleanup
TMP=""

echo "==> 上传到 App Store Connect / TestFlight"
xcrun altool --upload-app \
  --type ios \
  --file "$IPA" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

echo
echo "🎉 上传完成。10-30 分钟后到 https://appstoreconnect.apple.com/apps/6759859441 的 TestFlight Tab 查看构建。"
