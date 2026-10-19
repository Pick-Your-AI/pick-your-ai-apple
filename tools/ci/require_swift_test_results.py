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

# Preserve the catalog/editor profile as historical evidence. This composition
# adds the nine independently reviewed comparison-preparation cases while
# retaining every required case and class from that receiving source.
PROFILES["comparison-catalog-editor-ui"] = (96, {
    **PROFILES["catalog-editor-ui"][1],
    "PlannerUITests.ImportedBuildLibraryTests": (
        *PROFILES["catalog-editor-ui"][1]["PlannerUITests.ImportedBuildLibraryTests"],
        "testComparisonPreparationLeavesMainActorResponsiveAndPreservesInputs",
        "testNewSelectionComparisonFinishesBeforeCancelledOlderResultOrError",
        "testCancelledOlderComparisonCannotClearPendingNewerWork",
        "testReplacingBaselineRejectsLateComparisonAndRetainsNewQualification",
        "testClearedBaselineRejectsLateComparisonAndError",
        "testCancelledComparisonRejectsLateResultAndErrorWithoutClearingPin",
        "testInvalidatedQueuedComparisonNeverEntersWorker",
        "testCommittedBaselineDeletionCancelsPendingComparisonAndPreservesSelection",
        "testRejectedBaselineDeletionPreservesPinAndPendingComparison",
    ),
})

# The accepted quality boundary adds nine cases to the receiving Transfer tree.
# Keep the earlier 48-case profile scoped to its own source and results.
PROFILES["quality-catalog-editor-transfer"] = (57, {
    **PROFILES["catalog-editor-transfer"][1],
    "PlannerTransferTests.QualityEvaluationRunTests": (
        "testCanonicalRecordRetainsIdentityAndEverySupportedField",
        "testSharedCanonicalQualityConformanceVectorsUseRawNumericTokens",
        "testOptionalAbsenceRemainsDistinctFromEmptyArraysAndStrings",
        "testRecordedLabelsChronologyDuplicatesAndPrivateTextAreNotReinterpreted",
        "testNumericViewsRemainExactWithoutNarrowingOrRounding",
        "testDuplicateRootAndMeasurementKeysIncludingEscapedAliasesFail",
        "testByteDepthAndAggregateNodeLimitsApplyBeforeSchemaAcceptance",
        "testUnsupportedAndMalformedInputReturnsPayloadFreeErrors",
        "testNormalizedOutputCannotExceedTheDecoderLimitOrChangeTheValue",
    ),
})

# Source-link review adds fourteen executed cases while retaining every required
# identity from the separately qualified 87-case receiving source.
PROFILES["catalog-source-ui"] = (101, {
    **PROFILES["catalog-editor-ui"][1],
    "PlannerUITests.CatalogSourceLinkPolicyTests": (
        "testApprovedHTTPSDestinationsPreserveTheCompleteURLAndHost",
        "testUnreviewedAndConfusableAuthoritiesCannotBecomeCandidates",
        "testMalformedAndNonHTTPSInputCannotBeRepairedIntoNavigation",
        "testTheURLByteLimitIsExactAndCannotBeConfiguredAbove4096",
        "testConfigurationRequiresExplicitBoundedASCIIDNSNames",
        "testDiagnosticDescriptionsRedactSourceAddressesAndOpeningIDs",
    ),
    "PlannerUITests.CatalogSourceReviewModelTests": (
        "testSourceReviewRequiresLoadedVisibleRecordAndExactConfirmation",
        "testDefaultPolicyAndMissingOrUnsafeSourcesNeverOfferAnOpening",
        "testSourceReviewReplacementAndClosureRetireCapturedActionsAndCallbacks",
        "testRejectedSystemHandoffRequiresFreshExplicitReviewToRetry",
        "testClosingDetailsRetiresAllNavigationAndRetainsThePinnedRecord",
        "testSourcePaginationOnlyExposesOrderedRecordsWithoutChangingConsentOrPins",
        "testStaleContradictoryProvenanceNeverBecomesVerifiedByAnAcceptedHandoff",
        "testARecreatedVersionCannotUseThePreviousDetailReviewOrHandoff",
    ),
})

