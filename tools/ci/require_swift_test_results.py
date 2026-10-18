#!/usr/bin/env python3
"""Require executed XCTest results from the pinned Darwin SwiftPM test runner.

Compilation output and the separate Swift Testing zero-test footer are not
XCTest execution evidence. Unknown or incomplete result formats fail closed.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re


TRANSFER_DETAILS = {
    "PlannerTransferTests.CatalogItemDetailsTests": (
        "testEveryCanonicalKindUsesItsExactSchemaFieldsAndPreservesItemIdentity",
        "testMissingFalseZeroAndEmptyTextRemainDifferent",
        "testUnknownAndIncompleteCollectionsRetainTheirExactRecordedContents",
        "testProvenanceRetainsContradictionsAndRawStatusWithoutCreatingAnEvidenceGrade",
        "testAbsentOptionalDeclarationsDoNotAcquireDefaultsOrAuthority",
        "testDistinctVersionsAndExactDecimalValuesDoNotCollapseOrChangeDuringProjection",
    ),
}
UI_DETAILS = {
    "PlannerUITests.CatalogDetailsModelTests": (
        "testBundledDetailsResolveAllExactKindsWithoutInvalidatingAnIssuedPage",
        "testBundledDetailsRejectForgedRowsAndChangedCatalogPins",
        "testFailureAndRetryKeepTheExactSelectedPin",
        "testMismatchedResolvedIdentityOrHashCannotBecomeVisible",
        "testDismissalRejectsALateCancellationIgnoringResultAndRetiredActions",
        "testSourcePaginationRetainsEveryRecordAndNeverChangesTheItemPin",
        "testLiteralDisplayEscapesInvisibleControlsAndBoundsCompleteUnicodeScalars",
        "testSheetIdentityIncludesTheCatalogReleaseAndCompleteRow",
    ),
}

# The stacked details candidate and the editor receiving composition have
# different exact inventories. Retain both profiles without treating either
# candidate's historical output as execution of the other composition.
PROFILES = {
    "catalog-details-transfer": (42, TRANSFER_DETAILS),
    "catalog-details-ui": (68, UI_DETAILS),
    "catalog-editor-transfer": (48, {
        **TRANSFER_DETAILS,
        "PlannerTransferTests.BuildTransferTests": (
            "testLocalSnapshotEncodingPreservesPrivateFieldsAndReopensExactly",
            "testSnapshotEncodingRejectsExpansionPastItsDecodeLimit",
        ),
        "PlannerTransferTests.BuildComparisonTests": (
            "testFieldLikeSelectionIDsKeepPublicSettingChanges",
            "testAddedAndRemovedFieldLikeSelectionIDsRetainPublicFields",
            "testFieldLikeLinkIDsKeepChangesAdditionsAndRemovals",
            "testFieldLikeIDsDoNotDisableNestedPrivateFieldRedaction",
        ),
    }),
    "catalog-editor-ui": (87, {
        **UI_DETAILS,
        "PlannerUITests.CatalogBrowserModelTests": (
            "testBundledPreviewValidatesAllKindsAndRemainsVisiblySynthetic",
            "testConcurrentPreviewLoadsPreserveBothIssuedPageTokens",
            "testCombinedFiltersSortCountsAndDistinctVersionPinsPersistAcrossRecreation",
            "testFailedNextPageRetainsRowsCountFiltersAndCursorUntilRetrySucceeds",
            "testLateCancellationIgnoringResponseCannotReplaceNewerFiltersOrRows",
            "testChangedCatalogResetsWholePageCollectionAndRetryKeepsFilters",
            "testInvalidStoredAndEditedFiltersNeverReachSourceOrOverwriteLastValidPreferences",
            "testUnavailableFirstPageAndEmptyResultsAreDifferentStates",
        ),
        "PlannerUITests.ImportedBuildLibraryTests": (
            "testLocalRenamePreservesSnapshotAndHistoryAcrossRestart",
            "testDuplicateCreatesFreshForkAndRetainsSyntheticQualificationAndLocks",
            "testStaleRenameDuplicateAndDeleteCannotMutateNewerRevision",
            "testConfirmedDeleteTargetsCapturedEntryAndPreservesDifferentSelection",
            "testLargeLibraryRetainsCorruptWrapperAndUnrelatedMetadataAfterRenameDeleteAndRestart",
            "testEntireUnreadablePageStillReachesLaterValidBuild",
            "testMalformedQualificationCannotBeOpenedMutatedOrSilentlyDropped",
            "testPreviewPreparationLeavesMainActorResponsive",
            "testCancelledPreviewPreparationCannotPublishOrWrite",
            "testExportPreparationLeavesMainActorResponsiveAndPreservesQualification",
            "testClearedExportRejectsLateBytesAndErrorsAndRetryUsesNewAlias",
            "testInvalidatedQueuedExportNeverEntersPreparation",
            "testCancelledExportPreparationCannotPublishOrWrite",
        ),
        "PlannerUITests.ComparisonFieldTextTests": (
            "testUserTextCannotImpersonateMissingPrivateEmptyOrTypedValues",
            "testOriginalSentinelStringsRemainExplicitText",
            "testMultilineTextIsPreservedWithoutTruncation",
        ),
        "PlannerUITests.DraftLibraryModelTests": (
            "testSuccessfulRefreshClearsLibraryFailureAndLoadsCurrentRecords",
            "testLibraryFailureAndRecoveryPreserveConflictGuidanceAndUnsavedInput",
            "testPageRetryClearsItsFailureWithoutReplacingRowsOnFailedRead",
            "testHistoryPageFailureKeepsContextAndSuccessfulRetryClearsItsNotice",
            "testHistoryRecoveryPreservesIndependentConflictNotice",
            "testHistoryRecoveryDoesNotClearOutstandingLibraryFailure",
        ),
    }),
}

CASE = re.compile(
    r"^Test Case '-\[([A-Za-z_][A-Za-z0-9_.]*) (test[A-Za-z0-9_]+)\]' "
    r"(passed|failed|skipped) \([^\r\n]*\)\.$", re.MULTILINE
)
SUMMARY = re.compile(
    r"^Test Suite 'All tests' passed at [^\r\n]+\r?\n"
    r"[ \t]*Executed ([0-9]+) tests?, with 0 failures \(0 unexpected\)", re.MULTILINE
)


def verify(text: str, expected_total: int, required_cases: set[tuple[str, str]]) -> None:
    records = CASE.findall(text)
    identities = [(suite, name) for suite, name, _ in records]
    if expected_total < 1 or len(records) != expected_total:
        raise ValueError(f"Expected {expected_total} executed XCTest cases; found {len(records)}")
    if len(set(identities)) != expected_total:
        raise ValueError("Duplicate XCTest case identities cannot satisfy the execution count")
    if any(status != "passed" for _, _, status in records):
        raise ValueError("Every XCTest case must pass; failed and skipped cases are not acceptance")
    missing = required_cases - set(identities)
    if missing:
        raise ValueError("Required XCTest cases did not execute: " + ", ".join(
            f"{suite}.{name}" for suite, name in sorted(missing)))
    if SUMMARY.findall(text) != [str(expected_total)]:
        raise ValueError("Require one complete All tests success summary with the exact execution count")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", choices=PROFILES)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    total, groups = PROFILES[args.profile]
    required = {(suite, name) for suite, names in groups.items() for name in names}
    try:
        verify(args.log.read_text(encoding="utf-8"), total, required)
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(1, f"Swift execution evidence rejected: {error}\n")
    print(f"Verified {total} distinct executed XCTest cases, all passed; "
          f"all {len(required)} required cases across {len(groups)} XCTest classes executed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
