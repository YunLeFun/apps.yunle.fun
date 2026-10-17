import os
from pathlib import Path
import subprocess
import time

root = Path(os.environ['YLF_CI_OUTPUT'])
target = root / 'tests-none1.log'
deadline = time.monotonic() + 1500
while time.monotonic() < deadline:
    if target.exists() and '[DEBUG-cookie] wait.failed' in target.read_text(errors='replace'):
        break
    time.sleep(0.1)
else:
    raise SystemExit(0)

pids = subprocess.run(['pgrep', '-x', 'YunleFun'], capture_output=True, text=True).stdout.split()
services = subprocess.run(['xcrun', 'simctl', 'spawn', os.environ['YLF_CI_SIMULATOR'],
                           'launchctl', 'list'], capture_output=True, text=True, timeout=5).stdout
for line in services.splitlines():
    parts = line.split()
    if len(parts) == 3 and 'WebKit.Networking' in parts[2] and parts[0].isdigit():
        pids.append(parts[0])
process_list = subprocess.run(['ps', '-axo', 'pid,comm'], capture_output=True, text=True).stdout
for line in process_list.splitlines():
    if 'RuntimeRoot/' in line and 'NetworkingExtension.appex/com.apple.WebKit.Networking' in line:
        pids.append(line.split()[0])
pids = list(dict.fromkeys(pids))
if pids:
    state = subprocess.run(['ps', '-p', ','.join(pids), '-o', 'pid,ppid,state,comm'],
                           capture_output=True, text=True).stdout
    (root / 'stalled-processes.log').write_text(state)
    processes = [subprocess.Popen(['sample', pid, '1', '-file', str(root / ('sample-' + pid + '.log'))],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) for pid in pids]
    for process in processes:
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.terminate()
