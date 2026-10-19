"""Exercise the real reference verifier against disposable local inputs.

Every subprocess runs with normal or optimized Python and the installed reference
dependencies. These checks do not execute Swift or establish native parity.
"""

from copy import deepcopy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


PACKAGE = Path(__file__).resolve().parents[2]
CORPORA = (
    ("catalog", "catalog_vectors"),
    ("quality", "quality_vectors"),
    ("cost", "cost_vectors"),
    ("resource-estimate", "resource_estimate_vectors"),
    ("placement", "placement_vectors"),
)


class VerifyContractChecks(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="transfer-verifier-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "PlannerTransfer"
        self.tools = self.root / "Tools"
        self.tools.mkdir(parents=True)
        for source in (PACKAGE / "Tools").glob("*.py"):
            shutil.copy2(source, self.tools / source.name)
        for relative in ("Sources/PlannerTransfer/Resources",
                         "Tests/PlannerTransferTests/Fixtures"):
            shutil.copytree(PACKAGE / relative, self.root / relative)
        shutil.copy2(PACKAGE / "source-manifest.json", self.root / "source-manifest.json")
        self.resources = self.root / "Sources/PlannerTransfer/Resources"
        self.fixtures = self.root / "Tests/PlannerTransferTests/Fixtures"

    def verify(self, optimized, *, setup=""):
        # -E keeps PYTHONOPTIMIZE/PYTHONPATH from changing either requested mode;
        # -B also makes the read-only input check cover the copied Python tools.
        command = [sys.executable, "-E", "-B", *(["-O"] if optimized else [])]
        verifier = self.tools / "verify_contract.py"
        if setup:
            command.extend(["-c", (
                "import runpy, sys\nfrom pathlib import Path\n"
                f"sys.path.insert(0, {str(self.tools)!r})\n"
                f"{setup}\n"
                f"runpy.run_path({str(verifier)!r}, run_name='__main__')\n"
            )])
        else:
            command.append(str(verifier))
        return subprocess.run(command, cwd=self.root, capture_output=True,
                              text=True, encoding="utf-8", timeout=30)

    def require_failure(self, result, diagnostic):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(diagnostic, result.stderr)
        self.assertNotIn("Verified ", result.stdout)

    def require_success(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        lines = result.stdout.splitlines()
        self.assertEqual(len(lines), 6, result.stdout)
        for line, expected in zip(lines, (
            "Verified 12 source hashes and 129 canonical conformance cases.",
            "Verified all 29 catalog kinds and 1635 canonical catalog cases;",
            "Verified 202 canonical quality cases;",
            "Verified 520 canonical cost cases;",
            "Verified 223 canonical resource estimate cases;",
            "Verified 98 canonical placement cases:",
        )):
            self.assertTrue(line.startswith(expected), line)

    def fixture(self, corpus):
        return self.fixtures / (corpus + "-conformance.json")

    def consistent_expectation_setup(self, corpus, module):
        # Let an intentionally changed expectation reach the real schema check.
        # Only generation freshness is controlled here; validation is never mocked.
        return (f"import {module}\n"
                f"{module}.encoded_vectors = lambda: "
                f"Path({str(self.fixture(corpus))!r}).read_text(encoding='utf-8')")

    def test_valid_corpora_succeed_in_both_modes_without_writing_inputs(self):
        def snapshot():
            return {str(path.relative_to(self.root)): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in self.root.rglob("*") if path.is_file()}

        original = snapshot()
        for optimized in (False, True):
            with self.subTest(optimized=optimized):
                self.require_success(self.verify(optimized))
                self.assertEqual(snapshot(), original)

    def test_each_required_format_is_checked_before_success(self):
        for format_name in ("date-time", "uri"):
            for optimized in (False, True):
                with self.subTest(format=format_name, optimized=optimized):
                    result = self.verify(optimized, setup=(
                        "from jsonschema import FormatChecker\n"
                        f"FormatChecker.checkers.pop({format_name!r}, None)"
                    ))
                    self.require_failure(result, "Install Tools/requirements.txt")

    def test_every_source_pin_rejects_changed_bytes(self):
        manifest = json.loads((self.root / "source-manifest.json").read_text())
        for source in manifest["files"]:
            target = (self.fixtures if source.startswith("examples/") else self.resources) / Path(source).name
            original = target.read_bytes()
            target.write_bytes(original + b"\n")
            try:
                for optimized in (False, True):
                    with self.subTest(source=source, optimized=optimized):
                        self.require_failure(self.verify(optimized), source)
            finally:
                target.write_bytes(original)

    def test_canonical_conformance_expectations_are_checked(self):
        path = self.fixtures / "conformance.json"
        cases = json.loads(path.read_text())
        cases[0]["valid"] = not cases[0]["valid"]
        path.write_text(json.dumps(cases), encoding="utf-8")
        for optimized in (False, True):
            with self.subTest(optimized=optimized):
                self.require_failure(self.verify(optimized), cases[0]["name"])

    def test_every_generated_corpus_rejects_stale_bytes(self):
        for corpus, _ in CORPORA:
            path = self.fixture(corpus)
            original = path.read_bytes()
            path.write_bytes(original + b"\n")
            try:
                for optimized in (False, True):
                    with self.subTest(corpus=corpus, optimized=optimized):
                        self.require_failure(self.verify(optimized), "Stale " + corpus.replace("-", " "))
            finally:
                path.write_bytes(original)

    def test_standalone_vector_checks_reject_stale_bytes_in_both_modes(self):
        for corpus, module in CORPORA:
            if corpus == "resource-estimate":
                continue  # This generator emits JSON; it has no check command.
            path = self.fixture(corpus)
            original = path.read_bytes()
            for optimized in (False, True):
                with self.subTest(corpus=corpus, optimized=optimized):
                    command = [sys.executable, "-E", "-B", *(["-O"] if optimized else []),
                               str(self.tools / (module + ".py"))]
                    valid = subprocess.run(command, cwd=self.root, capture_output=True,
                                           text=True, encoding="utf-8", timeout=10)
                    self.assertEqual(valid.returncode, 0, valid.stderr)
                    self.assertIn("deterministic generation verified.", valid.stdout)
                    path.write_bytes(original + b"\n")
                    try:
                        stale = subprocess.run(command, cwd=self.root, capture_output=True,
                                               text=True, encoding="utf-8", timeout=10)
                        self.assertNotEqual(stale.returncode, 0, stale.stdout)
                        self.assertIn("vectors are stale", stale.stderr)
                        self.assertNotIn("deterministic generation verified.", stale.stdout)
                        self.assertEqual(path.read_bytes(), original + b"\n")
                    finally:
                        path.write_bytes(original)

    def test_every_generated_corpus_executes_canonical_parity(self):
        for corpus, module in CORPORA:
            path = self.fixture(corpus)
            original = path.read_bytes()
            cases = json.loads(original)
            cases[0]["canonicalValid"] = not cases[0]["canonicalValid"]
            if corpus == "placement":
                # Keep client parity consistent to isolate the canonical check.
                cases[0]["clientValid"] = cases[0]["canonicalValid"]
            path.write_text(json.dumps(cases), encoding="utf-8")
            try:
                for optimized in (False, True):
                    with self.subTest(corpus=corpus, optimized=optimized):
                        result = self.verify(optimized, setup=self.consistent_expectation_setup(corpus, module))
                        self.require_failure(result, cases[0]["name"])
            finally:
                path.write_bytes(original)

    def test_duplicate_catalog_kind_is_rejected_after_hash_verification(self):
        path = self.fixtures / "catalog.json"
        catalog = json.loads(path.read_text())
        catalog["items"].append(deepcopy(catalog["items"][0]))
        path.write_text(json.dumps(catalog), encoding="utf-8")
        # Rebind this disposable fixture so the independent identity guard runs.
        manifest_path = self.root / "source-manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["files"]["examples/catalog.json"] = hashlib.sha256(path.read_bytes()).hexdigest()
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        for optimized in (False, True):
            with self.subTest(optimized=optimized):
                self.require_failure(self.verify(optimized), "catalog")

    def test_placement_client_parity_is_checked(self):
        path = self.fixture("placement")
        cases = json.loads(path.read_text())
        cases[0]["clientValid"] = not cases[0]["clientValid"]
        path.write_text(json.dumps(cases), encoding="utf-8")
        for optimized in (False, True):
            with self.subTest(optimized=optimized):
                result = self.verify(optimized, setup=self.consistent_expectation_setup("placement", "placement_vectors"))
                self.require_failure(result, cases[0]["name"])

    def test_valid_recovery_after_a_late_failure(self):
        path = self.fixture("placement")
        original = path.read_bytes()
        for optimized in (False, True):
            with self.subTest(optimized=optimized):
                path.write_bytes(original + b"\n")
                self.require_failure(self.verify(optimized), "Stale placement vectors")
                path.write_bytes(original)
                self.require_success(self.verify(optimized))


if __name__ == "__main__":
    unittest.main()
