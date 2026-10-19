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

# Accepted placement conformance adds four methods to the complete Graph/editor
# receiver. Preserve the 71-case profile and every earlier source receipt.
PROFILES["placement-graph-resource-quality-catalog-editor-transfer"] = (75, {
    **PROFILES["graph-resource-quality-catalog-editor-transfer"][1],
    "PlannerTransferTests.PlacementRelationshipTests": (
        "testSharedPlacementVectorsPreserveTransportAndRejectUnsupportedFields",
        "testMixedAccessPathsRolesAndDirectedLinksAreNotCollapsed",
        "testMemoryFactsCountsAndContextQuantitiesRemainSeparateAndAbsent",
        "testRejectedPlacementAndVersionInputsPreserveThePriorSnapshotAndRecovery",
    ),
})

# Accepted synthetic-fixture admission contributes eight actual Apple-lane
# methods. A skipped hash-dependent method cannot qualify this receiving source.
PROFILES["fixture-placement-graph-resource-quality-catalog-editor-transfer"] = (83, {
    **PROFILES["placement-graph-resource-quality-catalog-editor-transfer"][1],
    "PlannerTransferTests.SyntheticFixtureAdmissionTests": (
        "testCanonicalFixtureBytesMatchFrozenInventory",
        "testCanonicalArtifactsKeepShapePinsAndSyntheticLabels",
        "testMalformedFullFixturesFailTheirExistingBoundariesAndOriginalsRemainValid",
        "testProductionRejectsFullCanonicalPairBeforeAnyDownload",
        "testProductionReadCannotPromotePersistedPreviewAndPreviewStillReopens",
        "testChangedPriceBytesDoNotReplacePreviewAndExactRetryRecovers",
        "testCancellationDuringFullPairDownloadPreservesPreviewAndRetryRecovers",
        "testSyntheticResponseCannotEnterLiveEnvironmentOrCreatePreviewEndpoint",
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

# The selected-snapshot cost context adds 22 UI cases. Pin all 133 exact
# class-qualified identities, including earlier cases previously guarded only
# by the total. Historical profiles retain their own source and execution scope.
PROFILES["comparison-catalog-source-privacy-cost-ui"] = (133, {
    **PROFILES["comparison-catalog-source-privacy-ui"][1],
    "PlannerUITests.CostCoveragePresentationTests": (
        "testRemovingMostExpensiveRateShowsPartialAndNeverWithinBudget",
        "testAbsentEstimateAndAbsentAmountNeverInventZero",
        "testLiteralZeroKeepsItsCoverageAndRateConditions",
        "testContradictoryCompleteCoverageRemainsVisibleAndCannotPass",
        "testOtherOrInvalidVisibleRevisionSuppressesReceivedAmountAndDetails",
        "testCurrenciesArePreservedWithoutConversionOrAggregation",
        "testExactAmountsRetainTrailingZerosAndBeyondBinaryPrecisionBudgetBoundary",
        "testExpiredUnverifiedAndNonMonthlyEstimatesKeepBudgetUnknown",
        "testNoBudgetDoesNotCreateAComparison",
        "testMissingCostDetailsKeepOriginalOrderDuplicatesAndEmptyEntries",
    ),
    "PlannerUITests.DraftLibraryModelTests": (
        *PROFILES["comparison-catalog-source-privacy-ui"][1]["PlannerUITests.DraftLibraryModelTests"],
        "testCreateSaveReopenDuplicateAndDelete",
        "testConflictPreservesUnsavedInput",
        "testUnknownEditorPayloadIsPreserved",
        "testUnknownPayloadFieldsAreNotSilentlyDiscarded",
        "testInvalidTitleRetainsEditsAndDoesNotAcknowledgeSave",
        "testEditsDuringOpenKeepOriginalDraftAndUnsavedInput",
        "testLifecycleSaveDuringOpenPersistsLatestEditsToOriginalDraft",
        "testEditsArrivingDuringSaveRemainDirty",
        "testRefreshFailureDoesNotRevokeDurableAcknowledgement",
        "testDirtyNavigationGuardsAndSelectedDeletion",
        "testEditorBindingsCannotChangeDuringDestructiveDelete",
        "testLibraryKeepsOnlyOneBoundedPage",
        "testRestoreAppendsHistoryAndReopensWithoutCurrentAnalysis",
        "testRestoreCannotDiscardDirtyOrConcurrentSavedEdits",
        "testEditsDuringRestorationRemainDirtyAndCanBeSaved",
        "testHistoryIsBoundedAndClearedAcrossDrafts",
        "testUnsupportedHistoryCannotBeRestoredFromEditor",
        "testLifecycleSaveDuringHistoryReadIsDrainedWithLatestEdits",
        "testLifecycleSaveDuringRestoreUsesNewRevisionAndLatestEdits",
    ),
    "PlannerUITests.EditorAutosaveTests": (
        "testDebounceSavesOnlyLatestInputAndReopensAcknowledgedRevision",
        "testDiscardDecisionFreezesCancelledTimerAndLifecycleSaveUntilConfirmed",
        "testCancellingDiscardDecisionRestartsProductionSavePathForLatestInput",
        "testDialogBindingDismissalBeforeDiscardActionCannotRearmAWrite",
        "testQueuedReadsCannotEnterStorageOrBlockDiscardDecision",
        "testCancelledDraftTimerCannotSaveAnotherDraft",
        "testAutosaveDuringSuspendedWriteDrainsLatestInput",
        "testInputReturningToOldBaselineDuringWriteIsAutosavedAfterAcknowledgement",
        "testDelayedOpenPreservesAndAutosavesNewInputInOriginalDraft",
        "testRestorationPreservesRevertedLateInputAndAutosavesIt",
        "testFailedAutosaveRetainsDirtyInputAndCanRetryExplicitly",
        "testUndoAndRedoAppendRevisionsAndNewEditClearsRedo",
        "testUndoAfterNewerEditAndRestorationRetainsEveryDurableRevision",
    ),
    "PlannerUITests.EditorUndoHistoryTests": (
        "testBothHistoryDirectionsRemainBounded",
        "testByteLimitAndOversizedCurrentTextDoNotSilentlyDiscardInput",
    ),
    "PlannerUITests.ImportedBuildCostContextTests": (
        "testExactBudgetDigitsCurrencyAndSnapshotBytesArePreserved",
        "testAbsentBudgetIsDistinctFromAnExactZeroBudget",
        "testMissingAndInvalidRevisionDoNotReceiveADefaultOrTruncatedIdentity",
        "testLargestRepresentableRevisionIsExactAndOverflowIsUnavailable",
        "testValidFrozenSnapshotWithWideRevisionRemainsReadableButHasNoCostContext",
        "testIntegralDecimalRevisionAliasesKeepTheirMathematicalIdentity",
        "testMalformedPresentBudgetIsUnavailableInsteadOfMissingOrZero",
        "testMissingOrInvalidCurrencyCannotBeInferredEvenWithoutABudget",
        "testMissingObjectivesAndUnreadableIdentityHaveExplicitUnavailableContexts",
        "testLocalLabelRevisionDoesNotReplacePinnedWireRevisionOrBudget",
        "testChangedSelectionUsesOnlyItsOwnWireIdentityBudgetAndCurrency",
        "testReimportAndDuplicateUseFreshForkIdentityAndKeepCostUnavailable",
    ),
    "PlannerUITests.ImportedBuildLibraryTests": (
        *PROFILES["comparison-catalog-source-privacy-ui"][1]["PlannerUITests.ImportedBuildLibraryTests"],
        "testPreviewAndCancelNeverWriteStorage",
        "testConfirmedForksNeverReuseSourceOrLocalIdentity",
        "testSyntheticLabelSurvivesPersistenceAndExportEnvelope",
        "testExportRequiresAliasAndDoesNotExposeLocalOwner",
        "testInvalidAndOversizedFilesCannotCreateRows",
        "testValidLocalFileCanBePreviewedWithoutImport",
        "testUnsupportedStoredFormatIsPreserved",
    ),
    "PlannerUITests.LocalLibraryStartupTests": (
        "testMainActorProcessesEditorActionWhileStartupOpenerIsBlocked",
        "testCancelledSceneDoesNotPublishAndCanRetry",
        "testCancelledStartupCannotReplaceNewAttempt",
        "testSupersededStartupCannotReplaceNewAttemptEvenWithoutCancellation",
        "testFailureIsExplicitAndLaterAppearanceCanRetryWithoutReopeningReadyStores",
        "testFactoryPropagatesDirectoryPreparationError",
    ),
    "PlannerUITests.LocalLibraryStoresTests": (
        "testCorruptImportedLibraryDoesNotHideSavedNotesOrHistory",
        "testCorruptNotesDoNotHideExistingImportedLibrary",
    ),
})

# Fixed complete inventories for the newly selected retained-build composition.
# Earlier profiles retain their original source scope and method identities.
PROFILES['integrated-retained-transfer'] = (181, {
    'PlannerTransferTests.DependencyParticipantTests': (
        'testActualFrozenModeOnlyEdgeReachesBothEndpointsAndKeepsGraphIdentity',
        'testEachFrozenActivationHasItsOwnExplicitAdapterBehavior',
        'testGraphDuplicatesCyclesAndRelationshipLabelsRemainSourceEvidence',
        'testValidatedBuildContextRetainsDisabledAndRemovedSelectionIdentities',
        'testMalformedBuildAndGraphStillRejectBeforeAnyAdapterProjection',
    ),
    'PlannerTransferTests.BuildComparisonExactTextTests': (
        'testDistinctUnicodeVersionPinsAppearAsARevisionDifference',
        'testDistinctUnicodeVersionPinsCannotClaimOneImmutableRevision',
        'testDistinctUnicodeScopesRemainVisibleInsideAnArray',
        'testDistinctUnicodePrivateKeysConflictWithoutLeakingIntoAnotherRevision',
        'testEquivalentEscapesNumbersWhitespaceAndObjectOrderPreserveRevisionIdentity',
    ),
    'PlannerTransferTests.BuildComparisonTests': (
        'testSameSnapshotHasNoConfigurationDifferences',
        'testReorderedSelectionsAndLinksRemainEquivalentAtSameIdentity',
        'testExactSettingAndLockChangesArePinnedToEachRevision',
        'testFieldLikeSelectionIDsKeepPublicSettingChanges',
        'testAddedAndRemovedFieldLikeSelectionIDsRetainPublicFields',
        'testFieldLikeLinkIDsKeepChangesAdditionsAndRemovals',
        'testFieldLikeIDsDoNotDisableNestedPrivateFieldRedaction',
        'testAbsentWorkloadIsNeverRenderedAsZero',
        'testAddedAndRemovedSelectionsKeepRolesVersionsAndDisabledState',
        'testDecimalStringsAndRelationshipChangesStayExact',
        'testAmbiguousSelectionAndLinkIDsRejectWithoutPayloadDiagnostic',
        'testConflictingContentsAtOneRevisionAreNotAcceptedAsARevisionChange',
        'testPrivateInfrastructureValuesAreNotRetainedInResult',
        'testForeignMeasurementsInExtensionsAreNeverTransplantedOrRanked',
        'testForkMetadataNeverChangesConfigurationOrConfersReadiness',
        'testLargeComparisonFailsExplicitlyInsteadOfTruncatingChanges',
    ),
    'PlannerTransferTests.BuildTransferTests': (
        'testCanonicalConformanceCorpus',
        'testCanonicalFixtureAndExactLockPreservation',
        'testEmptyDraftRejectedWithoutMutation',
        'testLocalSnapshotEncodingPreservesPrivateFieldsAndReopensExactly',
        'testSnapshotEncodingRejectsExpansionPastItsDecodeLimit',
        'testAll29SelectionKindsUseTheirConditionalSettings',
        'testMaliciousBoundariesAndRedactedErrors',
        'testUnknownFieldsDecimalTypesDatesAndEnums',
        'testPrivateProjectionAndSecretReferences',
        'testResourceAndPrivateInfrastructureLimits',
        'testEnvelopeAndUntrustedOwner',
        'testExponentNumbersRemainAcceptedAfterEncoding',
        'testExponentRevisionSurvivesSnapshotExportAndPreview',
    ),
    'PlannerTransferTests.CatalogItemDetailsTests': (
        'testEveryCanonicalKindUsesItsExactSchemaFieldsAndPreservesItemIdentity',
        'testMissingFalseZeroAndEmptyTextRemainDifferent',
        'testUnknownAndIncompleteCollectionsRetainTheirExactRecordedContents',
        'testProvenanceRetainsContradictionsAndRawStatusWithoutCreatingAnEvidenceGrade',
        'testAbsentOptionalDeclarationsDoNotAcquireDefaultsOrAuthority',
        'testDistinctVersionsAndExactDecimalValuesDoNotCollapseOrChangeDuringProjection',
    ),
    'PlannerTransferTests.CatalogItemTests': (
        'testAll29CanonicalKindsDecodeWithoutLosingFieldsOrIdentity',
        'testSharedCanonicalCatalogConformanceVectors',
        'testDuplicateKeysAndEscapedAliasesAreRejectedBeforeDecoding',
        'testCatalogBoundaryKeepsExistingByteDepthAndComplexityLimits',
        'testEncodingRejectsExpansionPastTheDecodeByteLimit',
        'testUnknownBillingAndOptionalFactsStayUninferred',
    ),
    'PlannerTransferTests.CatalogSnapshotTests': (
        'testWholeCanonicalCatalogPreservesMetadataOrderAndEveryKind',
        'testSharedCanonicalEnvelopeVectorsAndAllOrNothingAdmission',
        'testDuplicateEnvelopeAndNestedEscapedKeysAreRejected',
        'testWholeDocumentLimitsCannotBeEvadedByIndividuallyAdmissibleItems',
        'testDuplicateIdentityIsPreservedForTheReceivingGraphPolicy',
        'testEncodingRejectsExpansionWithoutChangingTheSnapshot',
    ),
    'PlannerTransferTests.CostEstimateRecordTests': (
        'testCanonicalRecordRetainsEveryFieldAndDecimalSpelling',
        'testSharedCanonicalCostVectorsUseActualRawNumberTokens',
        'testLongDecimalStringsStayExactWithoutNumericConversion',
        'testReportedAmountsCurrenciesCoverageAndIdentityAreNotQualified',
        'testArrayOrderDuplicateRowsAndPrivateTextArePreserved',
        'testDuplicateRootAndMoneyKeysIncludingEscapedAliasesFail',
        'testByteDepthAndAggregateLimitsApplyBeforeSchemaAdmission',
        'testMalformedAndUnsupportedInputsHavePayloadFreeErrors',
        'testNormalizedOutputRetainsValueAndTheSameByteLimit',
    ),
    'PlannerTransferTests.DependencyGraphTests': (
        'testCanonicalGraphPreservesEveryDirectedRelationshipAndLabel',
        'testSharedCanonicalDependencyGraphVectors',
        'testRepeatedIdentifiersSelfEdgesAndCyclesRemainUnmodified',
        'testDuplicateRootAndEscapedEdgeKeysAreRejected',
        'testCompleteDocumentByteDepthAndNodeLimitsPrecedeSchemaValidation',
        'testEncodedExpansionCannotReturnBytesThatCannotBeReopened',
    ),
    'PlannerTransferTests.DeploymentManifestTests': (
        'testCanonicalManifestRetainsAllReferencesAndRoundTrips',
        'testSharedReferenceVectorsRetainExplicitCanonicalAndClientBoundaries',
        'testReaderPreservesEveryDeclaredStatusWithoutApprovalInference',
        'testRawDuplicateMembersAndEscapedAliasesRejectBeforeSchema',
        'testByteDepthNodeAndNumericLimitsApplyToTheWholeManifest',
        'testUnsupportedVersionsAndMissingEvidenceReferencesCannotCreateDefaults',
        'testLateInvalidApprovalIsRejectedWithPrivateInputsUnchangedAndRetryable',
        'testProposedLocalPairPreservesLocksMonitoringPrivateFieldsAndDeclarations',
        'testProposedHelperDoesNotDowngradeOtherDeclaredStatusesAndCanRetry',
        'testForeignAndStaleBuildBindingsRejectWithoutChangingEitherArtifact',
        'testMissingDisabledWrongKindAndEveryDuplicateTargetIdentityReject',
        'testNonprefixedFrozenSelectionIdentityIsAcceptedByExactBinding',
        'testOptionalTiersAndMonitoringOmissionRemainExplicitWithoutNewSelections',
        'testIncompatibleSyntheticTierInputsAndUnverifiedReferencesAreNotEvaluated',
        'testAllReportedApprovalsCannotPromoteAProposedPlan',
        'testLocalEncodingExpansionReturnsNoPairAndLeavesInputsRecoverable',
    ),
    'PlannerTransferTests.DurableTransferTests': (
        'testEmptyAutosaveSurvivesRejectedExportAndStoreReopen',
    ),
    'PlannerTransferTests.HistoricalCostComparisonTests': (
        'testSameHistoricalRecordRetainsBothInputsWithoutInventingQualification',
        'testDifferentPricebooksCurrenciesAndPeriodsRemainSeparate',
        'testAbsentLinesStayAbsentAndPartialZeroIsStillUnqualified',
        'testLineChangesRetainUsageRateMethodConfidenceAndAssumptions',
        'testLineOrderDoesNotManufactureChangesAndIDChangeIsRemovalPlusAddition',
        'testWrongBuildAndObsoleteRevisionCannotBindToVisibleSnapshot',
        'testPricebookMustMatchItsOwnSavedBuildLock',
        'testUnknownPricedAndUnpricedSelectionsRejectWithoutChangingDecoder',
        'testDuplicateLineIDsFailComparisonAdmissionRatherThanOverwrite',
        'testDuplicateBuildSelectionIDsFailComparisonAdmission',
        'testOneEstimateIdentityCannotHideChangedHistoricalContents',
        'testOneBuildRevisionCannotCarryConflictingSavedConfiguration',
        'testReportedCompleteWithUnpricedSelectionsRemainsExplicitlyUnqualified',
        'testEveryNestedCurrencyMismatchRemainsVisibleOnTheCorrectSide',
        'testExactUnicodeAndLongDecimalTextSurviveChangesAndLocalSerialization',
        'testDifferentHistoricalBuildsKeepTheirOwnSelectionBindings',
    ),
    'PlannerTransferTests.HistoricalQualityComparisonTests': (
        'testCanonicalScenarioPreservesWholeInputsAndIndependentSerialization',
        'testWrongBuildOrRevisionRejectsAndValidPairRecovers',
        'testDuplicateSuiteAndUnrelatedSelectionIDsRejectInsteadOfReplacingRows',
        'testMissingAndWrongKindEvaluationSuiteReferencesReject',
        'testDuplicateMetricNamesRejectEvenWhenTheirUnitsDiffer',
        'testCanonicallyEquivalentMetricNamesRemainTwoExactDisplayRows',
        'testUnchangedRunKeepsEveryMeasurementAndReportedOnlyQualification',
        'testChangedMeasurementsPreserveContradictoryReportedNumbersAndLabels',
        'testAddedAndRemovedMeasurementsStayAbsentInsteadOfBecomingZero',
        'testMetricJoinOrderIsStableWhileOriginalRowOrderRemainsIntact',
        'testChangedRecordCannotReuseOneRunIdentityAndRecoveryKeepsInputs',
        'testConflictingImmutableBuildRevisionRejectsThenNewRevisionRecovers',
        'testReorderedBuildRecordsPreserveIdentityButAmbiguousLinksReject',
        'testEveryRecordedFieldChangeRetainsItsOwnBindingAndConditions',
        'testMissingEmptyAndPresentUnitsRemainDistinctOnEachSide',
        'testOpaqueUnicodeVersionsAndUnitsNeverBorrowCanonicalEquality',
        'testIncompleteAndDisabledSuiteLabelsRemainPerSideWithoutNewVerdicts',
        'testSupportedNumericValuesStayExactWithoutNarrowingOrRounding',
        'testDifferentComponentTuplesAndUnmatchedMetricsNeverTransferEvidence',
        'testChronologyPrivateArtifactReferencesAndNotesRemainUnverifiedLocalValues',
    ),
    'PlannerTransferTests.NetworkArtifactRecoveryTests': (
        'testTimeoutDuringSecondArtifactPreservesStoredPairAndExplicitRetry',
        'testThrottledSecondArtifactPreservesStoredPairAndExplicitRetry',
        'testDisconnectedSecondArtifactNeverCommitsPartialData',
        'testMalformedSecondArtifactPreservesStoredPairAndExplicitRetry',
        'testValidChangedPricebookBytesCannotReplacePinnedPair',
        'testActualRequestCancellationPreservesPairAndNewerDraftRevision',
    ),
    'PlannerTransferTests.PlacementRelationshipTests': (
        'testSharedPlacementVectorsPreserveTransportAndRejectUnsupportedFields',
        'testMixedAccessPathsRolesAndDirectedLinksAreNotCollapsed',
        'testMemoryFactsCountsAndContextQuantitiesRemainSeparateAndAbsent',
        'testRejectedPlacementAndVersionInputsPreserveThePriorSnapshotAndRecovery',
    ),
    'PlannerTransferTests.QualityEvaluationRunTests': (
        'testCanonicalRecordRetainsIdentityAndEverySupportedField',
        'testSharedCanonicalQualityConformanceVectorsUseRawNumericTokens',
        'testOptionalAbsenceRemainsDistinctFromEmptyArraysAndStrings',
        'testRecordedLabelsChronologyDuplicatesAndPrivateTextAreNotReinterpreted',
        'testNumericViewsRemainExactWithoutNarrowingOrRounding',
        'testDuplicateRootAndMeasurementKeysIncludingEscapedAliasesFail',
        'testByteDepthAndAggregateNodeLimitsApplyBeforeSchemaAcceptance',
        'testUnsupportedAndMalformedInputReturnsPayloadFreeErrors',
        'testNormalizedOutputCannotExceedTheDecoderLimitOrChangeTheValue',
    ),
    'PlannerTransferTests.ResourceEstimateTests': (
        'testCanonicalArtifactPreservesBuildEstimatorSelectionIdentityAndRoundTrip',
        'testSharedCanonicalResourceVectorsAndExplicitClientSubsets',
        'testDecimalSpellingAndSourceAbsenceRemainExactWithoutBinaryConversion',
        'testForeignPartialRepeatedDeclarationsStayUnevaluatedAndInOrder',
        'testDuplicateKeysEscapedAliasesAndDuplicateSelectionsAreRejected',
        'testAggregateBoundsPrecedeSchemaAdmissionAndCoverTheWholeArtifact',
        'testEncodingExpansionFailsWithoutChangingTheValidatedEstimate',
        'testLateInvalidEntriesVersionsAndSchemaAvailabilityFailWithoutPartialResults',
    ),
    'PlannerTransferTests.RulesetTests': (
        'testCompleteCanonicalRulesetPreservesMetadataEveryRuleAndRoundTrip',
        'testSharedCanonicalSyntaxVectorsRejectEveryMalformedAlternative',
        'testOneOfRequiresExactlyOneMatchAndPropagatesSchemaFailures',
        'testUnknownPolicyAndLiteralValuesRemainUnevaluatedAndUnchanged',
        'testRepeatedRuleIdentitiesAndOrderRemainAvailableForReceivingPolicy',
        'testDuplicateMetadataAndEscapedExpressionKeysAreRejected',
        'testWholeArtifactBoundsApplyAcrossIndividuallyAdmissibleRules',
        'testEncodingExpansionIsRejectedWithoutChangingTheRuleset',
    ),
    'PlannerTransferTests.SyntheticFixtureAdmissionTests': (
        'testCanonicalFixtureBytesMatchFrozenInventory',
        'testCanonicalArtifactsKeepShapePinsAndSyntheticLabels',
        'testMalformedFullFixturesFailTheirExistingBoundariesAndOriginalsRemainValid',
        'testProductionRejectsFullCanonicalPairBeforeAnyDownload',
        'testProductionReadCannotPromotePersistedPreviewAndPreviewStillReopens',
        'testChangedPriceBytesDoNotReplacePreviewAndExactRetryRecovers',
        'testCancellationDuringFullPairDownloadPreservesPreviewAndRetryRecovers',
        'testSyntheticResponseCannotEnterLiveEnvironmentOrCreatePreviewEndpoint',
    ),
    'PlannerTransferTests.T6QualityGuidanceTests': (
        'testAdmittedCompatibilityPassDoesNotSupplyQualityOrApproval',
        'testCompatibilityPassKeepsFailedThresholdAndMissingArtifactsVisible',
        'testIncompleteRunAndKnownFailureRetainBothReasons',
        'testReportedContradictionsAreNotRecalculatedOrPromoted',
        'testDisabledSelectionAndAbsentFalseZeroSettingsRemainDistinct',
        'testOptionalTiersCanBeOmittedWithoutHidingT6Guidance',
        'testAbsentT6SelectionsPromptReviewWithoutInventingRequirements',
        'testExistingAdmissionRejectsForeignBindingsAndRecoversWithoutMutation',
        'testDuplicateSelectionsRemainVisibleWithoutARecordAndAdmissionStillRejectsThem',
        'testIncompatibleCrossTierReportAndQualityRecordKeepSeparateOutcomes',
        'testChangedRevisionRejectsOldQualityAndLateCompatibilityThenRecovers',
        'testOriginalOrderPinsRolesAndGuardrailSettingsArePreserved',
        'testExactDecimalsUnicodeAndPrivateReferencesRemainOriginalLocalValues',
    ),
})

PROFILES['integrated-retained-ui'] = (192, {
    'PlannerUITests.CatalogBrowserModelTests': (
        'testBundledPreviewValidatesAllKindsAndRemainsVisiblySynthetic',
        'testConcurrentPreviewLoadsPreserveBothIssuedPageTokens',
        'testCombinedFiltersSortCountsAndDistinctVersionPinsPersistAcrossRecreation',
        'testFailedNextPageRetainsRowsCountFiltersAndCursorUntilRetrySucceeds',
        'testLateCancellationIgnoringResponseCannotReplaceNewerFiltersOrRows',
        'testChangedCatalogResetsWholePageCollectionAndRetryKeepsFilters',
        'testInvalidStoredAndEditedFiltersNeverReachSourceOrOverwriteLastValidPreferences',
        'testUnavailableFirstPageAndEmptyResultsAreDifferentStates',
    ),
    'PlannerUITests.CatalogDetailsModelTests': (
        'testBundledDetailsResolveAllExactKindsWithoutInvalidatingAnIssuedPage',
        'testBundledDetailsRejectForgedRowsAndChangedCatalogPins',
        'testFailureAndRetryKeepTheExactSelectedPin',
        'testMismatchedResolvedIdentityOrHashCannotBecomeVisible',
        'testDismissalRejectsALateCancellationIgnoringResultAndRetiredActions',
        'testSourcePaginationRetainsEveryRecordAndNeverChangesTheItemPin',
        'testLiteralDisplayEscapesInvisibleControlsAndBoundsCompleteUnicodeScalars',
        'testSheetIdentityIncludesTheCatalogReleaseAndCompleteRow',
    ),
    'PlannerUITests.CatalogSourceLinkPolicyTests': (
        'testApprovedHTTPSDestinationsPreserveTheCompleteURLAndHost',
        'testUnreviewedAndConfusableAuthoritiesCannotBecomeCandidates',
        'testMalformedAndNonHTTPSInputCannotBeRepairedIntoNavigation',
        'testTheURLByteLimitIsExactAndCannotBeConfiguredAbove4096',
        'testConfigurationRequiresExplicitBoundedASCIIDNSNames',
        'testDiagnosticDescriptionsRedactSourceAddressesAndOpeningIDs',
    ),
    'PlannerUITests.CatalogSourceReviewModelTests': (
        'testSourceReviewRequiresLoadedVisibleRecordAndExactConfirmation',
        'testDefaultPolicyAndMissingOrUnsafeSourcesNeverOfferAnOpening',
        'testSourceReviewReplacementAndClosureRetireCapturedActionsAndCallbacks',
        'testRejectedSystemHandoffRequiresFreshExplicitReviewToRetry',
        'testClosingDetailsRetiresAllNavigationAndRetainsThePinnedRecord',
        'testSourcePaginationOnlyExposesOrderedRecordsWithoutChangingConsentOrPins',
        'testStaleContradictoryProvenanceNeverBecomesVerifiedByAnAcceptedHandoff',
        'testARecreatedVersionCannotUseThePreviousDetailReviewOrHandoff',
    ),
    'PlannerUITests.ComparisonFieldTextTests': (
        'testUserTextCannotImpersonateMissingPrivateEmptyOrTypedValues',
        'testOriginalSentinelStringsRemainExplicitText',
        'testMultilineTextIsPreservedWithoutTruncation',
    ),
    'PlannerUITests.CostCoveragePresentationTests': (
        'testRemovingMostExpensiveRateShowsPartialAndNeverWithinBudget',
        'testAbsentEstimateAndAbsentAmountNeverInventZero',
        'testLiteralZeroKeepsItsCoverageAndRateConditions',
        'testContradictoryCompleteCoverageRemainsVisibleAndCannotPass',
        'testOtherOrInvalidVisibleRevisionSuppressesReceivedAmountAndDetails',
        'testCurrenciesArePreservedWithoutConversionOrAggregation',
        'testExactAmountsRetainTrailingZerosAndBeyondBinaryPrecisionBudgetBoundary',
        'testExpiredUnverifiedAndNonMonthlyEstimatesKeepBudgetUnknown',
        'testNoBudgetDoesNotCreateAComparison',
        'testMissingCostDetailsKeepOriginalOrderDuplicatesAndEmptyEntries',
    ),
    'PlannerUITests.DraftLibraryModelTests': (
        'testCreateSaveReopenDuplicateAndDelete',
        'testConflictPreservesUnsavedInput',
        'testUnknownEditorPayloadIsPreserved',
        'testUnknownPayloadFieldsAreNotSilentlyDiscarded',
        'testInvalidTitleRetainsEditsAndDoesNotAcknowledgeSave',
        'testEditsDuringOpenKeepOriginalDraftAndUnsavedInput',
        'testLifecycleSaveDuringOpenPersistsLatestEditsToOriginalDraft',
        'testEditsArrivingDuringSaveRemainDirty',
        'testRefreshFailureDoesNotRevokeDurableAcknowledgement',
        'testSuccessfulRefreshClearsLibraryFailureAndLoadsCurrentRecords',
        'testLibraryFailureAndRecoveryPreserveConflictGuidanceAndUnsavedInput',
        'testDirtyNavigationGuardsAndSelectedDeletion',
        'testEditorBindingsCannotChangeDuringDestructiveDelete',
        'testLibraryKeepsOnlyOneBoundedPage',
        'testPageRetryClearsItsFailureWithoutReplacingRowsOnFailedRead',
        'testHistoryPageFailureKeepsContextAndSuccessfulRetryClearsItsNotice',
        'testHistoryRecoveryPreservesIndependentConflictNotice',
        'testHistoryRecoveryDoesNotClearOutstandingLibraryFailure',
        'testRestoreAppendsHistoryAndReopensWithoutCurrentAnalysis',
        'testRestoreCannotDiscardDirtyOrConcurrentSavedEdits',
        'testEditsDuringRestorationRemainDirtyAndCanBeSaved',
        'testHistoryIsBoundedAndClearedAcrossDrafts',
        'testUnsupportedHistoryCannotBeRestoredFromEditor',
        'testLifecycleSaveDuringHistoryReadIsDrainedWithLatestEdits',
        'testLifecycleSaveDuringRestoreUsesNewRevisionAndLatestEdits',
    ),
    'PlannerUITests.EditorAutosaveTests': (
        'testDebounceSavesOnlyLatestInputAndReopensAcknowledgedRevision',
        'testDiscardDecisionFreezesCancelledTimerAndLifecycleSaveUntilConfirmed',
        'testCancellingDiscardDecisionRestartsProductionSavePathForLatestInput',
        'testDialogBindingDismissalBeforeDiscardActionCannotRearmAWrite',
        'testQueuedReadsCannotEnterStorageOrBlockDiscardDecision',
        'testCancelledDraftTimerCannotSaveAnotherDraft',
        'testAutosaveDuringSuspendedWriteDrainsLatestInput',
        'testInputReturningToOldBaselineDuringWriteIsAutosavedAfterAcknowledgement',
        'testDelayedOpenPreservesAndAutosavesNewInputInOriginalDraft',
        'testRestorationPreservesRevertedLateInputAndAutosavesIt',
        'testFailedAutosaveRetainsDirtyInputAndCanRetryExplicitly',
        'testUndoAndRedoAppendRevisionsAndNewEditClearsRedo',
        'testUndoAfterNewerEditAndRestorationRetainsEveryDurableRevision',
    ),
    'PlannerUITests.EditorUndoHistoryTests': (
        'testBothHistoryDirectionsRemainBounded',
        'testByteLimitAndOversizedCurrentTextDoNotSilentlyDiscardInput',
    ),
    'PlannerUITests.EditorExactTextTests': (
        'testCanonicalTitleEditPersistsExactBytesAndUndoRedoRevisions',
        'testCanonicalNotesEditPersistsExactBytesAndUndoRedoRevisions',
        'testExactRepeatedInputDoesNotCreateDirtyStateOrUndoOrRevision',
        'testOrdinaryAsciiEditRetainsTheExistingSaveAndUndoBehavior',
        'testCanonicalBindingEditSchedulesTheNormalDebouncedSave',
        'testCanonicalEditsDuringRestoreSurviveTheActorSuspension',
        'testCanonicalLateEditPreventsAnOlderOpenFromReplacingTheSelection',
    ),
    'PlannerUITests.ImportedBuildCostContextTests': (
        'testExactBudgetDigitsCurrencyAndSnapshotBytesArePreserved',
        'testAbsentBudgetIsDistinctFromAnExactZeroBudget',
        'testMissingAndInvalidRevisionDoNotReceiveADefaultOrTruncatedIdentity',
        'testLargestRepresentableRevisionIsExactAndOverflowIsUnavailable',
        'testOversizedWireRevisionRejectsBeforeCreatingCostContext',
        'testIntegralDecimalRevisionAliasesKeepTheirMathematicalIdentity',
        'testMalformedPresentBudgetIsUnavailableInsteadOfMissingOrZero',
        'testMissingOrInvalidCurrencyCannotBeInferredEvenWithoutABudget',
        'testMissingObjectivesAndUnreadableIdentityHaveExplicitUnavailableContexts',
        'testLocalLabelRevisionDoesNotReplacePinnedWireRevisionOrBudget',
        'testChangedSelectionUsesOnlyItsOwnWireIdentityBudgetAndCurrency',
        'testReimportAndDuplicateUseFreshForkIdentityAndKeepCostUnavailable',
    ),
    'PlannerUITests.ImportedBuildLibraryTests': (
        'testPreviewAndCancelNeverWriteStorage',
        'testConfirmedForksNeverReuseSourceOrLocalIdentity',
        'testSyntheticLabelSurvivesPersistenceAndExportEnvelope',
        'testExportRequiresAliasAndDoesNotExposeLocalOwner',
        'testInvalidAndOversizedFilesCannotCreateRows',
        'testValidLocalFileCanBePreviewedWithoutImport',
        'testUnsupportedStoredFormatIsPreserved',
        'testLocalRenamePreservesSnapshotAndHistoryAcrossRestart',
        'testDuplicateCreatesFreshForkAndRetainsSyntheticQualificationAndLocks',
        'testStaleRenameDuplicateAndDeleteCannotMutateNewerRevision',
        'testConfirmedDeleteTargetsCapturedEntryAndPreservesDifferentSelection',
        'testLargeLibraryRetainsCorruptWrapperAndUnrelatedMetadataAfterRenameDeleteAndRestart',
        'testEntireUnreadablePageStillReachesLaterValidBuild',
        'testMalformedQualificationCannotBeOpenedMutatedOrSilentlyDropped',
        'testPreviewPreparationLeavesMainActorResponsive',
        'testCancelledPreviewPreparationCannotPublishOrWrite',
        'testExportPreparationLeavesMainActorResponsiveAndPreservesQualification',
        'testClearedExportRejectsLateBytesAndErrorsAndRetryUsesNewAlias',
        'testInvalidatedQueuedExportNeverEntersPreparation',
        'testCancelledExportPreparationCannotPublishOrWrite',
        'testComparisonPreparationLeavesMainActorResponsiveAndPreservesInputs',
        'testNewSelectionComparisonFinishesBeforeCancelledOlderResultOrError',
        'testCancelledOlderComparisonCannotClearPendingNewerWork',
        'testReplacingBaselineRejectsLateComparisonAndRetainsNewQualification',
        'testClearedBaselineRejectsLateComparisonAndError',
        'testCancelledComparisonRejectsLateResultAndErrorWithoutClearingPin',
        'testInvalidatedQueuedComparisonNeverEntersWorker',
        'testCommittedBaselineDeletionCancelsPendingComparisonAndPreservesSelection',
        'testRejectedBaselineDeletionPreservesPinAndPendingComparison',
    ),
    'PlannerUITests.ImportedBuildT6BindingTests': (
        'testLibrarySelectionUsesCompleteSnapshotAndNoCompatibilityDefault',
        'testSameIDRevisionWithChangedLockRetiresCompatibilityAndPicker',
        'testDuplicateForkGetsNewT6IdentityWithoutInheritedReport',
        'testLocalLabelRenameKeepsExactBuildReviewIdentity',
        'testDeleteOtherPreservesReviewAndDeleteSelectedRetiresIt',
        'testFailedOpenKeepsPriorSelectedReview',
    ),
    'PlannerUITests.LocalLibraryStartupTests': (
        'testMainActorProcessesEditorActionWhileStartupOpenerIsBlocked',
        'testCancelledSceneDoesNotPublishAndCanRetry',
        'testCancelledStartupCannotReplaceNewAttempt',
        'testSupersededStartupCannotReplaceNewAttemptEvenWithoutCancellation',
        'testFailureIsExplicitAndLaterAppearanceCanRetryWithoutReopeningReadyStores',
        'testFactoryPropagatesDirectoryPreparationError',
    ),
    'PlannerUITests.LocalLibraryStoresTests': (
        'testCorruptImportedLibraryDoesNotHideSavedNotesOrHistory',
        'testCorruptNotesDoNotHideExistingImportedLibrary',
    ),
    'PlannerUITests.PlannerUIPrivacyManifestTests': (
        'testPackagedManifestDeclaresOwnAppPreferencesReason',
    ),
    'PlannerUITests.T6ReviewModelTests': (
        'testReportedCompatibilityPassDoesNotSupplyQualityOrApproval',
        'testReportedQualityFailureAndZeroAreNotErasedByCompatibility',
        'testReportedQualityPassDoesNotOverrideIncompatibleInputs',
        'testMissingCurrentCompatibilityOrWrongLocksNeverBecomesPass',
        'testProposedPairPreservesPendingApprovalsLocksMonitoringAndPrivateFields',
        'testEveryNonProposedStatusIsRetainedWithoutPreparingArtifacts',
        'testMissingRequiredManifestReferencesStayIncompleteAndKeepQuality',
        'testOptionalSelectionsAndDisabledFalseRemainExplicit',
        'testWrongKindDuplicateOrDisabledTargetCannotPreparePlan',
        'testForeignBuildAndRevisionRecordsAreNeverRewrittenForFork',
        'testStaleSuccessAfterChangedLockCannotReplaceCurrentRetry',
        'testStaleFailureCannotReplaceNewSuccess',
        'testCancellationAndDeletionRejectLateCallbacksThenAllowRecovery',
        'testCallerCancellationRejectsCompletionEvenWhenWorkerIgnoresIt',
        'testMalformedOversizedAndDuplicateKeysFailWithoutPrivateErrorTextAndRecover',
        'testFileReadIsBoundedAndRemovalReturnsToUnanswered',
        'testCancelledPickerSuccessAndFailureCannotReviveSameBuild',
        'testNewPickerSupersedesOldCallbacksAndSuccessIsSingleUse',
        'testReviewRetryAndRestoredSelectionInvalidatePendingPicker',
        'testOwnedImporterDisappearancePreservesItsExactTerminalCallback',
        'testExplicitRouteCancellationRetiresAnOwnedImporterAfterDisappearance',
        'testOrdinaryDisappearanceCancelsUnfinishedReviewAndAllowsRecovery',
    ),
    'PlannerUITests.T6PlanReportTests': (
        'testDeterministicReportPreservesAllLocksAndOriginalQualityCounts',
        'testPrivateFieldsAndReferenceAddressesAreWithheldWithoutChangingInputs',
        'testApprovalOrderDuplicatesAndDecisionsRemainReported',
        'testQuotedUTF8PreservesSpellingAndCannotInjectLinesOrHiddenHeadings',
        'testRetainedSecretMarkersFailClosedAndAValidRetryRecovers',
        'testOutputLimitAppliesAfterEscapingWithoutChangingAValidInput',
        'testOnlyProposedExactlyBoundContentCanCreateAReport',
        'testOptionalLocksOmittedTiersDisabledMonitoringAndRollbackStayExplicit',
        'testFilesSaveRequiresExactReviewedPreviewAndIsSingleUse',
        'testCurrentFailureCancellationAndPreviewDismissalRecoverWithoutPrivateMutation',
        'testRetiredFilesCallbacksCannotBorrowNewContentOrRestoredSameBuild',
        'testLateReportPreparationSuccessAndFailureCannotReplaceFreshPreview',
        'testReportPreparationErrorsLeavePrivatePairAndAllowFreshRetry',
        'testOwnedExporterDisappearancePreservesItsExactTerminalCallback',
        'testExplicitRouteCancellationRetiresAnOwnedExporterAfterDisappearance',
        'testOrdinaryDisappearanceCancelsReportPreparationAndUnsubmittedPreview',
    ),
    'PlannerUITests.ImportedBuildT6NavigationTests': (
        'testRouteRequiresAnActiveSelectedBuildAndHasOnePresentation',
        'testNavigationPopRetiresBothOwnedImportersAndLateCallbacksBeforeRecovery',
        'testActualTabWithdrawalRetiresOwnedExportButSameTabReappearancePreservesIt',
        'testOldNavigationBindingCannotWithdrawReopenedSameBuildRoute',
        'testLabelRenamePreservesRouteButSameIDRevisionWithDifferentLocksWithdrawsIt',
        'testDeletingAnotherRowKeepsOwnedRequestAndDeletingSelectedClearsIt',
        'testClosingSelectedBuildClearsOwnedExportWithoutDeletingRetainedRow',
        'testFailedStorageActionPreservesRouteUntilActualLibraryOwnerReplacement',
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
