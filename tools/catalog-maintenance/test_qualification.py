"""Negative receipt controls. These synthetic specimens are not Swift execution."""
import base64
import copy
import importlib.util
import json
from pathlib import Path
import unittest

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


if __name__ == "__main__":
    unittest.main()
