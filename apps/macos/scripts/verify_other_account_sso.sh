#!/bin/bash
set -euo pipefail
umask 077

usage() {
    cat <<'USAGE'
Explicit real system-browser other-account SSO validation. No live action occurs by default.
  verify_other_account_sso.sh --run-managed-accounts
  verify_other_account_sso.sh --cleanup RUN_UUID

Uses only production-zero-balance and production-standard from the private
managed-account file. No games, purchases, permission changes or new accounts.
The operator clicks the real consumer/native/system browser UI. Each UI phase
allows 600 seconds; the dedicated test allows 3600 seconds total.
  verify_other_account_sso.sh --status RUN_UUID
  verify_other_account_sso.sh --ack RUN_UUID STAGE OBSERVATION

--status prints only the current safe stage and expected visible observation.
--ack records what was actually observed; it never delivers an auth callback.
Central system-browser remote logout is NOT claimed. Owned native/consumer
sessions and exact UUID stores are cleaned; reports distinguish this scope.
Cleanup is two-phase: remote logout is checkpointed, then a fresh test process
purges only confirmed UUID stores without reopening their consumer pages.
USAGE
}

# Read-only status and explicit visible-observation acknowledgement do not build,
# read credential inputs, or invoke a production API.
if [[ "${1:-}" == "--status" || "${1:-}" == "--ack" ]]; then
    python3 - "$HOME/Library/Containers/fun.yunle.macos.tests-host/Data/Library/Caches" "$@" <<'PY_HANDSHAKE'
import json, os, pathlib, stat, sys, uuid
cache, action, *args = sys.argv[1:]
expected = {
    'cancel-first-system-session': 'system-login-empty-then-cancelled',
    'login-b-system-session': 'system-login-empty-b-completed',
    'website-logout-b-and-cancel-retry': 'website-logout-system-login-empty-then-cancelled',
    'relogin-b-system-session': 'system-login-empty-b-completed',
    'authorize-current-host-a': 'native-current-account-authorized',
}
try:
    if len(args) != (1 if action == '--status' else 3):
        raise ValueError()
    run = str(uuid.UUID(args[0])).upper()
    directory = pathlib.Path(cache) / ('MacOtherAccountSSO-' + run)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o700 or info.st_uid != os.getuid():
        raise ValueError()
    path = directory / 'handshake.json'
    if not path.exists():
        if action != '--status':
            raise ValueError()
        print(json.dumps({'run': run, 'stage': 'not-waiting-for-ui'}))
        raise SystemExit(0)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd) as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != os.getuid():
            raise ValueError()
        handshake = json.load(stream)
    stage = handshake['stage']
    if handshake['run'].upper() != run or stage not in expected:
        raise ValueError()
    nonce = str(uuid.UUID(handshake['nonce'])).upper()
    if action == '--status':
        print(json.dumps({'run': run, 'stage': stage, 'instruction': handshake['instruction'],
                          'expectedObservation': expected[stage]}, indent=2))
    else:
        if args[1] != stage or args[2] != expected[stage]:
            raise ValueError()
        temporary = directory / ('ack-' + nonce + '.tmp')
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            with os.fdopen(fd, 'w') as stream:
                json.dump({'run': run, 'stage': stage, 'nonce': nonce, 'observed': args[2]}, stream)
                stream.flush()
                os.fsync(stream.fileno())
            # Publish a complete ack atomically, refusing to replace a stale one.
            os.link(temporary, directory / 'ack.json')
        finally:
            temporary.unlink(missing_ok=True)
        print('Visible observation acknowledged: ' + stage)
except (OSError, ValueError, KeyError, TypeError):
    raise SystemExit('No matching private handshake; verify the run UUID, stage and observed UI')
PY_HANDSHAKE
    exit "$?"
fi

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
run_dir="$cache_dir/MacOtherAccountSSO-$run_id"
checkpoint="$run_dir/checkpoint.json"
report_dir="$repo_root/apps/macos/build/validation/other-account-sso/$run_id"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/yunle-other-account-sso.XXXXXX")"
mkdir -p "$report_dir"
purge_attempted=false

