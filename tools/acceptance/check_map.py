#!/usr/bin/env python3
"""Check acceptance-map coverage; optionally compare a fresh paginated issue export."""
import argparse
import json
from pathlib import Path
import re


def section(body, heading):
    match = re.search(r'^## ' + re.escape(heading) + r'\n(.*?)(?=^## |\Z)', body, re.M | re.S)
    return match.group(1).strip() if match else ''


def check(condition, message):
    if not condition:
        raise SystemExit(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, help='JSON array of full REST issue objects, all pages')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    data = json.loads((root / 'docs/acceptance/issues.json').read_text())
    records = data['issues']
    numbers = [r['number'] for r in records]
    check(len(numbers) == len(set(numbers)), 'Duplicate issues')
    check(set(numbers) == set(range(1, 130)), 'Expected baseline issues 1–129; reconcile changed scope explicitly')
    count = 0
    for record in records:
        n = record['number']
        exact = re.findall(r'^- \[([ xX])\] (.*(?:\n(?!- \[).+)*)', record['acceptance_criteria_markdown'], re.M)
        check(exact, f'#{n}: empty acceptance criteria')
        check([(r['source_checked'], r['text']) for r in record['criteria']] == [(c.lower() == 'x', t) for c, t in exact], f'#{n}: parsed criteria differ')
        check(record['next_executable_action'] and record['updated_at'] and record['project'], f'#{n}: missing intake/action')
        check(record['criterion_completion_claimed'] is False, f'#{n}: unsupported completion claim')
        count += len(exact)
    if args.source:
        source = {}
        for original in json.loads(args.source.read_text()):
            if 'pull_request' in original:
                continue
            n = original['number']
            check(n not in source, f'#{n}: duplicate source issue; refresh paginated export')
            source[n] = original
        check(set(source) == set(numbers), 'Source issue set changed; refresh map')
        for record in records:
            n = record['number']
            original = source[n]
            for key in ('title', 'state', 'updated_at'):
                check(record[key] == original[key], f'#{n}: {key} changed')
            check(record['assignees'] == [a['login'] for a in original['assignees']], f'#{n}: assignees changed')
            for key, heading in [('acceptance_criteria_markdown', 'Acceptance criteria'), ('implementation_subtasks_markdown', 'Implementation subtasks'), ('prerequisites_markdown', 'Prerequisites'), ('delivery_output_markdown', 'Delivery output and review boundary')]:
                check(record[key] == section(original['body'], heading), f'#{n}: {heading} differs from source')
            check(record['validation_markdown'] == (section(original['body'], 'Validation and evidence') or section(original['body'], 'Validation')), f'#{n}: validation differs')
    print(f'PASS: {len(records)} issues, {count} exact criteria; ' + ('source preservation verified' if args.source else 'internal coverage verified'))


if __name__ == '__main__':
    main()
