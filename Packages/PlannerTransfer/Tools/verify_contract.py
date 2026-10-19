"""Verify pinned resources and replay the shared Swift/Python conformance corpus.
Install the adjacent requirements.txt into a fresh virtual environment first.
Validation is read-only; no research checkout or network is needed.
"""
import hashlib
import json
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource


def require(condition, message):
    """Keep mandatory validation active when Python assertions are disabled."""
    if not condition:
        raise SystemExit(message)


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'Sources/PlannerTransfer/Resources'
FIXTURES = ROOT / 'Tests/PlannerTransferTests/Fixtures'
summaries = []
require({'date-time', 'uri'} <= FormatChecker().checkers.keys(),
        'Install Tools/requirements.txt to enable canonical format checks')
manifest = json.loads((ROOT / 'source-manifest.json').read_text())
for source, digest in manifest['files'].items():
    target = (FIXTURES if source.startswith('examples/') else RESOURCES) / Path(source).name
    require(hashlib.sha256(target.read_bytes()).hexdigest() == digest,
            f'Source hash mismatch: {source}')
schemas = {p.name: json.loads(p.read_text()) for p in RESOURCES.glob('*.json')}
registry = Registry().with_resources((s['$id'], Resource.from_contents(s)) for s in schemas.values())
cases = json.loads((FIXTURES / 'conformance.json').read_text())
for case in cases:
    validator = Draft202012Validator(schemas[case['schema']], registry=registry, format_checker=FormatChecker())
    actual = validator.is_valid(case['payload'])
    require(actual == case['valid'], case['name'])
summaries.append(f'Verified {len(manifest["files"])} source hashes and {len(cases)} canonical conformance cases.')

# Catalog cases use compact mutations to avoid duplicating the canonical fixture.
# The Swift test applies these exact mutations before using the public decoder.
from catalog_vectors import apply_vector, encoded_vectors
catalog_cases_path = FIXTURES / 'catalog-conformance.json'
require(catalog_cases_path.read_text() == encoded_vectors(), 'Stale catalog vectors')
catalog_cases = json.loads(catalog_cases_path.read_text())
catalog = json.loads((FIXTURES / 'catalog.json').read_text())
items = {item['kind']: item for item in catalog['items']}
require(len(items) == len(catalog['items']) == 29, 'Expected exactly 29 unique catalog kinds')
require(set(items) == set(schemas['catalog-item.schema.json']['properties']['kind']['enum']),
        'Fixture catalog kinds do not match the canonical schema')
validator = Draft202012Validator(schemas['catalog-item.schema.json'], registry=registry, format_checker=FormatChecker())
for case in catalog_cases:
    payload = apply_vector(items[case['kind']], case)
    require(validator.is_valid(payload) == case['canonicalValid'], case['name'])
summaries.append(f'Verified all 29 catalog kinds and {len(catalog_cases)} canonical catalog cases; client subsets remain explicit.')

# Quality records retain reported results without assigning evidence authority.
# Swift inserts the raw replacement token before decoding, avoiding a Foundation
# number conversion that could hide an unsupported precision/exponent input.
from quality_vectors import apply_vector as apply_quality_vector, encoded_vectors as encoded_quality_vectors
quality_cases_path = FIXTURES / 'quality-conformance.json'
require(quality_cases_path.read_text() == encoded_quality_vectors(), 'Stale quality vectors')
quality_cases = json.loads(quality_cases_path.read_text())
quality = json.loads((FIXTURES / 'quality-evaluation-run.json').read_text())
validator = Draft202012Validator(schemas['quality-evaluation-run.schema.json'], registry=registry, format_checker=FormatChecker())
for case in quality_cases:
    payload = apply_quality_vector(quality, case)
    require(validator.is_valid(payload) == case['canonicalValid'], case['name'])
summaries.append(f'Verified {len(quality_cases)} canonical quality cases; recorded labels and client subsets remain explicit.')

# Cost records retain decimal strings and reported results without pricing them.
from cost_vectors import apply_vector as apply_cost_vector, encoded_vectors as encoded_cost_vectors
cost_cases_path = FIXTURES / 'cost-conformance.json'
require(cost_cases_path.read_text() == encoded_cost_vectors(), 'Stale cost vectors')
cost_cases = json.loads(cost_cases_path.read_text())
cost = json.loads((FIXTURES / 'cost-estimate.json').read_text())
validator = Draft202012Validator(schemas['cost-estimate.schema.json'], registry=registry, format_checker=FormatChecker())
for case in cost_cases:
    payload = apply_cost_vector(cost, case)
    require(validator.is_valid(payload) == case['canonicalValid'], case['name'])
