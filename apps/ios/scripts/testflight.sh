#!/usr/bin/env bash
#
# 原生 iOS 客户端（apps/ios）的 TestFlight 流程，分步执行：
#
#   bash scripts/testflight.sh archive    # Release 归档（自动签名）
#   bash scripts/testflight.sh export     # 导出 App Store Connect .ipa 并核对签名
#   bash scripts/testflight.sh validate   # 交由 App Store Connect 校验，不上传
#   bash scripts/testflight.sh upload     # 上传到 TestFlight（需 YUNLEFUN_CONFIRM_UPLOAD=1）
#
# validate / upload 需要 App Store Connect API Key（Access ≥ App Manager）：
#   export ASC_KEY_ID=xxxxxxxxxx
#   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   export ASC_KEY_P8=~/.appstoreconnect/private_keys/AuthKey_xxxxxxxxxx.p8
# 设置后 archive / export 也改用该 Key 管理签名，否则使用 Xcode 已登录账号。
#
# 正式标识 fun.yunle.apps 与旧版 Capacitor 客户端共用，构建会出现在同一个
# App Store Connect 应用下。旧版占用 0.1.0 的构建号，原生客户端从 0.2.0 起算。
# 产物写入 build/testflight（已忽略）。

set -euo pipefail
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$IOS_DIR/YunleFun.xcodeproj"
SCHEME="${IOS_SCHEME:-YunleFun}"
CONFIGURATION=Release
TEAM_ID="${IOS_TEAM_ID:-QT792GAY4C}"
BUNDLE_ID="${IOS_BUNDLE_ID:-fun.yunle.apps}"
OUT_DIR="${IOS_TESTFLIGHT_DIR:-$IOS_DIR/build/testflight}"
ARCHIVE="$OUT_DIR/YunleFun.xcarchive"
EXPORT_DIR="$OUT_DIR/export"
SIGNING_CERTIFICATE="${IOS_EXPORT_SIGNING_CERTIFICATE:-Apple Distribution}"

fail() {
  echo "❌ $*" >&2
  exit 1
}

auth_args=()
asc_configured() { [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_P8:-}" ]; }
load_asc() {
  if [ -n "${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}${ASC_KEY_P8:-}" ]; then
    asc_configured || fail "ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_P8 需同时设置"
    ASC_KEY_P8="${ASC_KEY_P8/#\~/$HOME}"
    [ -f "$ASC_KEY_P8" ] || fail "找不到 API Key 文件：$ASC_KEY_P8"
    auth_args=(
      -authenticationKeyPath "$ASC_KEY_P8"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID"
    )
  fi
}
require_asc() {
  asc_configured || fail "$1 需要 ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_P8（见脚本开头）"
  load_asc
  # altool 按 Key ID 在 ~/.appstoreconnect/private_keys 等固定目录查找 .p8。
  [ "$(basename "$ASC_KEY_P8")" = "AuthKey_$ASC_KEY_ID.p8" ] \
    || fail "ASC_KEY_P8 文件名应为 AuthKey_$ASC_KEY_ID.p8，altool 才能找到它"
}

plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }

