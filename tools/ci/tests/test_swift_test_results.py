"""Presentation-only log specimens test the gate, not Swift or native behavior."""
import importlib.util
from pathlib import Path
import unittest


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


if __name__ == "__main__":
    unittest.main()
