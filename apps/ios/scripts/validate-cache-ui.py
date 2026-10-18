#!/usr/bin/env python3
"""Run cache acceptance serially on an explicitly selected guest test simulator."""
import argparse
from contextlib import nullcontext
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--simulator", required=True)
parser.add_argument("--test-products", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path)
parser.add_argument("--repeat", type=int, default=2)
parser.add_argument("--phase", choices=["all", "core", "startup", "ui", "download", "automatic", "clear"], default="all")
parser.add_argument("--include-startup-probes", action="store_true", help="Include repeated offline sessions and anonymous engine startup regressions before UI groups")
parser.add_argument("--capture-slow-startup", action="store_true", help="Capture selected-device client/server stacks on slow startup progress; never restart services")
parser.add_argument("--expected-device-name", help="Required with --capture-slow-startup to guard device selection")
parser.add_argument("--restart-between-groups", action="store_true", help="Restart only the selected test device between groups to isolate simulator service sessions")
parser.add_argument("--restart-test-service", action="store_true", help="Restart only the selected device's XCTest control service before each group")
parser.add_argument("--restart-ui-groups", action="store_true", help="Restart only the selected device before UI groups, keeping core/network groups separate without another device boot")
args = parser.parse_args()
if args.repeat < 1:
    parser.error("--repeat must be positive")
if args.capture_slow_startup and not args.expected_device_name:
    parser.error("--capture-slow-startup requires --expected-device-name")
products = args.test_products.resolve(strict=True)
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
if list(output.iterdir()):
    parser.error("--output must be empty so previous results cannot mask a failure")
receipt = {
    "simulator": args.simulator, "testProducts": str(products),
    "phase": args.phase, "repeat": args.repeat,
    "restartDeviceBetweenGroups": args.restart_between_groups,
    "restartTestService": args.restart_test_service,
    "restartUiGroups": args.restart_ui_groups,
    "includeStartupProbes": args.include_startup_probes or args.phase == "startup",
    "captureSlowStartup": args.capture_slow_startup,
    "status": "running", "groups": [],
}
diagnostics = None


def save_receipt():
    (output / "validation-summary.json").write_text(json.dumps(receipt, indent=2) + "\n")


def session_snapshot():
    # Simulator shares the host kernel, so kern.boottime cannot identify its
    # boot. SpringBoard's launchd_sim parent and start time can, without resetting
    # or attaching to any device service. Keep XCTest/RunningBoard PIDs as well
    # to distinguish a service restart from a fresh device boot.
    listing = subprocess.check_output([
        "xcrun", "simctl", "spawn", args.simulator, "launchctl", "list"
    ], text=True, timeout=30)
    labels = {"com.apple.SpringBoard", "com.apple.runningboardd", "com.apple.testmanagerd"}
    services = {}
    for line in listing.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] in labels:
            services[fields[2]] = int(fields[0]) if fields[0].isdigit() else None
    springboard = services.get("com.apple.SpringBoard")
    if not springboard:
        raise RuntimeError("Cannot identify the selected simulator's system session")
    parent = int(subprocess.check_output([
        "ps", "-o", "ppid=", "-p", str(springboard)
    ], text=True, timeout=10).strip())
    launchd = subprocess.check_output([
        "ps", "-o", "pid=,lstart=,comm=", "-p", str(parent)
    ], text=True, timeout=10).strip()
    if "launchd_sim" not in launchd:
        raise RuntimeError("Selected device's SpringBoard has an unexpected parent")
    return {"time": datetime.now(timezone.utc).isoformat(), "launchdSim": launchd, "services": services,
            "hostLoad": list(os.getloadavg())}


def test_group(name, selectors, expected, flags=None):
    print("Running " + name, flush=True)
    if args.restart_between_groups or (args.restart_ui_groups and any(selector.startswith("YunleFunUITests/") for selector in selectors)):
        devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"], text=True, timeout=30))
        device = next(device for group in devices["devices"].values() for device in group if device["udid"] == args.simulator)
        if device["state"] != "Shutdown":
            subprocess.run(["xcrun", "simctl", "shutdown", args.simulator], check=True, timeout=60)
        subprocess.run(["xcrun", "simctl", "bootstatus", args.simulator, "-b"], check=True, timeout=300)
    if args.restart_test_service:
        subprocess.run(["xcrun", "simctl", "spawn", args.simulator, "launchctl", "stop", "com.apple.testmanagerd"], check=True, timeout=30)
    before = session_snapshot()
    started = time.monotonic()
    result_path = output / (name + ".xcresult")
    command = [
        "xcodebuild", "-testProductsPath", str(products),
        "-destination", "platform=iOS Simulator,id=" + args.simulator,
        "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
        # Keep Xcode's slow host bootstrap separate from the strict waits inside
        # the tests and the production downloader's bounded phase deadlines.
        "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "900",
        "-maximum-test-execution-time-allowance", "900",
        "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "-resultBundlePath", str(result_path),
    ]
    command += ["-only-testing:" + selector for selector in selectors]
    command.append("test-without-building")
    environment = {key: value for key, value in os.environ.items() if not key.startswith("TEST_RUNNER_YLF_CACHE_")}
    environment.update({"TEST_RUNNER_" + key: value for key, value in (flags or {}).items()})
    test_log = output / (name + ".log")
    if diagnostics:
        from simulator_startup_diagnostics import StartupWatcher
        watcher = StartupWatcher(diagnostics, output / (name + "-startup-diagnostics"), test_log)
    else:
        watcher = nullcontext()
    with test_log.open("w") as log, watcher:
        process = subprocess.Popen(command, env=environment, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            result = subprocess.CompletedProcess(command, process.wait(timeout=1200))
        except BaseException:
            # Give Xcode a chance to cancel its device session and write results
            # before forcing only this command's process group to exit.
            if process.poll() is None:
                process.send_signal(signal.SIGINT)
                try:
                    process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=10)
            raise
    after = session_snapshot()
    summary = json.loads(subprocess.check_output([
        "xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_path)
    ], text=True, timeout=30))
    (output / (name + ".json")).write_text(json.dumps(summary, indent=2) + "\n")
    counts = {key: summary[key] for key in ["totalTestCount", "passedTests", "failedTests", "skippedTests"]}
    receipt["groups"].append({"name": name, "selectors": selectors, **counts,
                              "elapsedSeconds": round(time.monotonic() - started, 3),
                              "sessionBefore": before, "sessionAfter": after})
    save_receipt()
    result.check_returncode()
    if counts != {"totalTestCount": expected, "passedTests": expected, "failedTests": 0, "skippedTests": 0}:
        raise RuntimeError(f"Unexpected test counts for {name}: {counts}")
    if not args.restart_between_groups and not args.restart_ui_groups:
        if before["launchdSim"] != receipt["initialSession"]["launchdSim"] or after["launchdSim"] != before["launchdSim"]:
            raise RuntimeError("Simulator rebooted during continuous-session validation")
    print(f"Passed {name}: {expected} tests, no failures or skips", flush=True)


