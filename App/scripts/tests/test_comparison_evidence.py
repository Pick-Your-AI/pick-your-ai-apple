"""Adversarial filesystem/CLI evidence checks; these are not native journeys."""
import copy
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

SCRIPT = Path(__file__).resolve().parents[1] / "require_comparison_evidence.py"
SPEC = importlib.util.spec_from_file_location("comparison_evidence", SCRIPT)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)
RUNNER_SPEC = importlib.util.spec_from_file_location("comparison_journey_runner", SCRIPT.with_name("ui-journey.py"))
runner = importlib.util.module_from_spec(RUNNER_SPEC)
RUNNER_SPEC.loader.exec_module(runner)


def png(width=375, height=667):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\x00" + b"\xff\xff\xff" * width) * height)) + chunk(b"IEND", b""))


def movie():
    def box(kind, data):
        return struct.pack(">I", len(data) + 8) + kind + data
    # Container specimen only: neither this fake media payload nor its passing
    # parser result claims to be a playable recording or native UI evidence.
    return box(b"ftyp", b"isom\x00\x00\x00\x00") + box(b"moov", b"synthetic") + box(b"mdat", b"synthetic")


def matrix(scenario, device="iphone"):
    result = {
        "schema_version": 1, "scenario": scenario, "fixture_sha256": gate.FIXTURE_HASH,
        "catalog_id": "catalog.comparison.examples.v1", "catalog_revision": 1,
        "captured_at": "2026-10-19T00:00:00Z", "device": device,
        "layout": "componentComparisonAlignedFields" if device == "ipad" and scenario == "default" else "componentComparisonStackedFields",
        "dynamic_type": "accessibility3-subtree" if scenario == "accessibility3" else "system-default",
        "selected": gate.selected([1, 2, 3, 4]), "recovered": gate.selected([1, 3, 4, 5]),
        "disk_gb": gate.cells([gate.RECORDED, gate.MISSING, gate.NA, gate.NA], ["0", None, None, None]),
        "network_gbps": gate.cells([gate.MISSING, gate.RECORDED, gate.NA, gate.NA], [None, "0", None, None]),
        "region": gate.cells([gate.RECORDED, gate.RECORDED, "Unknown: explicitly recorded as unknown", "Unknown: empty text recorded"],
                             ['"fixture-east"', '"fixture-west"', '"unknown"', '""']),
        "conditions": [], "final_count": "Compare selected components (0 of 4)", "query": "FICTIONAL",
        "kind_sort_selected": True, "active_kinds": "Compute Profile, Storage",
        "accessibility_audits": ["visible-field-navigation:hitRegion,sufficientElementDescription",
                                 "visible-conditions:textClipped,sufficientElementDescription",
                                 "visible-empty-controls:hitRegion,sufficientElementDescription"],
    }
    for index, unit in enumerate(["milliseconds/request", "seconds/request", "tokens/second", "requests/second"]):
        result["conditions"].append({
            "amount": 1000 if index == 0 else 1, "unit": unit,
            "region": ["fixture-east", "fixture-west", "unknown", ""][index],
            "offering": f"unqualified-fixture-v{index + 1}", "effective_at": "2026-10-19T00:00:00Z",
            "workload": "fictional-128-input-tokens",
            "qualification": "Fictional declaration; no conversion, ranking or rate applicability.",
        })
    return result


class ComparisonEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.attachments = self.root / "attachments"
        self.attachments.mkdir()
        self.log = self.root / "tests.log"
        self.log.write_text("\n".join(f"Test Case '-[PlannerAppUITests.ComponentComparisonJourneyTests {name}]' passed (1.0 seconds)."
                                      for name in gate.METHODS) + "\n")
        self.manifest = []
        for index, (name, scenario) in enumerate(gate.METHODS.items()):
            entries = []
            def add(human, data, suffix):
                exported = f"{index}-{len(entries)}{suffix}"
                (self.attachments / exported).write_bytes(data)
                entries.append({"suggestedHumanReadableName": human, "exportedFileName": exported})
            add("comparison-matrix.json", json.dumps(matrix(scenario)).encode(), ".json")
            for checkpoint in gate.CHECKPOINTS:
                add(f"comparison-accessibility-{checkpoint}.txt", b"Application, Window, synthetic parser specimen", ".txt")
                add(f"comparison-screen-{checkpoint}", png(), ".png")
            add("Screen Recording", movie(), ".mp4")
            self.manifest.append({"testIdentifier": f"ComponentComparisonJourneyTests/{name}()", "attachments": entries})
        self.save_manifest()

    def save_manifest(self):
        (self.attachments / "manifest.json").write_text(json.dumps(self.manifest))

    def run_cli(self, device="iphone"):
        return subprocess.run([sys.executable, str(SCRIPT), str(self.attachments), str(self.log), device],
                              capture_output=True, text=True, check=False)

    def test_complete_container_specimens_pass_real_cli_without_native_claim(self):
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        proof = json.loads(result.stdout)
        self.assertEqual(len(proof["journeys"]), 2)
        self.assertIn("no frame", proof["qualification"])
        # The same bounded two-scenario cohort must also qualify the pinned
        # landscape destination; this remains a synthetic parser specimen.
        for group, scenario in zip(self.manifest, gate.METHODS.values()):
            group["testIdentifier"] = "PlannerAppUITests/" + group["testIdentifier"]
            for entry in group["attachments"]:
                path = self.attachments / entry["exportedFileName"]
                if path.suffix == ".json":
                    path.write_text(json.dumps(matrix(scenario, "ipad")))
                elif path.suffix == ".png":
                    path.write_bytes(png(667, 375))
        self.save_manifest()
        result = self.run_cli("ipad")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["device"], "ipad")

    def test_wrong_class_retry_failure_skip_and_missing_attendance_reject(self):
        original = self.log.read_text()
        mutations = [original.replace("PlannerAppUITests.ComponentComparisonJourneyTests", "Other.ComponentComparisonJourneyTests", 1),
                     original + original.splitlines()[0] + "\n", original.replace("passed", "failed", 1),
                     original.replace("passed", "skipped", 1), original.splitlines()[0] + "\n"]
        for value in mutations:
            with self.subTest(value=value):
                self.log.write_text(value)
                self.assertNotEqual(self.run_cli().returncode, 0)

    def test_changed_units_zero_missing_na_hash_filter_and_layout_reject(self):
        path = self.attachments / self.manifest[0]["attachments"][0]["exportedFileName"]
        original = json.loads(path.read_text())
        for change in (
            lambda x: x["conditions"][1].update(unit="milliseconds/request"),
            lambda x: x["conditions"][1].update(amount=True),
            lambda x: x["disk_gb"][1].update(value="0", state=gate.RECORDED),
            lambda x: x["disk_gb"][2].update(state=gate.MISSING),
            lambda x: x.update(fixture_sha256="0" * 64),
            lambda x: x.update(query="", kind_sort_selected=False),
            lambda x: x.update(active_kinds="Storage", accessibility_audits=[]),
            lambda x: x.update(layout="componentComparisonAlignedFields"),
        ):
            value = copy.deepcopy(original)
            change(value)
            path.write_text(json.dumps(value))
            self.assertNotEqual(self.run_cli().returncode, 0)

    def test_success_summary_cannot_replace_missing_matrix_video_or_checkpoint(self):
        original = copy.deepcopy(self.manifest)
        for position in (0, 1, 2, -1):
            self.manifest = copy.deepcopy(original)
            self.manifest[0]["attachments"].pop(position)
            self.save_manifest()
            self.assertNotEqual(self.run_cli().returncode, 0)

    def test_duplicate_owner_or_file_and_unknown_manifest_fail_closed(self):
        original = copy.deepcopy(self.manifest)
        self.manifest[1]["testIdentifier"] = self.manifest[0]["testIdentifier"]
        self.save_manifest()
        self.assertNotEqual(self.run_cli().returncode, 0)
        self.manifest = copy.deepcopy(original)
        self.manifest[1]["attachments"][0]["exportedFileName"] = self.manifest[0]["attachments"][0]["exportedFileName"]
        self.save_manifest()
        self.assertNotEqual(self.run_cli().returncode, 0)
        (self.attachments / "manifest.json").write_text('{"differentSchema": []}')
        self.assertNotEqual(self.run_cli().returncode, 0)

    def test_unsafe_attachment_paths_and_symlinks_cannot_read_external_receipt(self):
        entry = self.manifest[0]["attachments"][0]
        for name in ("../tests.log", str(self.log), "..\\tests.log"):
            entry["exportedFileName"] = name
            self.save_manifest()
            self.assertNotEqual(self.run_cli().returncode, 0)
        (self.attachments / "linked.json").symlink_to(self.log)
        entry["exportedFileName"] = "linked.json"
        self.save_manifest()
        self.assertNotEqual(self.run_cli().returncode, 0)
        self.assertTrue(self.log.is_file())

    def test_corrupt_png_and_truncated_media_do_not_qualify(self):
        for data in (b"\x89PNG\r\n\x1a\n", png()[:-1], png().replace(b"IDAT", b"XXAT", 1)):
            with self.assertRaises(ValueError):
                gate.verify_png(data)
        for data in (b"", movie()[:-1], struct.pack(">I4s", 1, b"mdat"), struct.pack(">I4s", 7, b"mdat")):
            with self.assertRaises(ValueError):
                gate.verify_movie(data)
        screenshot = self.attachments / self.manifest[0]["attachments"][2]["exportedFileName"]
        for data in (png(1, 1), png(667, 375)):
            screenshot.write_bytes(data)
            self.assertNotEqual(self.run_cli().returncode, 0)

    def test_closed_suite_preserves_original_commands_pins_and_budgets(self):
        original = runner.test_command("owned", Path("original.xcresult"))
        current = runner.test_command("owned", Path("original.xcresult"), "component-comparison")
        self.assertEqual([x for x in original if not x.startswith("-only-testing:") and x != "Planner"],
                         [x for x in current if not x.startswith("-only-testing:") and x != "PlannerComparison"])
        self.assertEqual([x.removeprefix("-only-testing:") for x in current if x.startswith("-only-testing:")], list(runner.COMPARISON_TESTS))
        self.assertEqual(runner.TEST_TIMEOUT_SECONDS, 900)
        with self.assertRaises(KeyError):
            runner.test_command("owned", Path("other.xcresult"), "arbitrary-tests")

    def test_bad_export_or_evidence_exit_cannot_pass_successful_xctest(self):
        result = self.root / "original.xcresult"
        result.mkdir()
        summary = json.dumps({"result": "Passed", "totalTestCount": 2, "passedTests": 2, "failedTests": 0, "skippedTests": 0})
        for export_exit, verification_exit in ((1, 0), (0, 1), (0, 0)):
            responses = [subprocess.CompletedProcess([], 0, summary, ""),
                         subprocess.CompletedProcess([], export_exit, "", ""),
                         subprocess.CompletedProcess([], verification_exit, "{}", "")]
            outcome = {"xcodebuildExitCode": 0, "verifiedPassed": False}
            with patch.object(runner.subprocess, "run", side_effect=responses):
                runner.collect_summary(result, self.root, "iphone", outcome, "component-comparison")
            self.assertEqual(outcome["verifiedPassed"], export_exit == 0 and verification_exit == 0)

    def test_export_timeout_invalidates_summary_before_owned_cleanup(self):
        result = self.root / "timeout.xcresult"
        result.mkdir()
        summary = json.dumps({"result": "Passed", "totalTestCount": 2, "passedTests": 2, "failedTests": 0, "skippedTests": 0})
        outcome = {"xcodebuildExitCode": 0, "verifiedPassed": False}
        with patch.object(runner.subprocess, "run", side_effect=[
            subprocess.CompletedProcess([], 0, summary, ""), subprocess.TimeoutExpired("export", 60),
        ]):
            with self.assertRaises(subprocess.TimeoutExpired):
                runner.collect_summary(result, self.root, "iphone", outcome, "component-comparison")
        self.assertFalse(outcome["verifiedPassed"])


if __name__ == "__main__":
    unittest.main()
