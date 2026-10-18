"""Runner qualification without requiring a Swift installation."""
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('swift_mutations', Path(__file__).resolve().parents[1] / 'swift_mutations.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class SwiftMutationTests(unittest.TestCase):
    def name(self, mutation, mac=False):
        cls, method = mutation['test'].split('.')
        return f'-[PlannerCoreTests.{cls} {method}]' if mac else mutation['test']

    def start(self, mutation, mac=False):
        suffix = '.' if mac else ' at 2026-10-18 06:25:10.281'
        return f"Test Case '{self.name(mutation, mac)}' started{suffix}\n"

    def finish(self, mutation, status, mac=False):
        suffix = '.' if mac else ''
        return f"Test Case '{self.name(mutation, mac)}' {status} (0.001 seconds){suffix}\n"

    def output(self, mutation, mac=False):
        name = self.name(mutation, mac)
        return ("Test Suite 'Selected tests' started at 2026-10-18\n" + self.start(mutation, mac) +
                f'/tmp/Test.swift:20: error: {name} : {mutation["assertion"]} failed\n' +
                self.finish(mutation, 'failed', mac) +
                "Test Suite 'Selected tests' failed at 2026-10-18\n"
                "\t Executed 1 test, with 1 failure (0 unexpected) in 0.001 (0.001) seconds\n")

    def baseline(self, mac=False, mutations=None):
        mutations = runner.MUTATIONS if mutations is None else mutations
        cases = ''.join(self.start(m, mac) + self.finish(m, 'passed', mac) for m in mutations)
        return ("Test Suite 'All tests' started at 2026-10-18\n" + cases +
                "Test Suite 'All tests' passed at 2026-10-18\n" +
                f"\t Executed {len(mutations)} tests, with 0 failures (0 unexpected) in 0.003 (0.003) seconds\n"
                "◇ Test run started.\n✔ Test run with 0 tests passed after 0.001 seconds.\n")

    def test_linux_and_macos_assertion_receipts(self):
        for mutation in runner.MUTATIONS:
            for mac in [False, True]:
                self.assertTrue(runner.detected(1, self.output(mutation, mac), mutation))
                self.assertTrue(runner.baseline_passed(0, self.baseline(mac)))

    def test_compile_crash_wrong_test_and_unconditional_failure_do_not_qualify(self):
        m = runner.MUTATIONS[0]
        valid = self.output(m)
        for code, output in [(1, 'error: failed to compile'), (-9, valid), (0, valid),
                             (1, valid.replace(m['test'], 'OtherTests.testOther')),
                             (1, valid.replace(m['assertion'], 'XCTFail')),
                             (1, valid.replace("Test Suite 'Selected tests' failed", 'crashed'))]:
            self.assertFalse(runner.detected(code, output, m))

    def test_similarly_named_test_or_class_is_not_the_required_regression(self):
        for mutation in runner.MUTATIONS:
            cls, method = mutation['test'].split('.')
            for mac in [False, True]:
                for old, new in [(cls, cls + 'Extra'), (cls, 'Other' + cls),
                                 (method, method + 'Extra'), (method, 'other' + method)]:
                    with self.subTest(mutation=mutation['name'], mac=mac, replacement=new):
                        self.assertFalse(runner.detected(1, self.output(mutation, mac).replace(old, new), mutation))
                        self.assertFalse(runner.baseline_passed(0, self.baseline(mac).replace(old, new)))

    def test_wrong_module_and_assertion_identity_cannot_qualify(self):
        mutation = runner.MUTATIONS[0]
        for mac in [False, True]:
            valid = self.output(mutation, mac)
            self.assertFalse(runner.detected(1, valid.replace(
                f'error: {self.name(mutation, mac)} :',
                'error: OtherTests.testOther :'), mutation))
        self.assertFalse(runner.detected(1, self.output(mutation, True).replace(
            'PlannerCoreTests.', 'OtherModule.'), mutation))
        self.assertFalse(runner.baseline_passed(0, self.baseline(True).replace(
            'PlannerCoreTests.', 'OtherModule.')))

    def test_selected_failure_requires_complete_matching_execution(self):
        mutation = runner.MUTATIONS[0]
        valid = self.output(mutation)
        started = self.start(mutation)
        finished = self.finish(mutation, 'failed')
        invalid = [
            valid.replace(started, ''),
            valid.replace(started, started * 2),
            valid.replace(finished, finished * 2),
            valid.replace('Executed 1 test', 'Executed 0 tests'),
            valid.replace('Executed 1 test', 'Executed 2 tests'),
            valid.replace('with 1 failure', 'with 0 failures'),
            valid.replace('(0 unexpected)', '(1 unexpected)'),
            valid.replace("' failed (", "' skipped ("),
            valid.replace('failed (0.001 seconds)', 'failed'),
            valid.replace('in 0.001 (0.001)', 'in 0..001 (0.001)'),
            valid[:valid.index('\t Executed')],
            valid.replace("Test Suite 'Selected tests' started", "Test Suite 'Other tests' started"),
            valid + "Test Suite 'Selected tests' passed at 2026-10-18\n",
            valid + finished,
            valid.replace(started, started + "Test Case 'OtherTests.testOther' started.\n"),
        ]
        for index, output in enumerate(invalid):
            with self.subTest(case=index):
                self.assertFalse(runner.detected(1, output, mutation))

    def test_baseline_requires_actual_complete_passing_named_cases(self):
        valid = self.baseline()
        mutation = runner.MUTATIONS[0]
        finished = self.finish(mutation, 'passed')
        for code, output in [
            (0, 'Build complete!'),
            (0, '✔ Test run with 0 tests passed after 0.001 seconds.'),
            (0, self.baseline(mutations=())),
            (0, self.baseline(mutations=runner.MUTATIONS[1:])),
            (0, valid.replace('Executed 3 tests', 'Executed 4 tests')),
            (0, valid.replace(finished, finished * 2)),
            (0, valid.replace(finished, finished.replace('passed', 'skipped'))),
            (0, valid.replace(finished, finished.replace('passed', 'failed'))),
            (0, valid.replace('with 0 failures', 'with 1 failure')),
            (0, valid.replace('(0 unexpected)', '(1 unexpected)')),
            (1, valid),
        ]:
            with self.subTest(code=code, output=output):
                self.assertFalse(runner.baseline_passed(code, output))

    def make_package(self, root):
        package = root / 'package'
        sources = package / 'Sources/PlannerCore'
        sources.mkdir(parents=True)
        (package / 'Package.swift').write_text('// fixture only\n')
        for m in runner.MUTATIONS:
            (sources / m['file']).write_text(m['before'])
        return package

    def test_copies_only_and_cleans_temporaries(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package = self.make_package(root)
            called = []
            def fake_invoke(copy, swift, arguments, log, timeout):
                called.append(copy)
                self.assertNotEqual(copy, package)
                if not arguments: return 0, self.baseline()
                m = next(m for m in runner.MUTATIONS if m['test'] == arguments[-1])
                self.assertEqual((copy / 'Sources/PlannerCore' / m['file']).read_text(), m['after'])
                return 1, self.output(m)
            with patch.object(runner, 'invoke', side_effect=fake_invoke):
                self.assertEqual(len(runner.run(package, root / 'evidence', 'swift', 10)), 3)
            for m in runner.MUTATIONS:
                self.assertEqual((package / 'Sources/PlannerCore' / m['file']).read_text(), m['before'])
            self.assertTrue(all(not p.exists() for p in called))
            self.assertTrue((root / 'evidence/swift-mutations.json').is_file())

    def test_anchor_drift_fails_before_execution_and_removes_stale_receipt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package = self.make_package(root)
            m = runner.MUTATIONS[0]
            (package / 'Sources/PlannerCore' / m['file']).write_text(m['before'] * 2)
            output = root / 'evidence'; output.mkdir()
            receipt = output / 'swift-mutations.json'; receipt.write_text('stale success')
            with patch.object(runner, 'invoke') as invoke:
                with self.assertRaisesRegex(ValueError, 'exactly one source anchor'):
                    runner.run(package, output, 'swift', 10)
                invoke.assert_not_called()
            self.assertFalse(receipt.exists())

    def test_empty_successful_baseline_stops_before_mutations_and_removes_stale_receipt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package = self.make_package(root)
            output = root / 'evidence'; output.mkdir()
            receipt = output / 'swift-mutations.json'; receipt.write_text('stale success')
            with patch.object(runner, 'invoke', return_value=(0, 'Build complete!')) as invoke:
                with self.assertRaisesRegex(ValueError, 'execute and pass every named regression'):
                    runner.run(package, output, 'swift', 10)
                self.assertEqual(invoke.call_count, 1)
            self.assertFalse(receipt.exists())
            for mutation in runner.MUTATIONS:
                self.assertEqual((package / 'Sources/PlannerCore' / mutation['file']).read_text(), mutation['before'])

    def test_rejects_output_in_source_package(self):
        with tempfile.TemporaryDirectory() as tmp:
            package = self.make_package(Path(tmp))
            with self.assertRaisesRegex(ValueError, 'outside the source'):
                runner.run(package, package / 'evidence', 'swift', 10)

    def test_real_invocation_rejects_log_alias_without_truncating_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package = self.make_package(root)
            source = package / 'Package.swift'
            original = source.read_bytes()
            output = root / 'evidence'; output.mkdir()
            log = output / 'baseline.log'; log.symlink_to(source)
            child = root / 'synthetic-swift'
            child.write_text(f'#!{sys.executable}\nraise SystemExit(0)\n')
            child.chmod(0o755)
            with self.assertRaisesRegex(ValueError, 'unshared regular'):
                runner.run(package, output, str(child), 10)
            self.assertEqual(source.read_bytes(), original)
            self.assertTrue(log.is_symlink())

    def test_all_output_destinations_are_checked_before_any_cleanup(self):
        names = ['swift-mutations.json', 'baseline.log',
                 *(m['name'] + '.log' for m in runner.MUTATIONS)]
        for name in names:
            for kind in ['symlink', 'hardlink', 'directory', 'fifo']:
                with self.subTest(name=name, kind=kind), tempfile.TemporaryDirectory() as tmp:
                    root = Path(tmp)
                    package = self.make_package(root)
                    source = package / 'Package.swift'
                    original = source.read_bytes()
                    output = root / 'evidence'; output.mkdir()
                    target = output / name
                    if kind == 'symlink': target.symlink_to(source)
                    elif kind == 'hardlink': target.hardlink_to(source)
                    elif kind == 'directory': target.mkdir()
                    else: os.mkfifo(target)
                    before = target.lstat()
                    receipt = output / 'swift-mutations.json'
                    if name != receipt.name: receipt.write_text('prior success')
                    with patch.object(runner, 'invoke', return_value=(0, 'Build complete!')) as invoke:
                        with self.assertRaisesRegex(ValueError, 'unshared regular'):
                            runner.run(package, output, 'swift', 10)
                        invoke.assert_not_called()
                    self.assertEqual(source.read_bytes(), original)
                    after = target.lstat()
                    self.assertEqual((after.st_ino, after.st_mode, after.st_nlink),
                                     (before.st_ino, before.st_mode, before.st_nlink))
                    if name != receipt.name: self.assertEqual(receipt.read_text(), 'prior success')

    def test_output_cannot_traverse_source_even_when_final_directory_is_outside(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package = self.make_package(root)
            outside = root / 'outside'; outside.mkdir()
            (package / 'escape').symlink_to(outside, target_is_directory=True)
            with patch.object(runner, 'invoke') as invoke:
                with self.assertRaisesRegex(ValueError, 'outside the source'):
                    runner.run(package, package / 'escape' / 'evidence', 'swift', 10)
                invoke.assert_not_called()
            self.assertFalse((outside / 'evidence').exists())
            self.assertTrue((package / 'escape').is_symlink())

    def test_safe_output_alias_retries_clear_receipt_and_all_prior_logs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package = self.make_package(root)
            output = root / 'evidence'; output.mkdir()
            alias = root / 'outside-alias'; alias.symlink_to(output, target_is_directory=True)
            names = ['swift-mutations.json', 'baseline.log',
                     *(m['name'] + '.log' for m in runner.MUTATIONS)]
            for name in names: (output / name).write_text('prior result')
            with patch.object(runner, 'invoke', return_value=(0, 'Build complete!')):
                with self.assertRaisesRegex(ValueError, 'execute and pass every named regression'):
                    runner.run(package, alias, 'swift', 10)
            self.assertTrue(all(not (output / name).exists() for name in names))
            def recovered(copy, swift, arguments, log, timeout):
                with log.open('x') as stream: stream.write('new execution')
                if not arguments: return 0, self.baseline()
                mutation = next(m for m in runner.MUTATIONS if m['test'] == arguments[-1])
                return 1, self.output(mutation)
            with patch.object(runner, 'invoke', side_effect=recovered):
                self.assertEqual(len(runner.run(package, alias, 'swift', 10)), 3)
            self.assertTrue(all((output / name).is_file() for name in names))
            self.assertTrue(alias.is_symlink())

    def test_invoke_does_not_replace_an_output_created_after_preflight(self):
        for kind in ['regular', 'symlink', 'hardlink']:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / 'source'; source.write_text('retained source')
                log = root / 'baseline.log'
                if kind == 'regular': log.write_text('another execution')
                elif kind == 'symlink': log.symlink_to(source)
                else: log.hardlink_to(source)
                before = log.read_bytes()
                with patch.object(runner.subprocess, 'run') as execute:
                    with self.assertRaises(FileExistsError):
                        runner.invoke(root, 'swift', [], log, 10)
                    execute.assert_not_called()
                self.assertEqual(log.read_bytes(), before)
                self.assertEqual(source.read_text(), 'retained source')

    def test_receipt_does_not_follow_an_alias_created_during_execution(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package = self.make_package(root)
            source = package / 'Package.swift'; original = source.read_bytes()
            output = root / 'evidence'
            def intercepted(copy, swift, arguments, log, timeout):
                if not arguments: return 0, self.baseline()
                mutation = next(m for m in runner.MUTATIONS if m['test'] == arguments[-1])
                if mutation == runner.MUTATIONS[-1]:
                    (output / 'swift-mutations.json').symlink_to(source)
                return 1, self.output(mutation)
            with patch.object(runner, 'invoke', side_effect=intercepted):
                with self.assertRaises(FileExistsError):
                    runner.run(package, output, 'swift', 10)
            self.assertEqual(source.read_bytes(), original)
            self.assertTrue((output / 'swift-mutations.json').is_symlink())


if __name__ == '__main__':
    unittest.main()
