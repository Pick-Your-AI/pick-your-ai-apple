"""Guard the privileged workflow boundary without executing expressions or network I/O."""
import ast
from pathlib import Path
import re
import unittest


WORKFLOW = Path(__file__).resolve().parents[3] / ".github/workflows/obsolete-pr-checks.yml"


def evaluate(expression, context):
    """Interpret only the boolean/comparison subset used by the actual job guard."""
    tree = ast.parse(expression.replace("&&", " and ").replace("||", " or "), mode="eval")

    def value(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name) and node.id == "github":
            return context
        if isinstance(node, ast.Attribute):
            owner = value(node.value)
            return owner.get(node.attr, "") if isinstance(owner, dict) else ""
        if isinstance(node, ast.BoolOp) and isinstance(node.op, (ast.And, ast.Or)):
            parts = [bool(value(part)) for part in node.values]
            return all(parts) if isinstance(node.op, ast.And) else any(parts)
        if isinstance(node, ast.Compare) and len(node.ops) == 1 and isinstance(node.ops[0], ast.Eq):
            return value(node.left) == value(node.comparators[0])
        raise AssertionError("Unsupported workflow expression; review its trust boundary")

    return bool(value(tree.body))


class ObsoleteWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = WORKFLOW.read_text()
        cls.safety, cls.retire = cls.workflow.split("  safety-tests:\n", 1)[1].split("\n  retire:\n", 1)
        guard = re.search(r"^    if: >-\n((?:[ ]{6,}[^\n]+\n)+)", cls.retire, re.MULTILINE)
        if guard is None:
            raise AssertionError("Missing explicit maintenance job guard")
        cls.guard = " ".join(guard.group(1).split())

    def context(self, event="pull_request_target", action="closed", base="main", state="closed"):
        return {
            "repository": "Pick-Your-AI/pick-your-ai-apple",
            "ref": "refs/heads/main",
            "event_name": event,
            "event": {"action": action, "pull_request": {"state": state, "base": {"ref": base}}},
        }

    def test_only_closed_main_target_events_are_subscribed(self):
        trigger = re.search(r"^  pull_request_target:\n((?:    [^\n]+\n)+)", self.workflow, re.MULTILINE)
        self.assertIsNotNone(trigger)
        self.assertEqual(trigger.group(1).splitlines(), ["    types: [closed]", "    branches: [main]"])

    def test_closed_main_pr_allows_metadata_maintenance(self):
        for merged in (False, True):
            with self.subTest(merged=merged):
                context = self.context()
                context["event"]["pull_request"]["merged"] = merged
                self.assertTrue(evaluate(self.guard, context))

    def test_opened_reopened_and_non_main_closures_are_rejected(self):
        for context in (
            self.context(action="opened", state="open"),
            self.context(action="reopened", state="open"),
            self.context(state="open"),
            self.context(base="integration/signed-candidate"),
            self.context(base=""),
        ):
            with self.subTest(context=context):
                self.assertFalse(evaluate(self.guard, context))

    def test_ordinary_pr_code_cannot_enter_mutation_job(self):
        for ref in ("refs/pull/12/merge", "refs/heads/main"):
            context = self.context(event="pull_request")
            context["ref"] = ref
            self.assertFalse(evaluate(self.guard, context))

    def test_existing_main_maintenance_events_remain_allowed(self):
        for event in ("push", "workflow_run", "workflow_dispatch"):
            with self.subTest(event=event):
                context = self.context(event=event)
                context["event"] = {}
                self.assertTrue(evaluate(self.guard, context))

    def test_foreign_repositories_and_non_main_refs_are_rejected_for_every_event(self):
        for event in ("push", "workflow_run", "workflow_dispatch", "pull_request_target"):
            for key, rejected in (("repository", "someone/fork"), ("ref", "refs/heads/feature"), ("ref", "refs/tags/main")):
                with self.subTest(event=event, key=key, rejected=rejected):
                    context = self.context(event=event)
                    context[key] = rejected
                    self.assertFalse(evaluate(self.guard, context))

    def test_unknown_or_missing_event_context_is_rejected(self):
        self.assertFalse(evaluate(self.guard, self.context(event="issue_comment")))
        context = self.context()
        context["event"] = {}
        self.assertFalse(evaluate(self.guard, context))

    def test_both_jobs_use_only_pinned_checkout_and_immutable_event_sha(self):
        for job in (self.safety, self.retire):
            self.assertEqual(re.findall(r"uses: ([^\s]+)", job),
                             ["actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"])
            self.assertEqual(job.count("ref: ${{ github.sha }}"), 1)
            self.assertEqual(job.count("persist-credentials: false"), 1)
        self.assertEqual(re.findall(r"(?m)^        run: (.+)$", self.retire),
                         ["python3 tools/ci/retire_obsolete_pr_runs.py --apply"])
        self.assertEqual(set(re.findall(r"\$\{\{\s*([^}]+?)\s*\}\}", self.retire.split("    steps:\n", 1)[1])),
                         {"github.sha", "github.token", "github.event.action",
                          "github.event.pull_request.state", "github.event.pull_request.base.ref"})

    def test_job_permissions_are_explicit_and_minimal(self):
        def permissions(job):
            match = re.search(r"^    permissions:\n((?:      [^\n]+\n)+)", job, re.MULTILINE)
            self.assertIsNotNone(match)
            return dict(line.strip().split(": ", 1) for line in match.group(1).splitlines())

        self.assertEqual(permissions(self.safety), {"contents": "read"})
        self.assertEqual(permissions(self.retire),
                         {"contents": "read", "pull-requests": "read", "actions": "write"})
        self.assertNotIn("GITHUB_TOKEN:", self.safety)
        self.assertNotIn("secrets.", self.workflow)


if __name__ == "__main__":
    unittest.main()
