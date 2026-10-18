"""Real Git regressions for the conservative native allocation boundary."""

import importlib.util
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


if __name__ == "__main__":
    unittest.main()
