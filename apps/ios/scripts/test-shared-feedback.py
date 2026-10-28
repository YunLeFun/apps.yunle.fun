#!/usr/bin/env python3
"""Run the actual extension-safe sources and their XCTest cases on macOS, without a simulator."""
from pathlib import Path
import signal
import subprocess
import tempfile


def stop(_signum, _frame):
    raise KeyboardInterrupt


def main():
    ios = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="yunle-share-feedback-tests-") as temporary:
        root = Path(temporary)
        source = root / "Sources" / "ShareFeedbackCore"
        tests = root / "Tests" / "ShareFeedbackCoreTests"
        source.mkdir(parents=True)
        tests.mkdir(parents=True)
        files = list((ios / "SharedFeedback").glob("*.swift")) + [
            ios / "YunleFun/Models/FeedbackScreenshot.swift",
            ios / "YunleFun/Models/FeedbackChannel.swift",
            ios / "YunleFun/Models/SupportTicket.swift",
            ios / "YunleFun/Services/SupportTicketClient.swift",
        ]
        for path in files:
            (source / path.name).symlink_to(path)
        for name in ["SharedFeedbackTestSupport.swift", "SharedFeedbackHistoryTests.swift",
                     "SharedScreenshotImporterTests.swift", "ShareFeedbackComposerTests.swift", "SharedFeedbackClientTests.swift", "SupportTicketClientTests.swift"]:
            (tests / name).symlink_to(ios / "YunleFunTests" / name)
        (root / "Package.swift").write_text('''// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "ShareFeedbackCore", platforms: [.macOS(.v13)], targets: [
    .target(name: "ShareFeedbackCore"),
    .testTarget(name: "ShareFeedbackCoreTests", dependencies: ["ShareFeedbackCore"]),
])
''')
        process = subprocess.Popen(["swift", "test", "--package-path", str(root), "--jobs", "4"])
        try:
            return process.wait()
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop)
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
