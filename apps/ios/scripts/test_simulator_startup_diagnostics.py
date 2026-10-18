"""Safety and event-boundary regressions; no simulator or process is controlled."""
import unittest
from unittest.mock import patch
from simulator_startup_diagnostics import ProgressTracker, SimulatorDiagnostics


class StartupDiagnosticsTests(unittest.TestCase):
    def test_navigation_policy_does_not_hide_a_stalled_engine(self):
        tracker = ProgressTracker()
        tracker.feed("operation=ABCD-1234 event=preparing-engine elapsed=0.0", 10)
        tracker.feed("operation=ABCD-1234 event=main-frame-navigation-allowed elapsed=2.0", 12)
        self.assertEqual(tracker.overdue(19, 8), ["download-ABCD-1234"])
        self.assertEqual(tracker.overdue(20, 8), [])

    def test_completed_or_failed_operations_do_not_trigger_later(self):
        for terminal in ["provisional-navigation-started", "archive-complete", "failed", "cancelled"]:
            tracker = ProgressTracker()
            tracker.feed("operation=ABCD event=preparing-engine elapsed=0.0", 10)
            tracker.feed(f"operation=ABCD event={terminal} elapsed=2.0", 12)
            self.assertEqual(tracker.overdue(30, 8), [])

    def test_cached_and_ui_waits_are_tracked_independently(self):
        tracker = ProgressTracker()
        tracker.feed("CACHE_STARTUP_PROBE opening iteration=1", 10)
        tracker.feed("CACHE_UI_PROBE opening operation=ABCD-1234", 11)
        tracker.feed("CACHE_STARTUP_PROBE rendered iteration=1 elapsed=2.0", 12)
        self.assertEqual(tracker.overdue(20, 8), ["cache-ui-ABCD-1234"])

    def test_downloader_error_clears_only_its_pending_operation(self):
        tracker = ProgressTracker()
        tracker.feed("operation=ABCD event=preparing-engine elapsed=0.0", 10)
        tracker.feed("operation=1234 event=preparing-engine elapsed=0.0", 10)
        tracker.feed("operation=ABCD phase=engine elapsed=2.0 error-domain=NSURLErrorDomain error-code=-999", 12)
        self.assertEqual(tracker.overdue(20, 8), ["download-1234"])

    def test_delayed_duplicate_log_does_not_reopen_completed_download(self):
        tracker = ProgressTracker()
        tracker.feed("operation=ABCD event=preparing-engine elapsed=0.0", 10)
        tracker.feed("operation=ABCD event=archive-complete elapsed=2.0", 12)
        tracker.feed("operation=ABCD event=preparing-engine elapsed=0.0", 13)
        self.assertEqual(tracker.overdue(30, 8), [])

    def test_another_devices_services_and_extensions_are_excluded(self):
        diagnostics = SimulatorDiagnostics.__new__(SimulatorDiagnostics)
        diagnostics.launchd = 100
        diagnostics.identity = {"uuid": "boot-a", "proc_start_abstime": 1}
        rows = [
            {"pid": 100, "parent": 1, "path": "/a/launchd_sim"},
            {"pid": 101, "parent": 100, "path": "/a/runningboardd"},
            {"pid": 102, "parent": 100, "path": "/a/WebContentExtension"},
            {"pid": 201, "parent": 200, "path": "/b/runningboardd"},
            {"pid": 202, "parent": 200, "path": "/b/WebContentExtension"},
        ]
        with patch("simulator_startup_diagnostics._processes", return_value=rows), \
             patch("simulator_startup_diagnostics.process_usage", return_value=diagnostics.identity), \
             patch("simulator_startup_diagnostics.host_snapshot", return_value={}):
            self.assertEqual([p["pid"] for p in diagnostics.snapshot()["processes"]], [100, 101, 102])

    def test_reused_launchd_pid_stops_capture(self):
        diagnostics = SimulatorDiagnostics.__new__(SimulatorDiagnostics)
        diagnostics.launchd = 100
        diagnostics.identity = {"uuid": "boot-a", "proc_start_abstime": 1}
        with patch("simulator_startup_diagnostics.process_usage", return_value={"uuid": "boot-b", "proc_start_abstime": 2}):
            with self.assertRaisesRegex(RuntimeError, "ended or launchd PID was reused"):
                diagnostics.snapshot()


if __name__ == "__main__":
    unittest.main()
