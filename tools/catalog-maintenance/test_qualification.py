"""Negative receipt controls. These synthetic specimens are not Swift execution."""
import base64
import copy
from contextlib import nullcontext, redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("maintenance_driver", HERE / "run.py")
DRIVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DRIVER)


def specimen():
    raw = (HERE / "Sources/MaintenanceDrill/Fixtures/build-a.json").read_bytes()
    build = json.loads(raw)
    selected = next(x for x in build["selections"] if x["catalog_item_id"] == "cat.compute_profile.fixture")
    baseline = {"component_id": selected["catalog_item_id"],
                "component_version": selected["catalog_item_version"],
                "catalog_snapshot_id": build["locks"]["catalog_snapshot_id"],
                "display_grade": "independentlyVerified", "original_status": "verified",
                "review_requirement": "none"}
    draft = {"payload_base64": base64.b64encode(raw).decode(), "revision": 1,
             "analysis_is_current": False}
    neighbour = dict(draft, payload_base64=base64.b64encode(b'{"synthetic":"unrelated"}').decode())
    results = []
    for phase in ("seed", "maintain", "reopen"):
        warnings = []
        if phase != "seed":
            for event in ("correction", "retraction", "later-notices", "unrelated-retraction"):
                changed = event != "unrelated-retraction"
                warnings.append(dict(baseline, event=event,
                                     display_grade="unverified" if changed else "independentlyVerified",
                                     review_requirement="recheckRequired" if changed else "none"))
        results.append({"format": 1, "classification": "synthetic-only", "status": "passed",
                        "mode": "portable", "phase": phase, "draft": copy.deepcopy(draft),
                        "history": [copy.deepcopy(draft)], "neighbour": copy.deepcopy(neighbour),
                        "neighbour_history": [copy.deepcopy(neighbour)], "baseline": copy.deepcopy(baseline),
                        "warnings": warnings,
                        "catalog_cache": {"status": "unexecuted",
                                          "reason": "portable-scope-does-not-emulate-CryptoKit"}})
    return results, {"build-a.json": raw}


def native_specimen():
    """Closed parser specimens, never a claimed native execution."""
    results, inputs = specimen()
    for name in ("catalog-a.json", "pricebook-a.json", "catalog-b.json", "pricebook-b.json"):
        inputs[name] = (HERE / "Sources/MaintenanceDrill/Fixtures" / name).read_bytes()

    def record(version):
        pins = []
        value = {"is_synthetic": True, "cached_at": 1792141200 if version == "a" else 1792227600}
        for kind in ("catalog", "pricebook"):
            raw = inputs[f"{kind}-{version}.json"]
            parsed = json.loads(raw)
            pins.append({"kind": kind, "sha256": DRIVER.digest(raw),
                         "identity": {key: parsed[key] for key in
                                      ("schema_version", "id", "revision", "captured_at")}})
            value[f"{kind}_base64"] = base64.b64encode(raw).decode()
        value["manifest"] = {"pins": pins}
        return value

    for value in results:
        phase = value["phase"]
        value["mode"] = "native"
        value["catalog_cache"] = {
            "status": "passed", "current_checks": "unknown",
            "controls": (["pricebook-download-failure", "cancelled-second-artifact", "production-denied"]
                         if phase == "maintain" else ["production-denied"]),
            "active": record("a" if phase == "seed" else "b"), "retained": record("a")}
    return results, inputs


