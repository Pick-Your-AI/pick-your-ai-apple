#!/usr/bin/env python3
"""Require all four real native evidence-rendering XCTest methods to pass."""
import argparse
from pathlib import Path

import swift_mutations


REQUIRED = {
    "EvidenceRenderingTests.testSharedEvidenceVectorsRenderReportedOutcomesSeverityAndEveryPresenceState",
    "EvidenceRenderingTests.testReportedPassAndReadyRemainSeparateFromMissingEvidenceOnCompactAndWideViews",
    "EvidenceRenderingTests.testClaimGradesRequireTheirExistingInspectionAndIndependentSupportInputs",
    "EvidenceRenderingTests.testCorrectionAndFreshnessNoticesPreserveRetainedIdentityAndRequireARecheck",
}


def require_rendering_receipt(output):
    result = swift_mutations.suite_results(output, "Selected tests", "passed", module="PlannerUITests", require_module=True)
    if result is None:
        raise ValueError("Missing complete, uniquely qualified native rendering XCTest execution")
    cases, failures, unexpected, _ = result
    if cases != {name: "passed" for name in REQUIRED} or failures != 0 or unexpected != 0:
        raise ValueError("The four exact native rendering tests did not all pass without failures or skips")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    require_rendering_receipt(args.log.read_text())
    print(f"PASS {len(REQUIRED)} actual native evidence-rendering methods; {args.log.name}")


if __name__ == "__main__":
    main()
