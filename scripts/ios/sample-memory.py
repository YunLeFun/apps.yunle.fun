"""Sample host and candidate WebKit processes in one isolated iOS Simulator."""
import argparse
import datetime
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--simulator", required=True)
parser.add_argument("--host-pid", required=True, type=int)
parser.add_argument("--sampler", required=True, type=Path)
parser.add_argument("--out", required=True, type=Path)
parser.add_argument("--count", type=int, default=3)
parser.add_argument("--interval", type=float, default=1)
args = parser.parse_args()
if args.count < 1 or args.count > 60 or not 0 <= args.interval <= 10:
    parser.error("Use 1...60 samples and an interval of 0...10 seconds")

rows = []
for line in subprocess.check_output(["ps", "-axo", "pid=,ppid=,command="], text=True).splitlines():
    parts = line.strip().split(None, 2)
    if len(parts) == 3:
        rows.append((int(parts[0]), int(parts[1]), parts[2]))
host = next((command for pid, _, command in rows if pid == args.host_pid), "")
if args.simulator not in host:
    parser.error("The host PID must belong to the specified simulator")
launchd = next((pid for pid, _, command in rows
                if command.startswith("launchd_sim ") and args.simulator in command), None)
if launchd is None:
    parser.error("No live launchd process found for this simulator")

candidates = {}
for pid, parent, command in rows:
    if parent != launchd:
        continue
    if "WebContentExtension.appex/" in command:
        candidates[pid] = "unattributed-web-content"
    elif "NetworkingExtension.appex/" in command:
        candidates[pid] = "unattributed-networking"

samples = []
start = time.monotonic()
for index in range(args.count):
    result = subprocess.run([str(args.sampler), str(args.host_pid), *map(str, candidates)],
                            capture_output=True, text=True, check=False)
    if result.returncode not in (0, 1):
        raise RuntimeError("Memory sampler failed: " + result.stderr.strip())
    processes = json.loads(result.stdout)
    samples.append({
        "timestampUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "elapsedSeconds": time.monotonic() - start,
        "processes": processes,
    })
    if index < args.count - 1:
        time.sleep(args.interval)

report = {
    "simulator": args.simulator,
    "hostPID": args.host_pid,
    "candidateWebKitProcesses": [{"pid": pid, "role": role} for pid, role in candidates.items()],
    "attribution": "Candidates are not assigned to this app until verified independently",
    "samplesBeforeDebuggerAttachment": samples,
}
args.out.parent.mkdir(parents=True, exist_ok=True)
args.out.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({"file": str(args.out), "hostPID": args.host_pid,
                  "hostPhysicalFootprintBytes": [sample["processes"][0].get("physicalFootprintBytes") for sample in samples],
                  "candidateWebKitPIDs": list(candidates)}))
