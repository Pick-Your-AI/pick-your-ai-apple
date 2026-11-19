"""Fresh-child CLI checks using synthetic exports of the captured acceptance map."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SECTIONS = (
    ('acceptance_criteria_markdown', 'Acceptance criteria'),
    ('implementation_subtasks_markdown', 'Implementation subtasks'),
    ('prerequisites_markdown', 'Prerequisites'),
    ('delivery_output_markdown', 'Delivery output and review boundary'),
    ('validation_markdown', 'Validation and evidence'),
)


def source_row(record):
    return {
        'number': record['number'],
        'title': record['title'],
        'state': record['state'],
        'updated_at': record['updated_at'],
        'assignees': [{'login': login} for login in record['assignees']],
        'body': '\n\n'.join(
            f'## {heading}\n{record[key]}' for key, heading in SECTIONS
        ) + '\n',
    }


class CheckMapCLITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper_bytes = (ROOT / 'tools/acceptance/check_map.py').read_bytes()
        cls.map_bytes = (ROOT / 'docs/acceptance/issues.json').read_bytes()
        cls.captured = json.loads(cls.map_bytes)
        cls.rows = [source_row(record) for record in cls.captured['issues']]
        cls.success = 'PASS: 129 issues, 465 exact criteria; '

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.helper = self.root / 'tools/acceptance/check_map.py'
        self.map_path = self.root / 'docs/acceptance/issues.json'
        self.source = self.root / 'source.json'
        self.helper.parent.mkdir(parents=True)
        self.map_path.parent.mkdir(parents=True)
        self.helper.write_bytes(self.helper_bytes)
        self.map_path.write_bytes(self.map_bytes)

    def run_check(self, rows=None, *, source_text=None):
        command = [sys.executable, '-I']
        if sys.flags.optimize:
            command.append('-O')
        command.append(str(self.helper))
        if rows is not None or source_text is not None:
            self.source.write_text(source_text if source_text is not None else json.dumps(rows, ensure_ascii=False) + '\n')
            source_before = self.source.read_bytes()
            command.extend(['--source', str(self.source)])
        map_before = self.map_path.read_bytes()
        result = subprocess.run(
            command, cwd=self.root, capture_output=True, text=True, timeout=10,
            check=False,
        )
        self.assertEqual(self.map_path.read_bytes(), map_before)
        self.assertEqual(self.helper.read_bytes(), self.helper_bytes)
        if rows is not None or source_text is not None:
            self.assertEqual(self.source.read_bytes(), source_before)
        return result

    def assert_pass(self, result, *, source=True):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        suffix = 'source preservation verified' if source else 'internal coverage verified'
        self.assertEqual(result.stdout, self.success + suffix + '\n')

    def assert_rejected(self, result, message):
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertEqual(result.stderr, message + '\n')

    def test_captured_map_internal_coverage(self):
        self.assert_pass(self.run_check(), source=False)

    def test_unique_export_preserves_all_captured_rows(self):
        self.assert_pass(self.run_check(self.rows))

    def test_unique_export_order_is_irrelevant(self):
        self.assert_pass(self.run_check(list(reversed(self.rows))))

    def test_pull_request_rows_are_filtered_before_duplicate_checks(self):
        pr = {'number': 1, 'title': 'Synthetic PR, not an issue', 'pull_request': {}}
        rows = [pr, {'pull_request': {}}] + self.rows + [copy.deepcopy(pr)]
        self.assert_pass(self.run_check(rows))

    def test_changed_then_captured_duplicate_is_rejected(self):
        changed = copy.deepcopy(self.rows[0])
        changed['title'] += ' [synthetic changed observation]'
        self.assert_rejected(
            self.run_check([changed] + self.rows),
            '#1: duplicate source issue; refresh paginated export',
        )

    def test_captured_then_changed_duplicate_is_rejected(self):
        changed = copy.deepcopy(self.rows[0])
        changed['title'] += ' [synthetic changed observation]'
        self.assert_rejected(
            self.run_check(self.rows + [changed]),
            '#1: duplicate source issue; refresh paginated export',
        )

    def test_identical_issue_duplicate_is_rejected(self):
        self.assert_rejected(
            self.run_check(self.rows + [copy.deepcopy(self.rows[0])]),
            '#1: duplicate source issue; refresh paginated export',
        )

    def test_duplicate_of_last_captured_issue_is_rejected(self):
        self.assert_rejected(
            self.run_check(self.rows + [copy.deepcopy(self.rows[-1])]),
            '#129: duplicate source issue; refresh paginated export',
        )

    def test_missing_source_issue_is_rejected(self):
        self.assert_rejected(
            self.run_check(self.rows[:-1]), 'Source issue set changed; refresh map',
        )

    def test_extra_source_issue_is_rejected(self):
        extra = copy.deepcopy(self.rows[0])
        extra['number'] = 130
        self.assert_rejected(
            self.run_check(self.rows + [extra]), 'Source issue set changed; refresh map',
        )

    def test_changed_source_metadata_is_still_rejected(self):
        changes = (
            ('title', 'Synthetic changed title'),
            ('state', 'closed'),
            ('updated_at', '2026-10-19T00:00:00Z'),
            ('assignees', [{'login': 'synthetic-owner'}]),
        )
        for key, value in changes:
            with self.subTest(field=key):
                rows = copy.deepcopy(self.rows)
                rows[0][key] = value
                self.assert_rejected(self.run_check(rows), f'#1: {key} changed')

    def test_changed_source_sections_are_still_rejected(self):
        for key, heading in SECTIONS:
            with self.subTest(section=heading):
                record = copy.deepcopy(self.captured['issues'][0])
                record[key] += '\nSynthetic changed section.'
                rows = [source_row(record)] + self.rows[1:]
                message = 'validation differs' if key == 'validation_markdown' else f'{heading} differs from source'
                self.assert_rejected(self.run_check(rows), f'#1: {message}')

    def test_legacy_validation_heading_remains_supported(self):
        rows = copy.deepcopy(self.rows)
        for row in rows:
            row['body'] = row['body'].replace('## Validation and evidence\n', '## Validation\n')
        self.assert_pass(self.run_check(rows))

    def test_duplicate_rejection_then_repaired_export_succeeds(self):
        self.assert_rejected(
            self.run_check(self.rows + [copy.deepcopy(self.rows[0])]),
            '#1: duplicate source issue; refresh paginated export',
        )
        self.assert_pass(self.run_check(self.rows))

    def test_existing_map_invariants_are_still_rejected(self):
        for defect, message in (
            ('duplicate', 'Duplicate issues'),
            ('scope', 'Expected baseline issues 1–129; reconcile changed scope explicitly'),
            ('empty', '#1: empty acceptance criteria'),
            ('criteria', '#1: parsed criteria differ'),
            ('intake', '#1: missing intake/action'),
            ('completion', '#1: unsupported completion claim'),
        ):
            with self.subTest(defect=defect):
                data = copy.deepcopy(self.captured)
                records = data['issues']
                if defect == 'duplicate':
                    records[1]['number'] = records[0]['number']
                elif defect == 'scope':
                    records.pop()
                elif defect == 'empty':
                    records[0]['acceptance_criteria_markdown'] = ''
                elif defect == 'criteria':
                    records[0]['criteria'][0]['text'] += ' changed'
                elif defect == 'intake':
                    records[0]['next_executable_action'] = ''
                elif defect == 'completion':
                    records[0]['criterion_completion_claimed'] = True
                self.map_path.write_text(json.dumps(data, ensure_ascii=False) + '\n')
                self.assert_rejected(self.run_check(), message)

    def test_source_issue_identity_requires_a_positive_integer(self):
        for value in (True, 1.0, False, 0, -1, '1', None, [], {}):
            with self.subTest(value=value, type=type(value).__name__):
                rows = copy.deepcopy(self.rows)
                rows[0]['number'] = value
                self.assert_rejected(
                    self.run_check(rows),
                    'Source issue numbers must be positive integers',
                )

    def test_captured_issue_identity_requires_a_positive_integer(self):
        for value in (True, 1.0, False, 0, -1, '1', None, [], {}):
            for compare_source in (False, True):
                with self.subTest(value=value, type=type(value).__name__, source=compare_source):
                    data = copy.deepcopy(self.captured)
                    data['issues'][0]['number'] = value
                    self.map_path.write_text(json.dumps(data, ensure_ascii=False) + '\n')
                    self.assert_rejected(
                        self.run_check(self.rows if compare_source else None),
                        'Captured issue numbers must be positive integers',
                    )

    def test_pull_request_identity_values_remain_outside_issue_admission(self):
        filtered = [
            {'number': value, 'pull_request': {}}
            for value in (True, 1.0, False, 0, -1, '1', None, [], {})
        ]
        self.assert_pass(self.run_check(filtered + self.rows + [{'pull_request': {}}]))

    def test_invalid_identity_rejection_then_repaired_inputs_succeed(self):
        rows = copy.deepcopy(self.rows)
        rows[0]['number'] = True
        self.assert_rejected(
            self.run_check(rows), 'Source issue numbers must be positive integers',
        )
        self.assert_pass(self.run_check(self.rows))
        data = copy.deepcopy(self.captured)
        data['issues'][0]['number'] = 1.0
        self.map_path.write_text(json.dumps(data, ensure_ascii=False) + '\n')
        self.assert_rejected(
            self.run_check(self.rows), 'Captured issue numbers must be positive integers',
        )
        self.map_path.write_bytes(self.map_bytes)
        self.assert_pass(self.run_check(), source=False)
        self.assert_pass(self.run_check(self.rows))

    def test_numeric_checkbox_aliases_reject_and_literal_states_recover(self):
        for marker, checked, aliases in ((' ', False, (0, 0.0)), ('x', True, (1, 1.0)), ('X', True, (1, 1.0))):
            for alias in aliases:
                for compare_source in (False, True):
                    with self.subTest(marker=marker, alias=alias, type=type(alias).__name__, source=compare_source):
                        data = copy.deepcopy(self.captured)
                        record = data['issues'][0]
                        record['acceptance_criteria_markdown'] = record['acceptance_criteria_markdown'].replace('- [ ]', f'- [{marker}]', 1)
                        criterion = record['criteria'][0]
                        criterion['source_checked'] = checked
                        rows = [source_row(record)] + self.rows[1:]
                        source = rows if compare_source else None
                        self.map_path.write_text(json.dumps(data, ensure_ascii=False) + '\n')
                        self.assert_pass(self.run_check(source), source=compare_source)

                        criterion['source_checked'] = alias
                        self.map_path.write_text(json.dumps(data, ensure_ascii=False) + '\n')
                        self.assert_rejected(
                            self.run_check(source), '#1: source checkbox states must be booleans',
                        )

                        criterion['source_checked'] = checked
                        self.map_path.write_text(json.dumps(data, ensure_ascii=False) + '\n')
                        self.assert_pass(self.run_check(source), source=compare_source)

    def test_literal_checkbox_states_still_have_to_match_source_markdown(self):
        for marker, checked in ((' ', False), ('x', True), ('X', True)):
            for compare_source in (False, True):
                with self.subTest(marker=marker, source=compare_source):
                    data = copy.deepcopy(self.captured)
                    record = data['issues'][0]
                    record['acceptance_criteria_markdown'] = record['acceptance_criteria_markdown'].replace('- [ ]', f'- [{marker}]', 1)
                    record['criteria'][0]['source_checked'] = not checked
                    rows = [source_row(record)] + self.rows[1:]
                    self.map_path.write_text(json.dumps(data, ensure_ascii=False) + '\n')
                    self.assert_rejected(
                        self.run_check(rows if compare_source else None), '#1: parsed criteria differ',
                    )

    def test_source_duplicate_members_cannot_shadow_changed_metadata(self):
        original = '"title": ' + json.dumps(self.rows[0]['title'])
        changed = '"title": "Synthetic changed observation"'
        for replacement in (changed + ', ' + original, original + ', ' + changed,
                            original + ', ' + original):
            with self.subTest(replacement=replacement):
                raw = json.dumps(self.rows).replace(original, replacement, 1)
                self.assert_rejected(self.run_check(source_text=raw),
                                     "Source export: duplicate JSON object member 'title'")
        self.assert_pass(self.run_check(self.rows))

    def test_map_duplicate_members_cannot_shadow_checkbox_states(self):
        for replacement in ('"source_checked": true, "source_checked": false',
                            '"source_checked": false, "source_checked": true',
                            '"source_checked": false, "source_checked": false'):
            for compare_source in (False, True):
                with self.subTest(replacement=replacement, source=compare_source):
                    raw = self.map_bytes.decode().replace('"source_checked": false', replacement, 1)
                    self.assertNotEqual(raw, self.map_bytes.decode())
                    self.map_path.write_text(raw)
                    self.assert_rejected(self.run_check(self.rows if compare_source else None),
                                         "Captured map: duplicate JSON object member 'source_checked'")
        self.map_path.write_bytes(self.map_bytes)
        self.assert_pass(self.run_check(), source=False)
        self.assert_pass(self.run_check(self.rows))

    def test_nested_source_members_are_checked_before_filtering_pr_rows(self):
        # Ambiguous JSON is rejected even if the containing row is not an issue.
        raw = '[{"pull_request": {}, "metadata": {"state": "old", "state": "new"}},' + json.dumps(self.rows)[1:]
        self.assert_rejected(self.run_check(source_text=raw),
                             "Source export: duplicate JSON object member 'state'")
        self.assert_pass(self.run_check([{'pull_request': {}, 'metadata': {'state': 'new'}}] + self.rows))

    def test_escaped_member_names_collide_after_json_decoding(self):
        title = json.dumps(self.rows[0]['title'])
        raw = json.dumps(self.rows).replace('"title": ' + title,
                                           '"title": ' + title + ', "ti\\u0074le": ' + title, 1)
        self.assert_rejected(self.run_check(source_text=raw),
                             "Source export: duplicate JSON object member 'title'")
        raw = self.map_bytes.decode().replace('"source_checked": false',
            '"source_checked": false, "source_chec\\u006bed": false', 1)
        self.map_path.write_text(raw)
        self.assert_rejected(self.run_check(),
                             "Captured map: duplicate JSON object member 'source_checked'")

    def test_distinct_member_names_and_same_names_in_separate_objects_remain_valid(self):
        rows = copy.deepcopy(self.rows)
        for row in rows:
            row['Title'] = 'Distinct from title'
            row['metadata'] = {'title': 'Different object, same allowed member name'}
        self.assert_pass(self.run_check(rows))

    def test_malformed_json_has_input_specific_diagnostic(self):
        result = self.run_check(source_text='[')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertTrue(result.stderr.startswith('Source export: invalid JSON: '), result.stderr)
        self.assertNotIn('Traceback', result.stderr)
        self.map_path.write_text('{')
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertTrue(result.stderr.startswith('Captured map: invalid JSON: '), result.stderr)
        self.assertNotIn('Traceback', result.stderr)


if __name__ == '__main__':
    unittest.main()