def seed(*options):
    # Finish the UI test's app process before writing an explicitly opted-in fixture.
    stopped = subprocess.run([
        "xcrun", "simctl", "terminate", args.simulator, "fun.yunle.apps.native-dev"
    ], text=True, capture_output=True, timeout=30)
    if stopped.returncode and not any(message in stopped.stderr.lower() for message in [
        "not running", "no such process", "not found", "found nothing"
    ]):
        raise RuntimeError(stopped.stderr)
    subprocess.run([
        sys.executable, str(Path(__file__).with_name("seed-cache-ui-fixtures.py")), args.simulator, *options
    ], check=True, timeout=60)


try:
    save_receipt()
    subprocess.run(["xcrun", "simctl", "bootstatus", args.simulator, "-b"], check=True, timeout=300)
    receipt["initialSession"] = session_snapshot()
    if args.capture_slow_startup:
        from simulator_startup_diagnostics import SimulatorDiagnostics
        diagnostics = SimulatorDiagnostics(args.simulator, args.expected_device_name)
    save_receipt()
    if args.phase == "all":
        test_group("cold-start", ["YunleFunTests/ApplicationCacheRuntimeTests/testColdRuntimeClearsIdentityWithoutAnExistingWebView"], 1)
    if args.phase in ["all", "core"]:
        test_group("cache-core", ["YunleFunTests/" + name for name in [
            "ApplicationCacheRepositoryTests", "ApplicationCacheStoreTests", "ApplicationCacheAutomaticUpdateTests",
            "ApplicationCacheDownloaderTests", "ApplicationCacheWebKitTests",
            "ApplicationCacheRuntimeTests/testRuntimeUsesSavedResourcesAndNewSessionSeesUpdatedCache",
        ]], 26)
        # Fresh process: controlled WebKit doubles may still have asynchronous
        # process teardown when their tests finish. Do not overlap that with the
        # real network download's strict production deadline.
        test_group("cache-live", ["YunleFunTests/ApplicationCacheLiveTests"], 2, {"YLF_CACHE_LIVE_TEST": "1"})
    if args.phase == "startup" or args.include_startup_probes:
        test_group("startup-cached-sessions", ["YunleFunTests/ApplicationCacheRuntimeTests/testRepeatedCachedSessionsReleaseWebViews"], 1,
                   {"YLF_CACHE_STARTUP_PROBE": "1"})
        test_group("startup-anonymous-engines", ["YunleFunTests/ApplicationCacheStartupTests/testRepeatedAnonymousDownloadsReleaseEngines"], 1,
                   {"YLF_CACHE_STARTUP_PROBE": "1", "YLF_CACHE_LIVE_TEST": "1"})
    for repetition in range(1, args.repeat + 1):
        if args.phase in ["all", "ui", "download"]:
            test_group(f"download-update-clear-{repetition}", ["YunleFunUITests/ApplicationCacheUITests/testDownloadUpdateOpenAndClear"], 1, {"YLF_CACHE_UI_TEST": "1"})
        if args.phase in ["all", "ui", "automatic"]:
            seed("--automatic")
            test_group(f"automatic-update-{repetition}", ["YunleFunUITests/ApplicationCacheUITests/testAutomaticUpdateKeepsRunningCacheUntilReopened"], 1, {"YLF_CACHE_UI_AUTOMATIC": "1"})
        if args.phase in ["all", "ui", "clear"]:
            seed()
            test_group(f"clear-confirmations-{repetition}", ["YunleFunUITests/ApplicationCacheUITests/testClearConfirmationsWithLocalFixtures"], 1, {"YLF_CACHE_UI_FIXTURES": "1"})
    receipt["status"] = "passed"
except BaseException as error:
    receipt["status"] = "failed"
    receipt["error"] = str(error)
    raise
finally:
    save_receipt()
