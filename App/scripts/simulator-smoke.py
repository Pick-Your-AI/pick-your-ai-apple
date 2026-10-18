#!/usr/bin/env python3
"""Install/launch on an available iPhone and iPad simulator; no device claim."""
import json
import subprocess

def run(*args):
    return subprocess.check_output(args, text=True).strip()

inventory = json.loads(run("xcrun", "simctl", "list", "--json"))
runtimes = [r for r in inventory["runtimes"] if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
if not runtimes:
    raise SystemExit("No available iOS simulator runtime")
runtime = max(runtimes, key=lambda r: tuple(int(v) for v in r["version"].split(".")))
for family in ("iPhone", "iPad"):
    available = [d for d in inventory["devices"].get(runtime["identifier"], [])
                 if d.get("isAvailable") and d["name"].startswith(family)]
    if not available:
        raise SystemExit(f"No available {family} for {runtime['name']}")
    compatible = available[0]
    device = next(d for d in inventory["devicetypes"]
                  if d["name"] == compatible["name"])
    udid = run("xcrun", "simctl", "create", f"Planner-{family}-CI", device["identifier"], runtime["identifier"])
    try:
        print(f"Smoke launch: {device['name']}, iOS {runtime['version']}", flush=True)
        run("xcrun", "simctl", "boot", udid)
        run("xcrun", "simctl", "bootstatus", udid, "-b")
        run("xcrun", "simctl", "install", udid, ".build/native/Build/Products/Debug-iphonesimulator/Planner.app")
        print(run("xcrun", "simctl", "launch", "--terminate-running-process", udid, "invalid.pickyourai.localpreview"))
        run("xcrun", "simctl", "terminate", udid, "invalid.pickyourai.localpreview")
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", udid], check=False)
        subprocess.run(["xcrun", "simctl", "delete", udid], check=False)
