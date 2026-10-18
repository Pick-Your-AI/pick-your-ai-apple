#!/usr/bin/env python3
"""Read-only frozen-v1 preparation runner; not an Apple runtime implementation."""
import argparse
import copy
import hashlib
import importlib.metadata
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

HERE = Path(__file__).resolve().parent
LOCK = json.loads((HERE / 'contract-lock.json').read_text())
SAMPLES = {
    'catalog-snapshot': 'catalog', 'build': 'build',
    'dependency-graph': 'dependency-graph', 'ruleset': 'ruleset',
    'evaluation-report': 'evaluation-report', 'pricebook': 'pricebook',
    'cost-estimate': 'cost-estimate', 'event': 'event',
    'resource-estimate': 'resource-estimate',
    'quality-evaluation-run': 'quality-evaluation-run',
    'deployment-manifest': 'deployment-manifest',
}


def read(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_source(root):
    """Trust only the pinned manifest, then verify every frozen import byte."""
    manifest_bytes = (root / 'IMPORT_MANIFEST.json').read_bytes()
    if hashlib.sha256(manifest_bytes).hexdigest() != LOCK['import_manifest_sha256']:
        raise ValueError('Frozen import manifest differs from contract-lock.json')
    manifest = json.loads(manifest_bytes)
    if manifest['contract_version'] != LOCK['contract_version']:
        raise ValueError('Unexpected contract version')
    for entry in manifest['files']:
        path = (root / entry['path']).resolve()
        if not path.is_relative_to(root.resolve()) or digest(path) != entry['sha256']:
            raise ValueError(f"Frozen import hash mismatch: {entry['path']}")
    return manifest


def copy_verified_source(root, snapshot, manifest):
    """Copy listed inputs, then verify the complete copy before consumption."""
    root = root.resolve()
    for entry in manifest['files']:
        source = (root / entry['path']).resolve()
        if not source.is_relative_to(root):
            raise ValueError(f"Frozen import hash mismatch: {entry['path']}")
        target = snapshot / entry['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    # The source checkout can change after verify_source. Pin the bytes that
    # will actually be consumed, using its already verified in-memory manifest.
    for entry in manifest['files']:
        if digest(snapshot / entry['path']) != entry['sha256']:
            raise ValueError(f"Frozen import hash mismatch: {entry['path']}")


def versions():
    result = {}
    for line in (HERE / 'requirements.txt').read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        name, expected = line.split('==')
        actual = importlib.metadata.version(name)
        if actual != expected:
            raise ValueError(f'{name}: expected {expected}, installed {actual}')
        result[name] = actual
    return result


def vectors(root):
    """Concrete payloads and boolean schema results consumable by any client."""
    cases = []
    for schema, sample in SAMPLES.items():
        payload = read(root / 'examples' / f'{sample}.json')
        cases.append(dict(id=f'{schema}/valid', schema=f'{schema}.schema.json',
                          payload=payload, valid=True))
        required = read(root / 'schemas' / f'{schema}.schema.json')['required']
        for field in required:
            changed = copy.deepcopy(payload)
            del changed[field]
            cases.append(dict(id=f'{schema}/missing/{field}', schema=f'{schema}.schema.json',
                              payload=changed, valid=False))
        for label, key, value in [('future-version', 'schema_version', '99.0.0'),
                                  ('unknown-field', 'unrecognized_fixture_field', True)]:
            changed = copy.deepcopy(payload)
            changed[key] = value
            cases.append(dict(id=f'{schema}/{label}', schema=f'{schema}.schema.json',
                              payload=changed, valid=False))
    # A decimal is a string boundary, never a JSON floating-point coercion.
    build = read(root / 'examples/build.json')
    build['objectives']['monthly_budget_amount'] = 0.1
    cases.append(dict(id='build/numeric-money', schema='build.schema.json', payload=build, valid=False))
    return cases


def schema_results(root, cases):
    schemas = {p.name: read(p) for p in (root / 'schemas').glob('*.schema.json')}
    registry = Registry().with_resources((s['$id'], Resource.from_contents(s)) for s in schemas.values())
    for schema in schemas.values():
        Draft202012Validator.check_schema(schema)
    results = []
    for case in cases:
        validator = Draft202012Validator(schemas[case['schema']], registry=registry,
                                         format_checker=FormatChecker())
        actual = validator.is_valid(case['payload'])
        results.append(dict(id=case['id'], expected=case['valid'], actual=actual,
                            passed=actual == case['valid']))
    return results


def domain_results(root):
    # Execute only after verification, from a disposable copy. Never install a backend.
    spec = importlib.util.spec_from_file_location('frozen_reference', root / 'reference/evaluate.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = lambda name: read(root / 'examples' / f'{name}.json')
    build, catalog, rules = data('build'), data('catalog'), data('ruleset')
    evaluator = module.Evaluator(build, catalog, rules)
    results = []
    def check(name, actual, expected):
        results.append(dict(id=name, actual=actual, expected=expected, passed=actual == expected))
    # Adjacent values beyond binary64 precision must not compare equal.
    check('decimal/precision', evaluator.compare('eq', '9007199254740992', '9007199254740993'), False)
    check('decimal/fraction', str(module.numeric('0.1') + module.numeric('0.2')), '0.3')
    check('unknown/typed', evaluator.compare('eq', module.UNKNOWN, 'unknown') is module.UNKNOWN, True)
    report = evaluator.evaluate()
    outcome = next(f['outcome'] for f in report['findings'] if f['rule_id'] == 'rule.vram.estimate.fit')
    check('unknown/missing-resource', outcome, 'unknown')
    broken = copy.deepcopy(build)
    next(s for s in broken['selections'] if s['kind'] == 'vector_database')['settings']['index_dimension'] = 1024
    report = module.Evaluator(broken, catalog, rules, cost_estimate=data('cost-estimate'),
                              resource_estimate=data('resource-estimate')).evaluate()
    outcome = next(f['outcome'] for f in report['findings'] if f['rule_id'] == 'rule.embedding.dimension')
    check('rule/dimension-mismatch', outcome, 'fail')
    check('rule/dimension-readiness', report['deployment_readiness'], 'blocked')
    return results


def mutation_results(root, cases):
    results = []
    for name in ('required-field', 'decimal', 'rule'):
        with tempfile.TemporaryDirectory() as tmp:
            mutated = Path(tmp) / 'v1'
            shutil.copytree(root, mutated)
            if name == 'required-field':
                path = mutated / 'schemas/build.schema.json'
                schema = read(path)
                schema['required'].remove('id')
                path.write_text(json.dumps(schema))
                checks = schema_results(mutated, cases)
            else:
                path = mutated / 'reference/evaluate.py'
                original = path.read_text()
                before, after = (('return Decimal(x)', 'return float(x)') if name == 'decimal' else
                                 ("return equal if op=='eq' else not equal", "return True if op=='eq' else not equal"))
                if original.count(before) != 1:
                    raise ValueError(f'Mutation anchor changed: {name}')
                path.write_text(original.replace(before, after))
                checks = domain_results(mutated)
            failures = [c['id'] for c in checks if not c['passed']]
            results.append(dict(id=name, detected=bool(failures), failing_checks=failures))
    return results


def run(root):
    manifest = verify_source(root)
    dependency_versions = versions()
    # Copy exactly manifest-covered files, excluding untracked scripts or bytecode.
    with tempfile.TemporaryDirectory() as tmp:
        snapshot = Path(tmp) / 'v1'
        copy_verified_source(root, snapshot, manifest)
        cases = vectors(snapshot)
        schema = schema_results(snapshot, cases)
        domain = domain_results(snapshot)
        reference = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-v'],
                                   cwd=snapshot, capture_output=True, text=True,
                                   env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'}, timeout=120)
        if reference.returncode:
            raise ValueError('Canonical reference suite failed:\n' + reference.stdout + reference.stderr)
        mutations = mutation_results(snapshot, cases)
        if not all(c['passed'] for c in schema + domain) or not all(m['detected'] for m in mutations):
            raise ValueError('Conformance or mutation checks failed')
        return dict(lock=LOCK, python=sys.version.split()[0], dependencies=dependency_versions,
                    canonical_reference='passed', schema_results=schema, domain_results=domain,
                    mutations=mutations, vectors=cases,
                    limitations=['Synthetic Python reference preparation only',
                                 'Swift/Apple runtime, migrations, device and receiving acceptance unverified'])


def prepare_output(root, output):
    """Invalidate an accepted receipt without unlinking source inputs or link targets."""
    # Resolve parent aliases, but keep the final component so unlink never follows it.
    output = output.parent.resolve(strict=True) / output.name
    if output.is_relative_to(root) or output.is_relative_to(HERE):
        raise ValueError('Output must be outside the frozen contract and conformance tool directories')
    try:
        existing = output.lstat()
    except FileNotFoundError:
        return output
    if not stat.S_ISREG(existing.st_mode) or existing.st_nlink != 1:
        raise ValueError('Output must be an unshared regular file (no links or directories)')
    output.unlink()
    return output


def write_report(output, result):
    contents = json.dumps(result, sort_keys=True, indent=2) + '\n'
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=output.parent,
                                         prefix='.conformance-', suffix='.tmp', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(contents)
        temporary.replace(output)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contract-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        root = args.contract_root.resolve()
        output = prepare_output(root, args.output)
        result = run(root)
        write_report(output, result)
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f'Conformance failed: {error}\n')
    print(f"PASS {len(result['schema_results'])} schema vectors, {len(result['domain_results'])} domain checks, "
          f"3 detected mutations; contract {LOCK['contract_version']}; {LOCK['fixture_bundle_version']}")


if __name__ == '__main__':
    sys.dont_write_bytecode = True
    main()
