#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK="$PROJECT_DIR/android/app/build/outputs/apk/release/app-release.apk"
AAB="$PROJECT_DIR/android/app/build/outputs/bundle/release/app-release.aab"

required_variables=(
  YUNLEFUN_ANDROID_VERSION_CODE
  YUNLEFUN_ANDROID_RELEASE_STORE_FILE
  YUNLEFUN_ANDROID_RELEASE_STORE_PASSWORD
  YUNLEFUN_ANDROID_RELEASE_KEY_ALIAS
  YUNLEFUN_ANDROID_RELEASE_KEY_PASSWORD
  YUNLEFUN_ANDROID_RELEASE_CERT_SHA256
)

for variable_name in "${required_variables[@]}"; do
  if [ -z "${!variable_name:-}" ]; then
    echo "Missing required release signing variable: $variable_name" >&2
    exit 1
  fi
done

if ! [[ "$YUNLEFUN_ANDROID_VERSION_CODE" =~ ^[1-9][0-9]*$ ]]; then
  echo "YUNLEFUN_ANDROID_VERSION_CODE must be a positive integer" >&2
  exit 1
fi

if [ ! -f "$YUNLEFUN_ANDROID_RELEASE_STORE_FILE" ]; then
  echo "Release keystore does not exist: $YUNLEFUN_ANDROID_RELEASE_STORE_FILE" >&2
  exit 1
fi

expected_certificate_sha256="$(printf '%s' "$YUNLEFUN_ANDROID_RELEASE_CERT_SHA256" | tr -d ':' | tr '[:lower:]' '[:upper:]')"
if ! [[ "$expected_certificate_sha256" =~ ^[0-9A-F]{64}$ ]]; then
  echo "YUNLEFUN_ANDROID_RELEASE_CERT_SHA256 must be a SHA-256 certificate fingerprint" >&2
  exit 1
fi

keystore_certificate_sha256="$(
  keytool -list -v \
    -keystore "$YUNLEFUN_ANDROID_RELEASE_STORE_FILE" \
    -storepass:env YUNLEFUN_ANDROID_RELEASE_STORE_PASSWORD \
    -alias "$YUNLEFUN_ANDROID_RELEASE_KEY_ALIAS" \
    | sed -n 's/^[[:space:]]*SHA256: //p' \
    | head -n 1 \
    | tr -d ':' \
    | tr '[:lower:]' '[:upper:]'
)"
if [ "$keystore_certificate_sha256" != "$expected_certificate_sha256" ]; then
  echo "Release keystore certificate does not match YUNLEFUN_ANDROID_RELEASE_CERT_SHA256" >&2
  exit 1
fi

android_sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "$android_sdk_root" ] && [ -f "$PROJECT_DIR/android/local.properties" ]; then
  android_sdk_root="$(sed -n 's/^sdk\.dir=//p' "$PROJECT_DIR/android/local.properties" | tail -n 1)"
fi
if [ -z "$android_sdk_root" ] || [ ! -d "$android_sdk_root/build-tools" ]; then
  echo "Android SDK build-tools were not found" >&2
  exit 1
fi

apksigner="$(find "$android_sdk_root/build-tools" -mindepth 2 -maxdepth 2 -type f -name apksigner | sort -V | tail -n 1)"
if [ -z "$apksigner" ]; then
  echo "apksigner was not found under Android SDK build-tools" >&2
  exit 1
fi

cd "$PROJECT_DIR"
pnpm build
LANG=en_US.UTF-8 pnpm exec cap sync android
(
  cd android
  ./gradlew testReleaseUnitTest lintRelease assembleRelease bundleRelease
)

if [ ! -f "$APK" ] || [ ! -f "$AAB" ]; then
  echo "Signed Android release artifacts were not produced" >&2
  exit 1
fi

"$apksigner" verify --verbose "$APK"
apk_certificate_sha256="$(
  "$apksigner" verify --print-certs "$APK" \
    | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' \
    | head -n 1 \
    | tr -d ':' \
    | tr '[:lower:]' '[:upper:]'
)"
if [ "$apk_certificate_sha256" != "$expected_certificate_sha256" ]; then
  echo "Release APK certificate does not match the pinned upload key" >&2
  exit 1
fi
jarsigner -verify -strict \
  -keystore "$YUNLEFUN_ANDROID_RELEASE_STORE_FILE" \
  -storepass:env YUNLEFUN_ANDROID_RELEASE_STORE_PASSWORD \
  "$AAB"
aab_certificate_sha256="$(
  keytool -printcert -jarfile "$AAB" \
    | sed -n 's/^[[:space:]]*SHA256: //p' \
    | head -n 1 \
    | tr -d ':' \
    | tr '[:lower:]' '[:upper:]'
)"
if [ "$aab_certificate_sha256" != "$expected_certificate_sha256" ]; then
  echo "Release AAB certificate does not match the pinned upload key" >&2
  exit 1
fi
shasum -a 256 "$APK" "$AAB"

echo "Android release artifacts verified:"
echo "  $APK"
echo "  $AAB"
