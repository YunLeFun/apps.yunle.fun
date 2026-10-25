#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
  run|--verify|--debug|--logs|--telemetry|--build|--test) ;;
  *) echo "usage: $0 [--verify|--debug|--logs|--telemetry|--build|--test]" >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/apps/macos"
BUILD_DIR="$PROJECT_DIR/build"
DERIVED_DATA="${YLF_MAC_DERIVED_DATA:-$BUILD_DIR/DerivedData}"
APP_BUNDLE="$BUILD_DIR/YunleFunMac.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/YunleFunMac"
running_app_pids() {
  while read -r app_pid; do
    if [[ "$(ps -p "$app_pid" -o comm= 2>/dev/null || true)" == "$APP_BINARY" ]]; then
      printf '%s\n' "$app_pid"
    fi
  done < <(pgrep -x YunleFunMac || true)
}
mkdir -p "$BUILD_DIR"
RUN_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/yunlefun-macos.XXXXXX")"
trap 'rm -rf "$RUN_TEMP"' EXIT

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --spec "$PROJECT_DIR/project.yml" >/dev/null
fi

# Only stop this checkout's staged app, never another task's build or test host.
if [[ "$MODE" != "--build" && "$MODE" != "--test" ]]; then
  while read -r app_pid; do
    kill "$app_pid" 2>/dev/null || true
  done < <(running_app_pids)
fi

ACTION=build
CONFIGURATION=Debug
if [[ "$MODE" == "--test" ]]; then ACTION=test; CONFIGURATION=Testing; fi
if ! xcodebuild -project "$PROJECT_DIR/YunleFunMac.xcodeproj" -scheme YunleFunMac \
    -configuration "$CONFIGURATION" -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
    -parallel-testing-enabled NO -collect-test-diagnostics never \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
    -maximum-test-execution-time-allowance 90 CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
    "$ACTION" >"$RUN_TEMP/build.log" 2>&1; then
  if command -v rg >/dev/null 2>&1; then
    rg -n 'error:|Testing failed:|Test Case .* failed|\*\* (TEST|BUILD) FAILED|\.xcresult$' "$RUN_TEMP/build.log" | tail -45 >&2 || tail -45 "$RUN_TEMP/build.log" >&2
  else
    tail -60 "$RUN_TEMP/build.log" >&2
  fi
  exit 1
fi
if [[ "$MODE" == "--test" ]]; then
  sed -n '/Test Suite .* started/,$p' "$RUN_TEMP/build.log" | tail -18
  exit 0
fi
if [[ "$MODE" == "--build" ]]; then
  echo "Built: $DERIVED_DATA/Build/Products/Debug/YunleFunMac.app"
  exit 0
fi

# Keep the runnable result; temporary staging and logs are removed on every exit.
ditto "$DERIVED_DATA/Build/Products/Debug/YunleFunMac.app" "$RUN_TEMP/YunleFunMac.app"
rm -rf "$APP_BUNDLE"
mv "$RUN_TEMP/YunleFunMac.app" "$APP_BUNDLE"

case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --debug) lldb -- "$APP_BINARY" ;;
  --logs)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "YunleFunMac"'
    ;;
  --telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "fun.yunle.macos.dev"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 2
    if [[ -z "$(running_app_pids)" ]]; then
      echo "Launch failed: this checkout's app is not running." >&2
      exit 1
    fi
    echo "Launched: $APP_BUNDLE"
    ;;
esac
