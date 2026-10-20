"""Real Git regressions for the conservative native allocation boundary."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "native_scope.py"
SPEC = importlib.util.spec_from_file_location("apple_native_scope", SOURCE)
scope = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = scope
SPEC.loader.exec_module(scope)


class NativeScopeTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.repo = Path(self.folder.name)
        self.command("init", "--quiet")
        self.command("config", "user.name", "Synthetic CI scope fixture")
        self.command("config", "user.email", "ci-fixture@example.invalid")
        self.command("config", "commit.gpgsign", "false")
        # Finish fixture-owned maintenance before TemporaryDirectory cleanup.
        self.command("config", "maintenance.autoDetach", "false")
        self.write("README.md", "Synthetic documentation\n")
        self.write("Sources/Value.swift", "struct Value {}\n")
        self.initial = self.commit()

    def command(self, *args, input=None):
        return subprocess.check_output(["git", *args], cwd=self.repo, input=input,
                                       stderr=subprocess.PIPE).decode().strip()

    def write(self, path, text):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def commit(self):
        self.command("add", "--all")
        self.command("commit", "--quiet", "--allow-empty", "-m", "Synthetic scope input")
        return self.command("rev-parse", "HEAD")

    def push(self, head=None, before=None):
        return scope.choose(self.repo, event="push", head=head or self.command("rev-parse", "HEAD"),
                            before=before or self.initial)

    def test_regular_documentation_push_skips_native(self):
        for path in ["README.md", "docs/acceptance/issue-33-draft-snapshot-boundary.md",
                     "App/README.md", "App/UI_JOURNEY.md",
                     "Packages/PlannerData/README.md", "tools/conformance/README.md",
                     "docs/validation/issue-113-policy.md", "docs/validation/submission-sdk.md"]:
            self.write(path, "Changed synthetic documentation\n")
        result = self.push(self.commit())
        self.assertFalse(result.native_required)
        self.assertEqual(result.changed_files, 8)

    def test_pr_uses_exact_test_merge_against_its_base(self):
        self.write("docs/REPOSITORY_SCOPE.md", "Synthetic PR\n")
        topic = self.commit()
        tree = self.command("rev-parse", "HEAD^{tree}")
        merge = self.command("commit-tree", tree, "-p", self.initial, "-p", topic,
                             input=b"Synthetic test merge\n")
        self.command("checkout", "--quiet", "--detach", merge)
        result = scope.choose(self.repo, event="pull_request", head=merge, base=self.initial)
        self.assertFalse(result.native_required)
        self.assertTrue(scope.choose(self.repo, event="pull_request", head=merge, base=topic).native_required)
        self.assertTrue(scope.choose(self.repo, event="pull_request", head=topic, base=self.initial).native_required)

    def test_code_after_more_than_three_thousand_docs_still_runs(self):
        for index in range(3_005):
            self.write(f"docs/case-{index:04}.md", "Synthetic\n")
        self.write("Sources/Value.swift", "struct ChangedValue {}\n")
        result = self.push(self.commit())
        self.assertTrue(result.native_required)
        self.assertEqual(result.changed_files, 3_006)

    def test_markdown_fixture_is_not_documentation(self):
        self.write("Packages/PlannerUI/Tests/Fixtures/input.md", "Fixture input\n")
        self.assertTrue(self.push(self.commit()).native_required)

    def test_unknown_markdown_in_document_directories_still_runs(self):
        previous = self.initial
        for path in ["normative.md", "docs/validation/new-contract.md", "tools/bundle/README.md"]:
            with self.subTest(path=path):
                self.write(path, "Unreviewed Markdown input\n")
                head = self.commit()
                self.assertTrue(self.push(head, before=previous).native_required)
                previous = head

    def test_source_renamed_to_markdown_still_runs(self):
        (self.repo / "docs").mkdir()
        self.command("mv", "Sources/Value.swift", "docs/REPOSITORY_SCOPE.md")
        self.assertTrue(self.push(self.commit()).native_required)

    def test_deleted_source_still_runs(self):
        (self.repo / "Sources/Value.swift").unlink()
        self.assertTrue(self.push(self.commit()).native_required)

    def test_deleted_regular_documentation_can_skip(self):
        (self.repo / "README.md").unlink()
        self.assertFalse(self.push(self.commit()).native_required)

    def test_executable_markdown_still_runs(self):
        os.chmod(self.repo / "README.md", 0o755)
        self.assertTrue(self.push(self.commit()).native_required)

    def test_existing_source_symlink_prevents_doc_skip(self):
        (self.repo / "Sources/Indirect.swift").symlink_to("../README.md")
        linked = self.commit()
        self.write("README.md", "struct MarkdownBackedSource {}\n")
        self.assertTrue(self.push(self.commit(), before=linked).native_required)

    def test_submodule_prevents_doc_skip(self):
        self.command("update-index", "--add", "--cacheinfo", f"160000,{self.initial},Vendor/Dependency")
        self.command("commit", "--quiet", "-m", "Synthetic gitlink")
        linked = self.command("rev-parse", "HEAD")
        self.write("README.md", "Changed documentation\n")
        self.assertTrue(self.push(self.commit(), before=linked).native_required)

    def test_newline_path_cannot_impersonate_a_known_document(self):
        self.write("docs/line\nbreak.md", "Synthetic\n")
        result = self.push(self.commit())
        self.assertTrue(result.native_required)
        self.assertEqual(result.changed_files, 1)

    def test_unknown_events_empty_changes_and_bad_revisions_run(self):
        self.assertTrue(self.push().native_required)
        self.assertTrue(scope.choose(self.repo, event="workflow_dispatch", head=self.initial).native_required)
        self.assertTrue(scope.choose(self.repo, event="push", head=self.initial, before="0" * 40).native_required)
        self.assertTrue(scope.choose(self.repo, event="push", head=self.initial, before="f" * 40).native_required)
        self.assertTrue(scope.choose(self.repo, event="push", head="--help", before=self.initial).native_required)

    def test_divergent_push_and_checkout_mismatch_run(self):
        self.write("docs/one.md", "One\n")
        other = self.commit()
        self.command("checkout", "--quiet", "--detach", self.initial)
        self.write("docs/two.md", "Two\n")
        latest = self.commit()
        self.assertTrue(self.push(latest, before=other).native_required)
        self.assertTrue(self.push(other).native_required)

    def test_real_cli_reports_scope_and_boolean_output(self):
        self.write("docs/validation/native-scope.md", "Synthetic CLI\n")
        head = self.commit()
        output = self.repo / "output.txt"
        env = dict(os.environ, APPLE_CI_EVENT="push", APPLE_CI_HEAD=head,
                   APPLE_CI_BEFORE=self.initial, GITHUB_OUTPUT=str(output))
        result = subprocess.run([sys.executable, str(SOURCE)], cwd=self.repo, env=env,
                                check=True, capture_output=True, text=True)
        self.assertIn('"native_required": false', result.stdout)
        self.assertEqual(output.read_text(), "native_required=false\n")


    def test_finding_record_regular_changes_skip_exact_push_and_pr_comparisons(self):
        path = "docs/validation/issue-72-finding-explanations.md"
        previous = self.initial
        for action in ("add", "modify", "delete"):
            if action == "delete":
                (self.repo / path).unlink()
            else:
                self.write(path, f"Synthetic finding receipt: {action}\n")
            head = self.commit()
            with self.subTest(action=action, event="push"):
                result = self.push(head, before=previous)
                self.assertFalse(result.native_required)
                self.assertEqual(result.changed_files, 1)
            tree = self.command("rev-parse", "HEAD^{tree}")
            merge = self.command("commit-tree", tree, "-p", previous, "-p", head,
                                 input=b"Synthetic finding-record test merge\n")
            self.command("checkout", "--quiet", "--detach", merge)
            with self.subTest(action=action, event="pull_request"):
                result = scope.choose(self.repo, event="pull_request",
                                      head=merge, base=previous)
                self.assertFalse(result.native_required)
                self.assertEqual(result.changed_files, 1)
            self.command("checkout", "--quiet", "--detach", head)
            previous = head

    def test_finding_record_neighbor_and_mixed_source_changes_still_run(self):
        path = "docs/validation/issue-72-finding-explanations.md"
        for other in (
                path + ".extra",
                "docs/validation/issue-72-finding-explanations-copy.md",
                "Docs/validation/issue-72-finding-explanations.md",
                "Packages/PlannerUI/Tests/Fixtures/issue-72-finding-explanations.md",
                "Sources/Value.swift",
                ".github/workflows/native-ui.yml"):
            with self.subTest(other=other):
                self.command("reset", "--hard", self.initial)
                self.write(path, "Synthetic finding receipt\n")
                self.write(other, "Changed native or unreviewed input\n")
                result = self.push(self.commit())
                self.assertTrue(result.native_required)
                self.assertEqual(result.changed_files, 2)

    def test_finding_record_unsupported_modes_and_indirection_still_run(self):
        path = "docs/validation/issue-72-finding-explanations.md"
        for kind in ("executable", "symlink", "indirect-source", "source-rename"):
            with self.subTest(kind=kind):
                self.command("reset", "--hard", self.initial)
                target = self.repo / path
                target.parent.mkdir(parents=True, exist_ok=True)
                if kind == "source-rename":
                    self.command("mv", "Sources/Value.swift", path)
                elif kind == "symlink":
                    target.symlink_to("../../README.md")
                else:
                    self.write(path, "Synthetic finding receipt\n")
                    if kind == "executable":
                        os.chmod(target, 0o755)
                    else:
                        (self.repo / "Sources/Indirect.swift").symlink_to("../" + path)
                self.assertTrue(self.push(self.commit()).native_required)



    def test_maintenance_rejects_the_broader_documentation_and_tool_inputs(self):
        allowed = "docs/validation/issue-72-finding-explanations.md"
        # Enumerate the existing broader set; its membership is not permission
        # for the independent maintenance job. The expected allowance is literal.
        paths = scope.DOCUMENTATION_PATHS | {
            "tools/catalog-maintenance/README.md",
            "tools/catalog-maintenance/run.py",
            "tools/catalog-maintenance/fixture-manifest.json",
            ".github/workflows/catalog-maintenance.yml",
            allowed + ".extra",
            "Docs/validation/issue-72-finding-explanations.md",
            "Packages/PlannerTransfer/Resources/issue-72-finding-explanations.md",
        }
        self.assertIn(allowed, paths)
        for path in sorted(paths):
            with self.subTest(path=path):
                self.command("reset", "--hard", self.initial)
                self.write(path, "Changed maintenance comparison input\n")
                head = self.commit()
                result = scope.choose(self.repo, event="push", head=head,
                                      before=self.initial, job="macos-catalog-maintenance")
                self.assertEqual(result.native_required, path != allowed)
                self.assertEqual(result.changed_files, 1)

    def test_maintenance_exact_record_retains_merge_mode_and_tree_guards(self):
        path = "docs/validation/issue-72-finding-explanations.md"
        previous = self.initial
        for action in ("add", "modify", "delete"):
            if action == "delete":
                (self.repo / path).unlink()
            else:
                self.write(path, f"Synthetic maintenance comparison: {action}\n")
            head = self.commit()
            with self.subTest(action=action, event="push"):
                result = scope.choose(self.repo, event="push", head=head,
                                      before=previous, job="macos-catalog-maintenance")
                self.assertFalse(result.native_required)
                self.assertEqual(result.changed_files, 1)
            tree = self.command("rev-parse", "HEAD^{tree}")
            merge = self.command("commit-tree", tree, "-p", previous, "-p", head,
                                 input=b"Synthetic maintenance documentation merge\n")
            self.command("checkout", "--quiet", "--detach", merge)
            with self.subTest(action=action, event="pull_request"):
                result = scope.choose(self.repo, event="pull_request", head=merge,
                                      base=previous, job="macos-catalog-maintenance")
                self.assertFalse(result.native_required)
                self.assertEqual(result.changed_files, 1)
                self.assertTrue(scope.choose(
                    self.repo, event="pull_request", head=merge, base=head,
                    job="macos-catalog-maintenance").native_required)
            self.command("checkout", "--quiet", "--detach", head)
            previous = head

        for kind in ("executable", "symlink", "indirect-source", "source-rename", "mixed-source"):
            with self.subTest(kind=kind):
                self.command("reset", "--hard", self.initial)
                target = self.repo / path
                target.parent.mkdir(parents=True, exist_ok=True)
                if kind == "source-rename":
                    self.command("mv", "Sources/Value.swift", path)
                elif kind == "symlink":
                    target.symlink_to("../../README.md")
                else:
                    self.write(path, "Synthetic finding receipt\n")
                    if kind == "executable":
                        os.chmod(target, 0o755)
                    elif kind == "indirect-source":
                        (self.repo / "Sources/Indirect.swift").symlink_to("../" + path)
                    else:
                        self.write("Sources/Value.swift", "struct ChangedValue {}\n")
                head = self.commit()
                self.assertTrue(scope.choose(
                    self.repo, event="push", head=head, before=self.initial,
                    job="macos-catalog-maintenance").native_required)

    def test_maintenance_real_cli_requires_the_exact_document_and_valid_comparison(self):
        for path, valid, expected in (
                ("docs/validation/issue-72-finding-explanations.md", True, False),
                ("README.md", True, True),
                ("docs/validation/issue-72-finding-explanations.md", False, True)):
            with self.subTest(path=path, valid_comparison=valid):
                self.command("reset", "--hard", self.initial)
                self.write(path, "Synthetic CLI maintenance comparison\n")
                head = self.commit()
                output = self.repo / "scope-output.txt"
                env = dict(os.environ, APPLE_CI_EVENT="push", APPLE_CI_HEAD=head,
                           APPLE_CI_BEFORE=self.initial if valid else "0" * 40,
                           APPLE_CI_JOB="macos-catalog-maintenance", GITHUB_OUTPUT=str(output))
                result = subprocess.run([sys.executable, str(SOURCE)], cwd=self.repo, env=env,
                                        check=True, capture_output=True, text=True)
                try:
                    self.assertIs(json.loads(result.stdout)["native_required"], expected)
                    self.assertEqual(output.read_text(), f"native_required={str(expected).lower()}\n")
                finally:
                    output.unlink(missing_ok=True)


class AuditedPackageScopeTests(unittest.TestCase):
    command = NativeScopeTests.command
    write = NativeScopeTests.write
    commit = NativeScopeTests.commit
    packages = ("PlannerCore", "PlannerData", "PlannerTransfer", "PlannerCatalog", "PlannerUI")
    # Independent expected matrix from package tests and the two jobs' actual
    # Evidence/Cost harnesses and the App, including all four PlannerUI dependencies.
    affected = {
        "PlannerCore": {"macos-core", "macos-transfer", "native-ui"},
        "PlannerData": {"macos-core", "macos-storage", "macos-transfer", "native-ui"},
        "PlannerTransfer": {"macos-core", "macos-transfer", "native-ui"},
        "PlannerCatalog": {"macos-core", "macos-catalog-cache", "macos-transfer", "native-ui"},
        "PlannerUI": {"macos-core", "native-ui"},
    }

    def setUp(self):
        NativeScopeTests.setUp(self)
        for package in self.packages:
            self.write(f"Packages/{package}/Package.swift", "// Synthetic fixed dependencies\n")
            self.write(f"Packages/{package}/Sources/Value.swift", "struct Value {}\n")
            self.write(f"Packages/{package}/Tests/Fixtures/value.json", '{"synthetic": true}\n')
        for path in ("App/Planner.xcodeproj/project.pbxproj",
                     "App/Planner.xcodeproj/xcshareddata/xcschemes/Planner.xcscheme",
                     ".github/workflows/native-ui.yml", "App/scripts/launch.py",
                     "tools/storage/replay.py", "tools/conformance/mutations.py"):
            self.write(path, "Synthetic fixed native input\n")
        source = self.commit()
        leaves = {}
        for row in subprocess.check_output(["git", "ls-tree", "-r", "-z", source], cwd=self.repo).split(b"\0"):
            if row:
                fields, path = row.decode().split("\t", 1)
                leaves[path] = fields.split()
        dependencies = {f"Packages/{package}/Package.swift" for package in self.packages} | {
            "App/Planner.xcodeproj/project.pbxproj",
            "App/Planner.xcodeproj/xcshareddata/xcschemes/Planner.xcscheme",
        }
        jobs = {job: {} for job in {item for items in self.affected.values() for item in items}}
        for package, affected in self.affected.items():
            root = f"Packages/{package}"
            entry = ["040000", "tree", self.command("rev-parse", source + ":" + root)]
            for job in affected:
                jobs[job][root] = entry
        self.audit = {
            "version": 1, "source_revision": source,
            "dependencies": {path: leaves[path] for path in dependencies},
            "repository_inputs": {path: entry for path, entry in leaves.items()
                                  if not path.startswith("Packages/") and path != "README.md"},
            "jobs": jobs,
        }
        self.save_audit()
        self.initial = self.commit()

    def save_audit(self):
        self.write("tools/ci/native-inputs.json", json.dumps(self.audit, sort_keys=True) + "\n")

    def decide(self, job="macos-storage", before=None, head=None):
        return scope.choose(self.repo, event="push", job=job,
                            head=head or self.command("rev-parse", "HEAD"), before=before or self.initial)

    def change_package(self, package="PlannerCore"):
        self.write(f"Packages/{package}/Sources/Value.swift", "struct ChangedValue {}\n")
        return self.commit()

    def assert_all_native(self, before=None):
        for job in self.audit["jobs"]:
            with self.subTest(job=job):
                self.assertTrue(self.decide(job, before).native_required)

    def test_all_twenty_five_package_dependency_combinations(self):
        for package, affected in self.affected.items():
            self.command("reset", "--hard", self.initial)
            self.change_package(package)
            for job in self.audit["jobs"]:
                with self.subTest(package=package, job=job):
                    result = self.decide(job)
                    self.assertEqual(result.native_required, job in affected)
                    self.assertEqual(result.changed_files, 1)

    def test_legacy_transfer_test_closure_with_refreshed_pins_is_rejected(self):
        # The accepted Transfer target now links Core and Catalog. A refresh
        # that pins the current manifests but retains the old two-tree closure
        # must not allow their changes to skip the Transfer test job.
        original = json.dumps(self.audit)
        for package in ("PlannerCore", "PlannerCatalog"):
            with self.subTest(package=package):
                self.command("reset", "--hard", self.initial)
                self.audit = json.loads(original)
                self.audit["jobs"]["macos-transfer"].pop("Packages/PlannerCore")
                self.audit["jobs"]["macos-transfer"].pop("Packages/PlannerCatalog")
                self.save_audit()
                refreshed = self.commit()
                self.change_package(package)
                self.assertTrue(self.decide("macos-transfer", refreshed).native_required)

    def test_transfer_test_dependencies_include_added_and_deleted_resources(self):
        for package in ("PlannerCore", "PlannerCatalog"):
            for action in ("add", "delete"):
                with self.subTest(package=package, action=action):
                    self.command("reset", "--hard", self.initial)
                    if action == "add":
                        self.write(f"Packages/{package}/Tests/Fixtures/extra.md",
                                   "Synthetic test resource\n")
                    else:
                        (self.repo / f"Packages/{package}/Tests/Fixtures/value.json").unlink()
                    self.commit()
                    self.assertTrue(self.decide("macos-transfer").native_required)
                    self.assertFalse(self.decide("macos-storage").native_required)
                    self.assertTrue(self.decide("native-ui").native_required)

    def test_legacy_rendering_closures_with_refreshed_pins_are_rejected(self):
        # Current workflows render the UI through EvidenceHarness. Refreshing
        # only hashes must not resurrect the older package-only job closures.
        original = json.dumps(self.audit)
        for job, package in (("macos-core", "PlannerUI"),
                             ("macos-core", "PlannerData"),
                             ("native-ui", "PlannerCore")):
            with self.subTest(job=job, package=package):
                self.command("reset", "--hard", self.initial)
                self.audit = json.loads(original)
                self.audit["jobs"]["macos-core"].pop("Packages/PlannerUI", None)
                self.audit["jobs"]["macos-core"].pop("Packages/PlannerData", None)
                self.audit["jobs"]["native-ui"].pop("Packages/PlannerCore", None)
                self.save_audit()
                refreshed = self.commit()
                self.change_package(package)
                self.assertTrue(self.decide(job, refreshed).native_required)

    def test_rendering_dependencies_include_added_and_deleted_resources(self):
        for job, package in (("macos-core", "PlannerUI"),
                             ("macos-core", "PlannerData"),
                             ("native-ui", "PlannerCore")):
            for action in ("add", "delete"):
                with self.subTest(job=job, package=package, action=action):
                    self.command("reset", "--hard", self.initial)
                    if action == "add":
                        self.write(f"Packages/{package}/Tests/Fixtures/rendering.json",
                                   '{"synthetic": "rendering input"}\n')
                    else:
                        (self.repo / f"Packages/{package}/Tests/Fixtures/value.json").unlink()
                    self.commit()
                    self.assertTrue(self.decide(job).native_required)
                    self.assertFalse(self.decide("macos-catalog-cache").native_required)

    def test_legacy_imported_build_closures_with_refreshed_pins_are_rejected(self):
        # The selected real PlannerUI manifest now links Catalog and Transfer.
        # Neither a renderer nor the App may retain the earlier three-tree closure.
        original = json.dumps(self.audit)
        for job in ("macos-core", "native-ui"):
            for package in ("PlannerCatalog", "PlannerTransfer"):
                with self.subTest(job=job, package=package):
                    self.command("reset", "--hard", self.initial)
                    self.audit = json.loads(original)
                    for affected_job in ("macos-core", "native-ui"):
                        self.audit["jobs"][affected_job].pop("Packages/PlannerCatalog", None)
                        self.audit["jobs"][affected_job].pop("Packages/PlannerTransfer", None)
                    self.save_audit()
                    refreshed = self.commit()
                    self.change_package(package)
                    self.assertTrue(self.decide(job, refreshed).native_required)

    def test_imported_build_dependencies_include_added_and_deleted_resources(self):
        for job in ("macos-core", "native-ui"):
            for package in ("PlannerCatalog", "PlannerTransfer"):
                for action in ("add", "delete"):
                    with self.subTest(job=job, package=package, action=action):
                        self.command("reset", "--hard", self.initial)
                        if action == "add":
                            self.write(f"Packages/{package}/Tests/Fixtures/imported-build.json",
                                       '{"synthetic": "imported-build dependency"}\n')
                        else:
                            (self.repo / f"Packages/{package}/Tests/Fixtures/value.json").unlink()
                        self.commit()
                        self.assertTrue(self.decide(job).native_required)
                        self.assertFalse(self.decide("macos-storage").native_required)
                        self.assertEqual(self.decide("macos-catalog-cache").native_required,
                                         package == "PlannerCatalog")

    def test_added_test_resource_is_part_of_entire_package_tree(self):
        self.write("Packages/PlannerCore/Tests/NewTests/extra.md", "Synthetic executable test input\n")
        self.commit()
        self.assertTrue(self.decide("macos-core").native_required)
        self.assertFalse(self.decide("macos-storage").native_required)

    def test_deleted_resource_and_renamed_source_are_not_lost(self):
        (self.repo / "Packages/PlannerCore/Tests/Fixtures/value.json").unlink()
        self.command("mv", "Packages/PlannerCore/Sources/Value.swift", "Packages/PlannerCore/Sources/New.swift")
        self.commit()
        result = self.decide("macos-core")
        self.assertTrue(result.native_required)
        self.assertEqual(result.changed_files, 3)
        self.assertFalse(self.decide("macos-storage").native_required)

    def test_mixed_known_documentation_and_package_change(self):
        self.write("README.md", "Updated explanation\n")
        self.change_package()
        self.assertFalse(self.decide().native_required)
        self.assertEqual(self.decide().changed_files, 2)

    def test_changed_or_previously_drifted_manifests_run_all_jobs(self):
        for path in self.audit["dependencies"]:
            with self.subTest(path=path):
                self.command("reset", "--hard", self.initial)
                original = (self.repo / path).read_text()
                self.write(path, "Changed dependency closure\n")
                drifted = self.commit()
                self.assert_all_native()
                self.change_package()
                self.assert_all_native(before=drifted)
                self.command("reset", "--hard", drifted)
                self.write(path, original)
                self.commit()
                self.assert_all_native(before=drifted)

    def test_previously_changed_test_reader_keeps_its_job_running(self):
        self.write("Packages/PlannerCore/Tests/Reader.swift", 'let input = "../PlannerCatalog/fixture"\n')
        previous = self.commit()
        self.change_package("PlannerCatalog")
        self.assertTrue(self.decide("macos-core", previous).native_required)
        self.assertFalse(self.decide("macos-storage", previous).native_required)

    def test_restored_package_still_checks_previous_endpoint(self):
        previous = self.change_package()
        self.write("Packages/PlannerCore/Sources/Value.swift", "struct Value {}\n")
        self.commit()
        self.assertTrue(self.decide("macos-core", previous).native_required)
        self.assertFalse(self.decide("macos-storage", previous).native_required)

    def test_unknown_paths_and_package_prefix_lookalikes_run_all(self):
        for path in ("Packages/PlannerCoreExtra/Source.swift", "Packages/New/Package.swift",
                     "packages/PlannerCore/Source.swift", "docs/new-input.md", ".gitattributes"):
            with self.subTest(path=path):
                self.command("reset", "--hard", self.initial)
                self.write(path, "Unknown input\n")
                self.commit()
                self.assert_all_native()

    def test_prior_external_input_drift_cannot_hide_in_package_only_diff(self):
        for path in (".gitattributes", ".github/workflows/native-ui.yml", "App/scripts/launch.py",
                     "tools/storage/replay.py", "tools/conformance/mutations.py"):
            with self.subTest(path=path):
                self.command("reset", "--hard", self.initial)
                self.write(path, "Changed surrounding input\n")
                previous = self.commit()
                self.change_package()
                self.assert_all_native(before=previous)

    def test_executable_newline_and_symlink_package_inputs_run_all(self):
        self.change_package()
        os.chmod(self.repo / "Packages/PlannerCore/Sources/Value.swift", 0o755)
        self.commit()
        self.assert_all_native()
        self.command("reset", "--hard", self.initial)
        self.write("Packages/PlannerCore/Sources/new\nline.swift", "Synthetic\n")
        self.commit()
        self.assert_all_native()
        self.command("reset", "--hard", self.initial)
        (self.repo / "Packages/PlannerCore/Sources/Indirect.swift").symlink_to("../../../README.md")
        previous = self.commit()
        self.change_package("PlannerCatalog")
        self.assert_all_native(before=previous)

    def test_submodule_and_source_type_change_run_all(self):
        self.command("update-index", "--add", "--cacheinfo", f"160000,{self.initial},Packages/PlannerCore/Vendor")
        self.command("commit", "--quiet", "-m", "Synthetic package gitlink")
        self.assert_all_native()
        self.command("reset", "--hard", self.initial)
        target = self.repo / "Packages/PlannerCore/Sources/Value.swift"
        target.unlink()
        target.symlink_to("../../../README.md")
        self.commit()
        self.assert_all_native()

    def test_missing_and_unknown_job_identity_keep_native(self):
        self.change_package()
        for job in ("", "macos", "macos-storage\n", "--help"):
            self.assertTrue(self.decide(job).native_required)

    def test_missing_audit_does_not_use_an_untracked_working_copy(self):
        self.command("rm", "tools/ci/native-inputs.json")
        previous = self.commit()
        self.change_package()
        self.save_audit()
        self.assert_all_native(before=previous)

    def test_modified_working_copy_cannot_replace_tracked_audit(self):
        self.change_package()
        self.write("tools/ci/native-inputs.json", "This is not the committed Git blob\n")
        self.assertFalse(self.decide().native_required)

    def test_malformed_duplicate_oversized_and_incomplete_audits_run(self):
        invalid = ["{}", "[]", '{"version":1,"version":1}', "[" * 1000,
                   " " * (scope.MAX_AUDIT_BYTES + 1)]
        for raw in invalid:
            with self.subTest(raw=raw[:40]):
                self.command("reset", "--hard", self.initial)
                self.write("tools/ci/native-inputs.json", raw)
                previous = self.commit()
                self.change_package()
                self.assert_all_native(before=previous)

    def test_corrupted_pins_and_omitted_inputs_do_not_select_a_skip(self):
        original = json.dumps(self.audit)
        mutations = [
            lambda a: a.update(version=True),
            lambda a: a.update(source_revision="f" * 40),
            lambda a: a["jobs"]["native-ui"].pop("Packages/PlannerData"),
            lambda a: a["dependencies"].pop("Packages/PlannerData/Package.swift"),
            lambda a: a["repository_inputs"].pop("App/scripts/launch.py"),
            lambda a: a["repository_inputs"]["App/scripts/launch.py"].__setitem__(2, "0" * 40),
            lambda a: a["jobs"]["macos-storage"]["Packages/PlannerData"].__setitem__(1, "blob"),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                self.command("reset", "--hard", self.initial)
                self.audit = json.loads(original)
                mutate(self.audit)
                self.save_audit()
                previous = self.commit()
                self.change_package()
                self.assert_all_native(before=previous)
        self.audit = json.loads(original)

    def test_package_only_exact_pr_merge_and_cli(self):
        topic = self.change_package()
        tree = self.command("rev-parse", "HEAD^{tree}")
        merge = self.command("commit-tree", tree, "-p", self.initial, "-p", topic,
                             input=b"Synthetic audited PR merge\n")
        self.command("checkout", "--quiet", "--detach", merge)
        result = scope.choose(self.repo, event="pull_request", head=merge, base=self.initial, job="macos-storage")
        self.assertFalse(result.native_required)
        output = self.repo / "output.txt"
        env = dict(os.environ, APPLE_CI_EVENT="pull_request", APPLE_CI_HEAD=merge,
                   APPLE_CI_BASE=self.initial, APPLE_CI_JOB="macos-storage", GITHUB_OUTPUT=str(output))
        result = subprocess.run([sys.executable, str(SOURCE)], cwd=self.repo, env=env,
                                check=True, capture_output=True, text=True)
        self.assertFalse(json.loads(result.stdout)["native_required"])
        self.assertEqual(output.read_text(), "native_required=false\n")


    def test_finding_record_does_not_hide_package_or_prior_audit_drift(self):
        path = "docs/validation/issue-72-finding-explanations.md"
        self.write(path, "Synthetic finding receipt\n")
        self.commit()
        for job in self.audit["jobs"]:
            with self.subTest(case="only-record", job=job):
                self.assertFalse(self.decide(job).native_required)

        self.command("reset", "--hard", self.initial)
        self.write(path, "Synthetic finding receipt\n")
        self.change_package("PlannerCore")
        for job in self.audit["jobs"]:
            with self.subTest(case="mixed-package", job=job):
                result = self.decide(job)
                self.assertEqual(result.native_required, job in self.affected["PlannerCore"])
                self.assertEqual(result.changed_files, 2)

        for drift in ("Packages/PlannerData/Package.swift", ".github/workflows/native-ui.yml"):
            with self.subTest(case="prior-drift", path=drift):
                self.command("reset", "--hard", self.initial)
                self.write(drift, "Changed synthetic native input\n")
                previous = self.commit()
                self.write(path, "Synthetic finding receipt\n")
                self.change_package("PlannerCore")
                self.assert_all_native(before=previous)



    def test_maintenance_never_uses_a_package_audit_skip(self):
        job = "macos-catalog-maintenance"
        self.assertNotIn(job, scope.JOB_INPUTS)
        self.assertNotIn(job, self.audit["jobs"])
        for package in self.packages:
            for with_record in (False, True):
                with self.subTest(package=package, with_record=with_record):
                    self.command("reset", "--hard", self.initial)
                    if with_record:
                        self.write("docs/validation/issue-72-finding-explanations.md",
                                   "Synthetic finding receipt\n")
                    self.change_package(package)
                    result = self.decide(job)
                    self.assertTrue(result.native_required)
                    self.assertEqual(result.changed_files, 2 if with_record else 1)
                    self.assertEqual(result.reason, "No audited native job identity")


if __name__ == "__main__":
    unittest.main()