summaries.append(f'Verified {len(cost_cases)} canonical cost cases; decimal strings and reported coverage remain explicit.')

from resource_estimate_vectors import encoded_vectors as encoded_resource_vectors
resource_cases_path = FIXTURES / 'resource-estimate-conformance.json'
require(resource_cases_path.read_text() == encoded_resource_vectors(), 'Stale resource estimate vectors')
resource_cases = json.loads(resource_cases_path.read_text())
validator = Draft202012Validator(schemas['resource-estimate.schema.json'], registry=registry, format_checker=FormatChecker())
for case in resource_cases:
    require(validator.is_valid(json.loads(case['json'])) == case['canonicalValid'], case['name'])
summaries.append(f'Verified {len(resource_cases)} canonical resource estimate cases; no capacity, quality or tuple acceptance is inferred.')

# Placement vectors document existing transport and explicit v1 representation gaps.
# A schema-valid unresolved tuple is not a compatibility pass or a memory allocation.
from collections import Counter
from placement_vectors import apply_vector as apply_placement_vector, encoded_vectors as encoded_placement_vectors
placement_cases_path = FIXTURES / 'placement-conformance.json'
require(placement_cases_path.read_text() == encoded_placement_vectors(), 'Stale placement vectors')
placement_cases = json.loads(placement_cases_path.read_text())
build = json.loads((FIXTURES / 'build.json').read_text())
for case in placement_cases:
    is_build = case['fixture'] == 'build'
    original = build if is_build else items[case['fixture']]
    schema = schemas['build.schema.json' if is_build else 'catalog-item.schema.json']
    validator = Draft202012Validator(schema, registry=registry, format_checker=FormatChecker())
    payload = apply_placement_vector(original, case)
    require(validator.is_valid(payload) == case['canonicalValid'], case['name'])
    require(case['canonicalValid'] == case['clientValid'], case['name'])
summaries.append(f'Verified {len(placement_cases)} canonical placement cases: {dict(Counter(case["disposition"] for case in placement_cases))}; unresolved semantics remain explicit.')

# Graph mutations exercise the same public decoding inputs on Python and Swift.
from dependency_graph_vectors import encoded_vectors as encoded_graph_vectors
graph_cases_path = FIXTURES / 'dependency-graph-conformance.json'
require(graph_cases_path.read_text() == encoded_graph_vectors(), 'Stale dependency graph vectors')
graph_cases = json.loads(graph_cases_path.read_text())
graph = json.loads((FIXTURES / 'dependency-graph.json').read_text())
validator = Draft202012Validator(schemas['dependency-graph.schema.json'], registry=registry, format_checker=FormatChecker())
for case in graph_cases:
    require(validator.is_valid(apply_vector(graph, case)) == case['canonicalValid'], case['name'])
summaries.append(f'Verified {len(graph_cases)} canonical dependency graph cases; no executable graph policy is inferred.')

from ruleset_vectors import encoded_vectors as encoded_ruleset_vectors
ruleset_cases_path = FIXTURES / 'ruleset-conformance.json'
require(ruleset_cases_path.read_text() == encoded_ruleset_vectors(), 'Stale ruleset vectors')
ruleset_cases = json.loads(ruleset_cases_path.read_text())
validator = Draft202012Validator(schemas['ruleset.schema.json'], registry=registry, format_checker=FormatChecker())
for case in ruleset_cases:
    require(validator.is_valid(json.loads(case['json'])) == case['canonicalValid'], case['name'])
summaries.append(f'Verified {len(ruleset_cases)} canonical ruleset syntax cases; no rule evaluation is performed.')

# The whole catalog envelope is a separate artifact, with its original item order
# and duplicate identities retained. Structural admission does not activate it.
from catalog_snapshot_vectors import encoded_vectors as encoded_snapshot_vectors
snapshot_cases_path = FIXTURES / 'catalog-snapshot-conformance.json'
require(snapshot_cases_path.read_text() == encoded_snapshot_vectors(), 'Stale catalog snapshot vectors')
snapshot_cases = json.loads(snapshot_cases_path.read_text())
validator = Draft202012Validator(schemas['catalog-snapshot.schema.json'], registry=registry, format_checker=FormatChecker())
for case in snapshot_cases:
    require(validator.is_valid(apply_vector(catalog, case)) == case['canonicalValid'], case['name'])
summaries.append(f'Verified {len(snapshot_cases)} canonical catalog snapshot cases; activation and source-use remain separate.')

# A receipt describes the complete check, never a partially verified input set.
print('\n'.join(summaries))
