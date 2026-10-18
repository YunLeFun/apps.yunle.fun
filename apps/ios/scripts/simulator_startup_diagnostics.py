"""Read-only, bounded startup diagnostics for one explicitly selected simulator.

Resolve its launchd once while healthy. Captures use host process APIs rather
than making an RPC to the very launchd/RunningBoard service being investigated.
No process arguments, environments, user files, or other devices are sampled.
"""
from concurrent.futures import ThreadPoolExecutor
import ctypes
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import pty
import re
import select
import subprocess
import threading
import time


# ABI: macOS SDK sys/resource.h rusage_info_v2, libproc.h proc_pid_rusage.
_USAGE_FIELDS = [
    "user_time", "system_time", "pkg_idle_wkups", "interrupt_wkups", "pageins",
    "wired_size", "resident_size", "phys_footprint", "proc_start_abstime", "proc_exit_abstime",
    "child_user_time", "child_system_time", "child_pkg_idle_wkups", "child_interrupt_wkups",
    "child_pageins", "child_elapsed_abstime", "diskio_bytesread", "diskio_byteswritten",
]


class RusageV2(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(name, ctypes.c_uint64) for name in _USAGE_FIELDS]


class BsdShortInfo(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint32) for name in ["pid", "parent", "group", "status"]] + [
        ("comm", ctypes.c_char * 16)] + [(name, ctypes.c_uint32) for name in [
            "flags", "uid", "gid", "ruid", "rgid", "svuid", "svgid", "reserved"]]


_libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
_libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
_libproc.proc_pid_rusage.restype = ctypes.c_int
_libproc.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
_libproc.proc_pidinfo.restype = ctypes.c_int
_libproc.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
_libproc.proc_pidpath.restype = ctypes.c_int
_libproc.proc_listpids.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_int]
_libproc.proc_listpids.restype = ctypes.c_int
_libc = ctypes.CDLL(None, use_errno=True)
_libc.sysctlbyname.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p, ctypes.c_size_t]


def process_usage(pid):
    usage = RusageV2()
    if _libproc.proc_pid_rusage(pid, 2, ctypes.byref(usage)):
        return {"error": "proc_pid_rusage", "errno": ctypes.get_errno()}
    return {"uuid": bytes(usage.uuid).hex(), **{name: getattr(usage, name) for name in _USAGE_FIELDS}}


def read_command(command, timeout=8):
    return subprocess.check_output(command, text=True, timeout=timeout).strip()


def host_snapshot():
    value = ctypes.c_int()
    size = ctypes.c_size_t(ctypes.sizeof(value))
    ok = _libc.sysctlbyname(b"kern.memorystatus_vm_pressure_level", ctypes.byref(value), ctypes.byref(size), None, 0) == 0
    snapshot = {"time": datetime.now(timezone.utc).isoformat(), "monotonic": time.monotonic(),
            "load": list(os.getloadavg()), "memoryPressureLevel": value.value if ok else None,
            }
    try:
        snapshot["vmStat"] = read_command(["vm_stat"], timeout=1)
    except (subprocess.SubprocessError, OSError) as error:
        # Missing global VM counters must not prevent the scoped stack capture.
        snapshot["vmStatError"] = type(error).__name__
    return snapshot


def _process(pid):
    info = BsdShortInfo()
    if _libproc.proc_pidinfo(pid, 13, 0, ctypes.byref(info), ctypes.sizeof(info)) != ctypes.sizeof(info):
        return None
    path = ctypes.create_string_buffer(4096)
    if _libproc.proc_pidpath(pid, path, len(path)) <= 0:
        return None
    return {"pid": info.pid, "parent": info.parent, "stateCode": info.status, "path": os.fsdecode(path.value)}


