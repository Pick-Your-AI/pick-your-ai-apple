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


def read_json(path, label):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f'duplicate JSON object member {key!r}')
            result[key] = value
        return result

    try:
        return json.loads(path.read_text(), object_pairs_hook=unique_object)
    except json.JSONDecodeError as exc:
        raise SystemExit(f'{label}: invalid JSON: {exc}') from exc
    except ValueError as exc:
        raise SystemExit(f'{label}: {exc}') from exc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, help='JSON array of full REST issue objects, all pages')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    data = read_json(root / 'docs/acceptance/issues.json', 'Captured map')
    records = data['issues']
    numbers = [r['number'] for r in records]
    check(all(type(n) is int and n > 0 for n in numbers), 'Captured issue numbers must be positive integers')
    check(len(numbers) == len(set(numbers)), 'Duplicate issues')
    check(set(numbers) == set(range(1, 130)), 'Expected baseline issues 1–129; reconcile changed scope explicitly')
    count = 0
    for record in records:
        n = record['number']
        exact = re.findall(r'^- \[([ xX])\] (.*(?:\n(?!- \[).+)*)', record['acceptance_criteria_markdown'], re.M)
        check(exact, f'#{n}: empty acceptance criteria')
        check(all(type(r['source_checked']) is bool for r in record['criteria']),
              f'#{n}: source checkbox states must be booleans')
        check([(r['source_checked'], r['text']) for r in record['criteria']] == [(c.lower() == 'x', t) for c, t in exact], f'#{n}: parsed criteria differ')
        check(record['next_executable_action'] and record['updated_at'] and record['project'], f'#{n}: missing intake/action')
        check(record['criterion_completion_claimed'] is False, f'#{n}: unsupported completion claim')
        count += len(exact)
    if args.source:
        source = {}
        for original in read_json(args.source, 'Source export'):
            if 'pull_request' in original:
                continue
            n = original['number']
            check(type(n) is int and n > 0, 'Source issue numbers must be positive integers')
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