# This receiving tree contains both independently reviewed additions. Keep each
# earlier profile tied to its own source and require all 23 added case identities.
PROFILES["comparison-catalog-source-ui"] = (110, {
    **PROFILES["comparison-catalog-editor-ui"][1],
    "PlannerUITests.CatalogSourceLinkPolicyTests":
        PROFILES["catalog-source-ui"][1]["PlannerUITests.CatalogSourceLinkPolicyTests"],
    "PlannerUITests.CatalogSourceReviewModelTests":
        PROFILES["catalog-source-ui"][1]["PlannerUITests.CatalogSourceReviewModelTests"],
})

# The current-main resource boundary adds eight cases to the complete reviewed
# snapshot/editor/quality transfer source; old profiles retain their own totals.
PROFILES["resource-quality-catalog-editor-transfer"] = (65, {
    **PROFILES["quality-catalog-editor-transfer"][1],
    "PlannerTransferTests.ResourceEstimateTests": (
        "testCanonicalArtifactPreservesBuildEstimatorSelectionIdentityAndRoundTrip",
        "testSharedCanonicalResourceVectorsAndExplicitClientSubsets",
        "testDecimalSpellingAndSourceAbsenceRemainExactWithoutBinaryConversion",
        "testForeignPartialRepeatedDeclarationsStayUnevaluatedAndInOrder",
        "testDuplicateKeysEscapedAliasesAndDuplicateSelectionsAreRejected",
        "testAggregateBoundsPrecedeSchemaAdmissionAndCoverTheWholeArtifact",
        "testEncodingExpansionFailsWithoutChangingTheValidatedEstimate",
        "testLateInvalidEntriesVersionsAndSchemaAvailabilityFailWithoutPartialResults",
    ),
})

# The combined Graph/editor source retains the complete 65-case profile and
# adds all six graph methods. Earlier profiles and Graph-only receipts retain
# their own source identities; a padded older result cannot qualify this union.
PROFILES["graph-resource-quality-catalog-editor-transfer"] = (71, {
    **PROFILES["resource-quality-catalog-editor-transfer"][1],
    "PlannerTransferTests.DependencyGraphTests": (
        "testCanonicalGraphPreservesEveryDirectedRelationshipAndLabel",
        "testSharedCanonicalDependencyGraphVectors",
        "testRepeatedIdentifiersSelfEdgesAndCyclesRemainUnmodified",
        "testDuplicateRootAndEscapedEdgeKeysAreRejected",
        "testCompleteDocumentByteDepthAndNodeLimitsPrecedeSchemaValidation",
        "testEncodedExpansionCannotReturnBytesThatCannotBeReopened",
    ),
})

# The package privacy declaration requires an actual production-bundle read.
# Retain the earlier 110-case profile for its own source and execution receipts.
PROFILES["comparison-catalog-source-privacy-ui"] = (111, {
    **PROFILES["comparison-catalog-source-ui"][1],
    "PlannerUITests.PlannerUIPrivacyManifestTests": (
        "testPackagedManifestDeclaresOwnAppPreferencesReason",
    ),
})


