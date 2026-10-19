"""Preserve Graph validation when composing the seven-corpus reference gate.

All inputs are disposable copies of the unchanged frozen schema and fixtures.
The inherited observation helper calls the real installed reference validator.
"""

import json
import unittest

import reference_helper_checks as helpers


class GraphReferenceChecks(unittest.TestCase):
    run_copy = helpers.ReferenceHelperChecks.run_copy
    require_failure = helpers.ReferenceHelperChecks.require_failure

    def test_graph_generator_invariants_reject_in_all_python_modes(self):
        cases = (
            ('dependent_kind', 'count', 'Expected exactly 29 dependency graph kinds'),
            ('depends_on_kind', 'count', 'Expected exactly 29 dependency graph kinds'),
            ('relationship', 'count', 'Expected four dependency graph relationships and eight activations'),
            ('activation', 'count', 'Expected four dependency graph relationships and eight activations'),
            ('relationship', 'duplicate', 'Duplicate dependency graph vector names'),
        )
        for field, change, diagnostic in cases:
            def mutate(root):
                path = root / 'Sources/PlannerTransfer/Resources/dependency-graph.schema.json'
                schema = json.loads(path.read_text())
                values = schema['properties']['edges']['items']['properties'][field]['enum']
                if change == 'count':
                    values.pop()
                else:
                    values[1] = values[0]
                path.write_text(json.dumps(schema))

            for mode in helpers.MODES:
                with self.subTest(field=field, change=change, mode=mode):
                    result, trace = self.run_copy(mode, mutate, script='dependency_graph_vectors.py')
                    self.require_failure(result, diagnostic)
                    self.assertNotIn('deterministic generation verified', result.stdout)
                    self.assertEqual(trace['validator_calls'], 0)

    def test_missing_graph_inputs_never_emit_success_receipts(self):
        for relative in (
            'Sources/PlannerTransfer/Resources/dependency-graph.schema.json',
            'Tests/PlannerTransferTests/Fixtures/dependency-graph.json',
            'Tests/PlannerTransferTests/Fixtures/dependency-graph-conformance.json',
        ):
            def remove(root):
                (root / relative).unlink()

            for mode in helpers.MODES:
                with self.subTest(input=relative, mode=mode):
                    result, _ = self.run_copy(mode, remove)
                    self.require_failure(result, 'FileNotFoundError')