single_ipa() {
  shopt -s nullglob
  local ipas=("$EXPORT_DIR"/*.ipa)
  shopt -u nullglob
  [ "${#ipas[@]}" -eq 1 ] || fail "导出目录应有一个 .ipa，实际 ${#ipas[@]} 个：${EXPORT_DIR}（先运行 export）"
  echo "${ipas[0]}"
}

cmd_archive() {
  load_asc
  if [ -z "${ALLOW_DIRTY:-}" ] && [ -n "$(git -C "$IOS_DIR" status --porcelain -- .)" ]; then
    fail "apps/ios 有未提交的改动；TestFlight 构建应来自已提交的源码（临时绕过：ALLOW_DIRTY=1）"
  fi

  local settings bundle version build
  settings="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null | awk '/Build settings for action build and target YunleFun:/{t=1;next} /Build settings for action/{t=0} t')"
  bundle="$(awk '$1=="PRODUCT_BUNDLE_IDENTIFIER"{print $3; exit}' <<<"$settings")"
  version="$(awk '$1=="MARKETING_VERSION"{print $3; exit}' <<<"$settings")"
  build="$(awk '$1=="CURRENT_PROJECT_VERSION"{print $3; exit}' <<<"$settings")"
  [ "$bundle" = "$BUNDLE_ID" ] || fail "Release 标识为 ${bundle:-未知}，应为 $BUNDLE_ID"

  echo "==> 归档 $BUNDLE_ID $version ($build)"
  rm -rf "$ARCHIVE"
  mkdir -p "$OUT_DIR"
  xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$OUT_DIR/DerivedData" \
    -allowProvisioningUpdates \
    ${auth_args[@]+"${auth_args[@]}"} \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic

  local app
  app="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -type d -name '*.app' -print -quit)"
  [ -n "$app" ] || fail "归档中没有 Products/Applications/*.app"
  [ "$(plist_value "$app/Info.plist" CFBundleIdentifier)" = "$BUNDLE_ID" ] || fail "归档的 CFBundleIdentifier 不是 $BUNDLE_ID"
  [ "$(plist_value "$app/Info.plist" CFBundleShortVersionString)" = "$version" ] || fail "归档版本号与工程不一致"
  [ "$(plist_value "$app/Info.plist" CFBundleVersion)" = "$build" ] || fail "归档构建号与工程不一致"
  [ "$(plist_value "$app/Info.plist" ITSAppUsesNonExemptEncryption)" = "false" ] || fail "缺少 ITSAppUsesNonExemptEncryption=NO"
  [ -f "$app/PrivacyInfo.xcprivacy" ] || fail "归档缺少 PrivacyInfo.xcprivacy"
  plutil -lint "$app/PrivacyInfo.xcprivacy" >/dev/null
  # 先取结果再判断：pipefail 下 `| grep -q` 会因 SIGPIPE 误判。
  [ -z "$(find "$app" -name '*.storekit' -print -quit)" ] || fail "归档内含本地 StoreKit 测试配置，正式构建不应携带"
  echo "✅ 归档完成：${ARCHIVE}（$version / ${build}）"
}

cmd_export() {
  load_asc
  [ -d "$ARCHIVE" ] || fail "找不到归档 ${ARCHIVE}（先运行 archive）"
  rm -rf "$EXPORT_DIR"
  mkdir -p "$EXPORT_DIR"

  # 与旧版脚本一致：Xcode 26 起 stripSwiftSymbols / uploadSymbols 会让导出在
  # packaging 阶段失败，先关闭；dSYM 留在归档中，需要时单独上传。
  local signing
  if [ -n "${IOS_EXPORT_PROFILE_NAME:-}" ]; then
    signing="<key>signingStyle</key><string>manual</string>
	<key>signingCertificate</key><string>$SIGNING_CERTIFICATE</string>
	<key>provisioningProfiles</key><dict><key>$BUNDLE_ID</key><string>$IOS_EXPORT_PROFILE_NAME</string></dict>"
  else
    signing="<key>signingStyle</key><string>automatic</string>"
  fi
  cat > "$EXPORT_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key><string>export</string>
	<key>method</key><string>app-store-connect</string>
	<key>teamID</key><string>$TEAM_ID</string>
	$signing
	<key>stripSwiftSymbols</key><false/>
	<key>uploadSymbols</key><false/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

  echo "==> 导出 App Store Connect .ipa"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_DIR/ExportOptions.plist" \
    -allowProvisioningUpdates \
    ${auth_args[@]+"${auth_args[@]}"}

  local ipa tmp app profile signature
  ipa="$(single_ipa)"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  unzip -q "$ipa" -d "$tmp"
  app="$(find "$tmp/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
  [ -n "$app" ] || fail ".ipa 中没有 Payload/*.app"

  codesign --verify --deep --strict "$app" || fail "codesign 校验失败"
  signature="$(codesign -dvv "$app" 2>&1)"
  grep -qF "Authority=$SIGNING_CERTIFICATE" <<<"$signature" \
    || fail "签名证书不是 ${SIGNING_CERTIFICATE}，TestFlight 会拒绝"
  codesign -d --entitlements :- "$app" 2>/dev/null > "$tmp/entitlements.plist"
  [ "$(plist_value "$tmp/entitlements.plist" get-task-allow)" != "true" ] || fail "get-task-allow 为 true，不是发布签名"
  security cms -D -i "$app/embedded.mobileprovision" > "$tmp/profile.plist" 2>/dev/null || fail "无法读取 embedded.mobileprovision"
  profile="$(plist_value "$tmp/profile.plist" Name)"
  if /usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$tmp/profile.plist" >/dev/null 2>&1; then
    fail "描述文件「${profile}」包含设备列表，不是 App Store 描述文件"
  fi
  echo "✅ 导出完成：$ipa"
  echo "   签名：${SIGNING_CERTIFICATE}；描述文件：$profile"
}

cmd_validate() {
  require_asc validate
  local ipa
  ipa="$(single_ipa)"
  echo "==> App Store Connect 校验（不上传）：$ipa"
  xcrun altool --validate-app --type ios --file "$ipa" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "✅ 校验通过"
}

cmd_upload() {
  require_asc upload
  [ "${YUNLEFUN_CONFIRM_UPLOAD:-}" = "1" ] \
    || fail "上传会在 $BUNDLE_ID 下新增 TestFlight 构建；确认后用 YUNLEFUN_CONFIRM_UPLOAD=1 重新运行"
  local ipa
  ipa="$(single_ipa)"
  echo "==> 上传到 App Store Connect / TestFlight：$ipa"
  xcrun altool --upload-app --type ios --file "$ipa" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "🎉 上传完成。处理约 10–30 分钟后出现在 https://appstoreconnect.apple.com/apps/6759859441 的 TestFlight。"
}

case "${1:-}" in
  archive) cmd_archive ;;
  export) cmd_export ;;
  validate) cmd_validate ;;
  upload) cmd_upload ;;
  *)
    sed -n '3,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 64
    ;;
esac
