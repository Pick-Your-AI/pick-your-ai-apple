"""Synthetic review-output regressions; no dependency is installed or executed."""

from __future__ import annotations

import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "check_dependency_review.py"
SPEC = importlib.util.spec_from_file_location("dependency_review", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
REVIEW = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = REVIEW
SPEC.loader.exec_module(REVIEW)


def dependency(**overrides: object) -> dict[str, object]:
    row: dict[str, object] = {
        "change_type": "added",
        "manifest": "synthetic/requirements.txt",
        "ecosystem": "pip",
        "name": "synthetic-review-fixture",
        "version": "2.0.0",
        "scope": "development",
        "license": "MIT",
        "package_url": "pkg:pypi/synthetic-review-fixture@2.0.0",
        "source_repository_url": None,
        "vulnerabilities": [],
    }
    return {**row, **overrides}


def licenses(**overrides: object) -> dict[str, object]:
    return {"forbidden": [], "unresolved": [], "unlicensed": [], **overrides}


class DependencyReviewTests(unittest.TestCase):
    def test_empty_review_and_safe_addition_are_distinct_accepted_results(self) -> None:
        empty = REVIEW.evaluate([], licenses())
        added = REVIEW.evaluate([dependency()], licenses())
        self.assertTrue(empty.accepted)
        self.assertTrue(added.accepted)
        self.assertEqual((empty.added_dependencies, added.added_dependencies), (0, 1))

    def test_vulnerability_blocks_every_scope_even_at_low_severity(self) -> None:
        for scope in ("runtime", "development", "unknown"):
            with self.subTest(scope=scope):
                row = dependency(scope=scope, vulnerabilities=[{"severity": "low"}])
                result = REVIEW.evaluate([row], licenses())
                self.assertFalse(result.accepted)
                self.assertEqual(result.vulnerable_dependencies, 1)

    def test_disallowed_license_result_cannot_be_overridden_by_no_advisories(self) -> None:
        row = dependency(license="LicenseRef-Synthetic-Unapproved")
        result = REVIEW.evaluate([row], licenses(forbidden=[copy.deepcopy(row)]))
        self.assertFalse(result.accepted)
        self.assertEqual(result.disallowed_licenses, 1)

    def test_each_upstream_invalid_license_category_blocks(self) -> None:
        for category in ("forbidden", "unresolved", "unlicensed"):
            with self.subTest(category=category):
                row = dependency(license=None)
                result = REVIEW.evaluate([row], licenses(**{category: [row]}))
                self.assertFalse(result.accepted)

    def test_raw_null_license_can_be_resolved_by_upstream_license_api(self) -> None:
        row = dependency(license=None)
        del row["scope"]
        self.assertTrue(REVIEW.evaluate([row], licenses()).accepted)

    def test_pinned_contract_fixture_has_complete_clean_and_rejected_categories(self) -> None:
        fixture = json.loads((Path(__file__).with_name("fixtures") / "pinned-action-contract.json").read_text())
        self.assertEqual(fixture["upstream_commit"], "907a6e9569212033966bc0b69d32473b046dd66b")
        for case in fixture["cases"]:
            with self.subTest(case=case["name"]):
                changes = REVIEW.parse_output(json.dumps(case["dependency_changes"]))
                classified = REVIEW.parse_license_output(json.dumps(case["invalid_license_changes"]))
                self.assertEqual(REVIEW.evaluate(changes, classified).accepted, case["accepted"])

    def test_license_parser_rejects_array_missing_categories_and_invalid_category_types(self) -> None:
        cases = [[], {}, {"forbidden": [], "unresolved": []}, licenses(extra=[])]
        for category in ("forbidden", "unresolved", "unlicensed"):
            cases.extend([licenses(**{category: None}), licenses(**{category: {}}), licenses(**{category: [None]})])
        for value in cases:
            with self.subTest(value=value):
                with self.assertRaises(REVIEW.InvalidReview):
                    REVIEW.parse_license_output(json.dumps(value))
        self.assertEqual(REVIEW.parse_license_output(json.dumps(licenses())), licenses())

    def test_urgent_patch_recovery_removes_unsafe_version_and_checks_new_version(self) -> None:
        old = dependency(version="1.0.0", vulnerabilities=[{"severity": "critical"}])
        self.assertFalse(REVIEW.evaluate([old], licenses()).accepted)
        removed = {**old, "change_type": "removed"}
        recovered = REVIEW.evaluate([removed, dependency(version="1.0.1")], licenses())
        self.assertTrue(recovered.accepted)
        self.assertEqual((recovered.added_dependencies, recovered.removed_dependencies), (1, 1))
        still_unsafe = dependency(version="1.0.1", vulnerabilities=[{"severity": "high"}])
        self.assertFalse(REVIEW.evaluate([removed, still_unsafe], licenses()).accepted)

    def test_removal_of_unlicensed_dependency_is_not_blocked(self) -> None:
        result = REVIEW.evaluate([dependency(change_type="removed", license=None)], licenses())
        self.assertTrue(result.accepted)
        self.assertEqual(result.removed_dependencies, 1)

    def test_missing_or_unsupported_evidence_fails(self) -> None:
        mutations = (
            ("change_type", "renamed"), ("change_type", None), ("change_type", []),
            ("scope", None), ("scope", {}),
            ("scope", "production"), ("vulnerabilities", None), ("vulnerabilities", {}),
            ("name", ""), ("version", None), ("manifest", 1), ("ecosystem", " "),
        )
        for key, value in mutations:
            with self.subTest(key=key, value=value):
                with self.assertRaises(REVIEW.InvalidReview):
                    REVIEW.evaluate([dependency(**{key: value})], licenses())

    def test_parser_rejects_missing_malformed_nonarray_and_duplicate_key_output(self) -> None:
        for text in (None, "", " ", "{", "{}", "null", "[null]", '[{"x":NaN}]',
                     '[{"x":Infinity}]', '[{"license":"MIT","license":null}]'):
            with self.subTest(text=text):
                with self.assertRaises(REVIEW.InvalidReview):
                    REVIEW.parse_output(text)
        self.assertEqual(REVIEW.parse_output("[]"), [])

    def test_parser_rejects_excess_bytes_and_excessive_nesting(self) -> None:
        with self.assertRaises(REVIEW.InvalidReview):
            REVIEW.parse_output(" " * REVIEW.MAXIMUM_OUTPUT_BYTES + "[]")
        with self.assertRaises(REVIEW.InvalidReview):
            REVIEW.parse_output("[" * 2_000 + "]" * 2_000)

    def test_cli_rejects_missing_secondary_evidence_and_does_not_echo_payload(self) -> None:
        marker = "PRIVATE-SYNTHETIC-MARKER-DO-NOT-ECHO"
        env = {key: value for key, value in os.environ.items() if key not in {
            "DEPENDENCY_CHANGES", "INVALID_LICENSE_CHANGES"
        }}
        env["DEPENDENCY_CHANGES"] = json.dumps([dependency(name=marker)])
        env["DEPENDENCY_REVIEW_OUTCOME"] = "success"
        env["DEPENDENCY_SNAPSHOT_OUTCOME"] = "success"
        missing = subprocess.run([sys.executable, str(SCRIPT)], env=env, capture_output=True, text=True)
        self.assertEqual(missing.returncode, 1)
        self.assertNotIn(marker, missing.stdout + missing.stderr)
        env["INVALID_LICENSE_CHANGES"] = json.dumps(licenses())
        safe = subprocess.run([sys.executable, str(SCRIPT)], env=env, capture_output=True, text=True)
        self.assertEqual(safe.returncode, 0)
        self.assertTrue(json.loads(safe.stdout)["accepted"])
        self.assertNotIn(marker, safe.stdout + safe.stderr)
        env["DEPENDENCY_CHANGES"] = json.dumps([dependency(name=marker, license=None)])
        env["INVALID_LICENSE_CHANGES"] = json.dumps(licenses(unlicensed=[dependency(name=marker, license=None)]))
        rejected = subprocess.run([sys.executable, str(SCRIPT)], env=env, capture_output=True, text=True)
        self.assertEqual(rejected.returncode, 1)
        self.assertFalse(json.loads(rejected.stdout)["accepted"])
        self.assertNotIn(marker, rejected.stdout + rejected.stderr)


if __name__ == "__main__":
    unittest.main()
