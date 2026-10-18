"""Reproduce compact mutations of the unchanged frozen-v1 quality record fixture.

Both reference and client replay these mutations. Raw replacement JSON preserves
numeric tokens at the Swift decoder boundary; explicit client subsets are separate
from canonical validity. This generator never edits the schema or infers a verdict.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'Sources/PlannerTransfer/Resources'
FIXTURES = ROOT / 'Tests/PlannerTransferTests/Fixtures'
OUTPUT = FIXTURES / 'quality-conformance.json'


def apply_vector(original, case):
    value = deepcopy(original)
    if case['operation'] == 'none':
        return value
    replacement = json.loads(case['json']) if 'json' in case else None
    if not case['path']:
        assert case['operation'] == 'set'
        return replacement
    parent = value
    for key in case['path'][:-1]:
        parent = parent[int(key)] if isinstance(parent, list) else parent[key]
    key = int(case['path'][-1]) if isinstance(parent, list) else case['path'][-1]
    if case['operation'] == 'remove':
        del parent[key]
    else:
        assert case['operation'] == 'set'
        parent[key] = replacement
    return value


def vectors():
    schema = json.loads((RESOURCES / 'quality-evaluation-run.schema.json').read_text())
    fixture = json.loads((FIXTURES / 'quality-evaluation-run.json').read_text())
    cases = []

    def add(label, path=(), value=None, *, operation='set', valid=False, canonical=None, raw=None):
        case = dict(name=label, path=list(path), operation=operation,
                    canonicalValid=valid if canonical is None else canonical, clientValid=valid)
        if operation == 'set':
            case['json'] = raw if raw is not None else json.dumps(value, ensure_ascii=False, separators=(',', ':'))
            json.loads(case['json'])  # All shared vectors are JSON, including schema-invalid values.
        cases.append(case)

    add('canonical-fixture', operation='none', valid=True)
    add('wrong-root-type', value=[])
    add('unknown-root-field', ['private_future_field'], 'PRIVATE-PAYLOAD')
    for key in schema['required']:
        add('missing-' + key, [key], operation='remove')
    for key, prop in schema['properties'].items():
        add(key + ':null', [key], None)
        wrong = {'integer': 1.5, 'array': {}, 'string': True}.get(prop.get('type'), 1)
        add(key + ':wrong-type', [key], wrong)
    for version in ('0.9.0', '1.0.1', '2.0.0', ''):
        add('unsupported-version-' + version, ['schema_version'], version)
    for status in schema['properties']['status']['enum']:
        add('status-' + status, ['status'], status, valid=True)
    add('unsupported-status', ['status'], 'verified')

    for key, maximum in [('id', 120), ('build_id', 120), ('evaluation_suite_selection_id', 80)]:
        add(key + ':minimum-length', [key], 'aaa', valid=True)
        add(key + ':maximum-length', [key], 'a' * maximum, valid=True)
        add(key + ':short', [key], 'aa')
        add(key + ':long', [key], 'a' * (maximum + 1))
        for label, value in [('uppercase', 'Bad'), ('leading-digit', '1ab'), ('space', 'bad id')]:
            add(key + ':' + label, [key], value)
        add(key + ':terminal-newline-client-subset', [key], 'valid_id\n', canonical=True)
    add('suite-id-invalid-dot', ['evaluation_suite_selection_id'], 'suite.id')
    add('suite-id-invalid-colon', ['evaluation_suite_selection_id'], 'suite:id')
    add('suite-id-underscore-hyphen', ['evaluation_suite_selection_id'], 'suite_a-1', valid=True)
    add('record-id-punctuation', ['id'], 'quality.a_b:c-1', valid=True)

    for key in ('started_at', 'finished_at'):
        for label, value in [('leap-day', '2024-02-29T00:00:00Z'),
                             ('offset-fraction', '2026-10-16T09:00:00.123456+01:30'),
                             ('lowercase', '2026-10-16t09:00:00z')]:
            add(key + ':' + label, [key], value, valid=True)
        for label, value in [('bad-date', '2026-02-29T09:00:00Z'),
                             ('bad-time', '2026-10-16T24:00:00Z'),
                             ('missing-zone', '2026-10-16T09:00:00'),
                             ('date-only', '2026-10-16')]:
            add(key + ':' + label, [key], value)
    add('finished-before-started-is-preserved', ['finished_at'], '2026-10-15T00:00:00Z', valid=True)
    for key in ('evaluator_version', 'dataset_revision'):
        add(key + ':empty', [key], '')
        add(key + ':unicode-no-semver-policy', [key], 'fixture ☃ revision', valid=True)

    for key in ('build_revision', 'sample_size'):
        for label, token in [('minimum', '1'), ('integral-decimal', '1.0'),
                             ('integral-exponent', '1e3'), ('supported-large', '9e15')]:
            add(key + ':' + label, [key], raw=token, valid=True)
        for label, token in [('zero', '0'), ('negative', '-1'), ('boolean', 'true')]:
            add(key + ':' + label, [key], raw=token)
        add(key + ':unbounded-canonical-integer', [key], raw='9007199254740993', canonical=True)

    measurement = schema['properties']['measurements']['items']
    add('measurements-empty', ['measurements'], [])
    add('measurement-wrong-type', ['measurements', '0'], [])
    add('measurement-null', ['measurements', '0'], None)
    add('measurement-unknown-field', ['measurements', '0', 'private_future_field'], 'PRIVATE-PAYLOAD')
    for key in measurement['required']:
        add('measurement-missing-' + key, ['measurements', '0', key], operation='remove')
    for key, prop in measurement['properties'].items():
        add('measurement-' + key + ':null', ['measurements', '0', key], None)
        wrong = {'string': 1, 'number': True, 'boolean': 1}[prop['type']]
        add('measurement-' + key + ':wrong-type', ['measurements', '0', key], wrong)
    add('metric-empty', ['measurements', '0', 'metric'], '')
    add('metric-unicode', ['measurements', '0', 'metric'], 'qualité ☃', valid=True)
    add('unit-absent', ['measurements', '0', 'unit'], operation='remove', valid=True)
    add('unit-empty', ['measurements', '0', 'unit'], '', valid=True)
    add('unit-unrecognized-is-preserved', ['measurements', '0', 'unit'], 'fixture only', valid=True)
    add('reported-false-is-preserved', ['measurements', '0', 'passed'], False, valid=True)
    for comparator in measurement['properties']['comparator']['enum']:
        add('comparator-' + comparator, ['measurements', '0', 'comparator'], comparator, valid=True)
    add('unsupported-comparator', ['measurements', '0', 'comparator'], 'approximately')
    for key in ('observed', 'threshold'):
        for label, token in [('zero', '0'), ('negative-zero', '-0'), ('negative', '-123.45'),
                             ('significant-boundary', '1.23456789012345'),
                             ('small-boundary', '1e-12'), ('small-fraction', '1.23456789e-12'),
                             ('large-supported', '9e15'), ('trailing-zero-coefficient', '1.230000000000000000'),
                             ('zero-negative-exponent-boundary', '0e-64'), ('zero-positive-exponent-boundary', '-0e+64')]:
            add(key + ':' + label, ['measurements', '0', key], raw=token, valid=True)
        for label, token in [('too-precise', '1.234567890123456'), ('too-small', '1e-13'),
                             ('too-large', '1e16'), ('unbounded-large-integer', '9007199254740993'),
                             ('unsupported-exponent', '0e65'), ('long-token', '1.' + '0' * 127)]:
            add(key + ':' + label, ['measurements', '0', key], raw=token, canonical=True)

    repeated = deepcopy(fixture['measurements']) * 2
    add('duplicate-metrics-retained', ['measurements'], repeated, valid=True)
    contradictory = deepcopy(fixture['measurements'])
    contradictory[0].update(observed=-9, threshold=99, comparator='eq', passed=True)
    add('contradictory-reported-pass-preserved', ['measurements'], contradictory, valid=True)
    add('notes-absent', ['notes'], operation='remove', valid=True)
    add('notes-empty', ['notes'], [], valid=True)
    add('notes-empty-string', ['notes'], [''], valid=True)
    add('notes-unicode-and-duplicate-retained', ['notes'], ['fixture ☃', '', 'fixture ☃'], valid=True)
    for label, value in [('null', [None]), ('number', [1]), ('object', [{}])]:
        add('notes-invalid-item-' + label, ['notes'], value)
    add('artifacts-empty', ['artifacts'], [], valid=True)
    for label, uri in [('https', 'https://example.invalid/a%20b?x=1&y=2#fragment'),
                       ('urn', 'urn:example:fixture'), ('mailto', 'mailto:test@example.invalid'),
                       ('file', 'file:///tmp/fixture.json')]:
        add('artifact-uri-' + label, ['artifacts'], [uri], valid=True)
    add('duplicate-artifact-uris-retained', ['artifacts'], ['urn:example:fixture'] * 2, valid=True)
    add('artifact-ip-literal-client-subset', ['artifacts'], ['https://[::1]/'], canonical=True)
    for label, value in [('relative', 'artifact.json'), ('empty', ''), ('space', 'https://example.invalid/a b'),
                         ('percent', 'https://example.invalid/%ZZ'), ('null', None), ('boolean', True)]:
        add('artifact-invalid-' + label, ['artifacts'], [value])
    assert len({case['name'] for case in cases}) == len(cases)
    return cases


def encoded_vectors():
    return '[\n' + ',\n'.join(json.dumps(case, ensure_ascii=False, separators=(',', ':')) for case in vectors()) + '\n]\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='regenerate only the test-vector file')
    args = parser.parse_args()
    expected = encoded_vectors()
    if args.write:
        OUTPUT.write_text(expected)
    else:
        assert OUTPUT.read_text() == expected, 'Quality vectors are stale; run quality_vectors.py --write'
    print(f'Quality vectors: {len(vectors())}; deterministic generation verified.')
