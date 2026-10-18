#!/usr/bin/env python3
"""Capture one selected simulator's startup wait chain without controlling it."""
import argparse
import math
from pathlib import Path
import time
from simulator_startup_diagnostics import SimulatorDiagnostics, StartupWatcher


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--expected-device-name", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--watch-log", type=Path, help="Watch a cache XCTest log plus scoped download events instead of capturing immediately")
    parser.add_argument("--duration", type=float, default=600)
    args = parser.parse_args()
    if not math.isfinite(args.duration) or not 0 < args.duration <= 1800:
        parser.error("--duration must be in (0, 1800]")
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("--output must be empty")
    diagnostics = SimulatorDiagnostics(args.simulator, args.expected_device_name)
    if args.watch_log:
        if output.exists():
            output.rmdir()
        with StartupWatcher(diagnostics, output, args.watch_log) as watcher:
            try:
                watcher.stop.wait(args.duration)
            except KeyboardInterrupt:
                pass
    else:
        if output.exists():
            output.rmdir()
        report = diagnostics.capture(output, "manual-startup-investigation")
        if report["status"] != "captured":
            raise RuntimeError("Capture incomplete; inspect capture.json")


if __name__ == "__main__":
    main()
