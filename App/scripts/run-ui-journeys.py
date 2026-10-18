#!/usr/bin/env python3
"""Run real UI journeys on two newly created, isolated iOS simulators."""
import json
from pathlib import Path
import subprocess
import uuid


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    evidence = Path(".build/native-ui-evidence") / ("run-" + uuid.uuid4().hex)
    evidence.mkdir(parents=True, exist_ok=True)
    inventory = json.loads(output("xcrun", "simctl", "list", "--json"))
    (evidence / "simulator-inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
    runtime = "com.apple.CoreSimulator.SimRuntime.iOS-18-5"
    if not any(r["identifier"] == runtime and r.get("isAvailable") for r in inventory["runtimes"]):
        raise SystemExit("Required iOS 18.5 simulator runtime is unavailable. Install it in Xcode Settings > Components; this check will not select a different runtime.")
    selected = []
    for label, device_name in [("iphone", "iPhone SE (3rd generation)"), ("ipad", "iPad (10th generation)")]:
        matches = [d for d in inventory["devicetypes"] if d["name"] == device_name]
        if len(matches) != 1:
            raise SystemExit(f"Required simulator device type {device_name!r} is unavailable. Use the documented Xcode 16.4 setup; no substitute device is selected.")
        device_type = matches[0]["identifier"]
        udid = output("xcrun", "simctl", "create", f"Planner-UI-{label}", device_type, runtime)
        selected.append({"label": label, "name": device_name, "device_type": device_type, "runtime": runtime, "udid": udid})
        (evidence / "selected-simulators.json").write_text(json.dumps(selected, indent=2) + "\n")
        try:
            print(f"UI journey: {device_name}, iOS 18.5, {udid}", flush=True)
            subprocess.run([
                "xcodebuild", "test", "-project", "App/Planner.xcodeproj", "-scheme", "Planner",
                "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={udid}",
                "-destination-timeout", "120", "-parallel-testing-enabled", "NO",
                "-derivedDataPath", ".build/native-ui-tests",
                "-resultBundlePath", str(evidence / f"{label}.xcresult"),
                "CODE_SIGNING_ALLOWED=NO",
            ], check=True, timeout=15 * 60)
        finally:
            # Only devices created by this process are touched; no shared device
            # erasure, application reset flag, or host shutdown is used.
            subprocess.run(["xcrun", "simctl", "shutdown", udid], check=False)
            subprocess.run(["xcrun", "simctl", "delete", udid], check=False)


if __name__ == "__main__":
    main()
