"""Synthetic adversarial logs test qualification; these are never native receipts."""
from copy import deepcopy
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import consumer_receipts as receipts


def synthetic(kind, spelling='objc', *, storage_methods=None):
    corpus, _ = receipts.fixture(kind)
    expected = receipts.expected_wire(corpus) if kind == 'wire' else receipts.expected_migrations(corpus)
    module = 'PlannerConformanceTests' if kind == 'wire' else 'PlannerDataTests'
    methods = set(receipts.WIRE_TESTS.values()) if kind == 'wire' else (
        receipts.EXISTING_STORAGE_TESTS | receipts.PENDING_WRITE_TESTS
        | receipts.PENDING_WRITE_DISPATCH_TESTS | set(receipts.MIGRATION_TESTS.values()))
    if kind == 'migration' and storage_methods is not None:
        methods = set(storage_methods)
    marker = 'APPLE_WIRE_CASE ' if kind == 'wire' else 'APPLE_MIGRATION_CASE '
    lines = ["Test Suite 'All tests' started at SYNTHETIC"]
    for name in sorted(methods):
        cls, method = name.split('.')
        identity = f'-[{module}.{cls} {method}]' if spelling == 'objc' else (
            name if spelling == 'bare' else module + '.' + name)
        lines.append(f"Test Case '{identity}' started.")
        lines.extend(marker + json.dumps(value, sort_keys=True) for _, (owner, value) in sorted(expected.items()) if owner == name)
        lines.append(f"Test Case '{identity}' passed (0.001 seconds).")
    lines.extend(["Test Suite 'All tests' passed at SYNTHETIC",
                  f' Executed {len(methods)} tests, with 0 failures (0 unexpected) in 0.1 (0.1) seconds'])
    return '\n'.join(lines) + '\n'


def changed_observation(log, change, predicate=lambda value: True):
    lines = log.splitlines()
    for index, line in enumerate(lines):
        if line.startswith('APPLE_'):
            marker, text = line.split(' ', 1)
            value = json.loads(text)
            if not predicate(value):
                continue
            change(value)
            lines[index] = marker + ' ' + json.dumps(value, sort_keys=True)
            return '\n'.join(lines) + '\n'
    raise AssertionError('Missing synthetic observation')


