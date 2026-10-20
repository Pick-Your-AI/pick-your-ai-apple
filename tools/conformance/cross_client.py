#!/usr/bin/env python3
"""Materialize one pinned wire corpus for existing Swift/Python/web consumers."""
import argparse
from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile

import run as reference


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
OUTPUT = ROOT / 'Packages/PlannerConformance/Tests/PlannerConformanceTests/Fixtures/cross-client-v1.json'
LOCK = json.loads((HERE / 'cross-client-lock.json').read_text())
CONTRACTS = {
    'BuildSnapshot': 'build.schema.json',
    'CatalogItem': 'catalog-item.schema.json',
    'Selection': 'selection.schema.json',
    'EvaluationReport': 'evaluation-report.schema.json',
}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def checked_inputs(placement_root=None):
    result = {}
    for name, entry in LOCK['inputs'].items():
        root = placement_root if placement_root is not None and name.startswith('placement') else ROOT
        data = (root / entry['path']).read_bytes()
        if sha256(data) != entry['sha256']:
            raise ValueError(f'Pinned cross-client input differs: {name}')
        result[name] = data
    evidence_cases(result['evidence'])
    return result


def evidence_cases(data):
    """Select the exact original profile only after admitting the whole source."""
    evidence = json.loads(data)
    profile = LOCK['evidenceProfile']
    selected = profile['caseIDs']
    excluded = profile['excludedSourceCaseIDs']
    expected = selected + excluded
    if (profile['name'] != 'apple-cross-client-1/original-evidence-37' or
            len(selected) != 37 or len(excluded) != 4 or len(set(expected)) != 41 or
            evidence['lock']['contract_version'] != '1.0.0' or
            [case['id'] for case in evidence['cases']] != expected):
        raise ValueError('Pinned cross-client evidence profile identities differ')
    by_id = {case['id']: case for case in evidence['cases']}
    projected = dict(evidence, cases=[by_id[case_id] for case_id in selected])
    if sha256(encoded_bundle(projected)) != profile['sha256']:
        raise ValueError('Pinned cross-client evidence profile bytes differ')
    return projected['cases']


def load_placement_adapter(inputs, temporary):
    """Load only the checked adapter and helper, preserving ambient module state."""
    helper_path = temporary / 'contract_checks.py'
    helper_path.write_bytes(inputs['placementChecks'])
    helper_spec = importlib.util.spec_from_file_location('cross_client_contract_checks', helper_path)
    helper = importlib.util.module_from_spec(helper_spec)
    helper_spec.loader.exec_module(helper)
    adapter_path = temporary / 'placement_vectors.py'
    adapter_path.write_bytes(inputs['placementAdapter'])
    missing = object()
    original = sys.modules.get('contract_checks', missing)
    try:
        sys.modules['contract_checks'] = helper
        spec = importlib.util.spec_from_file_location('cross_client_placement', adapter_path)
        adapter = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(adapter)
        return adapter
    finally:
        if original is missing:
            del sys.modules['contract_checks']
        else:
            sys.modules['contract_checks'] = original


def cases(inputs, placement_adapter):
    """Keep canonical schema validity separate from the named client limits."""
    build = json.loads(inputs['build'])
    report = json.loads(inputs['report'])
    catalog = json.loads(inputs['catalog'])['items']
    items = {item['kind']: item for item in catalog}
    result = []

    def add(name, contract, payload, valid, reason, *, raw=None, disposition=None):
        text = raw if raw is not None else json.dumps(payload, sort_keys=True, ensure_ascii=False,
                                                      separators=(',', ':'), allow_nan=False)
        result.append(dict(id=name, contract=contract, schema=CONTRACTS[contract], payloadJSON=text,
                           payloadSHA256=sha256(text.encode('utf-8')), valid=valid, reason=reason,
                           disposition=disposition))

    add('canonical/build', 'BuildSnapshot', build, True, 'Exact original frozen-v1 bytes.',
        raw=inputs['build'].decode('utf-8'))
    add('canonical/report', 'EvaluationReport', report, True, 'Exact original frozen-v1 bytes.',
        raw=inputs['report'].decode('utf-8'))
    for item in catalog:
        add('canonical/catalog/' + item['kind'], 'CatalogItem', item, True,
            'One unchanged synthetic example for each of the 29 canonical kinds.')
    for selection in build['selections']:
        add('canonical/selection/' + selection['kind'], 'Selection', selection, True,
            'The canonical conditional settings and role remain unchanged.')

    placement = json.loads(inputs['placement'])
    if len(placement) != 98 or any(case['canonicalValid'] != case['clientValid'] for case in placement):
        raise ValueError('The reviewed placement corpus changed its shared boundary')
    for case in placement:
        is_build = case['fixture'] == 'build'
        payload = placement_adapter.apply_vector(build if is_build else items[case['fixture']], case)
        add('placement/' + case['name'], 'BuildSnapshot' if is_build else 'CatalogItem', payload,
            case['canonicalValid'], case['reason'], disposition=case['disposition'])

    for case in evidence_cases(inputs['evidence']):
        add(case['id'], 'EvaluationReport', None, case['valid'],
            'Retain the published #36 payload bytes and presence/outcome boundary.', raw=case['payloadJSON'])

    examples = [('BuildSnapshot', build), ('CatalogItem', items['workload']),
                ('Selection', build['selections'][0]), ('EvaluationReport', report)]
    for contract, original in examples:
        for label in ('missing-id', 'null-id', 'unknown-field'):
            value = deepcopy(original)
            if label == 'missing-id':
                del value['id']
            elif label == 'null-id':
                value['id'] = None
            else:
                value['not_a_contract_field'] = True
            add(f'boundary/{contract}/{label}', contract, value, False,
                'Reject the exact unsupported shape without inventing a default or dropping a field.')
        if contract != 'Selection':
            for version in ('0.9.0', '1.1.0', '99.0.0'):
                value = deepcopy(original)
                value['schema_version'] = version
                add(f'version/{contract}/{version}', contract, value, False,
                    'Frozen v1 has no adopted migration from this wire version; retain the source.')

    for label, amount, valid in [('exact-decimal-string', '9007199254740993.000000000001', True),
                                  ('numeric-money', 0.1, False), ('unknown-money', 'unknown', False)]:
        value = deepcopy(build)
        value['objectives']['monthly_budget_amount'] = amount
        add('boundary/build/' + label, 'BuildSnapshot', value, valid,
            'Money remains an exact decimal string; unknown is not zero and numbers are not coerced.')
    value = deepcopy(build)
    del value['locks']
    add('boundary/build/missing-locks', 'BuildSnapshot', value, False, 'Never insert or replace a missing source lock.')
    value = deepcopy(build)
    value['selections'] = []
    add('boundary/build/incomplete-draft', 'BuildSnapshot', value, False,
        'An editable incomplete draft is not a valid immutable wire snapshot.')
    value = deepcopy(items['model'])
    value['version'] = 'future-component-revision'
    add('identity/catalog-component-version', 'CatalogItem', value, True,
        'A component revision string is an identity, not the wire schema version or a binding approval.')
    value = deepcopy(build['selections'][0])
    value['catalog_item_version'] = 'retained-component-revision'
    add('identity/selection-component-version', 'Selection', value, True,
        'Keep the explicit component pin without silently upgrading or resolving it.')

    if len(result) != 223 or len({case['id'] for case in result}) != len(result):
        raise ValueError('Expected all 223 distinct cross-client cases')
    return result


