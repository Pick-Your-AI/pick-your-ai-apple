#!/usr/bin/env python3
"""Actual abrupt-exit queue replay; --self-test checks only the portable driver."""
import argparse
import math
import os
import pathlib
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import uuid


APPLICATION_ID = 0x50595131
BODY = b'{"build_id":"synthetic-build","revision":8,"decimal":"1.000"}'
BASELINE = (1, b"baseline", b"fixture-v1", b"synthetic-owner", 1,
            b"baseline-build", b"baseline-key", None, b'{"revision":1}', 0, None, None)
WRITE_PREFIX = (2, b"queued-write", b"fixture-v1", b"synthetic-owner", 2,
                b"synthetic-build", b"stable-key-queued-write", b'"7"', BODY)
CASES = (
    ("crash-enqueue", False, None, "verify-missing", None),
    ("commit-enqueue", False, 0, "verify-pending", 0),
    ("crash-attempt", True, 0, "verify-pending", 0),
    ("commit-attempt", True, 1, "verify-uncertain", 5),
    ("crash-outcome", True, 1, "verify-uncertain", 5),
    ("commit-outcome", True, 2, "verify-confirmed", 2),
)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def positive_seconds(value):
    try:
        number = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("deadline must be finite and positive") from error
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("deadline must be finite and positive")
    return number


def run(probe, mode, path, timeout, expected=0):
    try:
        result = subprocess.run([str(probe), mode, str(path)], capture_output=True,
                                text=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"{mode}: probe exceeded {timeout:g}-second deadline; "
                           f"stdout={error.stdout!r}; stderr={error.stderr!r}") from None
    require(result.returncode == expected,
            f"{mode}: expected exit {expected}, observed {result.returncode}; "
            f"stdout={result.stdout!r}; stderr={result.stderr!r}")
    if mode.startswith("verify-"):
        require(result.stdout == f"verified {mode}\n", f"{mode}: missing exact verification output")


def queue_rows(path, expected_state):
    require(path.is_file(), "queue database is missing")
    with sqlite3.connect(path) as db:
        require(db.execute("PRAGMA integrity_check").fetchall() == [("ok",)], "queue integrity failed")
        require(db.execute("PRAGMA application_id").fetchone() == (APPLICATION_ID,), "wrong queue application ID")
        require(db.execute("PRAGMA user_version").fetchone() == (1,), "queue schema version changed")
        rows = db.execute("""
            SELECT sequence,operation_id,environment,authority,method,build_id,idempotency_key,
                   precondition,body,state,attempt_id,attempt_generation
            FROM queue_writes ORDER BY sequence
        """).fetchall()
        session = db.execute("SELECT id,environment,authority,generation FROM queue_session").fetchall()
    require(rows and rows[0] == BASELINE, "baseline intent changed")
    require(len(rows) == (1 if expected_state is None else 2), "unexpected queue cardinality")
    require(len(session) == 1 and session[0][:3] == (1, b"fixture-v1", b"synthetic-owner"),
            "session partition or cardinality changed")
    canonical_uuid(session[0][3])
    if expected_state is not None:
        require(rows[1][:9] == WRITE_PREFIX, "immutable write body, key, target or precondition changed")
        require(rows[1][9] == expected_state, "unexpected durable write state")
        if expected_state == 0:
            require(rows[1][10:] == (None, None), "pending intent acquired attempt metadata")
        else:
            canonical_uuid(rows[1][10]); canonical_uuid(rows[1][11])
            if expected_state == 1:
                require(rows[1][11] == session[0][3], "live attempt lost its session generation")
    return rows


def canonical_uuid(value):
    require(isinstance(value, bytes) and len(value) == 36, "attempt/session identifier is not exact UUID bytes")
    try:
        parsed = uuid.UUID(value.decode("ascii"))
    except (UnicodeError, ValueError) as error:
        raise RuntimeError("attempt/session identifier is malformed") from error
    require(str(parsed).upper().encode("ascii") == value, "attempt/session identifier changed spelling")


