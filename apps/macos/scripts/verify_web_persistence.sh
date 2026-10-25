#!/bin/bash
set -euo pipefail

# Build a sandboxed Testing host, seed three synthetic profiles, let that
# process exit normally, then restore them in a separate test-host process.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
derived_data="${YLF_MAC_DERIVED_DATA:-$repo_root/apps/macos/build/DerivedData}"
report_dir="$repo_root/apps/macos/build/validation/web-persistence"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/yunle-web-persistence.XXXXXX")"
run_id="$(uuidgen)"
manifest="$HOME/Library/Containers/fun.yunle.macos.tests-host/Data/tmp/MacWebPersistence-$run_id/pending-webkit-stores.json"
mkdir -p "$report_dir"

build_command=(
    xcodebuild
    -project "$repo_root/apps/macos/YunleFunMac.xcodeproj"
    -scheme YunleFunMac -configuration Testing
    -derivedDataPath "$derived_data" -destination 'platform=macOS'
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
    -parallel-testing-enabled NO -collect-test-diagnostics never
    -test-timeouts-enabled YES -default-test-execution-time-allowance 60
    -maximum-test-execution-time-allowance 90
    -only-testing:YunleFunMacTests/MacWebPersistenceTests
)

run_phase() {
    local phase="$1"
    local action="$2"
    local result_bundle="$scratch_dir/$phase.xcresult"
    local result_code=0
    TEST_RUNNER_MAC_WEB_STORAGE_PHASE="$phase" \
    TEST_RUNNER_MAC_WEB_STORAGE_RUN_ID="$run_id" \
        "${build_command[@]}" -resultBundlePath "$result_bundle" "$action" \
        > "$report_dir/$phase.log" 2>&1 || result_code=$?
    if [[ -d "$result_bundle" ]]; then
        xcrun xcresulttool get test-results summary --path "$result_bundle" --compact \
            > "$report_dir/$phase-summary.json" 2>/dev/null || true
    fi
    if [[ "$result_code" -ne 0 ]]; then
        tail -40 "$report_dir/$phase.log" >&2
    fi
    return "$result_code"
}

finish() {
    local result_code=$?
    trap - EXIT INT TERM
    if [[ -f "$manifest" ]]; then
        printf 'Recovering the exact test-owned profiles from %s\n' "$manifest" >&2
        if ! run_phase cleanup test-without-building; then
            printf 'Cleanup needs attention; ownership record retained at %s\n' "$manifest" >&2
            result_code=1
        fi
    fi
    # Raw result bundles are rebuildable. Keep compact logs and summaries only.
    rm -rf "$scratch_dir"
    exit "$result_code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Seeding synthetic WebKit profiles, then exiting without a flush delay…\n'
run_phase seed test
printf 'Restoring the profiles in a new test-host process…\n'
run_phase restore test-without-building
if [[ -f "$manifest" ]]; then
    printf 'Restore left a cleanup manifest: %s\n' "$manifest" >&2
    exit 1
fi
printf 'WebKit cross-process persistence passed. Reports: %s\n' "$report_dir"