def _processes(parent):
    # PROC_PPID_ONLY=6 returns bytes of pid_t values. Never enumerate unrelated
    # host processes: under pressure even global ps can take many seconds.
    pids = (ctypes.c_int * 8192)()
    count = _libproc.proc_listpids(6, parent, pids, ctypes.sizeof(pids))
    if count <= 0 or count >= ctypes.sizeof(pids) or count % ctypes.sizeof(ctypes.c_int):
        raise RuntimeError("Cannot enumerate the selected launchd's child PIDs")
    rows = [_process(pid) for pid in [parent, *pids[:count // ctypes.sizeof(ctypes.c_int)]] if pid > 0]
    return [row for row in rows if row]


class SimulatorDiagnostics:
    def __init__(self, simulator, expected_name):
        devices = json.loads(read_command(["xcrun", "simctl", "list", "devices", "--json"]))
        device = next(d for ds in devices["devices"].values() for d in ds if d["udid"] == simulator)
        if device["name"] != expected_name or device["state"] != "Booted":
            raise RuntimeError("Diagnostic device must already be Booted and match --expected-device-name")
        self.simulator, self.device_name = simulator, expected_name
        listing = read_command(["xcrun", "simctl", "spawn", simulator, "launchctl", "list"])
        springboard = next(int(f[0]) for line in listing.splitlines()
                           if len(f := line.split()) == 3 and f[2] == "com.apple.SpringBoard" and f[0].isdigit())
        board = _process(springboard)
        parent = board["parent"] if board else None
        launchd = _process(parent) if parent else None
        if not launchd or Path(launchd["path"]).name != "launchd_sim":
            raise RuntimeError("Selected SpringBoard's parent is not launchd_sim")
        self.launchd = parent
        self.identity = process_usage(parent)
        if "error" in self.identity:
            raise RuntimeError("Cannot establish launchd process identity")

    def snapshot(self):
        identity = process_usage(self.launchd)
        if (identity.get("proc_start_abstime"), identity.get("uuid")) != (self.identity["proc_start_abstime"], self.identity["uuid"]):
            raise RuntimeError("Selected simulator session ended or launchd PID was reused")
        processes = []
        servers = {"runningboardd", "SpringBoard", "launchd_sim", "lsd", "testmanagerd", "backboardd"}
        for row in _processes(self.launchd):
            if row["pid"] != self.launchd and row["parent"] != self.launchd:
                continue
            name = Path(row["path"]).name
            role = "server" if name in servers else "extension" if any(s in name for s in ["WebContent", "Networking", "GPU", "xpcproxy"]) else "app" if name == "YunleFun" else None
            if role:
                processes.append({**row, "role": role, "usage": process_usage(row["pid"])})
        return {"host": host_snapshot(), "processes": processes}

    @staticmethod
    def _sample(process, folder, wave):
        pid, identity = process["pid"], process["usage"]
        current = process_usage(pid)
        if "error" in identity or (current.get("uuid"), current.get("proc_start_abstime")) != (identity.get("uuid"), identity.get("proc_start_abstime")):
            return {"pid": pid, "wave": wave, "error": "process-ended-or-replaced"}
        path = folder / f"wave-{wave}-{pid}.sample.txt"
        started = time.monotonic()
        try:
            result = subprocess.run(["sample", str(pid), "1", "20", "-file", str(path)], text=True, capture_output=True, timeout=20)
            return {"pid": pid, "wave": wave, "path": str(path), "returncode": result.returncode,
                    "startedMonotonic": started, "elapsedSeconds": time.monotonic() - started}
        except subprocess.TimeoutExpired:
            return {"pid": pid, "wave": wave, "error": "sample-timeout", "startedMonotonic": started}

    def capture(self, folder, reason):
        folder = Path(folder)
        folder.mkdir(parents=True, exist_ok=False)
        report = {"simulator": self.simulator, "deviceName": self.device_name,
                  "launchdPid": self.launchd, "launchdIdentity": self.identity,
                  "reason": reason, "snapshots": [], "samples": []}
        def save():
            (folder / "capture.json").write_text(json.dumps(report, indent=2) + "\n")
        save()
        try:
            # Two waves distinguish a fixed wait from progress. All client and
            # server samplers within a wave start concurrently; cap at 12 PIDs.
            with ThreadPoolExecutor(max_workers=12) as executor:
                for wave in [1, 2]:
                    snapshot = self.snapshot()
                    report["snapshots"].append(snapshot)
                    servers = [p for p in snapshot["processes"] if p["role"] != "extension"]
                    extensions = sorted([p for p in snapshot["processes"] if p["role"] == "extension"],
                                        key=lambda p: p["usage"].get("proc_start_abstime", 0), reverse=True)
                    selected = (servers + extensions)[:12]
                    report.setdefault("selected", []).append({"wave": wave, "pids": [p["pid"] for p in selected],
                                                              "omitted": [p["pid"] for p in extensions if p not in selected]})
                    futures = [executor.submit(self._sample, p, folder, wave) for p in selected]
                    for _ in range(4):
                        time.sleep(0.5)
                        report["snapshots"].append(self.snapshot())
                    report["samples"].extend(f.result() for f in futures)
                    save()
            report["status"] = "captured"
        except Exception as error:
            report.update(status="incomplete", error=type(error).__name__, detail=str(error))
        save()
        return report


class ProgressTracker:
    """Track fixed non-sensitive test/download events, never arbitrary log text."""
    def __init__(self):
        self.pending = {}
        self.finished = set()

    def feed(self, line, now):
        event = None
        if match := re.search(r"operation=([A-Fa-f0-9-]+) event=([a-z-]+) elapsed=([0-9.]+)", line):
            operation, stage, _ = match.groups()
            if stage == "preparing-engine":
                event = ("download-" + operation, True)
            elif stage in ["provisional-navigation-started", "capturing-archive", "archive-complete", "failed", "cancelled"]:
                event = ("download-" + operation, False)
        elif match := re.search(r"operation=([A-Fa-f0-9-]+) phase=[a-z]+ elapsed=[0-9.]+ error-domain=", line):
            event = ("download-" + match[1], False)
        elif match := re.search(r"CACHE_STARTUP_PROBE (opening|rendered|released) iteration=(\d+)", line):
            stage, iteration = match.groups()
            event = ("cached-session-" + iteration, stage == "opening")
        elif match := re.search(r"CACHE_UI_PROBE (opening|rendered|failed) operation=([A-Fa-f0-9-]+)", line):
            stage, operation = match.groups()
            event = ("cache-ui-" + operation, stage == "opening")
        if event:
            key, opening = event
            if opening:
                # The same event can arrive through XCTest stdout and OSLog at
                # different times. A delayed duplicate must not reopen a finish.
                if key not in self.finished:
                    self.pending.setdefault(key, now)
            else:
                self.pending.pop(key, None)
                self.finished.add(key)
        return event

    def overdue(self, now, threshold):
        keys = [key for key, started in self.pending.items() if now - started >= threshold]
        for key in keys:
            del self.pending[key]
        return keys


class StartupWatcher:
    """Watch a single test group's fixed progress events without controlling it."""
    def __init__(self, diagnostics, folder, test_log, threshold=8, max_captures=3):
        self.diagnostics, self.folder = diagnostics, Path(folder)
        self.test_log, self.threshold, self.max_captures = Path(test_log), threshold, max_captures
        self.stop = threading.Event()
        self.thread = None

    def __enter__(self):
        self.folder.mkdir(parents=True, exist_ok=False)
        self.thread = threading.Thread(target=self._run, name="simulator-startup-watcher")
        self.thread.start()
        return self

    def __exit__(self, *unused):
        self.stop.set()
        # Bounded captures finish and all owned sampler/log processes are reaped.
        self.thread.join()

    def _run(self):
        tracker, captures, events = ProgressTracker(), [], []
        tracker.pending["xctest-bootstrap"] = time.monotonic()
        master, slave = pty.openpty()
        predicate = f'processImagePath CONTAINS "{self.diagnostics.simulator}" AND subsystem == "fun.yunle.apps" AND category == "cache-download"'
        process = subprocess.Popen(["/usr/bin/log", "stream", "--style", "compact", "--level", "debug", "--predicate", predicate],
                                   stdout=slave, stderr=slave, start_new_session=True)
        os.close(slave)
        buffers, offset = {"test": b"", "events": b""}, 0
        report = {"thresholdSeconds": self.threshold, "maxCaptures": self.max_captures, "events": events}
        try:
            with ThreadPoolExecutor(max_workers=1) as executor:
                while not self.stop.is_set():
                    now = time.monotonic()
                    chunks = {}
                    if self.test_log.exists():
                        with self.test_log.open("rb") as source:
                            source.seek(offset)
                            chunks["test"] = source.read()
                            offset = source.tell()
                    if select.select([master], [], [], 0.1)[0]:
                        try:
                            chunks["events"] = os.read(master, 65536)
                        except OSError:
                            break
                    for source, chunk in chunks.items():
                        buffers[source] += chunk
                        while b"\n" in buffers[source]:
                            line, buffers[source] = buffers[source].split(b"\n", 1)
                            text = line.decode(errors="replace")
                            if source == "test" and "Test Case '-" in text:
                                tracker.pending.pop("xctest-bootstrap", None)
                            if event := tracker.feed(text, now):
                                events.append({"source": source, "time": now, "operation": event[0], "opening": event[1]})
                    # Bootstrap can include ordinary installation/control setup;
                    # label it separately from app/WebKit startup.
                    bootstrap = tracker.pending.pop("xctest-bootstrap", None)
                    overdue = tracker.overdue(now, self.threshold)
                    if bootstrap is not None:
                        if now - bootstrap >= 30:
                            overdue.append("xctest-bootstrap")
                        else:
                            tracker.pending["xctest-bootstrap"] = bootstrap
                    for reason in overdue:
                        if len(captures) < self.max_captures and not any(not future.done() for future in captures):
                            captures.append(executor.submit(self.diagnostics.capture, self.folder / f"episode-{len(captures) + 1}", reason))
                            print("Capturing startup services: " + reason, flush=True)
                    if process.poll() is not None:
                        raise RuntimeError("Scoped log stream exited unexpectedly")
                    self.stop.wait(0.1)
        except Exception as error:
            report.update(error=type(error).__name__, detail=str(error))
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait(timeout=5)
            os.close(master)
            report["captures"] = [future.result() for future in captures]
            (self.folder / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
