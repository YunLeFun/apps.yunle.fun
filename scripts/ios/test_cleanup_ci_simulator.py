"""Exercise the cleanup entry point without running any simulator command."""
import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).with_name("cleanup-ci-simulator.py")
OWNED = "10000000-0000-4000-8000-000000000001"
OTHER = "20000000-0000-4000-8000-000000000002"


class CleanupSimulatorTests(unittest.TestCase):
    def devices(self, state=None):
        devices = [{"udid": OTHER, "state": "Booted"}]
        if state is not None:
            devices.append({"udid": OWNED, "state": state})
        return {"devices": {"fixture-runtime": devices}}

    def invoke(self, observations=(), replies=None, identifier=OWNED, metadata=None):
        replies = replies or {}
        observations = iter(observations)
        calls = []

        def execute(command, **kwargs):
            self.assertEqual(command[:2], ["xcrun", "simctl"])
            operation = command[2]
            calls.append((command, kwargs.get("timeout")))
            if operation == "list":
                self.assertEqual(command[3:], ["devices", "--json"])
                value = next(observations)
                if value == "timeout":
                    raise subprocess.TimeoutExpired(command, kwargs["timeout"])
                return subprocess.CompletedProcess(command, 0, json.dumps(value), "")
            self.assertIn(operation, ["shutdown", "delete"])
            self.assertEqual(command[3:], [OWNED])
            value = replies.get(operation, 0)
            if value == "timeout":
                raise subprocess.TimeoutExpired(command, kwargs["timeout"])
            return subprocess.CompletedProcess(command, value, "", "native error" if value else "")

        def output(command, **kwargs):
            return execute(command, **kwargs).stdout

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "simulator.json").write_text(json.dumps(
                metadata if metadata is not None else {"id": identifier, "freshlyCreated": True}))
            environment = {"YLF_CI_SIMULATOR": identifier, "YLF_CI_OUTPUT": directory,
                           "YLF_CI_SOURCE_HEAD": "fixture", "GITHUB_RUN_ID": "fixture", "GITHUB_RUN_ATTEMPT": "1"}
            with mock.patch.dict(os.environ, environment), \
                    mock.patch.object(subprocess, "run", side_effect=execute), \
                    mock.patch.object(subprocess, "check_output", side_effect=output), \
                    contextlib.redirect_stdout(io.StringIO()):
                try:
                    runpy.run_path(str(SCRIPT), run_name="__main__")
                    code = 0
                except SystemExit as error:
                    code = error.code
            report = root / "cleanup-receipt.json"
            return code, json.loads(report.read_text()) if report.exists() else None, calls

    def test_timeout_still_checks_final_absence(self):
        code, report, calls = self.invoke(
            [self.devices("Shutting Down"), self.devices()],
            {"shutdown": "timeout", "delete": "timeout"})
        self.assertEqual(code, 0)
        self.assertTrue(report["verifiedAbsent"])
        self.assertEqual([entry["timedOut"] for entry in report["commands"]], [True, True])
        self.assertEqual([call[0][2] for call in calls], ["shutdown", "list", "delete", "list"])
        self.assertEqual([call[1] for call in calls], [30, 15, 60, 15])

    def test_normal_cleanup_requires_absence_and_keeps_other_device(self):
        code, report, calls = self.invoke([self.devices()])
        self.assertEqual(code, 0)
        self.assertTrue(report["verifiedAbsent"])
        self.assertEqual([call[0][2] for call in calls], ["shutdown", "delete", "list"])
        self.assertEqual([call[1] for call in calls], [30, 60, 15])

    def test_successful_commands_cannot_hide_remaining_device(self):
        code, report, _ = self.invoke([self.devices("Shutdown")])
        self.assertEqual(code, 1)
        self.assertFalse(report["verifiedAbsent"])
        self.assertEqual(report["observations"][-1]["state"], "Shutdown")

    def test_successful_commands_cannot_hide_unresponsive_query(self):
        code, report, _ = self.invoke(["timeout"])
        self.assertEqual(code, 1)
        self.assertFalse(report["verifiedAbsent"])
        self.assertEqual(report["observations"][-1]["presence"], "unknown")

    def test_malformed_query_cannot_be_treated_as_empty_inventory(self):
        code, report, _ = self.invoke([{}])
        self.assertEqual(code, 1)
        self.assertFalse(report["verifiedAbsent"])
        self.assertEqual(report["observations"][-1]["presence"], "unknown")

    def test_already_absent_after_shutdown_error_needs_no_delete(self):
        code, report, calls = self.invoke([self.devices()], {"shutdown": 1})
        self.assertEqual(code, 0)
        self.assertTrue(report["verifiedAbsent"])
        self.assertEqual([call[0][2] for call in calls], ["shutdown", "list"])

    def test_mismatched_ownership_refuses_all_commands(self):
        code, report, calls = self.invoke(metadata={"id": OTHER, "freshlyCreated": True})
        self.assertEqual(code, 1)
        self.assertEqual(report["result"], "refused")
        self.assertEqual(calls, [])

    def test_existing_device_without_creation_evidence_is_refused(self):
        code, report, calls = self.invoke(metadata={"id": OWNED, "freshlyCreated": False})
        self.assertEqual(code, 1)
        self.assertEqual(report["result"], "refused")
        self.assertEqual(calls, [])

    def test_global_simctl_selector_is_refused(self):
        code, report, calls = self.invoke(identifier="all")
        self.assertEqual(code, 1)
        self.assertEqual(report["result"], "refused")
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
