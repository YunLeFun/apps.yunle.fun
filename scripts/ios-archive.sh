#!/usr/bin/env bash
#
# Create the iOS release archive that scripts/ios-testflight.sh exports and uploads.
# Archive directly with xcodebuild so automatic signing can create or download the
# provisioning profile before the separate, manual-signing export step.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT/ios/App"

SCHEME="${IOS_SCHEME:-App}"
TARGET="${IOS_TARGET:-App}"
CONFIGURATION="${IOS_CONFIGURATION:-Release}"
TEAM_ID="${IOS_TEAM_ID:-QT792GAY4C}"
BUNDLE_ID="${IOS_BUNDLE_ID:-fun.yunle.apps}"
WORKSPACE="${IOS_WORKSPACE:-$SCHEME.xcworkspace}"
ARCHIVE_PATH="${IOS_ARCHIVE_PATH:-$IOS_DIR/$SCHEME.xcarchive}"

export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

cd "$ROOT"
bash scripts/sync-ios-version.sh

if [ ! -d "$IOS_DIR/$WORKSPACE" ] && [ ! -f "$IOS_DIR/$WORKSPACE" ]; then
  echo "Missing Xcode workspace: $IOS_DIR/$WORKSPACE" >&2
  exit 1
fi

case "$ARCHIVE_PATH" in
  *.xcarchive) ;;
  *)
    echo "IOS_ARCHIVE_PATH must end in .xcarchive: $ARCHIVE_PATH" >&2
    exit 1
    ;;
esac

ACTUAL_BUNDLE_ID="$(
  cd "$IOS_DIR"
  xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null \
    | awk -v target="$TARGET" '
        index($0, "Build settings for action build and target " target ":") { in_target = 1; next }
        in_target && $1 == "PRODUCT_BUNDLE_IDENTIFIER" && $2 == "=" { print $3; exit }
      '
)"
if [ -z "$ACTUAL_BUNDLE_ID" ]; then
  echo "Could not read PRODUCT_BUNDLE_IDENTIFIER for target $TARGET" >&2
  exit 1
fi
if [ "$ACTUAL_BUNDLE_ID" != "$BUNDLE_ID" ]; then
  echo "Bundle ID mismatch: target $TARGET uses $ACTUAL_BUNDLE_ID, expected $BUNDLE_ID" >&2
  echo "Update the Xcode target (and related App Store configuration) before archiving." >&2
  exit 1
fi

auth_args=()
if [ -n "${ASC_KEY_P8:-}" ] || [ -n "${ASC_KEY_ID:-}" ] || [ -n "${ASC_ISSUER_ID:-}" ]; then
  : "${ASC_KEY_P8:?ASC_KEY_P8 is required when using App Store Connect API authentication}"
  : "${ASC_KEY_ID:?ASC_KEY_ID is required when using App Store Connect API authentication}"
  : "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required when using App Store Connect API authentication}"

  ASC_KEY_P8="${ASC_KEY_P8/#\~/$HOME}"
  if [ ! -f "$ASC_KEY_P8" ]; then
    echo "Missing App Store Connect API key file: $ASC_KEY_P8" >&2
    exit 1
  fi

  auth_args=(
    -authenticationKeyPath "$ASC_KEY_P8"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
fi

echo "==> Archiving iOS app"
echo "    workspace: $WORKSPACE"
echo "    scheme: $SCHEME"
echo "    target: $TARGET"
echo "    configuration: $CONFIGURATION"
echo "    archive: $ARCHIVE_PATH"
echo "    team: $TEAM_ID"
echo "    bundle: $BUNDLE_ID"

rm -rf "$ARCHIVE_PATH"

cd "$IOS_DIR"
xcodebuild archive \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -configuration "$CONFIGURATION" \
  -allowProvisioningUpdates \
  "${auth_args[@]}" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic

echo "Archive created: $ARCHIVE_PATH"