class ConsumerReceiptTests(unittest.TestCase):
    def test_complete_named_wire_and_storage_sessions_require_all_pinned_observations(self):
        for kind, methods, observations in [('wire', 4, 223), ('migration', 85, 20)]:
            for spelling in ['objc', 'dotted']:
                with self.subTest(kind=kind, spelling=spelling):
                    result = receipts.qualify(kind, 0, synthetic(kind, spelling))
                    self.assertEqual(len(result['methods']), methods)
                    self.assertEqual(len(result['observations']), observations)
                    self.assertEqual(result['moduleIdentity'], 'explicit')

    def test_storage_receipt_requires_the_accepted_future_history_regression(self):
        log = synthetic('migration')
        identity = '-[PlannerDataTests.DraftStoreTests testRestoreRejectsFutureHistoryWithoutChangingReadableDrafts]'
        started = f"Test Case '{identity}' started.\n"
        passed = f"Test Case '{identity}' passed (0.001 seconds).\n"
        self.assertEqual(log.count(started), 1)
        self.assertEqual(log.count(passed), 1)
        missing = log.replace(started, '').replace(passed, '')
        old = missing.replace('Executed 85 tests', 'Executed 84 tests')
        wrong_class = log.replace(identity, identity.replace('DraftStoreTests', 'UnrelatedTests'))
        skipped = log.replace(passed, passed.replace(' passed ', ' skipped '))
        for candidate in [old, missing, wrong_class, skipped]:
            with self.assertRaises(ValueError):
                receipts.qualify('migration', 0, candidate)
        complete = receipts.qualify('migration', 0, log)
        self.assertEqual(len(complete['methods']), 85)
        self.assertEqual(len(complete['observations']), 20)

    def test_storage_receipt_requires_every_accepted_wal_and_hot_journal_method(self):
        source = (receipts.ROOT / 'Packages/PlannerData/Tests/PlannerDataTests/DraftStoreTests.swift').read_text()
        declared = {'DraftStoreTests.' + name for name in re.findall(r'^    func (test\w+)\(', source, re.MULTILINE)}
        self.assertEqual(len(declared), 31)
        self.assertEqual(receipts.EXISTING_STORAGE_TESTS, declared)
        methods = [
            'testUnknownWALSchemaPreservesDatabaseBytesAndJournalMode',
            'testUnknownSchemaInOrphanedWALIsRejectedWithoutCheckpoint',
            'testSupportedWALSchemaMigratesAndRemainsWritable',
            'testSupportedHotJournalRecoversAndRemainsWritable',
            'testUnknownSchemaAfterHotJournalRecoveryRejectsRecoveredVersion',
        ]
        log = synthetic('migration')
        previous = log
        for method in methods:
            identity = f'-[PlannerDataTests.DraftStoreTests {method}]'
            started = f"Test Case '{identity}' started.\n"
            passed = f"Test Case '{identity}' passed (0.001 seconds).\n"
            self.assertEqual(log.count(started), 1)
            self.assertEqual(log.count(passed), 1)
            missing = log.replace(started, '').replace(passed, '')
            candidates = [missing, missing.replace('Executed 85 tests', 'Executed 84 tests'),
                          log.replace(identity, identity.replace('DraftStoreTests', 'UnrelatedTests')),
                          log.replace(passed, passed.replace(' passed ', ' skipped '))]
            for index, candidate in enumerate(candidates):
                with self.subTest(method=method, candidate=index):
                    with self.assertRaises(ValueError):
                        receipts.qualify('migration', 0, candidate)
            previous = previous.replace(started, '').replace(passed, '')
        previous = previous.replace('Executed 85 tests', 'Executed 80 tests')
        with self.assertRaises(ValueError):
            receipts.qualify('migration', 0, previous)
        self.assertEqual(len(receipts.qualify('migration', 0, log)['methods']), 85)

    def test_storage_receipt_rejects_the_previous_35_method_cohort(self):
        source = (receipts.ROOT / 'Packages/PlannerData/Tests/PlannerDataTests/PendingBuildWriteStoreTests.swift').read_text()
        pending = re.findall(r'^    func (test\w+)\(', source, re.MULTILINE)
        self.assertEqual(len(pending), 35)
        preceding = (receipts.EXISTING_STORAGE_TESTS | receipts.PENDING_WRITE_TESTS
                     | set(receipts.MIGRATION_TESTS.values()))
        log = synthetic('migration', storage_methods=preceding)
        count = len(re.findall(r"^Test Case '[^']+' started\.", log, re.MULTILINE))
        for method in pending:
            identity = f'-[PlannerDataTests.PendingBuildWriteStoreTests {method}]'
            log = log.replace(f"Test Case '{identity}' started.\n", '')
            log = log.replace(f"Test Case '{identity}' passed (0.001 seconds).\n", '')
        previous = log.replace(f'Executed {count} tests', 'Executed 35 tests')
        self.assertEqual(len(re.findall(r"^Test Case '[^']+' started\.", previous, re.MULTILINE)), 35)
        self.assertEqual(previous.count('APPLE_MIGRATION_CASE '), 20)
        with self.assertRaisesRegex(ValueError, 'Every exact required XCTest method'):
            receipts.qualify('migration', 0, previous)

    def test_storage_receipt_requires_every_accepted_pending_write_method(self):
        source = (receipts.ROOT / 'Packages/PlannerData/Tests/PlannerDataTests/PendingBuildWriteStoreTests.swift').read_text()
        declared = {'PendingBuildWriteStoreTests.' + name
                    for name in re.findall(r'^    func (test\w+)\(', source, re.MULTILINE)}
        self.assertEqual(len(declared), 35)
        self.assertEqual(receipts.PENDING_WRITE_TESTS, declared)
        log = synthetic('migration')
        complete = receipts.qualify('migration', 0, log)
        self.assertEqual(len(complete['methods']), 85)
        self.assertEqual(len(complete['observations']), 20)
        for name in sorted(declared):
            cls, method = name.split('.')
            identity = f'-[PlannerDataTests.{cls} {method}]'
            started = f"Test Case '{identity}' started.\n"
            passed = f"Test Case '{identity}' passed (0.001 seconds).\n"
            self.assertEqual(log.count(started), 1)
            self.assertEqual(log.count(passed), 1)
            missing = log.replace(started, '').replace(passed, '')
            candidates = [missing, missing.replace('Executed 85 tests', 'Executed 84 tests'),
                          log.replace(identity, identity.replace(cls, 'UnrelatedTests')),
                          log.replace(passed, passed.replace(' passed ', ' skipped ')),
                          log.replace(passed, passed.replace(' passed ', ' failed '))]
            for index, candidate in enumerate(candidates):
                with self.subTest(method=method, candidate=index):
                    with self.assertRaises(ValueError):
                        receipts.qualify('migration', 0, candidate)

    def test_bare_and_wrong_modules_reject_without_false_native_identity(self):
        for kind in ['wire', 'migration']:
            bare = synthetic(kind, 'bare')
            with self.assertRaises(ValueError):
                receipts.qualify(kind, 0, bare)
            local = receipts.qualify(kind, 0, bare, allow_bare_linux=True)
            self.assertEqual(local['moduleIdentity'], 'bare-linux-compatible')
            module = 'PlannerConformanceTests' if kind == 'wire' else 'PlannerDataTests'
            wrong = synthetic(kind).replace(module + '.', 'WrongModule.')
            for allow in [False, True]:
                with self.assertRaises(ValueError):
                    receipts.qualify(kind, 0, wrong, allow_bare_linux=allow)

    def test_failed_skipped_truncated_duplicate_and_zero_sessions_reject(self):
        log = synthetic('wire')
        first = next(line for line in log.splitlines() if line.startswith('Test Case '))
        changed = [log.replace(' passed (0.001 seconds).', ' skipped (0.001 seconds).', 1),
                   '\n'.join(log.splitlines()[:-1]), log + log,
                   log.replace(first, first + '\n' + first, 1),
                   "Test Suite 'All tests' started at SYNTHETIC\nTest Suite 'All tests' passed at SYNTHETIC\n"
                   ' Executed 0 tests, with 0 failures (0 unexpected) in 0.1 (0.1) seconds\n']
        for bad in changed:
            with self.assertRaises(ValueError):
                receipts.qualify('wire', 0, bad)
        for code in [-9, 1, 127]:
            with self.assertRaises(ValueError):
                receipts.qualify('wire', code, log)
        self.assertEqual(len(receipts.qualify('wire', 0, log)['observations']), 223)

    def test_missing_duplicate_unknown_and_moved_case_observations_reject(self):
        for kind in ['wire', 'migration']:
            log = synthetic(kind)
            row = next(line for line in log.splitlines() if line.startswith('APPLE_'))
            changed = [log.replace(row + '\n', '', 1), log.replace(row, row + '\n' + row, 1),
                       row + '\n' + log.replace(row + '\n', '', 1),
                       changed_observation(log, lambda value: value.update(id='not-a-case'))]
            for bad in changed:
                with self.assertRaises(ValueError):
                    receipts.qualify(kind, 0, bad)

    def test_observed_values_require_exact_booleans_nulls_and_field_sets(self):
        wire = synthetic('wire')
        for value in [False, 1, None, 'true']:
            with self.assertRaises(ValueError):
                receipts.qualify('wire', 0, changed_observation(wire, lambda row: row.update(accepted=value),
                                                               lambda row: row['accepted'] is True))
        for value in [False, 1, None]:
            with self.assertRaises(ValueError):
                receipts.qualify('wire', 0, changed_observation(wire, lambda row: row.update(preserved=value),
                                                               lambda row: row['accepted'] is True))
        migration = synthetic('migration')
        for value in [False, 1, None]:
            with self.assertRaises(ValueError):
                receipts.qualify('migration', 0, changed_observation(migration, lambda row:
                    row['observed'].update({next(iter(row['observed'])): value})))
        for kind in ['wire', 'migration']:
            with self.assertRaises(ValueError):
                receipts.qualify(kind, 0, changed_observation(synthetic(kind), lambda row: row.update(extra=True)))

    def test_duplicate_escaped_keys_and_malformed_observation_framing_reject(self):
        for kind in ['wire', 'migration']:
            log = synthetic(kind)
            for changed in [log.replace('"id": ', '"\\u0069d": "forged", "id": ', 1),
                            log.replace('APPLE_WIRE_CASE ', 'APPLE_WIRE_CASE', 1) if kind == 'wire' else
                            log.replace('APPLE_MIGRATION_CASE ', 'APPLE_MIGRATION_CASE', 1)]:
                with self.assertRaises(ValueError):
                    receipts.qualify(kind, 0, changed)
        migration = synthetic('migration').replace('"observed": {', '"observed": {"forged":true,"forged":true,', 1)
        with self.assertRaises(ValueError):
            receipts.qualify('migration', 0, migration)

    def test_fixture_byte_drift_rejects_and_recovery_uses_original_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for kind in ['wire', 'migration']:
                pin = receipts.LOCK['wireFixture' if kind == 'wire' else 'migrationFixture']
                source = receipts.ROOT / pin['path']
                target = root / pin['path']
                target.parent.mkdir(parents=True, exist_ok=True)
                original = source.read_bytes()
                target.write_bytes(original + b' ')
                with patch.object(receipts, 'ROOT', root):
                    with self.assertRaisesRegex(ValueError, 'fixture bytes differ'):
                        receipts.fixture(kind)
                    target.write_bytes(original)
                    self.assertEqual(receipts.fixture(kind)[1], pin)
        wire, _ = receipts.fixture('wire')
        changed = deepcopy(wire)
        changed['cases'][0]['payloadJSON'] += ' '
        with self.assertRaisesRegex(ValueError, 'payload bytes differ'):
            receipts.expected_wire(changed)
        migration, _ = receipts.fixture('migration')
        changed = deepcopy(migration)
        next(case for case in changed['cases'] if case['id'] == 'v1-canonical-snapshot')['records'][0]['payloadJSON'] += ' '
        with self.assertRaisesRegex(ValueError, 'canonical payload bytes differ'):
            receipts.expected_migrations(changed)

    def test_old_success_is_invalidated_before_bad_qualification_and_recovery(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log, output = root / 'input.log', root / 'receipt.json'
            log.write_text(synthetic('wire'))
            output.write_text('{"staleSuccess":true}\n')
            prepared = receipts.prepare_output(output, log)
            with self.assertRaises(ValueError):
                receipts.qualify('wire', 1, log.read_text())
            self.assertFalse(output.exists())
            self.assertTrue(log.exists())
            receipts.publish(prepared, receipts.qualify('wire', 0, log.read_text()))
            self.assertEqual(len(json.loads(output.read_text())['observations']), 223)

    def test_output_never_unlinks_source_input_log_links_or_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / 'input.log'
            log.write_bytes(b'original log')
            link = root / 'symbolic.json'
            link.symlink_to(log)
            hardlink = root / 'hard.json'
            hardlink.hardlink_to(log)
            folder = root / 'folder.json'
            folder.mkdir()
            for destination in [log, link, hardlink, folder, receipts.HERE / 'cross-client-lock.json']:
                with self.assertRaises(ValueError):
                    receipts.prepare_output(destination, log)
            self.assertEqual(log.read_bytes(), b'original log')
            self.assertTrue(link.is_symlink())
            self.assertEqual(hardlink.read_bytes(), b'original log')
            self.assertTrue(folder.is_dir())

    def test_atomic_publication_failure_leaves_no_success_or_temporary_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / 'receipt.json'
            with patch.object(Path, 'replace', side_effect=OSError('simulated publication failure')):
                with self.assertRaises(OSError):
                    receipts.publish(output, {'synthetic': True})
            self.assertEqual(list(root.iterdir()), [])

    def test_current_storage_profile_matches_every_receiving_source_declaration(self):
        declared = set()
        for cls, expected in [('DraftStoreTests', 31), ('PendingBuildWriteStoreTests', 35),
                              ('PendingBuildWriteDispatcherTests', 15), ('MigrationFixtureTests', 4)]:
            source = (receipts.ROOT / f'Packages/PlannerData/Tests/PlannerDataTests/{cls}.swift').read_text()
            names = re.findall(r'^    func (test\w+)\(', source, re.MULTILINE)
            self.assertEqual(len(names), expected)
            self.assertEqual(len(set(names)), expected)
            declared.update(cls + '.' + name for name in names)
        self.assertEqual(len(declared), 85)
        result = receipts.qualify('migration', 0, synthetic('migration', storage_methods=declared))
        self.assertEqual(set(result['methods']), declared)
        self.assertEqual(len(result['observations']), 20)

    def test_storage_receipt_requires_every_accepted_dispatcher_method(self):
        source = (receipts.ROOT / 'Packages/PlannerData/Tests/PlannerDataTests/PendingBuildWriteDispatcherTests.swift').read_text()
        declared = {'PendingBuildWriteDispatcherTests.' + name
                    for name in re.findall(r'^    func (test\w+)\(', source, re.MULTILINE)}
        self.assertEqual(len(declared), 15)
        self.assertEqual(receipts.PENDING_WRITE_DISPATCH_TESTS, declared)
        log = synthetic('migration')
        complete = receipts.qualify('migration', 0, log)
        self.assertEqual(len(complete['methods']), 85)
        self.assertEqual(len(complete['observations']), 20)
        for name in sorted(declared):
            cls, method = name.split('.')
            identity = f'-[PlannerDataTests.{cls} {method}]'
            started = f"Test Case '{identity}' started.\n"
            passed = f"Test Case '{identity}' passed (0.001 seconds).\n"
            self.assertEqual(log.count(started), 1)
            self.assertEqual(log.count(passed), 1)
            missing = log.replace(started, '').replace(passed, '')
            another = next(value for value in sorted(declared) if value != name)
            other_cls, other_method = another.split('.')
            duplicate = f'-[PlannerDataTests.{other_cls} {other_method}]'
            candidates = [missing, missing.replace('Executed 85 tests', 'Executed 84 tests'),
                          log.replace(identity, identity.replace(cls, 'UnrelatedTests')),
                          log.replace(passed, passed.replace(' passed ', ' skipped ')),
                          log.replace(passed, passed.replace(' passed ', ' failed ')),
                          log.replace(identity, duplicate)]
            for index, candidate in enumerate(candidates):
                with self.subTest(method=method, candidate=index):
                    with self.assertRaises(ValueError):
                        receipts.qualify('migration', 0, candidate)

    def test_storage_receipt_rejects_previous_70_methods_and_unrelated_padding(self):
        previous = (receipts.EXISTING_STORAGE_TESTS | receipts.PENDING_WRITE_TESTS
                    | set(receipts.MIGRATION_TESTS.values()))
        self.assertEqual(len(previous), 70)
        unrelated = {f'UnrelatedTests.testUnrelatedDispatcher{index}' for index in range(15)}
        for methods in [previous, previous | unrelated]:
            with self.subTest(methods=len(methods)):
                log = synthetic('migration', storage_methods=methods)
                self.assertEqual(len(re.findall(r"^Test Case '[^']+' started\.", log, re.MULTILINE)),
                                 len(methods))
                self.assertEqual(log.count('APPLE_MIGRATION_CASE '), 20)
                with self.assertRaisesRegex(ValueError, 'Every exact required XCTest method'):
                    receipts.qualify('migration', 0, log)


if __name__ == '__main__':
    unittest.main()
