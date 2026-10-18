"""Reproduce frozen catalog-envelope test mutations without changing source inputs.

Python and Swift apply the same compact mutations to the hash-pinned synthetic
catalog. Item-specific coverage remains in catalog_vectors.py; these cases exercise
whole-document metadata, cardinality and propagation of nested item failures.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'Tests/PlannerTransferTests/Fixtures'
OUTPUT = FIXTURES / 'catalog-snapshot-conformance.json'


def vectors():
    catalog = json.loads((FIXTURES / 'catalog.json').read_text())
    schema = json.loads((ROOT / 'Sources/PlannerTransfer/Resources/catalog-snapshot.schema.json').read_text())
    cases = []

    def add(name, path=(), value=None, *, operation='set', valid=False, canonical=None):
        case = dict(name=name, path=list(path), operation=operation,
                    canonicalValid=valid if canonical is None else canonical, clientValid=valid)
        if operation == 'set':
            case['json'] = json.dumps(value, ensure_ascii=False, separators=(',', ':'))
        cases.append(case)

    add('canonical-catalog', operation='none', valid=True)
    for key in schema['required']:
        add('missing-' + key, [key], operation='remove')
        add('null-' + key, [key], None)
    for index, root in enumerate((None, True, 1, 'catalog', [])):
        add('wrong-root-' + str(index), value=root)
    add('unknown-root-field', ['future_field'], True)
    add('unsupported-version', ['schema_version'], '2.0.0')
    add('numeric-version', ['schema_version'], 1)
    for name, value in (('short', 'ab'), ('uppercase', 'Catalog.valid'), ('spaces', 'catalog invalid'), ('long', 'c' * 121)):
        add('invalid-id-' + name, ['id'], value)
    add('maximum-id-length', ['id'], 'c' * 120, valid=True)
    for name, value in (('zero', 0), ('negative', -1), ('fractional', 1.5), ('string', '1'), ('boolean', True)):
        add('invalid-revision-' + name, ['revision'], value)
    add('revision-minimum', ['revision'], 1, valid=True)
    add('revision-mathematical-integer', ['revision'], 2.0, valid=True)
    add('revision-exact-client-boundary', ['revision'], 999999999999999, valid=True)
    for name, value in (('date-only', '2026-10-18'), ('impossible-date', '2026-02-30T12:00:00Z'),
                        ('missing-zone', '2026-10-18T12:00:00'), ('boolean', True)):
        add('invalid-captured-at-' + name, ['captured_at'], value)
    add('captured-at-offset-preserved', ['captured_at'], '2024-02-29T12:34:56.125+05:30', valid=True)
    add('captured-at-lowercase', ['captured_at'], '2026-10-18t12:34:56z', valid=True)
    add('empty-items', ['items'], [])
    add('object-items', ['items'], {})
    add('single-item', ['items'], catalog['items'][:1], valid=True)
    add('reordered-items', ['items'], list(reversed(catalog['items'])), valid=True)
    add('duplicate-identical-items-preserved', ['items'], [catalog['items'][0]] * 2, valid=True)
    different = deepcopy(catalog['items'][0]); different['name'] += ' changed'
    add('conflicting-item-identity-preserved', ['items'], [catalog['items'][0], different], valid=True)
    for index, item in enumerate(catalog['items']):
        add('malformed-nested-' + item['kind'], ['items', str(index), 'spec', 'future_field'], True)
    add('one-invalid-item-among-valid-items', ['items'], [catalog['items'][0], None, catalog['items'][-1]])
    add('nested-unsupported-version', ['items', '0', 'schema_version'], '2.0.0')
    add('unsupported-large-revision', ['revision'], 9007199254740993, canonical=True)
    add('unsupported-terminal-newline-id', ['id'], 'catalog.valid\n', canonical=True)
    assert len({case['name'] for case in cases}) == len(cases)
    return cases


def encoded_vectors():
    return '[\n' + ',\n'.join(json.dumps(case, ensure_ascii=False, separators=(',', ':')) for case in vectors()) + '\n]\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='regenerate only catalog-envelope test mutations')
    args = parser.parse_args()
    expected = encoded_vectors()
    if args.write:
        OUTPUT.write_text(expected)
    else:
        assert OUTPUT.read_text() == expected, 'Catalog snapshot vectors are stale; run catalog_snapshot_vectors.py --write'
    print(f'Catalog snapshot vectors: {len(vectors())}; deterministic generation verified.')