def draft_control(path, expected_bytes=None):
    require(path.is_file(), "independent draft control is missing")
    before = path.read_bytes()
    with sqlite3.connect(path) as db:
        require(db.execute("PRAGMA integrity_check").fetchall() == [("ok",)], "draft integrity failed")
        require(db.execute("SELECT id,revision FROM drafts").fetchall() ==
                [("00000000-0000-0000-0000-000000000089", 1)], "draft head changed")
        require(db.execute("SELECT draft_id,revision,title,payload,restored_from FROM revisions").fetchall() ==
                [("00000000-0000-0000-0000-000000000089", 1, "Synthetic queue control", b"{}", None)],
                "draft history changed")
    require(path.read_bytes() == before, "draft inspection changed bytes")
    if expected_bytes is not None:
        require(before == expected_bytes, "queue operation changed the independent draft file")
    return before


def replay(probe, timeout=60.0):
    require(math.isfinite(timeout) and timeout > 0, "deadline must be finite and positive")
    with tempfile.TemporaryDirectory(prefix="pending-write-replay-") as directory:
        root = pathlib.Path(directory)
        for crash, needs_enqueue, before_state, verify, after_state in CASES:
            folder = root / crash; folder.mkdir()
            path = folder / "pending.sqlite"
            run(probe, "seed", path, timeout)
            queue_rows(path, None)
            original_draft = draft_control(folder / "drafts.sqlite")
            if needs_enqueue:
                run(probe, "enqueue", path, timeout)
                queue_rows(path, 0)
            run(probe, crash, path, timeout, expected=73)
            before = queue_rows(path, before_state)
            draft_control(folder / "drafts.sqlite", original_draft)
            run(probe, verify, path, timeout)
            after = queue_rows(path, after_state)
            draft_control(folder / "drafts.sqlite", original_draft)
            if before_state not in (None, 0):
                require(before[1][:9] == after[1][:9] and before[1][10:] == after[1][10:],
                        "recovery replaced immutable intent or attempt identity")
    return len(CASES)


