#!/usr/bin/env python3
"""Require one complete native CostCoverageView XCTest session."""
from __future__ import annotations

import argparse
from pathlib import Path
import re


REQUIRED = frozenset({
    "testMostExpensiveRateRemovalKeepsBudgetUnknownAndRecoveryVisible",
    "testMissingZeroExpiredUnsupportedMixedAndStaleCostsRemainQualified",
    "testLargeTextCompactAndWideLayoutsRetainExactMoneyAndBoundedMissingCosts",
})
CLASS = "PlannerCostUITests.CostRenderingTests"
ROOT = re.compile(r"Test Suite '(All tests|Selected tests)' (started|passed|failed|skipped) at .+")
IDENTITY = r"(?P<class>[A-Za-z_][A-Za-z0-9_.]*) (?P<method>test[A-Za-z0-9_]+)"
START = re.compile(r"Test Case '-\[" + IDENTITY + r"\]' started\.")
FINISH = re.compile(
    r"Test Case '-\[" + IDENTITY + r"\]' (?P<status>passed|failed|skipped) "
    r"\([0-9]+(?:\.[0-9]+)? seconds\)\.")
SUMMARY = re.compile(
    r"\s*Executed ([0-9]+) tests?, with ([0-9]+) failures? "
    r"\(([0-9]+) unexpected\) in [0-9]+(?:\.[0-9]+)? "
    r"\([0-9]+(?:\.[0-9]+)?\) seconds")


def require_cost_receipt(output: str) -> None:
    lines = output.splitlines()
    roots = []
    for index, line in enumerate(lines):
        if line.startswith(("Test Suite 'All tests'", "Test Suite 'Selected tests'")):
            match = ROOT.fullmatch(line)
            if match is None:
                raise ValueError("The native cost root has an unknown or incomplete format")
            roots.append((index, match))
    if (len(roots) != 2 or roots[0][1][1] != roots[1][1][1]
            or roots[0][1][2] != "started" or roots[1][1][2] != "passed"):
        raise ValueError("Exactly one complete passing native cost XCTest session is required")
    start, end = roots[0][0], roots[1][0]
    if end + 1 >= len(lines):
        raise ValueError("The native cost session has no complete final summary")
    summary = SUMMARY.fullmatch(lines[end + 1])
    if summary is None or tuple(map(int, summary.groups())) != (len(REQUIRED), 0, 0):
        raise ValueError("The final cost summary must report three tests and zero failures")
    started: set[str] = set()
    finished: dict[str, str] = {}
    for index, line in enumerate(lines):
        if line.startswith("Test Suite ") and re.search(r"' (failed|skipped) at ", line):
            raise ValueError("A failed or skipped suite cannot qualify native cost rendering")
        if not line.startswith("Test Case "):
            continue
        beginning = START.fullmatch(line)
        completion = FINISH.fullmatch(line)
        event = beginning or completion
        if event is None or not start < index < end or event["class"] != CLASS:
            raise ValueError("Unqualified, malformed or out-of-session native cost method")
        name = event["method"]
        if beginning:
            if name in started:
                raise ValueError("A duplicate native cost start cannot qualify the session")
            started.add(name)
        else:
            if name not in started or name in finished:
                raise ValueError("A native cost completion needs one preceding unique start")
            finished[name] = event["status"]
    if started != REQUIRED or finished != {name: "passed" for name in REQUIRED}:
        raise ValueError("All three exact native cost methods must start and pass without skips")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    try:
        require_cost_receipt(args.log.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(1, f"Native cost evidence rejected: {error}\n")
    print(f"PASS {len(REQUIRED)} actual native cost-rendering methods; {args.log.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
