#!/usr/bin/env bash
#
# 一键：从已有 archive 导出 app-store .ipa 并上传到 TestFlight
#
# 用法：
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
ARCHIVE="$IOS_DIR/App.xcarchive"
EXPORT_DIR="$IOS_DIR/output-appstore"

: "${ASC_KEY_ID:?需要设置 ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?需要设置 ASC_ISSUER_ID}"
: "${ASC_KEY_P8:?需要设置 ASC_KEY_P8（.p8 文件绝对路径）}"

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

echo "==> 生成 ExportOptions.plist（app-store-connect，automatic + cloud signing）"
mkdir -p "$EXPORT_DIR"
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
	<string>automatic</string>
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
	<string>QT792GAY4C</string>
</dict>
</plist>
EOF

echo "==> 导出 .ipa（API Key 认证走命令行参数，需 Admin 级 key 做 cloud signing）"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_P8" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

IPA="$EXPORT_DIR/App.ipa"
if [ ! -f "$IPA" ]; then
  echo "❌ 导出未产出 .ipa"
  exit 1
fi
echo "✅ 导出成功：$IPA"

echo "==> 校验 .ipa 签名"
TMP="$(mktemp -d)"
unzip -q "$IPA" -d "$TMP"
codesign -dvv "$TMP/Payload/App.app" 2>&1 | grep -E "Authority=Apple Distribution" || {
  echo "⚠️ 签名不是 Apple Distribution，TestFlight 会拒绝"; exit 1;
}
rm -rf "$TMP"

echo "==> 上传到 App Store Connect / TestFlight"
xcrun altool --upload-app \
  --type ios \
  --file "$IPA" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

echo
echo "🎉 上传完成。10-30 分钟后到 https://appstoreconnect.apple.com/apps/6759859441 的 TestFlight Tab 查看构建。"
