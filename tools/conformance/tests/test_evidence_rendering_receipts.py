"""Synthetic parser probes are never evidence that a native view was rendered."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import qualify_evidence_rendering as qualifier


class EvidenceRenderingReceiptTests(unittest.TestCase):
    def receipt(self, module="PlannerEvidenceUITests", methods=None, bare=False):
        methods = sorted(qualifier.REQUIRED) if methods is None else methods
        lines = ["Test Suite 'Selected tests' started at 2026-10-18"]
        for method in methods:
            cls, name = method.split(".")
            identity = f"{cls}.{name}" if bare else f"-[{module}.{cls} {name}]"
            lines += [f"Test Case '{identity}' started.", f"Test Case '{identity}' passed (0.010 seconds)."]
        lines += ["Test Suite 'Selected tests' passed at 2026-10-18",
                  f"\t Executed {len(methods)} tests, with 0 failures (0 unexpected) in 0.040 (0.040) seconds"]
        return "\n".join(lines) + "\n"

    def test_exact_native_ui_module_and_all_current_methods_are_required(self):
        qualifier.require_rendering_receipt(self.receipt())
        qualifier.require_rendering_receipt(self.receipt().replace("Selected tests", "All tests"))
        for text in [self.receipt(module="PlannerCoreTests"), self.receipt(module="PlannerUITests"),
                     self.receipt(module="OtherModule"), self.receipt(bare=True),
                     self.receipt(methods=sorted(qualifier.REQUIRED)[:-1]),
                     self.receipt().replace("EvidenceRenderingTests", "EvidenceRenderingTestsExtra"),
                     self.receipt().replace(sorted(qualifier.REQUIRED)[0].split(".")[1], "testOther")]:
            with self.assertRaises(ValueError):
                qualifier.require_rendering_receipt(text)

    def test_empty_skipped_duplicate_and_incomplete_output_cannot_qualify(self):
        complete = self.receipt()
        lines = complete.splitlines()
        for text in ["Build complete!", self.receipt(methods=[]), "Test run with 0 tests passed",
                     complete.replace("passed (0.010 seconds).", "skipped (0.010 seconds).", 1),
                     complete.replace(lines[1] + "\n", "", 1),
                     complete.replace(lines[1], lines[1] + "\n" + lines[1], 1),
                     complete.replace(lines[2], lines[2] + "\n" + lines[2], 1),
                     complete.replace(f"Executed {len(qualifier.REQUIRED)} tests", f"Executed {len(qualifier.REQUIRED) - 1} tests"),
                     complete.replace("with 0 failures", "with 1 failure"),
                     complete.replace("(0 unexpected)", "(1 unexpected)"),
                     "\n".join(lines[:-1]), complete + lines[2] + "\n",
                     complete + complete.replace("Selected tests", "All tests"),
                     "Test Suite 'All tests' started at SYNTHETIC\n" + complete]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                qualifier.require_rendering_receipt(text)

    def test_previous_four_method_receipt_cannot_qualify_the_date_extension(self):
        previous = sorted(qualifier.REQUIRED - {
            "EvidenceRenderingTests.testCaptureDateLocaleChangesPreserveGregorianDayAndRetainedEvidence",
            "EvidenceRenderingTests.testVisibleBuildAnalysisNeverRendersRetainedReportsForOtherRevisionsOrRetiredRequests",
            "EvidenceRenderingTests.testClaimCopyLocaleRTLAndRecoveryPreserveVerbatimEvidenceAndRecheck",
        })
        self.assertEqual(len(previous), 4)
        with self.assertRaises(ValueError):
            qualifier.require_rendering_receipt(self.receipt(methods=previous))

    def test_previous_five_method_receipt_cannot_qualify_the_copy_extension(self):
        previous = sorted(qualifier.REQUIRED - {
            "EvidenceRenderingTests.testClaimCopyLocaleRTLAndRecoveryPreserveVerbatimEvidenceAndRecheck",
            "EvidenceRenderingTests.testVisibleBuildAnalysisNeverRendersRetainedReportsForOtherRevisionsOrRetiredRequests",
        })
        self.assertEqual(len(previous), 5)
        with self.assertRaises(ValueError):
            qualifier.require_rendering_receipt(self.receipt(methods=previous))


    def test_each_five_method_predecessor_cannot_qualify_the_combined_extension(self):
        for absent in {
            "EvidenceRenderingTests.testCaptureDateLocaleChangesPreserveGregorianDayAndRetainedEvidence",
            "EvidenceRenderingTests.testVisibleBuildAnalysisNeverRendersRetainedReportsForOtherRevisionsOrRetiredRequests",
        }:
            with self.subTest(absent=absent):
                previous = sorted(qualifier.REQUIRED - {absent,
                    "EvidenceRenderingTests.testClaimCopyLocaleRTLAndRecoveryPreserveVerbatimEvidenceAndRecheck"})
                self.assertEqual(len(previous), 5)
                with self.assertRaises(ValueError):
                    qualifier.require_rendering_receipt(self.receipt(methods=previous))
        qualifier.require_rendering_receipt(self.receipt())

    def test_each_six_method_predecessor_cannot_qualify_the_combined_extension(self):
        extensions = {
            "EvidenceRenderingTests.testCaptureDateLocaleChangesPreserveGregorianDayAndRetainedEvidence",
            "EvidenceRenderingTests.testVisibleBuildAnalysisNeverRendersRetainedReportsForOtherRevisionsOrRetiredRequests",
            "EvidenceRenderingTests.testClaimCopyLocaleRTLAndRecoveryPreserveVerbatimEvidenceAndRecheck",
        }
        original = qualifier.REQUIRED - extensions
        self.assertEqual(len(original), 4)
        for absent in extensions:
            with self.subTest(absent=absent):
                previous = sorted(original | (extensions - {absent}))
                self.assertEqual(len(previous), 6)
                with self.assertRaises(ValueError):
                    qualifier.require_rendering_receipt(self.receipt(methods=previous))


if __name__ == "__main__":
    unittest.main()