class QualificationTests(unittest.TestCase):
    def test_complete_scoped_specimen_and_missing_or_duplicate_process(self):
        results, inputs = specimen()
        receipt = DRIVER.qualify_history("portable", results, inputs)
        self.assertFalse(receipt["rendered_ui"])
        for bad in (results[:2], [results[0], results[1], results[1]]):
            with self.assertRaises(DRIVER.QualificationError):
                DRIVER.qualify_history("portable", bad, inputs)

    def test_reopened_payload_or_historical_revision_rewrite_fails(self):
        for key in ("draft", "history"):
            results, inputs = specimen()
            entry = results[2][key] if key == "draft" else results[2][key][0]
            entry["payload_base64"] = base64.b64encode(b'{}').decode()
            with self.assertRaises(DRIVER.QualificationError):
                DRIVER.qualify_history("portable", results, inputs)

    def test_consistently_fabricated_currentness_cannot_pass(self):
        results, inputs = specimen()
        for r in results:
            r["draft"]["analysis_is_current"] = True
            r["history"][0]["analysis_is_current"] = True
        with self.assertRaises(DRIVER.QualificationError):
            DRIVER.qualify_history("portable", results, inputs)

    def test_wrong_target_or_missing_warning_fails(self):
        for operation in ("wrong-target", "missing-warning", "no-recheck"):
            results, inputs = specimen()
            if operation == "wrong-target":
                results[1]["warnings"][0]["component_version"] = "different"
            elif operation == "missing-warning":
                results[1]["warnings"].pop()
            else:
                results[1]["warnings"][1]["review_requirement"] = "none"
            with self.assertRaises(DRIVER.QualificationError):
                DRIVER.qualify_history("portable", results, inputs)

    def test_portable_output_cannot_claim_cache_execution(self):
        results, inputs = specimen()
        results[2]["catalog_cache"] = {"status": "passed"}
        with self.assertRaises(DRIVER.QualificationError):
            DRIVER.qualify_history("portable", results, inputs)
        results, inputs = specimen()
        with self.assertRaises(DRIVER.QualificationError):
            DRIVER.qualify_history("native", results, inputs)

    def test_byte_distinct_target_control_is_mandatory(self):
        good = {"format": 1, "classification": "synthetic-only", "status": "passed",
                "phase": "exact-target", "mode": "portable", "target_version_utf8": [195, 169],
                "other_version_utf8": [101, 204, 129], "observed": {"review_requirement": "none"}}
        DRIVER.qualify_target(good, "portable")
        for key, value in (("status", "failed"), ("other_version_utf8", [195, 169]),
                           ("observed", {"review_requirement": "recheckRequired"})):
            with self.assertRaises(DRIVER.QualificationError):
                DRIVER.qualify_target(dict(good, **{key: value}), "portable")


class NativeQualificationTests(unittest.TestCase):
    def test_native_requires_actual_recovery_denial_and_unknown_controls(self):
        results, inputs = native_specimen()
        self.assertEqual(DRIVER.qualify_history("native", results, inputs)["original_processes"], 3)
        for key, value in (("controls", ["production-denied"]),
                           ("controls", ["pricebook-download-failure", "cancelled-second-artifact"]),
                           ("current_checks", "passed"), ("status", "unexecuted")):
            with self.subTest(key=key, value=value):
                results, inputs = native_specimen()
                results[1]["catalog_cache"][key] = value
                with self.assertRaises(DRIVER.QualificationError):
                    DRIVER.qualify_history("native", results, inputs)

    def test_native_rejects_duplicate_missing_or_wrong_identity_pins(self):
        for operation in ("duplicate", "missing", "wrong-identity"):
            with self.subTest(operation=operation):
                results, inputs = native_specimen()
                pins = results[1]["catalog_cache"]["active"]["manifest"]["pins"]
                if operation == "duplicate":
                    pins.append(copy.deepcopy(pins[0]))
                elif operation == "missing":
                    pins.pop()
                else:
                    pins[0]["identity"]["revision"] = "unrelated"
                with self.assertRaises(DRIVER.QualificationError):
                    DRIVER.qualify_history("native", results, inputs)

    def test_native_rejects_mixed_releases_rewritten_history_and_tampered_bytes(self):
        for operation in ("mixed-active", "rewritten-retained", "bytes", "digest", "synthetic"):
            with self.subTest(operation=operation):
                results, inputs = native_specimen()
                cache = results[2]["catalog_cache"]
                if operation == "mixed-active":
                    cache["active"] = copy.deepcopy(results[0]["catalog_cache"]["active"])
                elif operation == "rewritten-retained":
                    cache["retained"] = copy.deepcopy(cache["active"])
                elif operation == "bytes":
                    cache["active"]["catalog_base64"] = base64.b64encode(b'{}').decode()
                elif operation == "digest":
                    cache["active"]["manifest"]["pins"][0]["sha256"] = "0" * 64
                else:
                    cache["active"]["is_synthetic"] = False
                with self.assertRaises(DRIVER.QualificationError):
                    DRIVER.qualify_history("native", results, inputs)


