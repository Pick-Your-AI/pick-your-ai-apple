"""Reproduce compact catalog mutation vectors from the unchanged frozen schema.

Only test inputs are generated. This never edits the schema or supplies defaults
at the product boundary. Both Python and Swift apply the same mutations to the
hash-pinned canonical fixture; canonical/client differences are explicit.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'Sources/PlannerTransfer/Resources'
FIXTURES = ROOT / 'Tests/PlannerTransferTests/Fixtures'
OUTPUT = FIXTURES / 'catalog-conformance.json'


def apply_vector(item, case):
    value = deepcopy(item)
    if case['operation'] == 'none':
        return value
    replacement = json.loads(case['json']) if 'json' in case else None
    if not case['path']:
        assert case['operation'] == 'set'
        return replacement
    parent = value
    for key in case['path'][:-1]:
        parent = parent[int(key)] if isinstance(parent, list) else parent[key]
    key = case['path'][-1]
    if isinstance(parent, list):
        key = int(key)
    if case['operation'] == 'remove':
        del parent[key]
    else:
        assert case['operation'] == 'set'
        parent[key] = replacement
    return value


def sample(schema):
    if 'enum' in schema:
        return schema['enum'][0]
    kind = schema['type']
    if kind == 'array':
        return [sample(schema['items'])]
    if kind == 'boolean':
        return False
    if kind in ('integer', 'number'):
        return schema.get('minimum', 1)
    assert kind == 'string', kind
    if schema.get('format') == 'uri':
        return 'https://example.invalid/fixture'
    if schema.get('pattern') == '^[A-Z]{3}$':
        return 'USD'
    return 'fixture.valid'


def vectors():
    schema = json.loads((RESOURCES / 'catalog-item.schema.json').read_text())
    catalog = json.loads((FIXTURES / 'catalog.json').read_text())
    kinds = schema['properties']['kind']['enum']
    items = {item['kind']: item for item in catalog['items']}
    assert len(kinds) == len(items) == 29 and set(kinds) == set(items)
    cases = []

    def add(kind, label, path=(), value=None, *, operation='set', valid=False, canonical=None):
        case = dict(name=kind + ':' + label, kind=kind, path=list(path), operation=operation,
                    canonicalValid=valid if canonical is None else canonical, clientValid=valid)
        if operation == 'set':
            case['json'] = json.dumps(value, ensure_ascii=False, separators=(',', ':'))
        cases.append(case)

    for kind in kinds:
        item = items[kind]
        spec = schema['$defs']['spec_' + kind]
        add(kind, 'canonical-fixture', operation='none', valid=True)
        for key in schema['required']:
            add(kind, 'missing-' + key, [key], operation='remove')
        add(kind, 'unknown-root-field', ['future_field'], True)
        add(kind, 'unknown-spec-field', ['spec', 'future_field'], True)
        add(kind, 'wrong-spec-type', ['spec'], [])
        add(kind, 'wrong-kind-tier', ['tier'], 'T1' if item['tier'] == 'T0' else 'T0')
        for key in spec['required']:
            add(kind, 'missing-spec-' + key, ['spec', key], operation='remove')
        for key, prop in spec['properties'].items():
            path = ['spec', key]
            typ = prop['type']
            add(kind, key + ':supported-value', path, sample(prop), valid=True)
            add(kind, key + ':null', path, None)
            wrong = {'string': 1, 'boolean': 1, 'integer': 1.5, 'number': True, 'array': {}}[typ]
            add(kind, key + ':wrong-type', path, wrong)
            if key in item['spec'] and key not in spec['required']:
                add(kind, key + ':optional-omitted', path, operation='remove', valid=True)
            for index, option in enumerate(prop.get('enum', [])):
                add(kind, key + ':enum-' + str(index), path, option, valid=True)
            if 'enum' in prop:
                add(kind, key + ':unknown-enum', path, 'future_unsupported')
            if 'pattern' in prop:
                add(kind, key + ':wrong-pattern', path, 'INVALID VALUE')
            if prop.get('format') == 'uri':
                add(kind, key + ':invalid-uri', path, 'not an absolute uri')
            if 'minLength' in prop:
                add(kind, key + ':short-string', path, 'x' * (prop['minLength'] - 1))
            if 'minimum' in prop:
                add(kind, key + ':minimum', path, prop['minimum'], valid=True)
                add(kind, key + ':below-minimum', path, prop['minimum'] - 1)
            if 'maximum' in prop:
                add(kind, key + ':maximum', path, prop['maximum'], valid=True)
                add(kind, key + ':above-maximum', path, prop['maximum'] + 1)
            if typ == 'array':
                child = prop['items']
                add(kind, key + ':wrong-item-type', path, [True])
                for index, option in enumerate(child.get('enum', [])):
                    add(kind, key + ':item-enum-' + str(index), path, [option], valid=True)
                if 'enum' in child:
                    add(kind, key + ':unknown-item-enum', path, ['future_unsupported'])
                if 'pattern' in child:
                    add(kind, key + ':invalid-item-reference', path, ['INVALID VALUE'])
                if prop.get('minItems', 0) > 0:
                    add(kind, key + ':too-few-items', path, [])
                else:
                    add(kind, key + ':empty-array', path, [], valid=True)
                if prop.get('uniqueItems'):
                    add(kind, key + ':duplicate-items', path, [sample(child)] * 2)

    kind = 'workload'
    for key in ('schema_version', 'id', 'kind', 'tier', 'name', 'version', 'status', 'billing_class', 'updated_at'):
        add(kind, 'root-' + key + ':wrong-type', [key], True)
    for key in ('kind', 'tier', 'status', 'billing_class'):
        add(kind, 'root-' + key + ':unknown-enum', [key], 'future_unsupported')
    for key in ('status', 'billing_class'):
        for option in schema['properties'][key]['enum']:
            add(kind, 'root-' + key + ':' + option, [key], option, valid=True)
    add(kind, 'unsupported-version', ['schema_version'], '2.0.0')
    add(kind, 'wrong-root-type', [], [])
    add(kind, 'invalid-id', ['id'], 'INVALID ID')
    add(kind, 'empty-name', ['name'], '')
    add(kind, 'long-name', ['name'], 'x' * 181)
    add(kind, 'unicode-scalar-name-boundary', ['name'], '\U0001f642' * 180, valid=True)
    add(kind, 'empty-version', ['version'], '')
    add(kind, 'provenance-empty', ['provenance'], [])
    add(kind, 'provenance-wrong-type', ['provenance'], {})
    add(kind, 'provenance-unknown-field', ['provenance', '0', 'future_field'], True)
    for key in ('checked_at', 'verification_status'):
        add(kind, 'provenance-missing-' + key, ['provenance', '0', key], operation='remove')
    for status in ('verified', 'user_supplied', 'estimated', 'unverified'):
        add(kind, 'provenance-status-' + status, ['provenance', '0', 'verification_status'], status, valid=True)
    add(kind, 'provenance-invalid-status', ['provenance', '0', 'verification_status'], 'trusted')
    add(kind, 'provenance-invalid-time', ['provenance', '0', 'checked_at'], '2026-02-30T12:00:00Z')
    add(kind, 'provenance-invalid-uri', ['provenance', '0', 'source_uri'], 'not a uri')
    add(kind, 'invalid-updated-at', ['updated_at'], '2026-02-30T12:00:00Z')
    add(kind, 'tags-duplicate', ['tags'], ['one', 'one'])
    add(kind, 'tags-wrong-item-type', ['tags'], [True])
    add(kind, 'license-optional-empty', ['license'], {}, valid=True)
    add(kind, 'license-boolean-types', ['license'], {'commercial_use_allowed': False, 'self_hosting_allowed': True}, valid=True)
    add(kind, 'license-unknown-field', ['license'], {'future_field': True})
    add(kind, 'license-wrong-boolean', ['license'], {'commercial_use_allowed': 1})
    add(kind, 'namespaced-extensions', ['extensions'], {'x_fixture': {'missing': None, 'flag': True, 'amount': '9007199254740993.123456789012'}}, valid=True)
    add(kind, 'unnamespaced-extensions', ['extensions'], {'unknown': {}})
    # The frozen catalog describes facts. Costs belong to selection/build/pricebook
    # boundaries, so even correctly formatted money cannot be invented in a spec.
    for key in ('monthly_budget', 'price', 'rates'):
        add('cost_policy', 'no-invented-' + key, ['spec', key], {'amount': '1.00', 'currency': 'USD'})
    # Explicit client representation subsets, not canonical-schema failures.
    add(kind, 'unsupported-large-number', ['spec', 'requests_per_day'], 9007199254740993, canonical=True)
    add(kind, 'unsupported-small-number', ['spec', 'uptime_target_pct'], 1e-13, canonical=True)
    add('model_provider', 'unsupported-ip-literal-uri', ['spec', 'api_base_url'], 'https://[::1]/', canonical=True)
    add(kind, 'unsupported-terminal-newline-id', ['id'], 'catalog.valid\n', canonical=True)
    add('cost_policy', 'unsupported-terminal-newline-currency', ['spec', 'default_currency'], 'USD\n', canonical=True)
    add(kind, 'unsupported-terminal-newline-extension-key', ['extensions'], {'x_fixture\n': True}, canonical=True)
    assert len({case['name'] for case in cases}) == len(cases)
    return cases


def encoded_vectors():
    # One compact case per line keeps the artifact small and human-diffable.
    return '[\n' + ',\n'.join(json.dumps(case, ensure_ascii=False, separators=(',', ':')) for case in vectors()) + '\n]\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='regenerate only the test-vector file')
    args = parser.parse_args()
    expected = encoded_vectors()
    if args.write:
        OUTPUT.write_text(expected)
    else:
        assert OUTPUT.read_text() == expected, 'Catalog vectors are stale; run catalog_vectors.py --write'
    print(f'Catalog vectors: {len(vectors())}; deterministic generation verified.')
