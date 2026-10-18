#!/usr/bin/env python3
"""Replay Swift's synthetic pricebook vectors against verified frozen-v1 schemas.

Usage: python tools/conformance/pricebook_vectors.py --contract-root PATH
Timestamp/URI format enforcement, input size and Int range are separate Swift
checks; these vectors only claim shared structural/enum/decimal validation.
"""
import argparse
import hashlib
from pathlib import Path
import run

FIXTURES = Path(__file__).resolve().parents[2] / 'Packages/PlannerCore/Tests/PlannerCoreTests/Fixtures'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contract-root', type=Path, required=True)
    args = parser.parse_args()
    run.verify_source(args.contract_root)
    run.versions()
    original = (args.contract_root / 'examples/pricebook.json').read_bytes()
    if original != (FIXTURES / 'pricebook.json').read_bytes():
        raise SystemExit('Canonical fixture changed')
    cases = run.read(FIXTURES / 'pricebook-vectors.json')
    results = run.schema_results(args.contract_root, cases)
    failures = [case['id'] for case in results if not case['passed']]
    if failures:
        raise SystemExit(f'FAIL: {failures}')
    print(f'PASS {len(results)} shared pricebook vectors; fixture SHA-256 {hashlib.sha256(original).hexdigest()}')


if __name__ == '__main__':
    main()