class JSONIdentityQualificationTests(unittest.TestCase):
    def test_single_native_pin_boolean_revision_cannot_alias_exact_fixture(self):
        results, inputs = native_specimen()
        original = inputs["catalog-a.json"]
        record = results[0]["catalog_cache"]["active"]
        pin = record["manifest"]["pins"][0]
        self.assertEqual(json.loads(original)["revision"], 1)
        pin["identity"]["revision"] = True
        observed = json.loads(json.dumps(results))
        self.assertIs(observed[0]["catalog_cache"]["active"]["manifest"]["pins"][0]
                      ["identity"]["revision"], True)
        self.assertEqual(base64.b64decode(record["catalog_base64"]), original)
        self.assertEqual(pin["sha256"], DRIVER.digest(original))
        with self.assertRaises(DRIVER.QualificationError):
            DRIVER.qualify_history("native", observed, inputs)

    def test_consistent_boolean_saved_and_history_revisions_fail_in_both_modes(self):
        for mode in ("portable", "native"):
            for record_key, history_key in (("draft", "history"), ("neighbour", "neighbour_history")):
                with self.subTest(mode=mode, record=record_key):
                    results, inputs = native_specimen() if mode == "native" else specimen()
                    for phase in results:
                        phase[record_key]["revision"] = True
                        phase[history_key][0]["revision"] = True
                    with self.assertRaises(DRIVER.QualificationError):
                        DRIVER.qualify_history(mode, json.loads(json.dumps(results)), inputs)

    def test_each_original_history_phase_requires_a_numeric_format(self):
        for mode in ("portable", "native"):
            for index in range(3):
                with self.subTest(mode=mode, phase=index):
                    results, inputs = native_specimen() if mode == "native" else specimen()
                    results[index]["format"] = True
                    with self.assertRaises(DRIVER.QualificationError):
                        DRIVER.qualify_history(mode, json.loads(json.dumps(results)), inputs)

    def test_exact_target_format_keeps_numbers_distinct_from_booleans(self):
        for mode in ("portable", "native"):
            good = {"format": 1, "classification": "synthetic-only", "status": "passed",
                    "phase": "exact-target", "mode": mode, "target_version_utf8": [195, 169],
                    "other_version_utf8": [101, 204, 129], "observed": {"review_requirement": "none"}}
            for value in (1, 1.0):
                with self.subTest(mode=mode, number=value):
                    DRIVER.qualify_target(json.loads(json.dumps(dict(good, format=value))), mode)
            for value in (True, False):
                with self.subTest(mode=mode, boolean=value):
                    with self.assertRaises(DRIVER.QualificationError):
                        DRIVER.qualify_target(json.loads(json.dumps(dict(good, format=value))), mode)

    def test_integral_numeric_history_and_pin_observations_remain_valid(self):
        for mode in ("portable", "native"):
            operations = ("format", "saved-records", "pins") if mode == "native" else ("format", "saved-records")
            for operation in operations:
                with self.subTest(mode=mode, operation=operation):
                    results, inputs = native_specimen() if mode == "native" else specimen()
                    for phase in results:
                        if operation == "format":
                            phase["format"] = 1.0
                        elif operation == "saved-records":
                            for record in (phase["draft"], phase["history"][0], phase["neighbour"],
                                           phase["neighbour_history"][0]):
                                record["revision"] = 1.0
                        else:
                            for record in (phase["catalog_cache"]["active"], phase["catalog_cache"]["retained"]):
                                for pin in record["manifest"]["pins"]:
                                    pin["identity"]["revision"] = float(pin["identity"]["revision"])
                    receipt = DRIVER.qualify_history(mode, json.loads(json.dumps(results)), inputs)
                    self.assertEqual(receipt["original_processes"], 3)
                    self.assertFalse(receipt["rendered_ui"])

    def test_nested_history_cannot_alias_boolean_currentness_with_numeric_zero(self):
        for mode in ("portable", "native"):
            for history_key in ("history", "neighbour_history"):
                with self.subTest(mode=mode, history=history_key):
                    results, inputs = native_specimen() if mode == "native" else specimen()
                    for phase in results:
                        phase[history_key][0]["analysis_is_current"] = 0
                    # Saved records still have the required Boolean false; only their
                    # corresponding historical observations have a different JSON type.
                    self.assertIs(results[0]["draft"]["analysis_is_current"], False)
                    self.assertIs(results[0]["neighbour"]["analysis_is_current"], False)
                    with self.assertRaises(DRIVER.QualificationError):
                        DRIVER.qualify_history(mode, json.loads(json.dumps(results)), inputs)

    def test_nonintegral_or_text_numeric_identities_remain_rejected(self):
        for mode in ("portable", "native"):
            operations = ("format", "saved-records", "pins") if mode == "native" else ("format", "saved-records")
            for operation in operations:
                for invalid in (1.5, "1", None):
                    with self.subTest(mode=mode, operation=operation, invalid=invalid):
                        results, inputs = native_specimen() if mode == "native" else specimen()
                        for phase in results:
                            if operation == "format":
                                phase["format"] = invalid
                            elif operation == "saved-records":
                                phase["draft"]["revision"] = invalid
                                phase["history"][0]["revision"] = invalid
                            else:
                                phase["catalog_cache"]["retained"]["manifest"]["pins"][0]["identity"]["revision"] = invalid
                        with self.assertRaises(DRIVER.QualificationError):
                            DRIVER.qualify_history(mode, json.loads(json.dumps(results)), inputs)