def bundle(contract_root, placement_root=None):
    dependency_versions = reference.versions()
    manifest = reference.verify_source(contract_root)
    inputs = checked_inputs(placement_root)
    # The callable placement adapter and its helper use their checked bytes.
    # No code from an unverified caller-selected path is imported or executed.
    with tempfile.TemporaryDirectory(prefix='planner-cross-client-') as directory:
        temporary = Path(directory)
        snapshot = temporary / 'v1'
        snapshot.mkdir()
        reference.copy_verified_source(contract_root, snapshot, manifest)
        manifest_bytes = reference.read_regular_bytes(contract_root / 'IMPORT_MANIFEST.json')
        (snapshot / 'IMPORT_MANIFEST.json').write_bytes(manifest_bytes)
        reference.verify_source(snapshot)
        for key, filename in [('build', 'build.json'), ('catalog', 'catalog.json'),
                              ('report', 'evaluation-report.json')]:
            if inputs[key] != (snapshot / 'examples' / filename).read_bytes():
                raise ValueError('Consumer example differs from its canonical original: ' + key)
        adapter = load_placement_adapter(inputs, temporary)
        vectors = cases(inputs, adapter)
        checks = reference.schema_results(snapshot, [dict(id=v['id'], schema=v['schema'],
                                                          payload=json.loads(v['payloadJSON']), valid=v['valid'])
                                                      for v in vectors])
        for check in checks:
            if not check['passed']:
                raise ValueError('Cross-client expectation differs from frozen schema: ' + check['id'])
    return dict(bundleVersion=LOCK['bundleVersion'], contractVersion=LOCK['contractVersion'],
                referenceLock=reference.LOCK, inputPins=LOCK['inputs'],
                referenceDependencies=dependency_versions, websiteRevision=LOCK['websiteRevision'],
                cases=vectors, limits=[
                    'Synthetic golden payloads; acceptance does not prove compatibility, capacity, rights or readiness.',
                    'These 223 vectors are the shared supported profile, not whole-schema or arbitrary-number/encoding equivalence.',
                    'Catalog six and quality eighteen existing client exclusions remain in their original complete suites.',
                    'Local SQLite versions 1/2/3 are distinct from frozen wire version 1.0.0; no shared successor is adopted.',
                    'A future consumer uses the published interface; its actual runtime remains unverified until executed.'
                ])


def encoded_bundle(value):
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + '\n').encode('utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contract-root', type=Path, required=True)
    parser.add_argument('--placement-root', type=Path,
                        help='Read-only prerequisite preparation checkout; all three placement inputs are hash-verified')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--write', action='store_true', help='Regenerate only the owned synthetic wire fixture')
    mode.add_argument('--check', action='store_true')
    args = parser.parse_args()
    try:
        result = bundle(args.contract_root.resolve(), args.placement_root)
        contents = encoded_bundle(result)
        if args.write:
            OUTPUT.parent.mkdir(parents=True, exist_ok=True)
            OUTPUT.write_bytes(contents)
        elif OUTPUT.read_bytes() != contents:
            raise ValueError('Cross-client consumer bytes differ; regenerate and review the fixture')
    except (ValueError, OSError) as error:
        parser.exit(1, f'Cross-client fixture verification failed: {error}\n')
    count = sum(case['valid'] for case in result['cases'])
    print(f"PASS {len(result['cases'])} cross-client vectors ({count} accepted, {len(result['cases']) - count} rejected); "
          f"{result['bundleVersion']}; SHA-256 {sha256(contents)}")


if __name__ == '__main__':
    main()
