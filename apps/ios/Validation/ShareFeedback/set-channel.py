"""Seed a remembered channel only in the task-owned simulator's validation App Group."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil

parser = argparse.ArgumentParser()
parser.add_argument('task_directory', type=Path)
parser.add_argument('channel', choices=['standard', 'testFlight'])
args = parser.parse_args()
owner = json.loads((args.task_directory / 'ownership.json').read_text())
assert owner['purpose'] == 'isolated system share and synthetic guest-ticket acceptance'
root = Path.home() / 'Library/Developer/CoreSimulator/Devices' / owner['simulator'] / 'data/Containers/Shared/AppGroup'
groups = []
for metadata in root.glob('*/.com.apple.mobile_container_manager.metadata.plist'):
    if plistlib.loads(metadata.read_bytes()).get('MCMMetadataIdentifier') == 'group.fun.yunle.apps.native-dev':
        groups.append(metadata.parent)
assert len(groups) == 1
path = groups[0] / 'SupportShare/receipts.json'
assert path.is_file() and not path.is_symlink()
state = json.loads(path.read_text())
assert state['schemaVersion'] == 1
state['context']['channel'] = args.channel
temporary = path.with_suffix('.qa-temporary')
assert not temporary.exists()
try:
    temporary.write_text(json.dumps(state))
    shutil.copystat(path, temporary)
    os.replace(temporary, path)
finally:
    temporary.unlink(missing_ok=True)
print('Seeded only the task-owned simulator channel:', args.channel)
