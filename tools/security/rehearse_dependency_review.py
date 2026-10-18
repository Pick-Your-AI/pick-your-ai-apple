#!/usr/bin/env python3
"""Replay harmless review-output fixtures through the actual command-line gate."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys


SCRIPT = Path(__file__).with_name("check_dependency_review.py")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    safe = {
        "change_type": "added", "manifest": "synthetic/requirements.txt",
        "ecosystem": "pip", "name": "synthetic-review-fixture", "version": "1.0.1",
        "scope": "development", "license": "MIT", "vulnerabilities": [],
        "package_url": "pkg:pypi/synthetic-review-fixture@1.0.1", "source_repository_url": None,
    }
    vulnerable = {
        **safe, "version": "1.0.0", "vulnerabilities": [{"severity": "critical"}],
    }
    unapproved = {**safe, "license": "LicenseRef-Synthetic-Unapproved"}
    clean_licenses = {"forbidden": [], "unresolved": [], "unlicensed": []}
    unlicensed = {**safe, "license": None}
    cases = [
        ("no-dependency-change", [], clean_licenses, 0),
        ("vulnerable-development-dependency", [vulnerable], clean_licenses, 1),
        ("unapproved-license", [unapproved], {**clean_licenses, "forbidden": [unapproved]}, 1),
        ("unresolved-license", [unlicensed], {**clean_licenses, "unlicensed": [unlicensed]}, 1),
        ("urgent-update-recovery", [{**vulnerable, "change_type": "removed"}, safe], clean_licenses, 0),
        ("patched-version-with-missing-review", [safe], None, 1),
    ]
    results = []
    for name, changes, licenses, expected in cases:
        # The synthetic replay needs no network, repository token or inherited
        # credentials. No package represented in the fixture is installed.
        env = {"PYTHONUTF8": "1", "DEPENDENCY_CHANGES": json.dumps(changes)}
        if licenses is not None:
            env["INVALID_LICENSE_CHANGES"] = json.dumps(licenses)
        run = subprocess.run(
            [sys.executable, str(SCRIPT)], env=env, capture_output=True, text=True,
            timeout=10, check=False,
        )
        results.append({
            "case": name, "expected_exit": expected, "actual_exit": run.returncode,
            "passed": run.returncode == expected,
            "report": json.loads(run.stdout) if run.stdout else None,
            "diagnostic": run.stderr.strip() or None,
        })
    report = {
        "schema_version": 1,
        "kind": "synthetic-dependency-review-output-drill",
        "python": platform.python_version(),
        "guard_sha256": hashlib.sha256(SCRIPT.read_bytes()).hexdigest(),
        "limits": [
            "Uses supplied synthetic review output; does not query an advisory database.",
            "Does not install a vulnerable package, change credentials or test a release binary.",
            "SPDX classifications are fixture inputs; hosted action classification remains a separate gate.",
        ],
        "passed": all(result["passed"] for result in results),
        "cases": results,
    }
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
