#!/usr/bin/env python3
"""Measure normal app startup on an explicitly named, already booted test device."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import ctypes
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import subprocess
import time
from simulator_startup_diagnostics import SimulatorDiagnostics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--simulator", required=True)
parser.add_argument("--expected-device-name", required=True)
parser.add_argument("--output", required=True, type=Path)
parser.add_argument("--repeat", type=int, default=8)
parser.add_argument("--timeout", type=float, default=20)
parser.add_argument("--sample-after", type=float, default=10)
args = parser.parse_args()
if args.repeat < 1 or not all(map(math.isfinite, [args.sample_after, args.timeout])) or not 0 < args.sample_after < args.timeout:
    parser.error("Require repeat > 0 and 0 < sample-after < timeout")
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
if list(output.iterdir()):
    parser.error("--output must be empty")
bundle = "fun.yunle.apps.native-dev"


def read_command(command, timeout=15):
    return subprocess.check_output(command, text=True, timeout=timeout).strip()


devices = json.loads(read_command(["xcrun", "simctl", "list", "devices", "--json"]))
device = next(d for ds in devices["devices"].values() for d in ds if d["udid"] == args.simulator)
if device["name"] != args.expected_device_name or device["state"] != "Booted":
    parser.error("The selected test device must already be booted and match its expected name")
container = Path(read_command(["xcrun", "simctl", "get_app_container", args.simulator, bundle, "data"]))
diagnostics = SimulatorDiagnostics(args.simulator, args.expected_device_name)
guest_log = container / "Library/Application Support/DiagnosticLogs/guest.json"
receipt = {"simulator": args.simulator, "deviceName": device["name"], "bundleId": bundle,
           "launchMode": "simctl-without-debugger", "timeoutSeconds": args.timeout,
           "sampleAfterSeconds": args.sample_after, "status": "running", "runs": []}
samples = []
libc = ctypes.CDLL(None, use_errno=True)
libc.sysctlbyname.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p, ctypes.c_size_t]


def memory_pressure_level():
    value = ctypes.c_int()
    size = ctypes.c_size_t(ctypes.sizeof(value))
    if libc.sysctlbyname(b"kern.memorystatus_vm_pressure_level", ctypes.byref(value), ctypes.byref(size), None, 0):
        return None
    return value.value


def save():
    (output / "startup-summary.json").write_text(json.dumps(receipt, indent=2) + "\n")


def stop_app():
    result = subprocess.run(["xcrun", "simctl", "terminate", args.simulator, bundle],
                            text=True, capture_output=True, timeout=20)
    if result.returncode and not any(s in result.stderr.lower() for s in ["not running", "no such process", "not found", "found nothing"]):
        raise RuntimeError(result.stderr)


def host_snapshot():
    return {"time": datetime.now(timezone.utc).isoformat(),
            "load": read_command(["uptime"]), "memory": read_command(["vm_stat"]),
            "memoryPressureLevel": memory_pressure_level()}


def diagnose(iteration):
    report = diagnostics.capture(output / f"launch-{iteration}-slow", "native-app-init")
    return report["samples"] + ([{"error": report["error"]}] if "error" in report else [])


try:
    save()
    with ThreadPoolExecutor(max_workers=2) as executor:
        for iteration in range(1, args.repeat + 1):
            stop_app()
            before = host_snapshot()
            start_ms = time.time_ns() // 1_000_000
            started = time.monotonic()
            stdout = output / f"launch-{iteration}.stdout.log"
            stderr = output / f"launch-{iteration}.stderr.log"
            stdout.touch(); stderr.touch()
            process = subprocess.Popen(["xcrun", "simctl", "launch", f"--stdout={stdout}",
                                        f"--stderr={stderr}", args.simulator, bundle],
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            ready = False
            marker_ms = None
            sampled = False
            try:
                while time.monotonic() - started < args.timeout:
                    # Read only the fixed startup marker. Never export other
                    # diagnostic messages, account partitions, or credentials.
                    try:
                        entries = json.loads(guest_log.read_text())["entries"]
                        markers = [e["timestamp"] for e in entries
                                   if e.get("message") == "app.launched" and e.get("timestamp", 0) >= start_ms]
                        marker_ms = max(markers) if markers else None
                        ready = marker_ms is not None
                    except (FileNotFoundError, json.JSONDecodeError):
                        pass
                    if ready and process.poll() is not None:
                        break
                    if process.poll() not in [None, 0]:
                        break
                    if not sampled and time.monotonic() - started >= args.sample_after:
                        sampled = True
                        # Diagnostics run independently of readiness polling;
                        # symbolication must not inflate the measured latency.
                        samples.append(executor.submit(diagnose, iteration))
                    time.sleep(0.05)
                elapsed = time.monotonic() - started
                if process.poll() is None:
                    process.terminate()
                command_out, command_error = process.communicate(timeout=10)
                (output / f"launch-{iteration}.command.log").write_text(command_out + command_error)
            finally:
                if process.poll() is None:
                    process.kill(); process.wait(timeout=10)
            passed = ready and process.returncode == 0 and elapsed < args.timeout
            receipt["runs"].append({"iteration": iteration, "passed": passed, "elapsedSeconds": round(elapsed, 3),
                                    "appInitSeconds": (marker_ms - start_ms) / 1000 if marker_ms else None,
                                    "startupMarkerObserved": ready, "commandReturncode": process.returncode,
                                    "before": before, "after": host_snapshot()})
            save()
            print(f"launch {iteration}: {'passed' if passed else 'FAILED'} in {elapsed:.3f}s", flush=True)
            # Keep this process alive until both waves finish. Do not count
            # symbolication in readiness latency or sample the next iteration.
            if sampled:
                samples[-1].result()
            if not passed:
                raise RuntimeError("Native startup did not reach the app.launched marker within its probe deadline")
    receipt["status"] = "passed"
except BaseException as error:
    receipt["status"] = "failed"
    receipt["error"] = str(error)
    raise
finally:
    receipt["samples"] = []
    for future in samples:
        try:
            receipt["samples"].extend(future.result())
        except Exception as error:
            receipt["samples"].append({"error": type(error).__name__})
    try:
        stop_app()
    finally:
        save()
