"""Remove one CI-created simulator and verify its absence, including after timeouts.

A timed-out simctl client does not prove whether CoreSimulator finished the action.
Commands are issued once; a successful inventory read must establish the result.
"""
import json
import os
from pathlib import Path
import subprocess
import time
import uuid


def text(value):
    return value.decode(errors="replace") if isinstance(value, bytes) else (value or "")


def command(arguments, timeout):
    started = time.monotonic()
    outcome = {"returnCode": None, "timedOut": False, "stdout": "", "stderr": ""}
    try:
        result = subprocess.run(["xcrun", "simctl", *arguments], capture_output=True,
                                text=True, timeout=timeout)
        outcome.update(returnCode=result.returncode, stdout=result.stdout, stderr=result.stderr)
    except subprocess.TimeoutExpired as error:
        outcome.update(timedOut=True, stdout=text(error.stdout), stderr=text(error.stderr))
    except (OSError, UnicodeError) as error:
        outcome["error"] = str(error)
    outcome["durationSeconds"] = round(time.monotonic() - started, 3)
    return outcome


def observe(simulator, after):
    outcome = command(["list", "devices", "--json"], 15)
    observation = {"after": after, "presence": "unknown", "state": None,
                   "returnCode": outcome["returnCode"], "timedOut": outcome["timedOut"],
                   "durationSeconds": outcome["durationSeconds"]}
    if outcome["returnCode"] != 0 or outcome["timedOut"]:
        observation["error"] = (outcome.get("error") or outcome["stderr"] or "Inventory query did not complete")[:4096]
        return observation
    try:
        groups = json.loads(outcome["stdout"])["devices"]
        if not isinstance(groups, dict) or any(not isinstance(group, list) for group in groups.values()):
            raise ValueError("Invalid simulator inventory groups")
        devices = [device for group in groups.values() for device in group]
        if any(not isinstance(device, dict) or not isinstance(device.get("udid"), str) for device in devices):
            raise ValueError("Invalid simulator inventory entry")
        matches = [device for device in devices if device["udid"].lower() == simulator.lower()]
        observation.update(presence="present" if matches else "absent",
                           state=matches[0].get("state") if matches else None)
    except (ValueError, KeyError, TypeError) as error:
        observation["error"] = str(error)
    return observation


def main():
    output = os.environ.get("YLF_CI_OUTPUT")
    if not output:
        print("Refusing cleanup without a job output directory")
        return 1
    root = Path(output)
    simulator = os.environ.get("YLF_CI_SIMULATOR", "")
    receipt = {"simulator": simulator, "sourceHead": os.environ.get("YLF_CI_SOURCE_HEAD"),
               "runID": os.environ.get("GITHUB_RUN_ID"), "runAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
               "ownershipVerified": False, "commands": [], "observations": [],
               "verifiedAbsent": False, "result": "unverified"}

    def mutate(operation, timeout):
        outcome = command([operation, simulator], timeout)
        receipt["commands"].append({"operation": operation, "timeoutSeconds": timeout,
                                    **{key: value[:4096] if isinstance(value, str) else value
                                       for key, value in outcome.items()}})
        print(operation + ": " + ("timed out" if outcome["timedOut"] else str(outcome["returnCode"])), flush=True)
        return outcome

    def absent(after):
        state = observe(simulator, after)
        receipt["observations"].append(state)
        print("Inventory after " + after + ": " + state["presence"], flush=True)
        if state["presence"] == "absent":
            receipt.update(verifiedAbsent=True, result="verified_absent")
            return True
        return False

    try:
        try:
            # Reject simctl's global selectors and IDs not created by this job.
            if str(uuid.UUID(simulator)).lower() != simulator.lower():
                raise ValueError("A canonical simulator UUID is required")
            metadata = json.loads((root / "simulator.json").read_text())
            if not isinstance(metadata, dict) or metadata.get("freshlyCreated") is not True or metadata.get("id") != simulator:
                raise ValueError("Simulator does not match this job's creation receipt")
        except (ValueError, OSError, TypeError) as error:
            receipt.update(result="refused", reason=str(error))
            return 1
        receipt["ownershipVerified"] = True
        shutdown = mutate("shutdown", 30)
        if (shutdown["timedOut"] or shutdown["returnCode"] != 0) and absent("shutdown"):
            return 0
        mutate("delete", 60)
        # Always read back, even when the delete client timed out or returned an error.
        return 0 if absent("delete") else 1
    finally:
        temporary = root / "cleanup-receipt.tmp"
        temporary.write_text(json.dumps(receipt, indent=2) + "\n")
        temporary.replace(root / "cleanup-receipt.json")
        print("Cleanup result: " + receipt["result"], flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
