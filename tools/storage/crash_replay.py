#!/usr/bin/env python3
"""Real abrupt-process-exit replay, using synthetic drafts only."""
import argparse
import math
import pathlib
import sqlite3
import subprocess
import tempfile


def positive_seconds(value):
    try:
        seconds = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a finite positive number of seconds") from error
    if not math.isfinite(seconds) or seconds <= 0:
        raise argparse.ArgumentTypeError("must be a finite positive number of seconds")
    return seconds


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("probe", type=pathlib.Path, help="built DraftCrashProbe executable")
parser.add_argument("--timeout-seconds", type=positive_seconds, default=60.0,
                    help="deadline for each probe phase (default: 60 seconds)")
args = parser.parse_args()
probe = str(args.probe.resolve())

def require(condition, message):
    if not condition:
        raise SystemExit(message)

def run(mode, path, expected=0):
    try:
        result = subprocess.run([probe, mode, str(path)], capture_output=True,
                                text=True, timeout=args.timeout_seconds)
    except subprocess.TimeoutExpired as error:
        raise SystemExit(f"{mode}: probe exceeded {args.timeout_seconds:g}-second deadline; "
                         f"stdout={error.stdout!r}; stderr={error.stderr!r}") from None
    require(result.returncode == expected,
            f"{mode}: expected exit {expected}, observed {result.returncode}; "
            f"stdout={result.stdout!r}; stderr={result.stderr!r}")

def legacy_records(db):
    return (db.execute("SELECT id,revision FROM drafts ORDER BY id").fetchall(),
            db.execute("SELECT draft_id,revision,title,payload FROM revisions ORDER BY draft_id,revision").fetchall())

with tempfile.TemporaryDirectory() as root:
    path = pathlib.Path(root) / "drafts.sqlite"
    run("seed", path)
    for mode in ("crash-write", "crash-commit"):
        run(mode, path, 73)
        run("verify", path)
        with sqlite3.connect(path) as db:
            require(db.execute("PRAGMA integrity_check").fetchone() == ("ok",),
                    f"{mode}: database integrity check failed")
    legacy = pathlib.Path(root) / "legacy.sqlite"
    with sqlite3.connect(legacy) as db:
        db.executescript("""
            CREATE TABLE drafts(id TEXT PRIMARY KEY,revision INTEGER NOT NULL);
            CREATE TABLE revisions(draft_id TEXT NOT NULL REFERENCES drafts(id) ON DELETE CASCADE,
              revision INTEGER NOT NULL,title TEXT NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(draft_id,revision));
            INSERT INTO drafts VALUES('00000000-0000-0000-0000-000000000001',1);
            INSERT INTO revisions VALUES('00000000-0000-0000-0000-000000000001',1,'Legacy',X'7b7d');
            PRAGMA user_version=1;
        """)
        original_legacy = legacy_records(db)
    run("crash-migration", legacy, 73)
    with sqlite3.connect(legacy) as db:
        require(db.execute("PRAGMA user_version").fetchone() == (1,),
                "crash-migration: schema version changed before commit")
        require("restored_from" not in [r[1] for r in db.execute("PRAGMA table_info(revisions)")],
                "crash-migration: restoration column survived interrupted migration")
        require(legacy_records(db) == original_legacy,
                "crash-migration: legacy records changed before commit")
    run("verify", legacy)
    with sqlite3.connect(legacy) as db:
        require(legacy_records(db) == original_legacy,
                "verify: legacy records changed during recovery")
print("PASS: abrupt exits after history write, before commit and during migration preserve durable revision")
