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

# Catalog cases use compact mutations to avoid duplicating the canonical fixture.
# The Swift test applies these exact mutations before using the public decoder.
from catalog_vectors import apply_vector, encoded_vectors
catalog_cases_path = FIXTURES / 'catalog-conformance.json'
assert catalog_cases_path.read_text() == encoded_vectors(), 'Stale catalog vectors'
catalog_cases = json.loads(catalog_cases_path.read_text())
catalog = json.loads((FIXTURES / 'catalog.json').read_text())
items = {item['kind']: item for item in catalog['items']}
assert len(items) == len(catalog['items']) == 29
assert set(items) == set(schemas['catalog-item.schema.json']['properties']['kind']['enum'])
validator = Draft202012Validator(schemas['catalog-item.schema.json'], registry=registry, format_checker=FormatChecker())
for case in catalog_cases:
    payload = apply_vector(items[case['kind']], case)
    assert validator.is_valid(payload) == case['canonicalValid'], case['name']
print(f'Verified all 29 catalog kinds and {len(catalog_cases)} canonical catalog cases; client subsets remain explicit.')

# Quality records retain reported results without assigning evidence authority.
# Swift inserts the raw replacement token before decoding, avoiding a Foundation
# number conversion that could hide an unsupported precision/exponent input.
from quality_vectors import apply_vector as apply_quality_vector, encoded_vectors as encoded_quality_vectors
quality_cases_path = FIXTURES / 'quality-conformance.json'
assert quality_cases_path.read_text() == encoded_quality_vectors(), 'Stale quality vectors'
quality_cases = json.loads(quality_cases_path.read_text())
quality = json.loads((FIXTURES / 'quality-evaluation-run.json').read_text())
validator = Draft202012Validator(schemas['quality-evaluation-run.schema.json'], registry=registry, format_checker=FormatChecker())
for case in quality_cases:
    payload = apply_quality_vector(quality, case)
    assert validator.is_valid(payload) == case['canonicalValid'], case['name']
print(f'Verified {len(quality_cases)} canonical quality cases; recorded labels and client subsets remain explicit.')

from resource_estimate_vectors import encoded_vectors as encoded_resource_vectors
resource_cases_path = FIXTURES / 'resource-estimate-conformance.json'
assert resource_cases_path.read_text() == encoded_resource_vectors(), 'Stale resource estimate vectors'
resource_cases = json.loads(resource_cases_path.read_text())
validator = Draft202012Validator(schemas['resource-estimate.schema.json'], registry=registry, format_checker=FormatChecker())
for case in resource_cases:
    assert validator.is_valid(json.loads(case['json'])) == case['canonicalValid'], case['name']
print(f'Verified {len(resource_cases)} canonical resource estimate cases; no capacity, quality or tuple acceptance is inferred.')

from catalog_snapshot_vectors import encoded_vectors as encoded_snapshot_vectors
snapshot_cases_path = FIXTURES / 'catalog-snapshot-conformance.json'
assert snapshot_cases_path.read_text() == encoded_snapshot_vectors(), 'Stale catalog snapshot vectors'
snapshot_cases = json.loads(snapshot_cases_path.read_text())
validator = Draft202012Validator(schemas['catalog-snapshot.schema.json'], registry=registry, format_checker=FormatChecker())
for case in snapshot_cases:
    payload = apply_vector(catalog, case)
    assert validator.is_valid(payload) == case['canonicalValid'], case['name']
print(f'Verified {len(snapshot_cases)} canonical catalog snapshot cases; whole-document limits remain explicit.')

# Placement vectors document existing transport and explicit v1 representation gaps.
# A schema-valid unresolved tuple is not a compatibility pass or a memory allocation.
from collections import Counter
from placement_vectors import apply_vector as apply_placement_vector, encoded_vectors as encoded_placement_vectors
placement_cases_path = FIXTURES / 'placement-conformance.json'
assert placement_cases_path.read_text() == encoded_placement_vectors(), 'Stale placement vectors'
placement_cases = json.loads(placement_cases_path.read_text())
build = json.loads((FIXTURES / 'build.json').read_text())
for case in placement_cases:
    is_build = case['fixture'] == 'build'
    original = build if is_build else items[case['fixture']]
    schema = schemas['build.schema.json' if is_build else 'catalog-item.schema.json']
    validator = Draft202012Validator(schema, registry=registry, format_checker=FormatChecker())
    payload = apply_placement_vector(original, case)
    assert validator.is_valid(payload) == case['canonicalValid'], case['name']
    assert case['canonicalValid'] == case['clientValid'], case['name']
print(f'Verified {len(placement_cases)} canonical placement cases: {dict(Counter(case["disposition"] for case in placement_cases))}; unresolved semantics remain explicit.')
