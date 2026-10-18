"""Portable checks of the replay driver, using only a synthetic probe protocol.

These fixtures do not execute Swift or establish native storage durability.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


DRIVER = Path(__file__).resolve().parents[1] / "crash_replay.py"
MODES = ["seed", "crash-write", "verify", "crash-commit", "verify",
         "crash-migration", "verify"]
PROBE = r'''
import json
import os
from pathlib import Path
import sqlite3
import sys

options = json.loads(os.environ["REPLAY_FIXTURE_OPTIONS"])
trace = Path(os.environ["REPLAY_FIXTURE_TRACE"])
modes = json.loads(trace.read_text()) if trace.exists() else []
mode, database = sys.argv[1], Path(sys.argv[2])
modes.append(mode)
trace.write_text(json.dumps(modes))
if options.get("always_zero"):
    raise SystemExit(0)
if len(modes) - 1 == options.get("bad_index"):
    print("synthetic probe stdout", flush=True)
    print("synthetic probe stderr", file=sys.stderr, flush=True)
    raise SystemExit(0 if mode.startswith("crash-") else 27)
if mode == "seed":
    with sqlite3.connect(database) as connection:
        connection.executescript("CREATE TABLE replay_probe(value INTEGER CHECK(value=1));"
                                 "INSERT INTO replay_probe VALUES(1);")
if mode == options.get("tamper_at"):
    if options["tamper"] == "file":
        database.write_bytes(b"synthetic invalid SQLite file")
    else:
        with sqlite3.connect(database) as connection:
            if options["tamper"] == "integrity":
                connection.execute("PRAGMA ignore_check_constraints=ON")
                connection.execute("UPDATE replay_probe SET value=2")
            elif options["tamper"] == "version":
                connection.execute("PRAGMA user_version=2")
            elif options["tamper"] == "column":
                connection.execute("ALTER TABLE revisions ADD COLUMN restored_from INTEGER")
if mode.startswith("crash-"):
    os._exit(73)
'''


class CrashReplayChecks(unittest.TestCase):
    def replay(self, optimized=False, **options):
        with tempfile.TemporaryDirectory(prefix="synthetic-replay-driver-") as directory:
            root = Path(directory)
            probe = root / "probe"
            probe.write_text(f"#!{sys.executable}\n" + PROBE, encoding="utf-8")
            probe.chmod(0o755)
            trace = root / "trace.json"
            environment = dict(os.environ)
            environment.pop("PYTHONOPTIMIZE", None)
            environment["REPLAY_FIXTURE_OPTIONS"] = json.dumps(options)
            environment["REPLAY_FIXTURE_TRACE"] = str(trace)
            result = subprocess.run(
                [sys.executable, *(["-O"] if optimized else []), str(DRIVER), str(probe)],
                env=environment, capture_output=True, text=True, timeout=20,
            )
            modes = json.loads(trace.read_text()) if trace.exists() else []
            return result, modes

    def require_failure(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("PASS:", result.stdout)
        self.assertTrue(result.stderr)

    def test_valid_synthetic_protocol_runs_every_phase_in_both_python_modes(self):
        for optimized in (False, True):
            with self.subTest(optimized=optimized):
                result, modes = self.replay(optimized)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(modes, MODES)
                self.assertEqual(result.stdout.count("PASS:"), 1)
                self.assertEqual(result.stderr, "")

    def test_wrong_exit_at_each_phase_stops_before_later_checks(self):
        for optimized in (False, True):
            for index, mode in enumerate(MODES):
                with self.subTest(optimized=optimized, index=index, mode=mode):
                    result, modes = self.replay(optimized, bad_index=index)
                    self.require_failure(result)
                    self.assertEqual(modes, MODES[:index + 1])
                    self.assertIn(mode, result.stderr)
                    self.assertIn("synthetic probe stdout", result.stderr)
                    self.assertIn("synthetic probe stderr", result.stderr)

    def test_zero_exit_probe_without_a_database_cannot_report_success(self):
        for optimized in (False, True):
            with self.subTest(optimized=optimized):
                result, modes = self.replay(optimized, always_zero=True)
                self.require_failure(result)
                self.assertEqual(modes, MODES[:2])

    def test_integrity_failures_after_either_write_prevent_success(self):
        for optimized in (False, True):
            for mode, calls in (("crash-write", 3), ("crash-commit", 5)):
                with self.subTest(optimized=optimized, mode=mode):
                    result, modes = self.replay(optimized, tamper_at=mode, tamper="integrity")
                    self.require_failure(result)
                    self.assertEqual(modes, MODES[:calls])

    def test_unreadable_database_after_either_write_prevents_success(self):
        for optimized in (False, True):
            for mode, calls in (("crash-write", 3), ("crash-commit", 5)):
                with self.subTest(optimized=optimized, mode=mode):
                    result, modes = self.replay(optimized, tamper_at=mode, tamper="file")
                    self.require_failure(result)
                    self.assertEqual(modes, MODES[:calls])

    def test_migration_version_change_prevents_recovery_verification(self):
        for optimized in (False, True):
            with self.subTest(optimized=optimized):
                result, modes = self.replay(optimized, tamper_at="crash-migration", tamper="version")
                self.require_failure(result)
                self.assertEqual(modes, MODES[:-1])

    def test_migration_column_change_prevents_recovery_verification(self):
        for optimized in (False, True):
            with self.subTest(optimized=optimized):
                result, modes = self.replay(optimized, tamper_at="crash-migration", tamper="column")
                self.require_failure(result)
                self.assertEqual(modes, MODES[:-1])


if __name__ == "__main__":
    unittest.main()
