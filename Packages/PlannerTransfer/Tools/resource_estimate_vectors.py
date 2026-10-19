"""Deterministic exact-text cases for the frozen ResourceEstimate boundary.

These synthetic cases check structure and preservation, never estimator validity,
metric/unit semantics, current-build binding, coverage or measured quality.
"""
import copy
import json
from pathlib import Path
from contract_checks import require

ROOT = Path(__file__).resolve().parents[1]


def vectors():
    fixture = json.loads((ROOT / 'Tests/PlannerTransferTests/Fixtures/resource-estimate.json').read_text())
    schema = json.loads((ROOT / 'Sources/PlannerTransfer/Resources/resource-estimate.schema.json').read_text())
    entry_schema = schema['properties']['estimates']['items']
    base = copy.deepcopy(fixture)
    base['estimates'] = base['estimates'][:1]
    cases = []

    def add(name, payload, canonical=True, client=None, limit=None):
        case = {'name': name, 'json': json.dumps(payload, separators=(',', ':'), ensure_ascii=True, allow_nan=False),
                'canonicalValid': canonical, 'clientValid': canonical if client is None else client}
        if limit is not None:
            case['clientLimit'] = limit
        cases.append(case)

    def replace(name, path, value, canonical=True, client=None, limit=None):
        payload = copy.deepcopy(base)
        target = payload
        for key in path[:-1]:
            target = target[key]
        target[path[-1]] = value
        add(name, payload, canonical, client, limit)

    def remove(name, path):
        payload = copy.deepcopy(base)
        target = payload
        for key in path[:-1]:
            target = target[key]
        del target[path[-1]]
        add(name, payload, False)

    add('canonical-complete-fixture', fixture)
    add('one-estimate-with-absent-source', base)
    for key in schema['required']:
        remove('missing-root-' + key, [key])
        replace('null-root-' + key, [key], None, False)
    for key in entry_schema['required']:
        remove('missing-entry-' + key, ['estimates', 0, key])
        replace('null-entry-' + key, ['estimates', 0, key], None, False)
    for name, value in [('array', []), ('null', None), ('boolean', True), ('string', 'unknown')]:
        add('wrong-root-type-' + name, value, False)
    replace('unknown-root-property', ['unknown'], True, False)
    replace('unknown-entry-property', ['estimates', 0, 'unknown'], True, False)
    replace('unsupported-schema-version', ['schema_version'], '2.0.0', False)
    replace('schema-version-number', ['schema_version'], 1, False)

    # The frozen schema enumerates metric and unit independently. Every allowed
    # combination remains parseable; a receiving semantic policy must check units.
    for metric in entry_schema['properties']['metric']['enum']:
        for unit in entry_schema['properties']['unit']['enum']:
            for confidence in entry_schema['properties']['confidence']['enum']:
                payload = copy.deepcopy(base)
                payload['estimates'][0].update(metric=metric, unit=unit, confidence=confidence)
                add(f'declared-{metric}-{unit}-{confidence}', payload)
    for key, values in {
        'metric': ['quality.accuracy', 'inference.measured_tokens_per_second', 'unknown', 1],
        'unit': ['GB', 'unknown', 1],
        'confidence': ['approved', 'unknown', 1],
        'estimator_id': ['', 1],
        'estimator_version': ['', 1],
    }.items():
        for index, value in enumerate(values):
            replace(f'invalid-{key}-{index}', ['estimates', 0, key], value, False)
    replace('opaque-estimator-identity-is-not-trust', ['estimates', 0, 'estimator_id'], ' ')
    replace('opaque-estimator-version-is-not-semver', ['estimates', 0, 'estimator_version'], 'unknown')

    for index, value in enumerate(['0', '0.0', '20.000', '0.000000000001',
                                   '9007199254740993.123456789012', '9' * 300 + '.000000000001']):
        replace(f'exact-decimal-string-{index}', ['estimates', 0, 'value'], value)
    for index, value in enumerate([True, False, None, {}, [], 0, 1.25, -1.25,
                                   '-1', '1e3', '01', '1.', '+1', '.5', 'NaN', 'Infinity',
                                   '1.0000000000001', ' 1', '1 ']):
        replace(f'invalid-decimal-{index}', ['estimates', 0, 'value'], value, False)
    replace('decimal-terminal-newline-subset', ['estimates', 0, 'value'], '1\n', True, False,
            'Strict end-of-input excludes the canonical pattern dollar-anchor newline exception.')

    for key in ('id', 'build_id'):
        for index, value in enumerate(['x', 'Wrong.id', 'a' * 121, 'bad id', 1]):
            replace(f'invalid-{key}-{index}', [key], value, False)
        replace('maximum-length-' + key, [key], 'a' * 120)
        replace('terminal-newline-' + key, [key], 'valid.id\n', True, False,
                'Strict end-of-input excludes the canonical pattern dollar-anchor newline exception.')
    for index, value in enumerate([0, -1, 1.5, True, '1']):
        replace(f'invalid-revision-{index}', ['build_revision'], value, False)
    replace('large-supported-revision', ['build_revision'], 1_000_000_000_000_000)
    replace('revision-numeric-subset', ['build_revision'], 9_007_199_254_740_993, True, False,
            'JSON numbers must fit the existing exact client representation limits.')
    for index, value in enumerate(['2024-02-29T23:59:59Z', '2026-10-18t03:20:01.123456z',
                                   '2026-10-18T03:20:01+23:59']):
        replace(f'valid-timestamp-{index}', ['generated_at'], value)
    for index, value in enumerate(['2026-02-29T00:00:00Z', '2026-02-30T00:00:00Z',
                                   '2026-10-18', '2026-10-18T24:00:00Z',
                                   '2026-10-18T00:60:00Z', '2026-10-18T00:00:00+24:00']):
        replace(f'invalid-timestamp-{index}', ['generated_at'], value, False)

    for index, value in enumerate([[], ['sel_model', 'sel_model'], [1], ['bad.id'], ['UPPER'], ['ab'], ['a' * 81], 'sel_model']):
        replace(f'invalid-selection-ids-{index}', ['estimates', 0, 'selection_ids'], value, False)
    replace('distinct-selection-order', ['estimates', 0, 'selection_ids'], ['sel_z', 'sel_a', 'sel_m'])
    replace('selection-id-terminal-newline-subset', ['estimates', 0, 'selection_ids'], ['sel_model\n'], True, False,
            'Strict end-of-input excludes the canonical pattern dollar-anchor newline exception.')
    for index, value in enumerate([[], [''], ['same', 'same'], ['unknown', 'condition-specific']]):
        replace(f'assumptions-preserved-{index}', ['estimates', 0, 'assumptions'], value)
    for index, value in enumerate([[1], [None], [{}], [[]], 'unknown']):
        replace(f'invalid-assumptions-{index}', ['estimates', 0, 'assumptions'], value, False)

    for index, value in enumerate(['https://example.invalid/estimate?version=1#conditions',
                                   'urn:example:synthetic-estimate', 'mailto:test@example.invalid',
                                   'https://example.invalid/a%20b']):
        replace(f'source-uri-syntax-{index}', ['estimates', 0, 'source_uri'], value)
    for index, value in enumerate(['', '/relative', 'https://example.invalid/a b',
                                   'https://example.invalid/%zz', None, 1]):
        replace(f'invalid-source-uri-{index}', ['estimates', 0, 'source_uri'], value, False)
    replace('source-ip-literal-subset', ['estimates', 0, 'source_uri'], 'https://[::1]/estimate', True, False,
            'The existing URI boundary excludes IP-literal hosts; URI shape grants no source trust.')

    replace('empty-estimates-rejected', ['estimates'], [], False)
    replace('repeated-estimates-preserved', ['estimates'], [base['estimates'][0], base['estimates'][0]])
    late_invalid = copy.deepcopy(base['estimates'][0])
    late_invalid['value'] = 20
    replace('invalid-later-estimate-rejects-entire-artifact', ['estimates'], [base['estimates'][0], late_invalid], False)
    require(len({case['name'] for case in cases}) == len(cases), 'Duplicate resource estimate vector names')
    return cases


def encoded_vectors():
    return json.dumps(vectors(), indent=2, ensure_ascii=True) + '\n'


if __name__ == '__main__':
    print(encoded_vectors(), end='')