# Current accepted main contributes 23 editor methods; this isolated comparison
# adds 18. Preserve the other profiles as source-bound historical inventories.
PROFILES["component-comparison-main-ui"] = (41, {
    "PlannerUITests.DraftLibraryModelTests": (
        "testCreateSaveReopenDuplicateAndDelete",
        "testConflictPreservesUnsavedInput",
        "testUnknownEditorPayloadIsPreserved",
        "testUnknownPayloadFieldsAreNotSilentlyDiscarded",
        "testInvalidTitleRetainsEditsAndDoesNotAcknowledgeSave",
        "testEditsArrivingDuringSaveRemainDirty",
        "testRefreshFailureDoesNotRevokeDurableAcknowledgement",
        "testSuccessfulRefreshClearsLibraryFailureAndLoadsCurrentRecords",
        "testLibraryFailureAndRecoveryPreserveConflictGuidanceAndUnsavedInput",
        "testDirtyNavigationGuardsAndSelectedDeletion",
        "testEditorBindingsCannotChangeDuringDestructiveDelete",
        "testLibraryKeepsOnlyOneBoundedPage",
        "testPageRetryClearsItsFailureWithoutReplacingRowsOnFailedRead",
        "testHistoryPageFailureKeepsContextAndSuccessfulRetryClearsItsNotice",
        "testHistoryRecoveryPreservesIndependentConflictNotice",
        "testHistoryRecoveryDoesNotClearOutstandingLibraryFailure",
        "testRestoreAppendsHistoryAndReopensWithoutCurrentAnalysis",
        "testRestoreCannotDiscardDirtyOrConcurrentSavedEdits",
        "testEditsDuringRestorationRemainDirtyAndCanBeSaved",
        "testHistoryIsBoundedAndClearedAcrossDrafts",
        "testUnsupportedHistoryCannotBeRestoredFromEditor",
        "testLifecycleSaveDuringHistoryReadIsDrainedWithLatestEdits",
        "testLifecycleSaveDuringRestoreUsesNewRevisionAndLatestEdits",
    ),
    "PlannerUITests.ComponentComparisonModelTests": (
        "testExplicitSelectionKeepsTwoToFourInOrderAndLimitRecoveryDoesNotReplaceAnyRecord",
        "testDuplicateSelectionIsIdempotentButChangedRecordCannotClaimTheHeldIdentity",
        "testCrossKindReuseOfOneItemVersionCannotBecomeASecondMemberOfTheSameCatalog",
        "testConflictingCatalogBytesOrCaptureCannotReplaceAnImmutableCatalogRevision",
        "testDifferentExactVersionsAndCatalogRevisionsRemainSeparateSelections",
        "testUnicodeEquivalentVersionSpellingsStayByteDistinctWithoutLosingTheirDisplay",
        "testExactDecimalZeroAndFalseRemainRecordedInsteadOfMissingOrRounded",
        "testMissingExplicitUnknownEmptyAndSuppliedDeclarationsHaveDifferentStates",
        "testNotApplicableRequiresAnAbsentKindDefinitionAndNeverAnAbsentOptionalValue",
        "testFourUnitAndConditionTuplesAreRetainedWithoutConversionRankingOrTransfer",
        "testWholeEvidenceLicenseAndTopLevelConditionsRemainInspectableWithoutAConfidenceUpgrade",
        "testEmptyAndUnknownCollectionsDoNotTurnIntoSupportOrNotApplicable",
        "testDifferenceFilteringNeverDropsHeldRecordsAndPreferencesSurviveAddFailureRemoveAndClear",
        "testSourceFailurePreservesExactSelectionAndInspectionUntilAnExplicitRecovery",
        "testInspectionReplacementAndRemovalRetireOnlyTheirCapturedIdentity",
        "testInvalidCatalogPinsAndInvalidItemsCannotEnterOrReplaceTheComparison",
        "testCompleteLiteralDisplayKeepsTypesLongConditionsAndEscapesInvisibleFormatting",
        "testIndependentSessionsDoNotRestoreAnUnqualifiedImplicitSelection",
    ),
})

# Accepted main #181 contributes two asynchronous-open recovery cases. Keep the
# original 41-case donor profile bound to its own source; the current receiving
# composition must execute every retained method plus both accepted additions.
PROFILES["component-comparison-current-main-ui"] = (43, {
    **PROFILES["component-comparison-main-ui"][1],
    "PlannerUITests.DraftLibraryModelTests": (
        *PROFILES["component-comparison-main-ui"][1]["PlannerUITests.DraftLibraryModelTests"],
        "testEditsDuringOpenKeepOriginalDraftAndUnsavedInput",
        "testLifecycleSaveDuringOpenPersistsLatestEditsToOriginalDraft",
    ),
})

# The sheet binding correction adds one actual presentation-boundary case.
# Preserve the 43-case receiving inventory; only the complete 44-case result
# can qualify this later source, including a stale callback on a reopened item.
PROFILES["component-comparison-inspection-ui"] = (44, {
    **PROFILES["component-comparison-current-main-ui"][1],
    "PlannerUITests.ComponentComparisonModelTests": (
        *PROFILES["component-comparison-current-main-ui"][1]["PlannerUITests.ComponentComparisonModelTests"],
        "testCapturedInspectionBindingRejectsStaleDismissalAndReplacement",
    ),
})

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
