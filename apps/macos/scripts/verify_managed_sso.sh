#!/bin/bash
set -euo pipefail
umask 077

usage() {
    cat <<'USAGE'
Explicit managed-account Play SSO validation. No live action occurs by default.
  verify_managed_sso.sh --run-managed-accounts
  verify_managed_sso.sh --cleanup RUN_UUID

Uses only production-zero-balance and production-standard from the private
managed-account file. No games, purchases, permission changes or new accounts.
USAGE
}

mode=""
case "${1:-}" in
    --run-managed-accounts)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        mode="journey"
        run_id="$(uuidgen)"
        ;;
    --cleanup)
        [[ $# -eq 2 ]] || { usage >&2; exit 2; }
        mode="cleanup"
        run_id="$(python3 - "$2" <<'PY'
import sys, uuid
try:
    print(str(uuid.UUID(sys.argv[1])).upper())
except ValueError:
    raise SystemExit('Cleanup requires a valid run UUID')
PY
        )"
        ;;
    ''|--help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
derived_data="${YLF_MAC_DERIVED_DATA:-$repo_root/apps/macos/build/DerivedData}"
cache_dir="$HOME/Library/Containers/fun.yunle.macos.tests-host/Data/Library/Caches"
run_dir="$cache_dir/MacManagedSSO-$run_id"
checkpoint="$run_dir/checkpoint.json"
report_dir="$repo_root/apps/macos/build/validation/managed-sso/$run_id"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/yunle-managed-sso.XXXXXX")"
mkdir -p "$report_dir"

build_command=(
    xcodebuild
    -project "$repo_root/apps/macos/YunleFunMac.xcodeproj"
    -scheme YunleFunMacLiveValidation -configuration Testing
    -derivedDataPath "$derived_data" -destination 'platform=macOS'
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
    -parallel-testing-enabled NO -collect-test-diagnostics never
    -test-timeouts-enabled YES -default-test-execution-time-allowance 180
    -maximum-test-execution-time-allowance 180
    -only-testing:YunleFunMacLiveTests/MacManagedSSOLiveTests
)

run_phase() {
    local phase="$1"
    local action="$2"
    local exit_code=0
    local result_bundle="$scratch_dir/$phase.xcresult"
    local raw_log="$scratch_dir/$phase.log"
    TEST_RUNNER_YLF_MAC_MANAGED_SSO_ENABLED=1 \
    TEST_RUNNER_YLF_MAC_MANAGED_SSO_MODE="$phase" \
    TEST_RUNNER_YLF_MAC_MANAGED_SSO_RUN_ID="$run_id" \
        "${build_command[@]}" -resultBundlePath "$result_bundle" "$action" \
        > "$raw_log" 2>&1 || exit_code=$?
    # Raw WebKit/framework diagnostics are private and temporary. Persist only
    # our fixed safe stages and compiler diagnostics, never page console output.
    python3 - "$raw_log" "$report_dir/$phase.log" <<'PY'
import pathlib, re, sys
lines = pathlib.Path(sys.argv[1]).read_text(errors='replace').splitlines()
safe = [line for line in lines if line.startswith('[ManagedSSO] ')
        or re.match(r'^\*\* TEST (SUCCEEDED|FAILED) \*\*$', line)
        or re.match(r'^/[^\r\n]+\.swift:\d+:\d+: (warning|error):', line)]
pathlib.Path(sys.argv[2]).write_text('\n'.join(safe) + '\n')
PY
    if [[ -d "$result_bundle" ]]; then
        xcrun xcresulttool get test-results summary --path "$result_bundle" --compact \
            > "$scratch_dir/$phase-summary.json" 2>/dev/null || true
        python3 - "$scratch_dir/$phase-summary.json" "$report_dir/$phase-summary.json" <<'PY'
import json, pathlib, sys
try:
    data = json.loads(pathlib.Path(sys.argv[1]).read_text())
    safe = {key: data[key] for key in ['result', 'passedTests', 'failedTests', 'skippedTests', 'totalTestCount'] if key in data}
    pathlib.Path(sys.argv[2]).write_text(json.dumps(safe, indent=2) + '\n')
except (OSError, ValueError):
    pass
PY
    fi
    local report_source="$cache_dir/MacManagedSSO-$run_id-$phase.report.json"
    if [[ -f "$report_source" ]]; then
        cp "$report_source" "$report_dir/$phase-report.json"
        rm "$report_source"
    fi
    cat "$report_dir/$phase.log"
    return "$exit_code"
}

finish() {
    local exit_code=$?
    trap - EXIT INT TERM
    set +e
    # Always remove the exact one-use input, including a build failure or signal.
    if [[ -f "$run_dir/accounts.json" ]]; then rm "$run_dir/accounts.json" || exit_code=1; fi
    if [[ "$mode" == "journey" && -f "$checkpoint" ]]; then
        printf 'Attempting exact-run cleanup: %s\n' "$run_id" >&2
        if ! run_phase cleanup test-without-building; then
            exit_code=1
        fi
    fi
    if [[ -f "$checkpoint" ]]; then
        printf 'Cleanup incomplete. Retry: %s --cleanup %s\n' "$0" "$run_id" >&2
        exit_code=1
    elif [[ -d "$run_dir" ]]; then
        # No recursive deletion here. A pre-test staging directory is removable
        # only if empty; unknown files remain available for inspection.
        rmdir "$run_dir" 2>/dev/null || exit_code=1
    fi
    rm -rf "$scratch_dir" || exit_code=1
    printf 'Safe validation reports: %s\n' "$report_dir"
    exit "$exit_code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "$mode" == "journey" ]]; then
    # Read only the two fixed credentials and never display values or JSON errors.
    python3 - "$HOME/.config/yunlefun/test-accounts.json" "$run_dir" <<'PY'
import json, os, pathlib, stat, sys
source, destination = map(pathlib.Path, sys.argv[1:])
try:
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'r') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != os.getuid():
            raise ValueError()
        pool = json.load(stream)
    expected = {'production-zero-balance': 'ylf_prod_zero', 'production-standard': 'ylf_prod_standard'}
    selected = []
    for account_id, username in expected.items():
        matches = [item for item in pool['accounts'] if item.get('id') == account_id]
        if len(matches) != 1:
            raise ValueError()
        item = matches[0]
        if item.get('environment') != 'production' or item.get('username') != username or not isinstance(item.get('password'), str) or not item['password']:
            raise ValueError()
        selected.append({key: item[key] for key in ['id', 'environment', 'username', 'password']})
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.mkdir(mode=0o700)  # Exclusive UUID, never overwrite another run.
    fd = os.open(destination / 'accounts.json', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump({'accounts': selected}, stream)
except Exception:
    raise SystemExit('Could not stage the two permitted managed accounts securely')
PY
else
    [[ -f "$checkpoint" ]] || { printf 'No checkpoint exists for this run UUID.\n' >&2; exit 2; }
fi

# Generate only after explicit opt-in. The ordinary scheme excludes live tests.
if ! xcodegen generate --spec "$repo_root/apps/macos/project.yml" --project "$repo_root/apps/macos" \
    > "$scratch_dir/xcodegen.log" 2>&1; then
    printf 'Could not generate the dedicated validation scheme. No login was started.\n' >&2
    exit 1
fi
printf 'Managed SSO mode=%s run=%s\n' "$mode" "$run_id"
run_phase "$mode" test
