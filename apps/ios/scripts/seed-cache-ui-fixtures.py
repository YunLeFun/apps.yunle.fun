#!/usr/bin/env python3
"""Seed cache fixtures in an empty native-dev simulator for opt-in UI tests."""
import argparse
import datetime
import hashlib
import json
import pathlib
import plistlib
import subprocess
import urllib.request

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("simulator_uuid")
parser.add_argument("--automatic", action="store_true", help="Seed an expired public Cloud Air cache for a real automatic update")
args = parser.parse_args()

container = subprocess.check_output([
    "xcrun", "simctl", "get_app_container", args.simulator_uuid, "fun.yunle.apps.native-dev", "data"
], text=True).strip()
directory = pathlib.Path(container) / "Library/Caches/CloudApplicationDownloads"
if list(directory.glob("*.cache")):
    raise SystemExit("Use an empty guest test simulator; existing downloads will not be changed.")
if args.automatic:
    with urllib.request.urlopen("https://apps.yunle.fun/api/apps/public", timeout=20) as response:
        catalog = json.load(response)
    applications = catalog["items"]
    applications = [app for app in applications if app["_id"] == "3b49fbed6a2707b9000a533e02729196"]
    if len(applications) != 1 or applications[0].get("websiteUrl") != "https://ac.yunyoujun.cn":
        raise SystemExit("Public Cloud Air metadata changed; inspect the catalog before seeding.")
    html = "<html><meta name='viewport' content='width=device-width'><body><h1>自动更新旧版本</h1></body></html>".encode()
else:
    applications = [
        {"_id": "cache-confirm-one", "name": "缓存确认测试一", "websiteUrl": "https://cache-ui.invalid/one"},
        {"_id": "cache-confirm-two", "name": "缓存确认测试二", "websiteUrl": "https://cache-ui.invalid/two"},
    ]
    html = b"<html><title>cache-ui</title></html>"

directory.mkdir(parents=True, exist_ok=True)
for application in applications:
    identifier, url = application["_id"], application["websiteUrl"]
    # Matches Foundation JSONEncoder's default slash escaping, used by ApplicationCacheEntry.key.
    key_input = json.dumps([identifier, "public", url], separators=(",", ":")).replace("/", "\\/")
    key = hashlib.sha256(key_input.encode()).hexdigest()
    archive = plistlib.dumps({"WebMainResource": {
        "WebResourceURL": url, "WebResourceMIMEType": "text/html",
        "WebResourceTextEncodingName": "UTF-8", "WebResourceData": html,
    }}, fmt=plistlib.FMT_BINARY)
    entry = {
        "id": key, "application": {key: value for key, value in application.items() if value is not None},
        "launchURL": {"relative": url},
        "downloadedAt": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) - datetime.timedelta(days=2),
        "byteCount": len(archive), "resourceCount": 1,
    }
    record = {"version": 1, "entry": entry, "archive": archive, "digest": hashlib.sha256(archive).digest()}
    (directory / (key + ".cache")).write_bytes(plistlib.dumps(record, fmt=plistlib.FMT_BINARY))
print(f"Seeded {len(applications)} cache record(s); the UI test clears them through the app.")
