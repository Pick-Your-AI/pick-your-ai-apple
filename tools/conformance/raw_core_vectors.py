#!/usr/bin/env python3
"""Replay Core's raw-wire cases without erasing duplicate keys first.

This is a strict raw-key client profile plus frozen structural validation, not
a change to JSON Schema or a claim about Swift byte/depth/number/format limits.
"""
import argparse
import hashlib
import json
from pathlib import Path
import unicodedata

import run

FIXTURES = Path(__file__).resolve().parents[2] / 'Packages/PlannerCore/Tests/PlannerCoreTests/Fixtures'


def unique_object(pairs):
    result, seen = {}, set()
    for key, value in pairs:
        identity = unicodedata.normalize('NFC', key)
        if identity in seen:
            raise ValueError('Ambiguous raw object keys')
        seen.add(identity)
        result[key] = value
    return result


def reject_constant(_):
    raise ValueError('Nonfinite JSON token')


def verify(contract_root):
    run.verify_source(contract_root)
    run.versions()
    bundle = run.read(FIXTURES / 'raw-contract-vectors.json')
    if bundle['fixture_version'] != 'core-raw-json-1':
        raise ValueError('Unsupported raw-wire fixture version')
    originals = {}
    for name, expected in bundle['base_sha256'].items():
        raw = (contract_root / 'examples' / (name + '.json')).read_bytes()
        if raw != (FIXTURES / (name + '.json')).read_bytes() or hashlib.sha256(raw).hexdigest() != expected:
            raise ValueError('Raw-wire source fixture changed')
        originals[name] = raw.decode('utf-8')
    parsed, failures = [], []
    for case in bundle['cases']:
        raw = originals[case['fixture']]
        for source, replacement in case['replacements']:
            if source not in raw:
                raise ValueError('Raw-wire mutation source did not match: ' + case['id'])
            raw = raw.replace(source, replacement)
        try:
            value = json.loads(raw, object_pairs_hook=unique_object, parse_constant=reject_constant)
        except ValueError:
            if case['valid']:
                failures.append(case['id'])
            continue
        parsed.append(dict(id=case['id'], schema=case['fixture'] + '.schema.json',
                           payload=value, valid=case['valid']))
    failures.extend(result['id'] for result in run.schema_results(contract_root, parsed) if not result['passed'])
    if failures:
        raise ValueError('Raw-wire conformance failed: ' + ', '.join(failures))
    return len(bundle['cases'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contract-root', type=Path, required=True)
    args = parser.parse_args()
    count = verify(args.contract_root)
    print(f'PASS {count} shared raw-wire cases; pinned fixtures and raw-key/frozen-structure profile')


if __name__ == '__main__':
    main()
