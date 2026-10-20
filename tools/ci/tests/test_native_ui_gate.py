"""Execute the literal result-only gate against every declared result tuple."""
import itertools
import os
from pathlib import Path
import subprocess
import textwrap
import unittest


class NativeResultGateTests(unittest.TestCase):
    def test_all_4096_scope_and_native_result_tuples(self):
        workflow = Path(__file__).resolve().parents[3] / '.github/workflows/native-ui.yml'
        job = workflow.read_text().split('\n  native-ui:\n', 1)[1]
        script = textwrap.dedent(job.split('        run: |\n', 1)[1])
        outcomes = ('success', 'failure', 'cancelled', 'skipped')
        required_values = ('true', 'false', '', 'unexpected')
        failures, observed, successes = [], 0, 0
        for scope, required, *native in itertools.product(outcomes, required_values, *([outcomes] * 4)):
            expected = scope == 'success' and (
                (required == 'true' and native == ['success'] * 4) or
                (required == 'false' and native == ['skipped'] * 4))
            env = {**os.environ, 'SCOPE_RESULT': scope, 'NATIVE_REQUIRED': required,
                   **dict(zip(('RENDERING_RESULT', 'SIMULATOR_RESULT', 'COST_RESULT', 'JOURNEYS_RESULT'), native))}
            result = subprocess.run(['bash', '-c', script], env=env, capture_output=True, timeout=2)
            actual = result.returncode == 0
            observed += 1; successes += actual
            if actual != expected:
                failures.append({'scope': scope, 'required': required, 'native': native, 'exit': result.returncode})
        self.assertEqual(observed, 4096)
        self.assertFalse(failures, failures[:8])
        self.assertEqual(successes, 2)


if __name__ == '__main__':
    unittest.main()