# These synthetic processes exercise driver rejection paths only. They do not
# import or execute PlannerData, prove server behavior, or substitute for the
# separately required real Swift probe invocation.
class DriverGuards(unittest.TestCase):
    def fake_probe(self, mutation=""):
        directory = tempfile.TemporaryDirectory(prefix="queue-driver-guard-")
        self.addCleanup(directory.cleanup)
        root = pathlib.Path(directory.name)
        path = root / "probe.py"
        source = r'''
import os, pathlib, sqlite3, sys, time, uuid
mode, raw = sys.argv[1:]
path = pathlib.Path(raw)
APPLICATION_ID = 0x50595131
BODY = b'{"build_id":"synthetic-build","revision":8,"decimal":"1.000"}'
baseline = (1,b"baseline",b"fixture-v1",b"synthetic-owner",1,b"baseline-build",b"baseline-key",None,b'{"revision":1}',0,None,None)
write = (2,b"queued-write",b"fixture-v1",b"synthetic-owner",2,b"synthetic-build",b"stable-key-queued-write",b'"7"',BODY,0,None,None)
if mode == "seed":
    with sqlite3.connect(path) as db:
        db.execute("CREATE TABLE queue_writes(sequence,operation_id,environment,authority,method,build_id,idempotency_key,precondition,body,state,attempt_id,attempt_generation)")
        db.execute("CREATE TABLE queue_session(id,environment,authority,generation)")
        db.execute("INSERT INTO queue_writes VALUES(?,?,?,?,?,?,?,?,?,?,?,?)", baseline)
        db.execute("INSERT INTO queue_session VALUES(1,?,?,?)", (b"fixture-v1",b"synthetic-owner",str(uuid.uuid4()).upper().encode()))
        db.execute("PRAGMA application_id=" + str(APPLICATION_ID)); db.execute("PRAGMA user_version=1")
    with sqlite3.connect(path.parent / "drafts.sqlite") as db:
        db.execute("CREATE TABLE drafts(id,revision)")
        db.execute("CREATE TABLE revisions(draft_id,revision,title,payload,restored_from)")
        db.execute("INSERT INTO drafts VALUES('00000000-0000-0000-0000-000000000089',1)")
        db.execute("INSERT INTO revisions VALUES('00000000-0000-0000-0000-000000000089',1,'Synthetic queue control',X'7b7d',NULL)")
elif mode in ("enqueue", "commit-enqueue"):
    with sqlite3.connect(path) as db: db.execute("INSERT INTO queue_writes VALUES(?,?,?,?,?,?,?,?,?,?,?,?)", write)
elif mode in ("commit-attempt", "crash-outcome", "commit-outcome"):
    with sqlite3.connect(path) as db:
        generation = db.execute("SELECT generation FROM queue_session").fetchone()[0]
        state = 2 if mode == "commit-outcome" else 1
        db.execute("UPDATE queue_writes SET state=?,attempt_id=?,attempt_generation=? WHERE sequence=2", (state,str(uuid.uuid4()).upper().encode(),generation))
elif mode == "verify-uncertain":
    with sqlite3.connect(path) as db: db.execute("UPDATE queue_writes SET state=5 WHERE state=1")
__MUTATION__
if mode.startswith("verify-"): print("verified " + mode)
if mode.startswith("crash-") or mode.startswith("commit-"): os._exit(73)
'''
        path.write_text("#!" + sys.executable + "\n" + source.replace("__MUTATION__", mutation), encoding="utf-8")
        path.chmod(0o700)
        return path

    def testValidSyntheticProtocolCoversAllSixCuts(self):
        self.assertEqual(replay(self.fake_probe(), 5), 6)

    def testIncorrectAbruptExitIsRejected(self):
        probe = self.fake_probe('if mode == "crash-enqueue": sys.exit(0)')
        with self.assertRaisesRegex(RuntimeError, "expected exit 73, observed 0"):
            replay(probe, 5)

    def testIncorrectSuccessExitIsRejected(self):
        probe = self.fake_probe('if mode == "verify-pending": sys.exit(73)')
        with self.assertRaisesRegex(RuntimeError, "expected exit 0, observed 73"):
            replay(probe, 5)

    def testMissingVerificationOutputIsRejected(self):
        probe = self.fake_probe('if mode.startswith("verify-"): sys.exit(0)')
        with self.assertRaisesRegex(RuntimeError, "missing exact verification output"):
            replay(probe, 5)

    def testChangedIntentFieldsAreRejected(self):
        for assignment in ["body=X'00'", "idempotency_key=X'01'", "precondition=X'02'", "build_id=X'03'"]:
            with self.subTest(assignment=assignment):
                mutation = 'if mode == "commit-enqueue":\n    with sqlite3.connect(path) as db: db.execute(' + repr("UPDATE queue_writes SET " + assignment + " WHERE sequence=2") + ')'
                with self.assertRaisesRegex(RuntimeError, "immutable write"):
                    replay(self.fake_probe(mutation), 5)

    def testChangedStateOrMissingRowsAreRejected(self):
        for statement, message in [("UPDATE queue_writes SET state=5 WHERE sequence=2", "durable write state"),
                                   ("DELETE FROM queue_writes WHERE sequence=2", "cardinality")]:
            with self.subTest(statement=statement):
                mutation = 'if mode == "commit-enqueue":\n    with sqlite3.connect(path) as db: db.execute(' + repr(statement) + ')'
                with self.assertRaisesRegex(RuntimeError, message):
                    replay(self.fake_probe(mutation), 5)

    def testChangedAttemptOrDraftIsRejected(self):
        bad_attempt = 'if mode == "verify-uncertain":\n    with sqlite3.connect(path) as db: db.execute("UPDATE queue_writes SET attempt_id=? WHERE sequence=2", (str(uuid.uuid4()).upper().encode(),))'
        with self.assertRaisesRegex(RuntimeError, "attempt identity"):
            replay(self.fake_probe(bad_attempt), 5)
        bad_draft = 'if mode == "commit-enqueue":\n    with sqlite3.connect(path.parent / "drafts.sqlite") as db: db.execute("UPDATE drafts SET revision=2")'
        with self.assertRaisesRegex(RuntimeError, "draft head changed"):
            replay(self.fake_probe(bad_draft), 5)

    def testInvalidSchemaAndGenerationAreRejected(self):
        for statement in ["PRAGMA user_version=99", "UPDATE queue_session SET generation=X'ff'"]:
            with self.subTest(statement=statement):
                mutation = 'if mode == "seed":\n    with sqlite3.connect(path) as db: db.execute(' + repr(statement) + ')'
                with self.assertRaises(RuntimeError):
                    replay(self.fake_probe(mutation), 5)

    def testTimeoutStopsBeforeLaterPhases(self):
        for delayed_start in (False, True):
            with self.subTest(delayed_start=delayed_start):
                probe = self.fake_probe('if mode == "seed": time.sleep(10)')
                if delayed_start:
                    # Reproduce a deadline before the child starts the protocol.
                    source = probe.read_text(encoding="utf-8")
                    probe.write_text(source.replace("import os, pathlib", "import time; time.sleep(10)\nimport os, pathlib"), encoding="utf-8")
                children = []
                launch = subprocess.Popen

                def capture_child(*args, **kwargs):
                    child = launch(*args, **kwargs)
                    children.append(child)
                    return child

                # Observe the real child in the parent; run still owns timeout,
                # kill and wait. Child startup is not guaranteed within 100 ms.
                with patch.object(subprocess, "Popen", side_effect=capture_child):
                    with self.assertRaisesRegex(RuntimeError, "seed: probe exceeded"):
                        replay(probe, 0.1)
                self.assertEqual(len(children), 1, "a later replay phase launched")
                child = children[0]
                self.assertIsNotNone(child.returncode, "timed-out child was not reaped")
                with self.assertRaises(ProcessLookupError): os.kill(child.pid, 0)
                with self.assertRaises(ChildProcessError): os.waitpid(child.pid, os.WNOHANG)

    def testInvalidDeadlineIsRejectedBeforeLaunching(self):
        for value in ["0", "-1", "inf", "nan", "text"]:
            with self.assertRaises(argparse.ArgumentTypeError): positive_seconds(value)
        for value in [0, -1, math.inf, math.nan]:
            with self.assertRaisesRegex(RuntimeError, "deadline"):
                replay(pathlib.Path("must-not-launch"), value)

    def testOptimizedPythonRetainsAllAcceptanceChecks(self):
        for mutation in ['if mode == "crash-enqueue": sys.exit(0)',
                         'if mode == "commit-enqueue":\n    with sqlite3.connect(path) as db: db.execute("UPDATE queue_writes SET body=X\'00\' WHERE sequence=2")']:
            probe = self.fake_probe(mutation)
            result = subprocess.run([sys.executable, "-O", __file__, str(probe)], capture_output=True, text=True, timeout=15)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("PASS:", result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("probe", nargs="?", type=pathlib.Path, help="built PendingWriteCrashProbe executable")
    parser.add_argument("--timeout-seconds", type=positive_seconds, default=60.0)
    parser.add_argument("--self-test", action="store_true", help="run synthetic portable driver guards only")
    args = parser.parse_args()
    if args.self_test:
        if args.probe is not None: parser.error("--self-test does not accept a Swift probe")
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(DriverGuards)
        return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1
    if args.probe is None: parser.error("a built Swift probe is required")
    try:
        count = replay(args.probe.resolve(), args.timeout_seconds)
    except (RuntimeError, sqlite3.Error, OSError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(f"PASS: {count} actual queue exit cuts preserve immutable intent, conservative recovery and independent draft history")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
