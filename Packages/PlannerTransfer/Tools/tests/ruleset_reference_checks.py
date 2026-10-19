"""Preserve Ruleset validation in the complete eight-corpus reference gate.

Every altered schema or fixture is an owned disposable copy. The observation
helper still invokes the installed canonical validator on each supplied case.
"""

import json
import unittest

import reference_helper_checks as helpers


class RulesetReferenceChecks(unittest.TestCase):
    run_copy = helpers.ReferenceHelperChecks.run_copy
    require_failure = helpers.ReferenceHelperChecks.require_failure

    def test_ruleset_generator_rejects_duplicate_names_in_all_python_modes(self):
        def duplicate_metric(root):
            path = root / 'Sources/PlannerTransfer/Resources/ruleset.schema.json'
            schema = json.loads(path.read_text())
            metrics = schema['$defs']['operand']['oneOf'][1]['properties']['metric']['enum']
            metrics[1] = metrics[0]
            path.write_text(json.dumps(schema))

        for mode in helpers.MODES:
            with self.subTest(mode=mode):
                result, trace = self.run_copy(mode, duplicate_metric, script='ruleset_vectors.py')
                self.require_failure(result, 'Duplicate ruleset vector names')
                self.assertNotIn('deterministic generation verified', result.stdout)
                self.assertEqual(trace['validator_calls'], 0)

    def test_missing_ruleset_inputs_never_emit_success_receipts(self):
        for relative in (
            'Sources/PlannerTransfer/Resources/ruleset.schema.json',
            'Tests/PlannerTransferTests/Fixtures/ruleset.json',
            'Tests/PlannerTransferTests/Fixtures/ruleset-conformance.json',
        ):
            def remove(root):
                (root / relative).unlink()

            for mode in helpers.MODES:
                with self.subTest(input=relative, mode=mode):
                    result, _ = self.run_copy(mode, remove)
                    self.require_failure(result, 'FileNotFoundError')
