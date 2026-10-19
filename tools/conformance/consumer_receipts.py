#!/usr/bin/env python3
"""Qualify complete named XCTest and per-vector observations, never a printed total alone.

This checks supplied execution evidence; it cannot authenticate that a caller
actually ran a command. The retained workflow/command and immutable source
identity supply that separate provenance. Synthetic guard tests are not runs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import stat
import tempfile

from swift_mutations import suite_results, test_identity


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
LOCK = json.loads((HERE / 'cross-client-lock.json').read_text())
WIRE_TESTS = {
    'BuildSnapshot': 'CrossClientTests.testBuildGoldenPayloadsRejectUnsupportedVersionsAndPreserveLocksAndRelationships',
    'CatalogItem': 'CrossClientTests.testCatalogGoldenPayloadsPreserveFactsWithoutInventingPlacement',
    'Selection': 'CrossClientTests.testSelectionGoldenPayloadsPreserveKindsRolesAndExactComponentPins',
    'EvaluationReport': 'CrossClientTests.testReportGoldenPayloadsPreserveUnknownsAndProducerOutcomes',
}
MIGRATION_TESTS = {
    'migration': 'MigrationFixtureTests.testHistoricalFixturesMigrateAndReopenWithoutRewritingPayloads',
    'rollback-retry': 'MigrationFixtureTests.testInterruptedFixtureMigrationsRollBackEveryStepBeforeRecovery',
    'unsupported-retain': 'MigrationFixtureTests.testFutureStorageVersionsAreRejectedWithoutResetAndOriginalBackupReopens',
    'history-restore': 'MigrationFixtureTests.testRestorationAfterMigrationAppendsHistoryAndRejectsStaleRevision',
}
EXISTING_STORAGE_TESTS = {
    'DraftStoreTests.' + name for name in (
        'testEmptyDraftSurvivesRestartWithoutInventedContractFields', 'testExactBytesAndLocksSurviveReopen',
        'testCASRejectsStaleWritesAcrossConnections', 'testCreateNeverOverwritesExistingID',
        'testRestoreAppendsHistoryAndRejectsStaleUndo', 'testDuplicateCreatesIndependentIdentityAndDeleteIsScoped',
        'testRestoreRejectsFutureHistoryWithoutChangingReadableDrafts',
        'testRenameCreatesRevisionAndStaleDeleteFails', 'testDeletedIDCannotBeReusedByDelayedCreateOrWrite',
        'testFailedDeleteDoesNotRetireIdentity', 'testVersionTwoMigratesWithoutChangingExistingHistory',
        'testInvalidPayloadsAndOversizeAreRejectedWithoutChangingDraft', 'testInvalidTitlesDoNotTruncateOrWrite',
        'testFailureAfterHistoryWriteRollsBackAndCanRetry', 'testFailureBeforeCommitRollsBackDelete',
        'testLegacyMigrationPreservesHistoryAndIsIdempotent', 'testInterruptedMigrationRollsBackSchemaThenRecovers',
        'testUnknownSchemaNeverResetsDatabase', 'testCorruptDatabaseNeverResetsFile',
        'testUnknownWALSchemaPreservesDatabaseBytesAndJournalMode',
        'testUnknownSchemaInOrphanedWALIsRejectedWithoutCheckpoint',
        'testSupportedWALSchemaMigratesAndRemainsWritable',
        'testSupportedHotJournalRecoversAndRemainsWritable',
        'testUnknownSchemaAfterHotJournalRecoveryRejectsRecoveredVersion',
        'testLargeLibraryCorruptRowIsolationAndPagination', 'testMalformedCurrentRowIsNotOverwritten',
        'testMissingHistoryIsDisclosedNotSilentlyDropped', 'testSeparateDatabasesDoNotShareIdentity',
        'testActualSQLiteFullRollsBackThenUnconstrainedReopenRecovers',
        'testCorruptTextAndRestorationTypesAreDisclosed', 'testDatabaseDiagnosticsDoNotContainPayloadOrPath',
    )
}


PENDING_WRITE_TESTS = {
    'PendingBuildWriteStoreTests.' + name for name in (
        'testIntentSurvivesReopenWithExactBodyAndPrecondition',
        'testCallerAndReturnedDataCannotMutateIntent',
        'testExactUTF8ValueEqualityAndSQLiteIdentity',
        'testExactUTF8PartitionsDoNotShareReadsOrCallbacks',
        'testIdenticalEnqueueAtCapacityReturnsExistingRecord',
        'testChangedDuplicateIntentIsRejectedWithoutAnyFileChange',
        'testReusedKeyOrOperationAcrossPartitionRejectsWithoutDisclosure',
        'testInvalidIntentAndLimitBounds',
        'testBodyAndAggregateLimitsRetainConfirmedRecords',
        'testOpeningParallelHandleDoesNotInvalidateLiveAttempt',
        'testParallelActivationAtomicallyInvalidatesOldSessionAndCallback',
        'testSwitchAwayAndBackCannotReviveOldToken',
        'testReopenRecoversCommittedAttemptAsUncertainWithoutResend',
        'testForeignStoreCannotUseSessionOrAttempt',
        'testSameBuildWaitsForConfirmationWhileOtherBuildCanProceed',
        'testConflictInvalidAndUncertainRetainImmutableIntentAndBlockFollowers',
        'testDuplicateCompletionAndDuplicateAttemptDoNotWrite',
        'testFailedEnqueueCommitRollsBackEverything',
        'testFailedAttemptCommitLeavesPendingIntentUnchanged',
        'testFailedActivationCommitPreservesGenerationAndAttempt',
        'testFailedOutcomeCommitPreservesAttempt',
        'testFailedDeactivationCommitRetainsLiveSession',
        'testActualSQLiteFullRetainsQueueThenUnconstrainedReopenRecovers',
        'testUnsupportedQueueWALRetainsDatabaseAndWALBytes',
        'testFutureVersionOnlyInOrphanedWALIsRejected',
        'testForeignApplicationInOrphanedWALKeepsOriginalBytes',
        'testSupportedWALQueueRemainsReadableAndWritable',
        'testSupportedHotRollbackJournalRecoversBeforeQueueRead',
        'testRollbackRestoresCommittedFutureVersionBeforeRejection',
        'testDraftAndForeignDatabaseAreNeverAdopted',
        'testCorruptDatabaseIsRetainedWithoutSensitiveDiagnostics',
        'testCorruptPredecessorCannotBeSkippedForDispatch',
        'testMalformedSessionOrAttemptMetadataBlocksAllWrites',
        'testCapacityAcrossPartitionsIsGlobalAndNeverEvicts',
        'testConcurrentEnqueueAndActivationHaveOneConsistentCommitOrder',
    )
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate observation property')
        result[key] = value
    return result


def fixture(kind):
    entry = LOCK['wireFixture' if kind == 'wire' else 'migrationFixture']
    data = (ROOT / entry['path']).read_bytes()
    if digest(data) != entry['sha256']:
        raise ValueError('Pinned consumer fixture bytes differ')
    return json.loads(data, object_pairs_hook=unique_object), entry


def expected_wire(corpus):
    if corpus['bundleVersion'] != 'apple-cross-client-1' or corpus['contractVersion'] != '1.0.0':
        raise ValueError('Unsupported wire fixture version')
    result = {}
    for case in corpus['cases']:
        if case['id'] in result or type(case['valid']) is not bool:
            raise ValueError('Duplicate or malformed wire case')
        if digest(case['payloadJSON'].encode('utf-8')) != case['payloadSHA256']:
            raise ValueError('Wire payload bytes differ')
        result[case['id']] = (WIRE_TESTS[case['contract']], dict(
            bundleVersion=corpus['bundleVersion'], id=case['id'], accepted=case['valid'],
            preserved=True if case['valid'] else None))
    if len(result) != 223:
        raise ValueError('Expected all 223 wire cases')
    return result


def expected_migrations(corpus):
    if corpus['fixtureVersion'] != 'apple-local-migrations-1' or corpus['unsupportedStorageVersions'] != [-1, 4, 99]:
        raise ValueError('Unsupported local migration fixture version')
    if corpus['canonicalBuildSHA256'] != LOCK['inputs']['build']['sha256']:
        raise ValueError('Migration canonical input pin differs')
    canonical = [record['payloadJSON'] for case in corpus['cases'] if case['id'] == 'v1-canonical-snapshot'
                 for record in case['records']]
    if len(canonical) != 1 or digest(canonical[0].encode('utf-8')) != corpus['canonicalBuildSHA256']:
        raise ValueError('Migration canonical payload bytes differ')
    result = {}

    def add(phase, name, fields):
        key = phase + '/' + name
        if key in result:
            raise ValueError('Duplicate migration case')
        result[key] = (MIGRATION_TESTS[phase], dict(fixtureVersion=corpus['fixtureVersion'], id=name,
                                                  phase=phase, observed={field: True for field in fields}))

    if len(corpus['cases']) != 6 or len({case['id'] for case in corpus['cases']}) != 6:
        raise ValueError('Expected six distinct historical database descriptions')
    for case in corpus['cases']:
        add('migration', case['id'], ['originalRecordsPreserved', 'reopenedRecordsPreserved', 'expectedStorageVersion'])
        for step in range(1, 4 - case['storageVersion']):
            add('rollback-retry', case['id'] + '/step-' + str(step),
                ['originalDatabaseBytesPreserved', 'originalStorageVersion', 'recoveredRecordsPreserved'])
        if len(case['records']) > 1:
            add('history-restore', case['id'], ['originalPayloadBytesPreserved', 'newRevisionAppended',
                                              'originalHistoryPreservedAfterStaleRejection'])
    for version in corpus['unsupportedStorageVersions']:
        add('unsupported-retain', 'storage-version-' + str(version),
            ['originalDatabaseBytesPreserved', 'separateOriginalBackupReopened'])
    if len(result) != 20:
        raise ValueError('Expected all 20 migration observations')
    return result


def strictly_equal(actual, expected):
    """JSON true is not the integer 1, and every observation field is required."""
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, dict):
        return actual.keys() == expected.keys() and all(strictly_equal(actual[k], v) for k, v in expected.items())
    return actual == expected


def qualify(kind, returncode, output, *, allow_bare_linux=False):
    corpus, pin = fixture(kind)
    wire = kind == 'wire'
    module = 'PlannerConformanceTests' if wire else 'PlannerDataTests'
    required = set(WIRE_TESTS.values()) if wire else (
        EXISTING_STORAGE_TESTS | PENDING_WRITE_TESTS | set(MIGRATION_TESTS.values()))
    result = suite_results(output, 'All tests', 'passed', module=module, require_module=not allow_bare_linux)
    if returncode != 0 or result is None:
        raise ValueError('A successful complete XCTest session with explicit module identity is required')
    tests, failures, unexpected, _ = result
    if set(tests) != required or failures or unexpected or any(value != 'passed' for value in tests.values()):
        raise ValueError('Every exact required XCTest method must run and pass without skips')
    expected = expected_wire(corpus) if wire else expected_migrations(corpus)
    marker = 'APPLE_WIRE_CASE ' if wire else 'APPLE_MIGRATION_CASE '
    seen = {}
    active = None
    for line in output.splitlines():
        start = re.fullmatch(r"Test Case '([^']+)' started(?:\.| at .+)", line)
        finish = re.fullmatch(r"Test Case '([^']+)' (?:passed|failed|skipped) \([0-9.]+ seconds\)\.?", line)
        if start:
            if active is not None:
                raise ValueError('Interleaved test observations cannot supply a sequential receipt')
            active = test_identity(start[1], module, not allow_bare_linux)
        elif finish:
            if active != test_identity(finish[1], module, not allow_bare_linux):
                raise ValueError('Observation test scope differs')
            active = None
        elif line.startswith(marker):
            observation = json.loads(line[len(marker):], object_pairs_hook=unique_object)
            if not isinstance(observation, dict) or not isinstance(observation.get('id'), str):
                raise ValueError('Malformed consumer observation')
            key = observation['id'] if wire else str(observation.get('phase')) + '/' + observation['id']
            if key not in expected or key in seen:
                raise ValueError('Unknown or duplicate consumer observation')
            method, wanted = expected[key]
            if active != method or not strictly_equal(observation, wanted):
                raise ValueError('Consumer observation differs from its case or actual test scope: ' + key)
            seen[key] = observation
        elif line.startswith(marker.strip()):
            raise ValueError('Malformed consumer observation framing')
    if set(seen) != set(expected):
        raise ValueError('Missing consumer case observations')
    return dict(kind=kind, fixtureVersion=corpus['bundleVersion' if wire else 'fixtureVersion'],
                fixtureSHA256=pin['sha256'], logSHA256=digest(output.encode('utf-8')),
                xctestModule=module, moduleIdentity='bare-linux-compatible' if allow_bare_linux else 'explicit',
                methods=sorted(tests), observations=[seen[key] for key in sorted(seen)],
                limitations=['Receipt qualification is not command/source authentication or physical-device/release evidence.'])


def prepare_output(output, log):
    output = output.parent.resolve(strict=True) / output.name
    if output.is_relative_to(ROOT.resolve()) or output == log.resolve():
        raise ValueError('Receipt output must be outside source and must not overwrite its input log')
    try:
        existing = output.lstat()
    except FileNotFoundError:
        return output
    if not stat.S_ISREG(existing.st_mode) or existing.st_nlink != 1:
        raise ValueError('Receipt output must be an unshared regular file')
    output.unlink()  # No stale success survives a later failed qualification.
    return output


def publish(output, result):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=output.parent,
                                         prefix='.consumer-', suffix='.tmp', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(json.dumps(result, sort_keys=True, indent=2) + '\n')
        temporary.replace(output)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('kind', choices=['wire', 'migration'])
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--exit-code', type=int, required=True, help='Actual retained command status; not inferred from text')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--allow-bare-linux', action='store_true',
                        help='Explicit local Linux-only compatibility; never establishes an Apple module identity')
    args = parser.parse_args()
    try:
        output = prepare_output(args.output, args.log)
        result = qualify(args.kind, args.exit_code, args.log.read_text(encoding='utf-8'),
                         allow_bare_linux=args.allow_bare_linux)
        publish(output, result)
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(1, f'Consumer receipt rejected: {error}\n')
    print(f"PASS {len(result['methods'])} exact XCTest methods and {len(result['observations'])} {args.kind} observations; "
          f"module identity {result['moduleIdentity']}")


if __name__ == '__main__':
    main()