class ProducerJSONQualificationTests(unittest.TestCase):
    """Actual driver entry point with synthetic responses, never Swift execution."""

    def exercise(self, mode, change=None, *, returncode=0, timed_out=False, source_changed=False):
        phases, inputs = native_specimen() if mode == "native" else specimen()
        phases.append({"format": 1, "classification": "synthetic-only", "status": "passed",
                       "phase": "exact-target", "mode": mode, "target_version_utf8": [195, 169],
                       "other_version_utf8": [101, 204, 129], "observed": {"review_requirement": "none"}})
        responses = {value["phase"]: json.dumps(value, separators=(",", ":")).encode()
                     for value in phases}
        if change is not None:
            change(responses)
        stderr = b"synthetic process diagnostic\n"
        calls = []

        def observe(command, **kwargs):
            calls.append(command)
            self.assertEqual(kwargs, {"capture_output": True, "timeout": 40, "check": False})
            raw = responses[command[2]]
            if timed_out:
                raise subprocess.TimeoutExpired(command, 40, output=raw, stderr=stderr)
            return subprocess.CompletedProcess(command, returncode, raw, stderr)

        source_guard = nullcontext()
        if source_changed:
            before = DRIVER.source_hashes()
            after = dict(before, synthetic_changed_source="different")
            source_guard = patch.object(DRIVER, "source_hashes", side_effect=[before, after, after])
        with tempfile.TemporaryDirectory(prefix="maintenance-parser-test-") as temporary:
            output = Path(temporary) / "observations"
            argv = ["run.py", "--contracts", temporary, "--executable", sys.executable,
                    "--mode", mode, "--output", str(output)]
            # Only the canonical fixture preflight and process responses are replaced.
            # The actual driver retains/qualifies bytes and checks its source inventory.
            with patch.object(DRIVER, "fixtures", return_value=inputs), \
                    patch.object(DRIVER.subprocess, "run", side_effect=observe), \
                    patch.object(sys, "argv", argv), source_guard, redirect_stdout(io.StringIO()):
                result = DRIVER.main()
            receipt = json.loads((output / "receipt.json").read_bytes())
            retained = {path.name: path.read_bytes() for path in output.iterdir() if path.is_file()}
        return {"exit": result, "receipt": receipt, "retained": retained,
                "responses": responses, "calls": calls, "stderr": stderr}

    def rejected_at(self, observed, phase, reason):
        self.assertEqual(observed["exit"], 1)
        receipt = observed["receipt"]
        self.assertEqual(receipt["status"], "failed")
        self.assertEqual(receipt["failure"], reason)
        self.assertIs(receipt["full_rehearsal_qualified"], False)
        expected = list(DRIVER.PHASES[:DRIVER.PHASES.index(phase) + 1])
        self.assertEqual([command[2] for command in observed["calls"]], expected)
        self.assertEqual([entry["argv"][2] for entry in receipt["commands"]], expected)
        self.assertEqual(receipt["source_inputs"], receipt["source_after"])
        raw = observed["responses"][phase]
        self.assertEqual(observed["retained"][phase + ".stdout.json"], raw)
        self.assertEqual(observed["retained"][phase + ".stderr.log"], observed["stderr"])
        self.assertEqual(receipt["commands"][-1]["stdout_sha256"], DRIVER.digest(raw))
        self.assertEqual(receipt["commands"][-1]["stderr_sha256"], DRIVER.digest(observed["stderr"]))

    def test_duplicate_status_is_rejected_in_every_original_phase(self):
        for mode in ("portable", "native"):
            for phase in DRIVER.PHASES:
                with self.subTest(mode=mode, phase=phase):
                    def change(responses):
                        responses[phase] = responses[phase].replace(
                            b'"status":"passed"', b'"status":"failed","status":"passed"', 1)
                    self.rejected_at(self.exercise(mode, change), phase, "duplicate producer JSON member")

    def test_nested_history_and_cache_identity_duplicates_are_rejected(self):
        for mode in ("portable", "native"):
            replacements = [(b'"history":[{', b'"history":[{"analysis_is_current":true,')]
            if mode == "native":
                replacements.append((b'"identity":{', b'"identity":{"revision":true,'))
            for before, after in replacements:
                with self.subTest(mode=mode, nested=before):
                    def change(responses):
                        self.assertIn(before, responses["reopen"])
                        responses["reopen"] = responses["reopen"].replace(before, after, 1)
                    self.rejected_at(self.exercise(mode, change), "reopen", "duplicate producer JSON member")

    def test_escaped_names_and_equal_duplicate_values_are_rejected(self):
        for mode in ("portable", "native"):
            for first in (b'"sta\\u0074us":"failed",', b'"status":"passed",'):
                with self.subTest(mode=mode, first=first):
                    def change(responses):
                        responses["seed"] = responses["seed"].replace(
                            b'"status":"passed"', first + b'"status":"passed"', 1)
                    self.rejected_at(self.exercise(mode, change), "seed", "duplicate producer JSON member")

    def test_ignored_deep_duplicates_fail_with_value_free_diagnostics(self):
        for mode in ("portable", "native"):
            with self.subTest(mode=mode):
                def change(responses):
                    responses["seed"] = responses["seed"][:-1] + (
                        b',"extra":{"items":[{"private-fixture-marker":1,"private-fixture-marker":2}]}}')
                observed = self.exercise(mode, change)
                self.rejected_at(observed, "seed", "duplicate producer JSON member")
                self.assertIsNone(observed["receipt"]["history_qualification"])
                self.assertNotIn("private-fixture-marker", observed["receipt"]["failure"])

    def test_nonstandard_constants_in_ignored_nested_fields_are_rejected(self):
        for mode in ("portable", "native"):
            for constant in (b"NaN", b"Infinity", b"-Infinity"):
                with self.subTest(mode=mode, constant=constant):
                    def change(responses):
                        responses["exact-target"] = responses["exact-target"][:-1] + (
                            b',"extra":{"items":[' + constant + b']}}')
                    self.rejected_at(self.exercise(mode, change), "exact-target",
                                     "nonstandard producer JSON constant")

    def test_valid_distinct_names_strings_and_numeric_identity_still_qualify(self):
        for mode in ("portable", "native"):
            with self.subTest(mode=mode):
                def change(responses):
                    for phase, raw in responses.items():
                        value = json.loads(raw)
                        value["format"] = 1.0
                        value["extra"] = {"first": {"same": 1}, "second": {"same": 2},
                                          "\u00e9": True, "e\u0301": False,
                                          "text": 'NaN Infinity -Infinity "status":"failed","status":"passed"'}
                        responses[phase] = json.dumps(value, separators=(",", ":")).encode()
                observed = self.exercise(mode, change)
                self.assertEqual(observed["exit"], 0)
                receipt = observed["receipt"]
                self.assertEqual(receipt["status"], "passed")
                self.assertEqual([entry["argv"][2] for entry in receipt["commands"]], list(DRIVER.PHASES))
                self.assertEqual(receipt["source_inputs"], receipt["source_after"])
                # This flag is asserted only for a mocked native specimen, not host evidence.
                self.assertIs(receipt["full_rehearsal_qualified"], mode == "native")
                self.assertFalse(receipt["history_qualification"]["physical_device"])
                for phase in DRIVER.PHASES:
                    self.assertEqual(observed["retained"][phase + ".stdout.json"], observed["responses"][phase])
                    self.assertEqual(observed["retained"][phase + ".stderr.log"], observed["stderr"])

        # These are raw producer tokens, not floats rounded by the test writer.
        for mode in ("portable", "native"):
            for token in (b"1.0", b"1e0", b"0.1e1", b"1.0000000000000000"):
                with self.subTest(mode=mode, integral_token=token):
                    def change(responses):
                        for phase, raw in responses.items():
                            raw = raw.replace(b'"format":1,', b'"format":' + token + b',', 1)
                            responses[phase] = raw.replace(b'"revision":1,', b'"revision":' + token + b',')
                    observed = self.exercise(mode, change)
                    self.assertEqual(observed["exit"], 0)
                    self.assertEqual(observed["receipt"]["status"], "passed")
                    self.assertIs(observed["receipt"]["full_rehearsal_qualified"], mode == "native")
                    for phase in DRIVER.PHASES:
                        self.assertEqual(observed["retained"][phase + ".stdout.json"], observed["responses"][phase])

    def test_ordinary_failed_and_malformed_observations_remain_rejected(self):
        for mode in ("portable", "native"):
            for scenario in ("failed", "malformed", "second-document"):
                with self.subTest(mode=mode, scenario=scenario):
                    def change(responses):
                        if scenario == "failed":
                            responses["seed"] = responses["seed"].replace(b'"status":"passed"', b'"status":"failed"', 1)
                        else:
                            responses["seed"] = b'{' if scenario == "malformed" else responses["seed"] + b'{}'
                    observed = self.exercise(mode, change)
                    self.assertEqual(observed["exit"], 1)
                    self.assertEqual(observed["receipt"]["status"], "failed")
                    self.assertIs(observed["receipt"]["full_rehearsal_qualified"], False)
                    self.assertEqual(len(observed["calls"]), 3 if scenario == "failed" else 1)
                    self.assertEqual(observed["retained"]["seed.stdout.json"], observed["responses"]["seed"])

        for mode in ("portable", "native"):
            for phase in DRIVER.PHASES:
                for token in (b"1.0000000000000001", b"0.99999999999999999", b"10000000000000001e-16"):
                    with self.subTest(mode=mode, phase=phase, fractional_token=token):
                        def change(responses):
                            responses[phase] = responses[phase].replace(
                                b'"format":1,', b'"format":' + token + b',', 1)
                        stopped_at = "exact-target" if phase == "exact-target" else "reopen"
                        reason = "exact-target original identity" if phase == "exact-target" else "actual phase/mode identity"
                        self.rejected_at(self.exercise(mode, change), stopped_at, reason)

            for token in (b"1.0000000000000001", b"0.99999999999999999"):
                with self.subTest(mode=mode, fractional_revision=token):
                    def change(responses):
                        for phase in DRIVER.PHASES[:3]:
                            responses[phase] = responses[phase].replace(
                                b'"revision":1,', b'"revision":' + token + b',')
                    self.rejected_at(self.exercise(mode, change), "reopen", "actual saved bytes and currentness")

    def test_output_budget_failed_exit_and_timeout_still_precede_json_admission(self):
        for scenario in ("budget", "exit", "timeout"):
            with self.subTest(scenario=scenario):
                def change(responses):
                    responses["seed"] = (b"x" * 1_048_577 if scenario == "budget"
                                         else b'{"status":"failed","status":"passed"}')
                observed = self.exercise("portable", change, returncode=3 if scenario == "exit" else 0,
                                         timed_out=scenario == "timeout")
                self.assertEqual(observed["exit"], 1)
                self.assertIs(observed["receipt"]["full_rehearsal_qualified"], False)
                self.assertEqual(len(observed["calls"]), 1)
                if scenario == "budget":
                    self.assertEqual(observed["receipt"]["failure"], "bounded original output")
                    self.assertEqual(observed["receipt"]["commands"], [])
                    self.assertNotIn("seed.stdout.json", observed["retained"])
                else:
                    self.rejected_at(observed, "seed", "actual seed failed; retained original is not a pass")
                    self.assertEqual(observed["receipt"]["commands"][0]["exit"], -1 if scenario == "timeout" else 3)
                    self.assertIs(observed["receipt"]["commands"][0]["timed_out"], scenario == "timeout")

    def test_source_change_still_precedes_json_admission(self):
        def change(responses):
            responses["seed"] = b'{"status":"failed","status":"passed"}'
        observed = self.exercise("portable", change, source_changed=True)
        self.assertEqual(observed["exit"], 1)
        self.assertEqual(observed["receipt"]["failure"], "source changed")
        self.assertIs(observed["receipt"]["full_rehearsal_qualified"], False)
        self.assertEqual(len(observed["calls"]), 1)
        self.assertEqual(observed["retained"]["seed.stdout.json"], observed["responses"]["seed"])
        self.assertNotEqual(observed["receipt"]["source_inputs"], observed["receipt"]["source_after"])


if __name__ == "__main__":
    unittest.main()
