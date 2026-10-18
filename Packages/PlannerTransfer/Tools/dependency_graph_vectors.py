"""Generate only synthetic mutations of the unchanged frozen dependency graph.

The canonical graph is a structural fixture, not approved executable policy.
Python and Swift consume the same compact mutations and record client subsets.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'Sources/PlannerTransfer/Resources'
FIXTURES = ROOT / 'Tests/PlannerTransferTests/Fixtures'
OUTPUT = FIXTURES / 'dependency-graph-conformance.json'


def vectors():
    schema = json.loads((RESOURCES / 'dependency-graph.schema.json').read_text())
    fixture = json.loads((FIXTURES / 'dependency-graph.json').read_text())
    edge_schema = schema['properties']['edges']['items']
    first = fixture['edges'][0]
    cases = []

    def add(name, path=(), value=None, *, operation='set', valid=False, canonical=None):
        case = dict(name='dependency-graph:' + name, path=list(path), operation=operation,
                    canonicalValid=valid if canonical is None else canonical, clientValid=valid)
        if operation == 'set':
            case['json'] = json.dumps(value, ensure_ascii=False, separators=(',', ':'))
        cases.append(case)

    add('canonical-fixture', operation='none', valid=True)
    for key in schema['required']:
        add('missing-' + key, [key], operation='remove')
        add('null-' + key, [key], None)
        add('wrong-type-' + key, [key], True)
    for key in edge_schema['required']:
        path = ['edges', '0', key]
        add('edge-missing-' + key, path, operation='remove')
        add('edge-null-' + key, path, None)
        add('edge-wrong-type-' + key, path, True)
    for key in ('dependent_kind', 'depends_on_kind'):
        kinds = edge_schema['properties'][key]['enum']
        assert len(kinds) == 29
        for kind in kinds:
            add(key + '-' + kind, ['edges', '0', key], kind, valid=True)
        add('unknown-' + key, ['edges', '0', key], 'future_unsupported')
    relationships = edge_schema['properties']['relationship']['enum']
    activations = edge_schema['properties']['activation']['enum']
    assert len(relationships) == 4 and len(activations) == 8
    for relationship in relationships:
        for activation in activations:
            edge = dict(first, relationship=relationship, activation=activation)
            add(relationship + '-' + activation, ['edges', '0'], edge, valid=True)
    for key in ('relationship', 'activation'):
        add('unknown-' + key, ['edges', '0', key], 'future_unsupported')
    add('unsupported-version', ['schema_version'], '2.0.0')
    add('wrong-root', [], [])
    add('invalid-id', ['id'], 'INVALID ID')
    add('invalid-edge-id', ['edges', '0', 'id'], 'INVALID ID')
    add('zero-revision', ['revision'], 0)
    add('negative-revision', ['revision'], -1)
    add('fractional-revision', ['revision'], 1.5)
    add('empty-edges', ['edges'], [])
    add('nonobject-edge', ['edges', '0'], [])
    add('empty-rationale', ['edges', '0', 'rationale'], '')
    add('unicode-rationale', ['edges', '0', 'rationale'], '\U0001f642', valid=True)
    add('unknown-root-field', ['future_field'], True)
    add('unknown-edge-field', ['edges', '0', 'future_field'], True)
    # Frozen v1 does not encode per-selection placement, roles or memory pools.
    for key in ('placement', 'component_role', 'memory_pool'):
        add('unsupported-' + key, ['edges', '0', key], 'synthetic')
    add('unsupported-hybrid-activation', ['edges', '0', 'activation'], 'hybrid')
    add('unsupported-extensions', ['extensions'], {'x_fixture': True})
    # The schema leaves repeated IDs, self edges and cycles to receiving policy.
    add('repeated-edge-preserved', ['edges'], [first, fixture['edges'][1], first], valid=True)
    add('self-edge-preserved', ['edges', '0', 'depends_on_kind'], first['dependent_kind'], valid=True)
    reverse = dict(first, id='dep.synthetic.reverse', dependent_kind=first['depends_on_kind'],
                   depends_on_kind=first['dependent_kind'])
    add('cycle-preserved', ['edges'], [first, reverse], valid=True)
    invalid = deepcopy(first)
    del invalid['rationale']
    add('one-invalid-edge-rejects-whole-graph', ['edges'], [first, invalid])
    # Deliberate representation subsets; not canonical-schema failures.
    add('unsupported-large-revision', ['revision'], 9_007_199_254_740_993, canonical=True)
    add('unsupported-terminal-newline-id', ['id'], 'graph.valid\n', canonical=True)
    add('unsupported-terminal-newline-edge-id', ['edges', '0', 'id'], 'edge.valid\n', canonical=True)
    assert len({case['name'] for case in cases}) == len(cases)
    return cases


def encoded_vectors():
    return '[\n' + ',\n'.join(json.dumps(case, ensure_ascii=False, separators=(',', ':'))
                            for case in vectors()) + '\n]\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='regenerate only the synthetic mutation file')
    args = parser.parse_args()
    expected = encoded_vectors()
    if args.write:
        OUTPUT.write_text(expected)
    else:
        assert OUTPUT.read_text() == expected, 'Graph vectors are stale; run dependency_graph_vectors.py --write'
    print(f'Dependency graph vectors: {len(vectors())}; deterministic generation verified.')
