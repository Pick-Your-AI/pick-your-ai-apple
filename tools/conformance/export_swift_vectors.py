#!/usr/bin/env python3
"""Export identical report JSON payloads for the frozen schema and Swift decoder."""
import argparse
import copy
import json
from pathlib import Path
import tempfile

import run as reference


def bundle(root):
    manifest = reference.verify_source(root)
    reference.versions()
    with tempfile.TemporaryDirectory() as directory:
        snapshot = Path(directory)
        reference.copy_verified_source(root, snapshot, manifest)
        return verified_bundle(snapshot)


def verified_bundle(root):
    cases = [c for c in reference.vectors(root) if c['schema'] == 'evaluation-report.schema.json']
    original = reference.read(root / 'examples/evaluation-report.json')

    def case(label, payload, valid):
        cases.append(dict(id='evaluation-report/' + label, schema='evaluation-report.schema.json',
                          payload=payload, valid=valid))

    for field in original:
        changed = copy.deepcopy(original)
        changed[field] = None
        case('null/' + field, changed, False)
    for outcome in ('pass', 'fail', 'unknown', 'skipped'):
        for severity in ('error', 'warning', 'info'):
            changed = copy.deepcopy(original)
            changed['findings'][0]['outcome'] = outcome
            changed['findings'][0]['severity'] = severity
            changed['findings'][0]['evidence'] = [
                {'path': 'absent'}, {'path': 'null', 'observed': None},
                {'path': 'literal', 'observed': 'unknown'},
            ]
            case('outcome/' + outcome + '/' + severity, changed, True)
    for field in ('outcome', 'severity'):
        changed = copy.deepcopy(original)
        changed['findings'][0][field] = 'unsupported'
        case('invalid-finding/' + field, changed, False)

    results = reference.schema_results(root, cases)
    if not all(result['passed'] for result in results):
        raise ValueError('Vector expectation disagrees with the pinned canonical schema')
    return dict(lock=reference.LOCK, schema='evaluation-report.schema.json',
                fixture_sha256=reference.digest(root / 'examples/evaluation-report.json'),
                cases=[dict(id=c['id'], valid=c['valid'],
                            payloadJSON=json.dumps(c['payload'], sort_keys=True, separators=(',', ':')))
                       for c in cases])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contract-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--check', action='store_true', help='Fail if the committed bundle differs')
    args = parser.parse_args()
    value = bundle(args.contract_root)
    content = (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()
    if args.check:
        if args.output.read_bytes() != content:
            parser.exit(1, 'Swift vector bundle differs from the verified canonical export\n')
        fixture = args.output.parent / 'evaluation-report.json'
        if reference.digest(fixture) != value['fixture_sha256']:
            parser.exit(1, 'Swift report fixture differs from the verified canonical source\n')
    else:
        args.output.write_bytes(content)
    print(f"PASS {len(value['cases'])} identical report vectors; contract {reference.LOCK['contract_version']}")


if __name__ == '__main__':
    main()
