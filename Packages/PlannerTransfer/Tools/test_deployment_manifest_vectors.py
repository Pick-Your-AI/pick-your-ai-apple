"""Owned synthetic filesystem regressions for the standalone reference entry.

Run in the adjacent hash-locked Python environment. No network, app, native SDK,
real approval record or deployment is involved. Unsupported FIFO/symlink/hardlink
subcases report their actual platform prerequisite; the other controls still run.
"""
import contextlib
import errno
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Tools/deployment_manifest_vectors.py"
SPEC = importlib.util.spec_from_file_location("deployment_vectors_under_test", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
CORPUS = MODULE.VECTORS.read_bytes()
INPUTS = [SOURCE, MODULE.MANIFEST, MODULE.VECTORS,
          *[ROOT / target for target, digest in MODULE.SOURCES.values()]]
BEFORE = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in INPUTS}


class DeploymentManifestVectorIOTests(unittest.TestCase):
    def setUp(self):
        owned = tempfile.TemporaryDirectory(prefix="deployment-manifest-io-")
        self.addCleanup(owned.cleanup)
        self.root = Path(owned.name)

    def invoke(self, path, args=None):
        output = io.StringIO()
        with mock.patch.object(MODULE, "VECTORS", path), contextlib.redirect_stdout(output):
            result = MODULE.main(["--write"] if args is None else args)
        self.assertEqual(result, 0)
        self.assertIn("133 DeploymentManifest vectors", output.getvalue())
        return output.getvalue()

    def failed(self, path):
        output = io.StringIO()
        with mock.patch.object(MODULE, "VECTORS", path), contextlib.redirect_stdout(output):
            with self.assertRaises((OSError, ValueError)):
                MODULE.main(["--write"])
        self.assertEqual(output.getvalue(), "")
        self.assertEqual(list(self.root.glob(".deployment-vectors-*")), [])

    def testNonregularOutputsPreserveTheirTargets(self):
        target = self.root / "target"
        target.write_bytes(b"private synthetic original")
        directory = self.root / "directory"
        directory.mkdir()
        with self.subTest(kind="directory"):
            self.failed(directory)
            self.assertTrue(directory.is_dir())
        with self.subTest(kind="symlink"):
            link = self.root / "link"
            try:
                link.symlink_to(target)
            except (NotImplementedError, OSError) as error:
                if os.name != "nt":
                    raise
                self.skipTest("Windows symlink capability unavailable: " + type(error).__name__)
            self.failed(link)
            self.assertTrue(link.is_symlink())
            self.assertEqual(target.read_bytes(), b"private synthetic original")
        with self.subTest(kind="fifo"):
            if not hasattr(os, "mkfifo"):
                self.skipTest("FIFO creation is unavailable on this platform")
            fifo = self.root / "fifo"
            os.mkfifo(fifo)
            before = fifo.lstat()
            child = """import importlib.util
from pathlib import Path
import sys
spec = importlib.util.spec_from_file_location("fifo_output_reference", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.VECTORS = Path(sys.argv[2])
try:
    module.main(["--write"])
except (OSError, ValueError):
    raise SystemExit(0)
raise SystemExit("FIFO was accepted as a regular output")
"""
            # The original faulty --write also blocks on an output FIFO. Keep
            # this regression bounded even if its nonregular guard is removed.
            result = subprocess.run([sys.executable, "-B", "-c", child,
                                     str(SOURCE), str(fifo)],
                                    capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))
            self.assertEqual(result.stdout, b"")
            self.assertEqual(result.stderr, b"")
            self.assertEqual(fifo.lstat().st_ino, before.st_ino)
            self.assertEqual(fifo.lstat().st_mode, before.st_mode)
            self.assertEqual(list(self.root.glob(".deployment-vectors-*")), [])
        self.assertEqual(target.read_bytes(), b"private synthetic original")

    def testMissingRegularAndHardlinkPublicationRetainOtherBytes(self):
        missing = self.root / "missing"
        self.invoke(missing)
        self.assertEqual(missing.read_bytes(), CORPUS)
        self.invoke(missing, [])
        regular = self.root / "regular"
        regular.write_bytes(b"old")
        regular.chmod(0o640)
        observed_mode = regular.stat().st_mode & 0o777
        self.invoke(regular)
        self.assertEqual(regular.stat().st_mode & 0o777, observed_mode)
        with self.subTest(kind="hardlink"):
            target = self.root / "hardlink-target"
            target.write_bytes(b"private hardlink original")
            linked = self.root / "linked"
            try:
                os.link(target, linked)
            except (NotImplementedError, OSError) as error:
                if os.name != "nt":
                    raise
                self.skipTest("Windows hardlink capability unavailable: " + type(error).__name__)
            before = target.stat().st_ino
            self.invoke(linked)
            self.assertEqual(target.read_bytes(), b"private hardlink original")
            self.assertEqual(target.stat().st_ino, before)
            self.assertNotEqual(linked.stat().st_ino, before)
            self.assertEqual(linked.read_bytes(), CORPUS)
        self.assertEqual(list(self.root.glob(".deployment-vectors-*")), [])

    def testPartialShortFsyncAndReplaceFailuresCleanAndRetry(self):
        real_open = Path.open
        for failure in ["partial", "short", "fsync", "replace"]:
            with self.subTest(failure=failure):
                destination = self.root / failure
                destination.write_bytes(b"original fixture")

                class BrokenWriter:
                    def __init__(self, path, args, kwargs):
                        self.stream = real_open(path, *args, **kwargs)

                    def __enter__(self):
                        return self

                    def __exit__(self, *args):
                        return self.stream.__exit__(*args)

                    def write(self, data):
                        self.stream.write(data[:7])
                        if failure == "partial":
                            raise OSError("synthetic partial write")
                        return 7

                    def __getattr__(self, name):
                        return getattr(self.stream, name)

                def opened(path, *args, **kwargs):
                    if args and args[0] == "xb" and path.name == "vectors.json":
                        return BrokenWriter(path, args, kwargs)
                    return real_open(path, *args, **kwargs)

                patcher = (mock.patch.object(Path, "open", opened)
                           if failure in ["partial", "short"]
                           else mock.patch.object(MODULE.os, failure,
                                                  side_effect=OSError("synthetic " + failure)))
                with patcher:
                    self.failed(destination)
                self.assertEqual(destination.read_bytes(), b"original fixture")
                self.invoke(destination)
                self.assertEqual(destination.read_bytes(), CORPUS)

    def testFdopenAcquisitionFailureClosesActualDescriptor(self):
        path = self.root / "input"
        path.write_bytes(b"input")
        opened = []
        real_open = os.open

        def opening(*args, **kwargs):
            descriptor = real_open(*args, **kwargs)
            opened.append(descriptor)
            return descriptor

        with mock.patch.object(MODULE.os, "open", opening):
            with mock.patch.object(MODULE.os, "fdopen",
                                   side_effect=OSError("synthetic acquisition")):
                with self.assertRaises(OSError):
                    MODULE.read_regular(path)
        self.assertEqual(len(opened), 1)
        with self.assertRaises(OSError) as caught:
            os.fstat(opened[0])
        self.assertEqual(caught.exception.errno, errno.EBADF)
        self.assertEqual(MODULE.read_regular(path), b"input")

    def testNonregularAndOversizedReadsRejectWithoutWaiting(self):
        directory = self.root / "directory"
        directory.mkdir()
        large = self.root / "large"
        with large.open("wb") as stream:
            stream.truncate(2 * 1024 * 1024 + 1)
        for path in [directory, large]:
            with self.subTest(path=path.name), self.assertRaises((OSError, ValueError)):
                MODULE.read_regular(path)
        with self.subTest(kind="fifo"):
            if not hasattr(os, "mkfifo"):
                self.skipTest("FIFO creation is unavailable on this platform")
            fifo = self.root / "fifo"
            os.mkfifo(fifo)
            child = """import importlib.util
from pathlib import Path
import sys
spec = importlib.util.spec_from_file_location("fifo_reference", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
try:
    module.read_regular(Path(sys.argv[2]))
except (OSError, ValueError):
    raise SystemExit(0)
raise SystemExit("FIFO was accepted as a regular input")
"""
            # subprocess.run kills and reaps the owned child on timeout. Removing
            # O_NONBLOCK must fail this regression without hanging the test runner.
            result = subprocess.run([sys.executable, "-B", "-c", child,
                                     str(SOURCE), str(fifo)],
                                    capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))
            self.assertEqual(result.stdout, b"")
        normal = self.root / "normal"
        normal.write_bytes(b"retry")
        self.assertEqual(MODULE.read_regular(normal), b"retry")

    def testChangedPinsManifestAndCorpusFailClosedInRealCLI(self):
        copy_root = self.root / "package"
        tool = copy_root / "Tools/deployment_manifest_vectors.py"
        originals = {}
        for source in INPUTS:
            destination = copy_root / source.relative_to(ROOT)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(source.read_bytes())
            originals[destination] = destination.read_bytes()
        changed = [copy_root / target for target, digest in MODULE.SOURCES.values()]
        changed += [copy_root / "Tools/deployment_manifest_source_manifest.json",
                    copy_root / "Tests/PlannerTransferTests/Fixtures/deployment-manifest-conformance.json"]
        for path in changed:
            with self.subTest(path=str(path.relative_to(copy_root))):
                original = originals[path]
                if path.name == "deployment_manifest_source_manifest.json":
                    altered = json.loads(original)
                    altered["files"][0]["sha256"] = "0" * 64
                    path.write_text(json.dumps(altered))
                else:
                    path.write_bytes(original + b" ")
                for optimized in [False, True]:
                    command = [sys.executable, "-B"] + (["-O"] if optimized else []) + [str(tool)]
                    result = subprocess.run(command, cwd=self.root, capture_output=True, timeout=20)
                    self.assertEqual(result.returncode, 2, (command, result.stdout, result.stderr))
                    self.assertNotIn(b"Verified", result.stdout)
                    self.assertIn(b"verification failed", result.stderr)
                path.write_bytes(original)
        for optimized in [False, True]:
            command = [sys.executable, "-B"] + (["-O"] if optimized else []) + [str(tool)]
            result = subprocess.run(command, cwd=self.root, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, (command, result.stdout, result.stderr))
            self.assertIn(b"133 DeploymentManifest vectors", result.stdout)

    def testSourceAndRealFixtureBytesStayExact(self):
        self.assertEqual(BEFORE, {path: hashlib.sha256(path.read_bytes()).hexdigest()
                                  for path in INPUTS})


if __name__ == "__main__":
    unittest.main(verbosity=2)
