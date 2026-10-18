#!/usr/bin/env python3
"""Real abrupt-process-exit replay, using synthetic drafts only."""
import pathlib
import sqlite3
import subprocess
import sys
import tempfile

probe = str(pathlib.Path(sys.argv[1]).resolve())

def run(mode, path, expected=0):
    result = subprocess.run([probe, mode, str(path)], capture_output=True, text=True)
    assert result.returncode == expected, (mode, result.returncode, result.stdout, result.stderr)

with tempfile.TemporaryDirectory() as root:
    path = pathlib.Path(root) / "drafts.sqlite"
    run("seed", path)
    for mode in ("crash-write", "crash-commit"):
        run(mode, path, 73)
        run("verify", path)
        with sqlite3.connect(path) as db:
            assert db.execute("PRAGMA integrity_check").fetchone() == ("ok",)
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
    run("crash-migration", legacy, 73)
    with sqlite3.connect(legacy) as db:
        assert db.execute("PRAGMA user_version").fetchone() == (1,)
        assert "restored_from" not in [r[1] for r in db.execute("PRAGMA table_info(revisions)")]
    run("verify", legacy)
print("PASS: abrupt exits after history write, before commit and during migration preserve durable revision")
