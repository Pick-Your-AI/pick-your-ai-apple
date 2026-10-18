"""Verify pinned resources and replay the shared Swift/Python conformance corpus.
Requires jsonschema[format]==4.26.0. Read-only; no research checkout or network is needed.
"""
import hashlib
import json
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'Sources/PlannerTransfer/Resources'
FIXTURES = ROOT / 'Tests/PlannerTransferTests/Fixtures'
assert {'date-time', 'uri'} <= FormatChecker().checkers.keys(), 'Install jsonschema[format] to enable canonical format checks'
manifest = json.loads((ROOT / 'source-manifest.json').read_text())
for source, digest in manifest['files'].items():
    target = (FIXTURES if source.startswith('examples/') else RESOURCES) / Path(source).name
    assert hashlib.sha256(target.read_bytes()).hexdigest() == digest, source
schemas = {p.name: json.loads(p.read_text()) for p in RESOURCES.glob('*.json')}
registry = Registry().with_resources((s['$id'], Resource.from_contents(s)) for s in schemas.values())
cases = json.loads((FIXTURES / 'conformance.json').read_text())
for case in cases:
    validator = Draft202012Validator(schemas[case['schema']], registry=registry, format_checker=FormatChecker())
    actual = validator.is_valid(case['payload'])
    assert actual == case['valid'], case['name']
print(f'Verified {len(manifest["files"])} source hashes and {len(cases)} canonical conformance cases.')

from resource_estimate_vectors import encoded_vectors as encoded_resource_vectors
resource_cases_path = FIXTURES / 'resource-estimate-conformance.json'
assert resource_cases_path.read_text() == encoded_resource_vectors(), 'Stale resource estimate vectors'
resource_cases = json.loads(resource_cases_path.read_text())
validator = Draft202012Validator(schemas['resource-estimate.schema.json'], registry=registry, format_checker=FormatChecker())
for case in resource_cases:
    assert validator.is_valid(json.loads(case['json'])) == case['canonicalValid'], case['name']
print(f'Verified {len(resource_cases)} canonical resource estimate cases; no capacity, quality or tuple acceptance is inferred.')
