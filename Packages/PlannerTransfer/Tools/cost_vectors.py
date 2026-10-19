"""Compact mutations of the unchanged frozen-v1 cost estimate example.

Reference and Swift checks replay the same cases. Raw JSON replacement tokens
avoid narrowing integral fields before the client decoder sees them. Reported
amounts remain decimal strings; this generator performs no pricing arithmetic.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
from contract_checks import require

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'Sources/PlannerTransfer/Resources'
FIXTURES = ROOT / 'Tests/PlannerTransferTests/Fixtures'
OUTPUT = FIXTURES / 'cost-conformance.json'


def apply_vector(original, case):
    value = deepcopy(original)
    if case['operation'] == 'none':
        return value
    replacement = json.loads(case['json']) if 'json' in case else None
    if not case['path']:
        require(case['operation'] == 'set', 'Unsupported cost vector operation: ' + case['operation'])
        return replacement
    parent = value
    for key in case['path'][:-1]:
        parent = parent[int(key)] if isinstance(parent, list) else parent[key]
    key = int(case['path'][-1]) if isinstance(parent, list) else case['path'][-1]
    if case['operation'] == 'remove':
        del parent[key]
    else:
        require(case['operation'] == 'set', 'Unsupported cost vector operation: ' + case['operation'])
        parent[key] = replacement
    return value


def vectors():
    schema = json.loads((RESOURCES / 'cost-estimate.schema.json').read_text())
    fixture = json.loads((FIXTURES / 'cost-estimate.json').read_text())
    cases = []

    def add(label, path=(), value=None, *, operation='set', valid=False, canonical=None, raw=None):
        case = dict(name=label, path=list(path), operation=operation,
                    canonicalValid=valid if canonical is None else canonical, clientValid=valid)
        if operation == 'set':
            case['json'] = raw if raw is not None else json.dumps(value, ensure_ascii=False, separators=(',', ':'))
            json.loads(case['json'])
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

    id_paths = [
        (['id'], 120), (['build_id'], 120), (['pricebook_id'], 120),
        (['line_items', '0', 'id'], 120), (['line_items', '0', 'selection_id'], 80),
        (['line_items', '0', 'price_rate_id'], 120),
    ]
    terminators = [('lf', '\n'), ('cr', '\r'), ('crlf', '\r\n'), ('nel', '\u0085'),
                   ('line-separator', '\u2028'), ('paragraph-separator', '\u2029'),
                   ('vertical-tab', '\u000b'), ('form-feed', '\u000c')]
    for path, maximum in id_paths:
        key = '/'.join(path)
        add(key + ':minimum', path, 'aaa', valid=True)
        add(key + ':maximum', path, 'a' * maximum, valid=True)
        for label, value in [('short', 'aa'), ('long', 'a' * (maximum + 1)),
                             ('uppercase', 'Bad'), ('digit-first', '1ab'), ('space', 'bad id')]:
            add(key + ':' + label, path, value)
        for label, suffix in terminators:
            add(key + ':terminal-' + label, path, 'valid_id' + suffix, canonical=label == 'lf')
    add('selection-id-punctuation', ['line_items', '0', 'selection_id'], 'sel_a-1', valid=True)
    add('selection-id-dot-invalid', ['line_items', '0', 'selection_id'], 'sel.a')
    add('record-id-punctuation', ['id'], 'estimate.a_b:c-1', valid=True)

    for key in ('build_revision', 'period_days'):
        for label, token in [('minimum', '1'), ('integral-decimal', '1.0'),
                             ('integral-exponent', '1e3'), ('large-exact', '9e15')]:
            add(key + ':' + label, [key], raw=token, valid=True)
        for label, token in [('zero', '0'), ('negative', '-1'), ('fractional', '1.5'),
                             ('boolean', 'true'), ('string', '"30"')]:
            add(key + ':' + label, [key], raw=token)
        for label, token in [('unbounded-integer', '9007199254740993'),
                             ('too-many-significant-digits', '1234567890123456'),
                             ('large-exponent', '1e65'), ('long-token', '1.' + '0' * 127)]:
            add(key + ':' + label, [key], raw=token, canonical=True)

    for label, value in [('leap-day', '2024-02-29T00:00:00Z'),
                         ('offset-fraction', '2026-10-16T09:00:00.123456+01:30'),
                         ('lowercase', '2026-10-16t09:00:00z'),
                         ('past-is-recorded', '2000-01-01T00:00:00Z'),
                         ('future-is-recorded', '2099-01-01T00:00:00Z')]:
        add('estimated-at:' + label, ['estimated_at'], value, valid=True)
    for label, value in [('bad-date', '2026-02-29T09:00:00Z'), ('bad-time', '2026-10-16T24:00:00Z'),
                         ('missing-zone', '2026-10-16T09:00:00'), ('date-only', '2026-10-16'),
                         ('invalid-offset', '2026-10-16T09:00:00+25:00')]:
        add('estimated-at:' + label, ['estimated_at'], value)
    for coverage in schema['properties']['coverage']['enum']:
        add('coverage-' + coverage, ['coverage'], coverage, valid=True)
    add('coverage-invalid', ['coverage'], 'guaranteed')

    add('line-items-empty', ['line_items'], [], valid=True)
    add('line-item-wrong-type', ['line_items', '0'], [])
    add('line-item-null', ['line_items', '0'], None)
    add('line-item-extra-field', ['line_items', '0', 'future_field'], 'PRIVATE-PAYLOAD')
    item = schema['properties']['line_items']['items']
    for key in item['required']:
        add('line-item:missing-' + key, ['line_items', '0', key], operation='remove')
    for key, prop in item['properties'].items():
        add('line-item:' + key + ':null', ['line_items', '0', key], None)
        add('line-item:' + key + ':wrong-type', ['line_items', '0', key],
            {} if prop.get('type') == 'array' else True)
        if 'enum' in prop:
            for member in prop['enum']:
                add('line-item:' + key + ':' + member, ['line_items', '0', key], member, valid=True)
            add('line-item:' + key + ':unsupported', ['line_items', '0', key], 'unsupported')
    add('line-items-duplicate-rows-retained', ['line_items'], fixture['line_items'] * 2, valid=True)
    add('line-items-reversed-retained', ['line_items'], list(reversed(fixture['line_items'])), valid=True)

    money_paths = [['subtotal'], ['tax'], ['total'],
                   ['line_items', '0', 'unit_price'], ['line_items', '0', 'amount']]
    for path in money_paths:
        label = '/'.join(path)
        add(label + ':extra-field', path + ['future_field'], 'PRIVATE-PAYLOAD')
        for key in ('amount', 'currency'):
            add(label + ':missing-' + key, path + [key], operation='remove')
            add(label + ':' + key + ':null', path + [key], None)
            add(label + ':' + key + ':wrong-type', path + [key], 1)

    decimal_paths = [path + ['amount'] for path in money_paths] + [['line_items', '0', 'quantity']]
    for path in decimal_paths:
        label = '/'.join(path)
        for name, value in [('zero', '0'), ('trailing-zeros', '1.2300'), ('twelve-fraction-digits', '0.123456789012'),
                             ('long-exact-string', '9' * 200 + '.123456789012')]:
            add(label + ':' + name, path, value, valid=True)
        for name, value in [('empty', ''), ('negative', '-1'), ('negative-zero', '-0'), ('leading-zero', '01'),
                             ('plus', '+1'), ('exponent', '1e3'), ('leading-dot', '.1'), ('trailing-dot', '1.'),
                             ('thirteen-fraction-digits', '0.1234567890123'), ('space', ' 1'), ('comma', '1,2')]:
            add(label + ':' + name, path, value)
        for name, suffix in terminators:
            add(label + ':terminal-' + name, path, '1' + suffix, canonical=name == 'lf')

    currency_paths = [['currency']] + [path + ['currency'] for path in money_paths]
    for path in currency_paths:
        label = '/'.join(path)
        add(label + ':unrecognized-letters-retained', path, 'ZZZ', valid=True)
        for name, value in [('lowercase', 'usd'), ('short', 'US'), ('long', 'USDX'), ('digits', '123')]:
            add(label + ':' + name, path, value)
        for name, suffix in terminators:
            add(label + ':terminal-' + name, path, 'USD' + suffix, canonical=name == 'lf')

    for path in (['warnings'], ['line_items', '0', 'assumptions']):
        label = '/'.join(path)
        for name, value in [('empty', []), ('empty-string', ['']),
                             ('private-unicode-duplicates', ['PRIVATE-PAYLOAD ☃', '', 'PRIVATE-PAYLOAD ☃'])]:
            add(label + ':' + name, path, value, valid=True)
        for name, value in [('null', [None]), ('number', [1]), ('object', [{}])]:
            add(label + ':invalid-item-' + name, path, value)

    add('unpriced-empty', ['unpriced_selection_ids'], [], valid=True)
    add('unpriced-known-and-unknown-not-resolved', ['unpriced_selection_ids'], ['sel_storage', 'sel_other'], valid=True)
    add('unpriced-order-retained', ['unpriced_selection_ids'], ['sel_z', 'sel_a'], valid=True)
    add('unpriced-duplicate', ['unpriced_selection_ids'], ['sel_same', 'sel_same'])
    for name, value in [('null', None), ('number', 1), ('object', {}), ('invalid-id', 'bad.id')]:
        add('unpriced:invalid-item-' + name, ['unpriced_selection_ids'], [value])
    add('unpriced-terminal-lf-client-subset', ['unpriced_selection_ids'], ['sel_a\n'], canonical=True)

    # No arithmetic or cross-currency assertion exists in the frozen structure.
    add('reported-total-not-recomputed', ['total', 'amount'], '1.0000', valid=True)
    add('reported-line-amount-not-multiplied', ['line_items', '0', 'amount', 'amount'], '0', valid=True)
    add('reported-money-currency-not-unified', ['line_items', '0', 'amount', 'currency'], 'EUR', valid=True)
    add('recorded-complete-with-unpriced-selection', ['unpriced_selection_ids'], ['sel_missing'], valid=True)
    require(len({case['name'] for case in cases}) == len(cases), 'Duplicate cost vector names')
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
        if OUTPUT.read_text() != expected:
            raise SystemExit('Cost vectors are stale; run cost_vectors.py --write')
    print(f'Cost vectors: {len(vectors())}; deterministic generation verified.')
