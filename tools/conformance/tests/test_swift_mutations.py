"""Runner qualification without requiring a Swift installation."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('swift_mutations', Path(__file__).resolve().parents[1] / 'swift_mutations.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class SwiftMutationTests(unittest.TestCase):
    def output(self, mutation, mac=False):
        cls, method = mutation['test'].split('.')
        name = f'-[PlannerCoreTests.{cls} {method}]' if mac else mutation['test']
        return (f'/tmp/Test.swift:20: error: {name} : {mutation["assertion"]} failed\n'
                f"Test Case '{name}' failed (0.001 seconds).\n"
                "Test Suite 'Selected tests' failed at 2026-10-18\n")

    def test_linux_and_macos_assertion_receipts(self):
        for mutation in runner.MUTATIONS:
            for mac in [False, True]:
                self.assertTrue(runner.detected(1, self.output(mutation, mac), mutation))

    def test_compile_crash_wrong_test_and_unconditional_failure_do_not_qualify(self):
        m = runner.MUTATIONS[0]
        valid = self.output(m)
        for code, output in [(1, 'error: failed to compile'), (-9, valid), (0, valid),
                             (1, valid.replace(m['test'], 'OtherTests.testOther')),
                             (1, valid.replace(m['assertion'], 'XCTFail')),
                             (1, valid.replace("Test Suite 'Selected tests' failed", 'crashed'))]:
            self.assertFalse(runner.detected(code, output, m))

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
                if not arguments: return 0, 'baseline passed'
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

    def test_rejects_output_in_source_package(self):
        with tempfile.TemporaryDirectory() as tmp:
            package = self.make_package(Path(tmp))
            with self.assertRaisesRegex(ValueError, 'outside the source'):
                runner.run(package, package / 'evidence', 'swift', 10)


if __name__ == '__main__':
    unittest.main()
