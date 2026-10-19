"""Presentation-only log specimens test the gate, not Swift or native behavior."""
import importlib.util
from contextlib import redirect_stderr, redirect_stdout
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "require_swift_test_results", Path(__file__).parents[1] / "require_swift_test_results.py")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class SwiftExecutionEvidenceTests(unittest.TestCase):
    required = {("PlannerUITests.DetailsTests", "testRequired")}
    lines = (
        "Test Case '-[PlannerUITests.ExistingTests testFirst]' passed (0.001 seconds).",
        "Test Case '-[PlannerUITests.ExistingTests testSecond]' passed (0.002 seconds).",
        "Test Case '-[PlannerUITests.DetailsTests testRequired]' passed (0.003 seconds).",
    )
    summary = "Test Suite 'All tests' passed at 2026-10-18 08:00:00.000.\n\t Executed 3 tests, with 0 failures (0 unexpected) in 0.006 seconds\n"

    def log(self, lines=None, summary=None):
        return "\n".join(self.lines if lines is None else lines) + "\n" + (
            self.summary if summary is None else summary)

    def test_accepts_complete_distinct_results_and_ignores_other_framework_footer(self):
        gate.verify(self.log() + "◇ Test run with 0 tests passed after 0.001 seconds.\n", 3, self.required)

    def test_compilation_and_source_mentions_do_not_establish_execution(self):
        with self.assertRaises(ValueError):
            gate.verify("Compiling DetailsTests.swift\nfunc testRequired()\n" + self.summary, 3, self.required)

    def test_missing_result_cannot_be_replaced_by_a_successful_summary(self):
        with self.assertRaises(ValueError):
            gate.verify(self.log(self.lines[:2]), 3, self.required)

    def test_same_method_in_another_suite_is_not_the_required_case(self):
        with self.assertRaises(ValueError):
            gate.verify(self.log().replace("PlannerUITests.DetailsTests", "PlannerUITests.OtherTests"), 3, self.required)

    def test_duplicate_results_do_not_satisfy_exact_count(self):
        with self.assertRaises(ValueError):
            gate.verify(self.log((self.lines[0], self.lines[0], self.lines[2])), 3, self.required)

    def test_failed_and_skipped_cases_fail_even_with_a_successful_summary(self):
        for status in ("failed", "skipped"):
            with self.subTest(status=status), self.assertRaises(ValueError):
                gate.verify(self.log().replace("testSecond]' passed", f"testSecond]' {status}"), 3, self.required)

    def test_wrong_total_or_nonfinal_summary_does_not_qualify(self):
        for summary in (self.summary.replace("Executed 3", "Executed 4"),
                        self.summary.replace("'All tests'", "'DetailsTests'"),
                        self.summary.replace("0 failures", "1 failures"),
                        self.summary + self.summary, ""):
            with self.subTest(summary=summary), self.assertRaises(ValueError):
                gate.verify(self.log(summary=summary), 3, self.required)

    def test_unknown_format_and_zero_case_plan_fail_closed(self):
        for text, count in ((self.log().replace("Test Case '-[", "Changed runner '["), 3),
                            (self.summary.replace("Executed 3", "Executed 0"), 0)):
            with self.subTest(count=count), self.assertRaises(ValueError):
                gate.verify(text, count, self.required)

    def profile_log(self, profile, total=None):
        expected, groups = gate.PROFILES[profile]
        total = expected if total is None else total
        cases = [(suite, name) for suite, names in groups.items() for name in names]
        cases += [("PlannerUITests.ExistingSpecimenTests", f"testExisting{index}")
                  for index in range(total - len(cases))]
        return "\n".join(f"Test Case '-[{suite} {name}]' passed (0.001 seconds)."
                         for suite, name in cases) + "\n" + self.summary.replace(
                             "Executed 3 tests", f"Executed {total} tests")

    def run_profile(self, profile, text):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "specimen.log"
            log.write_text(text, encoding="utf-8")
            with patch.object(sys, "argv", ["gate", profile, str(log)]), \
                    redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                return gate.main()

    def test_combined_profiles_require_each_class_qualified_group_through_cli(self):
        for profile in ("catalog-editor-transfer", "catalog-editor-ui", "comparison-catalog-editor-ui",
                        "quality-catalog-editor-transfer", "catalog-source-ui",
                        "comparison-catalog-source-ui", "resource-quality-catalog-editor-transfer",
                        "comparison-catalog-source-privacy-ui",
                        "graph-resource-quality-catalog-editor-transfer",
                        "component-comparison-main-ui", "component-comparison-current-main-ui",
                        "component-comparison-inspection-ui", "local-libraries-comparison-ui"):
            text = self.profile_log(profile)
            with self.subTest(profile=profile):
                self.assertEqual(self.run_profile(profile, text), 0)
            for suite in gate.PROFILES[profile][1]:
                # Keep the exact total and method names; another class cannot
                # impersonate any one of the independently retained features.
                replaced = text.replace(f"-[{suite} ", "-[UnrelatedTests.Impostor ")
                with self.subTest(profile=profile, missing_class=suite), \
                        self.assertRaises(SystemExit) as rejection:
                    self.run_profile(profile, replaced)
                self.assertEqual(rejection.exception.code, 1)

    def test_old_editor_cases_padded_to_41_cannot_replace_component_comparison_execution(self):
        profile = "component-comparison-main-ui"
        text = self.profile_log(profile)
        names = gate.PROFILES[profile][1]["PlannerUITests.ComponentComparisonModelTests"]
        for index, name in enumerate(names):
            text = text.replace(f"-[PlannerUITests.ComponentComparisonModelTests {name}]",
                                f"-[UnrelatedTests.Padding testPlaceholder{index}]")
        with self.assertRaises(SystemExit) as rejection:
            self.run_profile(profile, text)
        self.assertEqual(rejection.exception.code, 1)

    def test_each_accepted_open_recovery_case_is_required_by_current_comparison_profile(self):
        profile = "component-comparison-current-main-ui"
        text = self.profile_log(profile)
        for name in ("testEditsDuringOpenKeepOriginalDraftAndUnsavedInput",
                     "testLifecycleSaveDuringOpenPersistsLatestEditsToOriginalDraft"):
            # Preserve the successful total and all other method identities;
            # a same-class placeholder cannot stand in for either #181 case.
            replaced = text.replace(f"-[PlannerUITests.DraftLibraryModelTests {name}]",
                                    "-[PlannerUITests.DraftLibraryModelTests testUnrelatedPadding]")
            with self.subTest(missing_method=name), self.assertRaises(SystemExit) as rejection:
                self.run_profile(profile, replaced)
            self.assertEqual(rejection.exception.code, 1)

    def test_padded_stacked_evidence_cannot_qualify_receiving_profile(self):
        for stacked, receiving in (
                ("catalog-details-transfer", "catalog-editor-transfer"),
                ("catalog-details-ui", "catalog-editor-ui"),
                ("catalog-editor-ui", "comparison-catalog-editor-ui"),
                ("catalog-editor-transfer", "quality-catalog-editor-transfer"),
                ("quality-catalog-editor-transfer", "resource-quality-catalog-editor-transfer"),
                ("resource-quality-catalog-editor-transfer", "graph-resource-quality-catalog-editor-transfer"),
                ("catalog-editor-ui", "catalog-source-ui"),
                ("comparison-catalog-editor-ui", "comparison-catalog-source-ui"),
                ("catalog-source-ui", "comparison-catalog-source-ui"),
                ("comparison-catalog-source-ui", "comparison-catalog-source-privacy-ui"),
                ("component-comparison-main-ui", "component-comparison-current-main-ui"),
                ("component-comparison-current-main-ui", "component-comparison-inspection-ui"),
                ("component-comparison-inspection-ui", "local-libraries-comparison-ui")):
            with self.subTest(stacked=stacked):
                self.assertEqual(self.run_profile(stacked, self.profile_log(stacked)), 0)
                padded = self.profile_log(stacked, total=gate.PROFILES[receiving][0])
                with self.assertRaises(SystemExit) as rejection:
                    self.run_profile(receiving, padded)
                self.assertEqual(rejection.exception.code, 1)


if __name__ == "__main__":
    unittest.main()