build_command=(
    xcodebuild
    -project "$repo_root/apps/macos/YunleFunMac.xcodeproj"
    -scheme YunleFunMacLiveValidation -configuration Testing
    -derivedDataPath "$derived_data" -destination 'platform=macOS'
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
    -parallel-testing-enabled NO -collect-test-diagnostics never
    -test-timeouts-enabled YES -default-test-execution-time-allowance 3600
    -maximum-test-execution-time-allowance 3600
    -only-testing:YunleFunMacLiveTests/MacOtherAccountLiveTests/testRealSystemOtherAccountAndCancellation
)

run_phase() {
    local phase="$1"
    local action="$2"
    local exit_code=0
    if [[ "$phase" == "purge" ]]; then purge_attempted=true; fi
    local result_bundle="$scratch_dir/$phase.xcresult"
    local raw_log="$scratch_dir/$phase.log"
    local report_source="$cache_dir/MacOtherAccountSSO-$run_id-$phase.report.json"
    local fresh_report="$scratch_dir/$phase-report.json"
    # A prior interrupted invocation's report must not satisfy this phase.
    # These exact-run reports are copied to report_dir before normal removal.
    rm -f "$report_source" "$fresh_report" "$scratch_dir/$phase-summary.json"
    TEST_RUNNER_YLF_MAC_OTHER_SSO_ENABLED=1 \
    TEST_RUNNER_YLF_MAC_OTHER_SSO_MODE="$phase" \
    TEST_RUNNER_YLF_MAC_OTHER_SSO_RUN_ID="$run_id" \
        "${build_command[@]}" -resultBundlePath "$result_bundle" "$action" \
        > "$raw_log" 2>&1 || exit_code=$?
    # Raw WebKit/framework diagnostics are private and temporary. Persist only
    # our fixed safe stages and compiler diagnostics, never page console output.
    python3 - "$raw_log" "$report_dir/$phase.log" <<'PY'
import pathlib, re, sys
lines = pathlib.Path(sys.argv[1]).read_text(errors='replace').splitlines()
safe = [line for line in lines if line.startswith('[OtherAccountSSO] ')
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
    if [[ -f "$report_source" ]]; then
        cp "$report_source" "$fresh_report"
        cp "$fresh_report" "$report_dir/$phase-report.json"
        rm "$report_source"
    fi
    # XCTest may exit successfully when the only test was skipped. Require the
    # fresh result and exact-run phase proof, while preserving any build failure.
    if ! python3 - "$scratch_dir/$phase-summary.json" "$fresh_report" "$run_id" "$phase" <<'PY_PHASE_RESULT'
import json, pathlib, sys, uuid

def validate(summary, report, run, phase):
    if phase not in ('journey', 'cleanup', 'purge'):
        return False
    counts = {'totalTestCount': 1, 'passedTests': 1, 'failedTests': 0, 'skippedTests': 0}
    if summary.get('result') != 'Passed' or any(type(summary.get(key)) is not int or summary[key] != value for key, value in counts.items()):
        return False
    if uuid.UUID(report['run']) != uuid.UUID(run) or report.get('mode') != phase or report.get('failureStage') is not None:
        return False
    required = ('phasePassed', 'ownedHostAndConsumerCleanupComplete', 'consumerSDKSignOutComplete',
                'consumerAnonymousRemoteCheckComplete', 'hostRemoteSignOutComplete')
    if any(report.get(key) is not True for key in required):
        return False
    remaining = report.get('remainingProfiles')
    if type(remaining) is not int or not 0 <= remaining <= 4:
        return False
    if phase == 'journey' and report.get('journeyPassed') is not True:
        return False
    if phase == 'purge':
        previous, current = report.get('remoteCleanupProcessID'), report.get('currentProcessID')
        return (remaining == 0 and report.get('completeIncludingStorePurge') is True
                and report.get('pendingStorePurge') is False and report.get('ownedWebsiteStoresRemoved') is True
                and type(previous) is int and previous > 0 and type(current) is int and current > 0 and previous != current)
    return (report.get('completeIncludingStorePurge') is False and report.get('pendingStorePurge') is True
            and report.get('ownedWebsiteStoresRemoved') is False)

try:
    summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
    report = json.loads(pathlib.Path(sys.argv[2]).read_text())
    valid = isinstance(summary, dict) and isinstance(report, dict) and validate(summary, report, sys.argv[3], sys.argv[4])
except (OSError, ValueError, KeyError, TypeError, AttributeError):
    valid = False
if not valid:
    print('Validation requires one passed test and a fresh, matching, complete phase report.', file=sys.stderr)
    raise SystemExit(1)
PY_PHASE_RESULT
    then
        if [[ "$exit_code" -eq 0 ]]; then exit_code=1; fi
    fi
    cat "$report_dir/$phase.log"
    return "$exit_code"
}

ready_for_purge() {
    python3 - "$checkpoint" "$run_id" <<'PY'
import json, os, stat, sys, uuid
try:
    fd = os.open(sys.argv[1], os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd) as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != os.getuid():
            raise ValueError()
        data = json.load(stream)
    if str(uuid.UUID(data['run'])).upper() != sys.argv[2] or data.get('version') != 1:
        raise ValueError()
    profiles = {str(uuid.UUID(value)) for value in data['profiles']}
    confirmed = {str(uuid.UUID(value)) for value in data.get('signedOutProfiles', [])}
    ready = (len(data['profiles']) == len(profiles) <= 4 and len(confirmed) <= 4
             and profiles <= confirmed and data.get('remoteCleanupComplete') is True
             and data.get('hostSessionsRevoked') is True
             and isinstance(data.get('remoteCleanupProcessID'), int)
             and data['remoteCleanupProcessID'] > 0)
    raise SystemExit(0 if ready else 1)
except (OSError, ValueError, KeyError, TypeError):
    raise SystemExit(1)
PY
}

finish() {
    local exit_code=$?
    local cleanup_failed=false
    trap - EXIT INT TERM
    set +e
    # Always remove the exact one-use input, including a build failure or signal.
    if [[ -f "$run_dir/accounts.json" ]]; then rm "$run_dir/accounts.json" || cleanup_failed=true; fi
    if [[ "$mode" == "journey" && -f "$checkpoint" ]] && ! ready_for_purge; then
        printf 'Attempting exact-run remote cleanup: %s\n' "$run_id" >&2
        if ! run_phase cleanup test-without-building; then
            cleanup_failed=true
        fi
    fi
    if [[ -f "$checkpoint" && "$purge_attempted" == false ]] && ready_for_purge; then
        printf 'Purging confirmed UUID stores in a fresh process: %s\n' "$run_id" >&2
        if ! run_phase purge test-without-building; then
            cleanup_failed=true
        fi
    fi
    if [[ -f "$checkpoint" ]]; then
        printf 'Cleanup incomplete. Retry: %s --cleanup %s\n' "$0" "$run_id" >&2
        cleanup_failed=true
    elif [[ -d "$run_dir" ]]; then
        # No recursive deletion here. A pre-test staging directory is removable
        # only if empty; unknown files remain available for inspection.
        rmdir "$run_dir" 2>/dev/null || cleanup_failed=true
    fi
    rm -rf "$scratch_dir" || cleanup_failed=true
    if [[ "$cleanup_failed" == true && "$exit_code" -eq 0 ]]; then exit_code=1; fi
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
printf 'Other-account SSO mode=%s run=%s\n' "$mode" "$run_id"
printf 'UI handshake: %s --status %s\n' "$0" "$run_id"
phase="$mode"
# A retry after confirmed logout must not recreate the named stores. It resumes
# directly at purge; the test itself validates all markers and a different PID.
if [[ "$mode" == "cleanup" ]] && ready_for_purge; then phase="purge"; fi
run_phase "$phase" test
