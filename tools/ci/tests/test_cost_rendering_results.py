"""Synthetic log specimens qualify the receipt parser, never native rendering."""
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "cost_rendering_qualifier", Path(__file__).parents[2] / "cost-rendering" / "qualify.py")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class CostRenderingReceiptTests(unittest.TestCase):
    def log(self, root="Selected tests"):
        lines = [f"Test Suite '{root}' started at 2026-10-18 08:00:00.000."]
        for name in sorted(gate.REQUIRED):
            identity = f"-[{gate.CLASS} {name}]"
            lines += [f"Test Case '{identity}' started.",
                      f"Test Case '{identity}' passed (0.001 seconds)."]
        lines += [f"Test Suite '{root}' passed at 2026-10-18 08:00:00.003.",
                  "\t Executed 3 tests, with 0 failures (0 unexpected) in 0.003 (0.004) seconds"]
        return "\n".join(lines) + "\n"

    def rejected(self, output):
        with self.assertRaises(ValueError):
            gate.require_cost_receipt(output)

    def test_complete_selected_and_all_sessions_keep_their_actual_three_identities(self):
        for root in ("Selected tests", "All tests"):
            gate.require_cost_receipt(self.log(root))
            gate.require_cost_receipt(self.log(root) + "◇ Test run with 0 tests passed after 0.001 seconds.\n")

    def test_empty_compilation_and_success_summary_alone_do_not_prove_execution(self):
        for output in ("", "Compiling CostRenderingTests.swift\n", "\n".join(self.log().splitlines()[-2:])):
            self.rejected(output)

    def test_every_missing_or_replaced_method_fails_even_with_the_same_summary(self):
        for name in gate.REQUIRED:
            text = self.log()
            self.rejected(text.replace(name, "testUnrelatedPassingMethod"))
            self.rejected("\n".join(line for line in text.splitlines() if name not in line))
        self.rejected(self.log().replace(gate.CLASS, "PlannerOtherUITests.CostRenderingTests"))
        self.rejected(self.log().replace(gate.CLASS, "PlannerCostUITests.OtherTests"))

    def test_failed_or_skipped_methods_and_suites_cannot_supply_success(self):
        name = sorted(gate.REQUIRED)[0]
        for status in ("failed", "skipped"):
            self.rejected(self.log().replace(f"{name}]' passed", f"{name}]' {status}"))
            self.rejected(self.log().replace("'Selected tests' passed", f"'Selected tests' {status}"))
            self.rejected(self.log().replace(
                "Test Case ", f"Test Suite 'Other suite' {status} at 2026-10-18 08:00:00.000.\nTest Case ", 1))

    def test_starts_completions_and_case_boundaries_are_unique_and_ordered(self):
        text = self.log()
        first_start, first_finish = text.splitlines()[1:3]
        self.rejected(text.replace(first_start + "\n", "", 1))
        self.rejected(text.replace(first_start, first_start + "\n" + first_start, 1))
        self.rejected(text.replace(first_finish, first_finish + "\n" + first_finish, 1))
        self.rejected(text.replace(first_start + "\n" + first_finish, first_finish + "\n" + first_start, 1))
        self.rejected(first_start + "\n" + text)
        self.rejected(text + first_finish + "\n")
        self.rejected(text.replace("started.", "started in an unknown format", 1))

    def test_extra_sessions_methods_truncation_and_wrong_summaries_are_rejected(self):
        text = self.log()
        self.rejected(text + text)
        self.rejected(text + self.log("All tests"))
        self.rejected(text + "Test Suite 'Selected tests' started\n")
        self.rejected(text + "Test Suite 'All tests' unknown event at 2026-10-18 08:00:00.000.\n")
        self.rejected(text.replace("Test Suite 'Selected tests' passed", "Test Suite 'All tests' passed"))
        self.rejected(text[:text.rfind("\t Executed")])
        self.rejected(text.replace("Executed 3 tests", "Executed 4 tests"))
        self.rejected(text.replace("0 failures", "1 failures"))
        self.rejected(text.replace("(0 unexpected)", "(1 unexpected)"))
        self.rejected(text.replace(" (0.004) seconds", " seconds"))
        extra = (f"Test Case '-[{gate.CLASS} testExtra]' started.\n"
                 f"Test Case '-[{gate.CLASS} testExtra]' passed (0.001 seconds).\n")
        self.rejected(text.replace("Test Suite 'Selected tests' passed", extra + "Test Suite 'Selected tests' passed"))

    def test_cli_reads_the_literal_log_and_rejects_corruption_or_missing_input(self):
        with tempfile.TemporaryDirectory(prefix="cost-receipt-specimens-") as directory:
            path = Path(directory) / "native-shaped.log"
            with patch.object(sys, "argv", ["cost-qualifier", str(path)]), \
                    redirect_stdout(io.StringIO()) as stdout, redirect_stderr(io.StringIO()):
                path.write_text(self.log(), encoding="utf-8")
                self.assertEqual(gate.main(), 0)
                self.assertIn("PASS 3 actual native cost-rendering methods", stdout.getvalue())
                path.write_text(self.log().replace("0 failures", "1 failures"), encoding="utf-8")
                with self.assertRaises(SystemExit) as rejected:
                    gate.main()
                self.assertEqual(rejected.exception.code, 1)
                path.write_bytes(b"\xff")
                with self.assertRaises(SystemExit) as corrupted:
                    gate.main()
                self.assertEqual(corrupted.exception.code, 1)
                path.unlink()
                with self.assertRaises(SystemExit) as missing:
                    gate.main()
                self.assertEqual(missing.exception.code, 1)


if __name__ == "__main__":
    unittest.main()
