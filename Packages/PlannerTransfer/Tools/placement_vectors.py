"""Placement transport vectors over the unchanged frozen-v1 build/catalog fixtures.

The disposition describes this test's scope, not an executable compatibility
outcome. Structural acceptance never resolves placement, binding, memory capacity
or route budgets. Unsupported fields remain rejected instead of extending v1.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'Sources/PlannerTransfer/Resources'
FIXTURES = ROOT / 'Tests/PlannerTransferTests/Fixtures'
OUTPUT = FIXTURES / 'placement-conformance.json'


def mutation(path, value=None, *, remove=False):
    result = {'path': list(path), 'operation': 'remove' if remove else 'set'}
    if not remove:
        result['json'] = json.dumps(value, ensure_ascii=False, separators=(',', ':'))
    return result


def apply_vector(original, case):
    value = deepcopy(original)
    for change in case['mutations']:
        parent = value
        for key in change['path'][:-1]:
            parent = parent[int(key)] if isinstance(parent, list) else parent[key]
        key = change['path'][-1]
        if isinstance(parent, list):
            key = int(key)
        if change['operation'] == 'remove':
            del parent[key]
        else:
            assert change['operation'] == 'set'
            parent[key] = json.loads(change['json'])
    return value


def vectors():
    build = json.loads((FIXTURES / 'build.json').read_text())
    catalog = json.loads((FIXTURES / 'catalog.json').read_text())
    items = {item['kind']: item for item in catalog['items']}
    indices = {item['kind']: str(i) for i, item in enumerate(build['selections'])}
    cases = []

    def selection(kind, *path):
        return ['selections', indices[kind], *path]

    def add(name, changes=(), *, kind='build', disposition='preserved', reason,
            decision='none', error=None):
        valid = disposition in ('preserved', 'unresolved')
        assert valid == (error is None)
        cases.append(dict(name=name, fixture=kind, mutations=list(changes),
                          canonicalValid=valid, clientValid=valid,
                          disposition=disposition, decision=decision, reason=reason,
                          expectedError=error))

    add('canonical-relationships', reason='Preserve every supplied selection, directed link and exact lock; schema validity is not compatibility.')
    schema = json.loads((RESOURCES / 'build.schema.json').read_text())
    for relation in schema['properties']['links']['items']['properties']['relation']['enum']:
        add('relation-' + relation, [mutation(['links', '0', 'relation'], relation)],
            reason='Preserve this canonical relation label and its direction without assigning extra semantics.')
    for flag in (False, True):
        add('link-required-' + str(flag).lower(), [mutation(['links', '0', 'required'], flag)],
            reason='Preserve the explicit optional link flag; absence is a distinct representation.')
    add('link-direction-reversed', [mutation(['links', '0', 'from_selection_id'], 'sel_model_provider'),
                                   mutation(['links', '0', 'to_selection_id'], 'sel_model')],
        reason='Do not silently reverse endpoints to a preferred component order.')
    add('roles-remain-distinct', [mutation(selection('model', 'role'), 'generation-local'),
                                  mutation(selection('embedding_model', 'role'), 'retrieval_api'),
                                  mutation(selection('model', 'enabled'), False)],
        reason='Retain caller-supplied role labels and disabled selections; roles are not deployment assignments.')
    add('context-quantities-remain-distinct', [mutation(selection('context_policy', 'settings', 'requested_context_tokens'), 4096),
                                             mutation(selection('context_policy', 'settings', 'reserved_output_tokens'), 512),
                                             mutation(selection('model', 'settings', 'max_output_tokens'), 256),
                                             mutation(['objectives', 'avg_input_tokens'], 700),
                                             mutation(['objectives', 'avg_output_tokens'], 400)],
        reason='Keep requested input, generation reservation, selected output cap and workload averages separate; no sum, minimum or override is computed.')
    add('device-and-parallel-counts-remain-distinct', [mutation(selection('accelerator', 'settings', 'device_count'), 4),
                                                     mutation(selection('accelerator', 'settings', 'tensor_parallel_groups'), 2),
                                                     mutation(selection('inference_engine', 'settings', 'tensor_parallel_size'), 3),
                                                     mutation(selection('compute_profile', 'settings', 'instances'), 2)],
        reason='Preserve four independent counts; neither their equality nor allocatable pooled memory is inferred.')
    add('catalog-version-lock-not-rebound', [mutation(selection('model', 'catalog_item_version'), 'retained-revision-2')],
        disposition='unresolved', decision='CD-6/CD-7',
        reason='A syntactically valid pin is retained exactly; association with a retained catalog needs a separate binding check.')

    for mode in ('api', 'managed', 'self_hosted', 'hybrid'):
        add('catalog-mode-' + mode, [mutation(['spec', 'mode'], mode)], kind='deployment_mode',
            reason='Retain the existing catalog mode label; this does not create per-component operator or capacity facts.')
    add('catalog-per-device-vram', [mutation(['spec', 'vram_gb'], 24), mutation(['spec', 'interconnect'], 'nvlink')],
        kind='accelerator', reason='Retain advertised device memory and interconnect labels; do not multiply memory or infer allocation.')
    add('catalog-host-memory-and-count', [mutation(['spec', 'ram_gb'], 128), mutation(['spec', 'accelerator_count'], 4)],
        kind='compute_profile', reason='Host RAM and accelerator count remain separate facts from per-device VRAM.')
    add('catalog-explicit-cpu-facts', [mutation(['spec', 'accelerator_type'], 'cpu'), mutation(['spec', 'backends'], ['cpu']),
                                       mutation(['spec', 'vram_gb'], 0)], kind='accelerator',
        disposition='unresolved', decision='CD-2',
        reason='An explicitly supplied CPU kind and zero device VRAM do not establish host allocation, unified memory or runtime fit.')
    for kind, fields in [('compute_profile', ('accelerator_ref', 'accelerator_count')),
                         ('inference_engine', ('supports_multi_gpu',)),
                         ('model', ('min_weights_vram_gb',)),
                         ('context_policy', ('max_allowed_tokens',))]:
        changes = [mutation(['spec', field], remove=True) for field in fields if field in items[kind]['spec']]
        add('catalog-absent-' + kind, changes, kind=kind, disposition='unresolved', decision='CD-2/CD-11',
            reason='Optional absence remains absent; no zero, false, CPU-only assumption, pooling permission or vendor limit is inserted.')

    local = deepcopy(build['selections'][int(indices['model'])])
    local['role'] = 'generation_local'
    remote = deepcopy(local)
    remote.update(id='sel_remote_model', role='generation_api')
    remote['settings']['serving_mode'] = 'api'
    mixed = deepcopy(build['selections'])
    mixed[int(indices['model'])] = local
    mixed.append(remote)
    mixed_links = deepcopy(build['links'])
    mixed_links.append(dict(id='link.remote', from_selection_id='sel_remote_model',
                            to_selection_id='sel_model_provider', relation='provided_by', required=False))
    add('mixed-api-and-weight-selections', [mutation(['selections'], mixed), mutation(['links'], mixed_links)],
        disposition='unresolved', decision='CD-2/CD-6',
        reason='Both access paths and their role-bound IDs survive; access mode alone does not prove runtime operator, hybrid applicability or placement.')
    duplicate_role = deepcopy(mixed)
    duplicate_role[-1]['role'] = local['role']
    add('ambiguous-duplicate-kind-role', [mutation(['selections'], duplicate_role)],
        disposition='unresolved', decision='CD-6/CD-13',
        reason='The frozen build schema has no kind/role uniqueness rule; preserve ambiguity instead of silently choosing the first selection.')
    duplicate_id = deepcopy(mixed)
    duplicate_id[-1]['id'] = local['id']
    add('ambiguous-duplicate-selection-id', [mutation(['selections'], duplicate_id)],
        disposition='unresolved', decision='CD-6',
        reason='Structural parsing does not establish unique selection binding; a consumer must not select an arbitrary duplicate.')
    second_engine = deepcopy(build['selections'][int(indices['inference_engine'])])
    second_engine['id'] = 'sel_second_engine'
    add('two-engine-links', [mutation(['selections'], build['selections'] + [second_engine]),
                             mutation(['links'], build['links'] + [dict(id='link.engine.two', from_selection_id='sel_model', to_selection_id='sel_second_engine', relation='served_by')])],
        disposition='unresolved', decision='CD-6',
        reason='Two distinct engine candidates survive with the same role; structural parsing cannot select the applicable deployment binding.')
    for label, links in [
        ('self-link', [dict(id='link.self', from_selection_id='sel_model', to_selection_id='sel_model', relation='uses')]),
        ('cycle', [dict(id='link.cycle.a', from_selection_id='sel_model', to_selection_id='sel_inference_engine', relation='uses'),
                   dict(id='link.cycle.b', from_selection_id='sel_inference_engine', to_selection_id='sel_model', relation='uses')]),
        ('repeated-link', [build['links'][0], build['links'][0]]),
        ('dangling-link', [dict(id='link.missing', from_selection_id='sel_model', to_selection_id='sel_not_present', relation='served_by')]),
        ('empty-links', []),
    ]:
        add(label, [mutation(['links'], links)], disposition='unresolved', decision='CD-6',
            reason='The wire schema preserves this link inventory; referential integrity, completeness and deployment binding are separate decisions.')
    add('model-omitted-serving-mode', [mutation(selection('model', 'settings', 'serving_mode'), remove=True)],
        disposition='unresolved', decision='CD-2', reason='Missing access mode stays absent and never becomes weights, API or an operator classification.')
    add('adapter-base-inheritance-unresolved', [mutation(selection('fine_tuned_model', 'settings', 'use_adapter'), True),
                                                mutation(selection('fine_tuned_model', 'role'), 'adapter_generation')],
        disposition='unresolved', decision='CD-6', reason='Preserve use_adapter and derived_from without inheriting unproved base deployment, formats or context.')
    add('opaque-memory-extension-is-not-placement', [mutation(['extensions'], {'x_memory_pool': {'allocation_bytes': 1024, 'members': ['sel_accelerator']}})],
        disposition='unresolved', decision='CD-2', reason='The allowed extension is opaque local data, not approved memory semantics; the transfer boundary still rejects extensions.')
    add('logical-memory-store-is-not-device-memory', [mutation(selection('memory_store', 'settings', 'ttl_hours'), 24)],
        disposition='unresolved', decision='CD-2', reason='Agent-memory TTL and stored_in links do not define a hardware memory pool.')
    add('request-and-workload-counts-not-reconciled', [mutation(['objectives', 'max_concurrency'], 1),
                                                    mutation(selection('workload', 'settings', 'concurrency'), 4)],
        disposition='unresolved', decision='CD-5', reason='Different supplied request counts survive; no sequence expansion or per-stage allocation is guessed.')

    unsupported = [
        ('build-placement', ['placement'], {'device_selection_id': 'sel_accelerator'}),
        ('build-memory-pools', ['memory_pools'], [{'id': 'pool.fixture', 'bytes': 1024}]),
        ('selection-deployment', selection('model', 'deployment'), {'runtime_operator': 'self'}),
        ('selection-memory-pool', selection('model', 'memory_pool_ref'), 'pool.fixture'),
        ('model-runtime-operator', selection('model', 'settings', 'runtime_operator'), 'self'),
        ('model-component-placement', selection('model', 'settings', 'placement'), {'layers': [0, 8]}),
        ('mode-selection-setting', selection('deployment_mode', 'settings', 'mode'), 'hybrid'),
        ('link-role-binding', ['links', '0', 'role'], 'generation'),
        ('link-allocated-bytes', ['links', '0', 'allocation_bytes'], 1024),
        ('accelerator-pooled-vram', selection('accelerator', 'settings', 'pooled_vram_gb'), 96),
        ('accelerator-unified-memory', selection('accelerator', 'settings', 'unified_memory_gb'), 128),
        ('compute-allocation', selection('compute_profile', 'settings', 'allocatable_ram_gb'), 96),
        ('context-semantics', selection('context_policy', 'settings', 'context_semantics'), 'separate'),
        ('context-input-cap', selection('context_policy', 'settings', 'max_input_tokens'), 4096),
        ('context-route-override', selection('context_policy', 'settings', 'provider_override'), {'max_output_tokens': 256}),
        ('context-shared-total', selection('context_policy', 'settings', 'combined_context_tokens'), 4608),
        ('engine-sequence-expansion', selection('inference_engine', 'settings', 'sequences_per_request'), 4),
    ]
    for label, path, value in unsupported:
        add('unsupported-' + label, [mutation(path, value)], disposition='unsupported-field', error='schemaViolation',
            decision='CD-2/CD-5/CD-6/CD-11', reason='This field is not in frozen v1; reject it, retain the original input and route an explicit versioned proposal through Research #40.')
    for kind, field, value in [('accelerator', 'allocatable_bytes', 1024), ('accelerator', 'memory_pool_id', 'pool.fixture'),
                                ('accelerator', 'unified_memory_gb', 128), ('compute_profile', 'host_ram_gib', 128),
                                ('model', 'context_semantics', 'separate'), ('model', 'max_input_tokens', 4096),
                                ('context_policy', 'provider_override', {'max_output_tokens': 256})]:
        add('unsupported-catalog-' + field, [mutation(['spec', field], value)], kind=kind,
            disposition='unsupported-field', decision='CD-2/CD-11', error='schemaViolation',
            reason='A plausible researched concept is not an extra v1 catalog fact; reject without silently dropping or reinterpreting it.')

    for kind, path in [('build', selection('model', 'role')), ('build', selection('model', 'catalog_item_version')),
                       ('build', selection('context_policy', 'settings', 'requested_context_tokens')),
                       ('build', selection('context_policy', 'settings', 'reserved_output_tokens')),
                       ('build', ['links', '0', 'from_selection_id']), ('build', ['links', '0', 'to_selection_id']),
                       ('build', ['links', '0', 'relation']), ('build', ['locks', 'dependency_graph_revision']),
                       ('accelerator', ['spec', 'vram_gb']), ('compute_profile', ['spec', 'ram_gb']),
                       ('model', ['spec', 'context_window_tokens']), ('deployment_mode', ['spec', 'mode'])]:
        add('missing-' + kind + '-' + '-'.join(path), [mutation(path, remove=True)], kind=kind,
            disposition='invalid-contract', error='schemaViolation', reason='A required fact is missing; do not manufacture zero, defaults or a replacement fact.')
    for kind in ('build', 'accelerator'):
        for version in ('0.9.0', '1.0.1', '2.0.0'):
            add('unsupported-version-' + kind + '-' + version, [mutation(['schema_version'], version)], kind=kind,
                disposition='invalid-contract', error='unsupportedVersion', reason='This v1 decoder cannot migrate or relabel unsupported contract versions.')
    for label, path, value in [('role-uppercase', selection('model', 'role'), 'Primary'),
                                ('role-empty', selection('model', 'role'), ''),
                                ('relation-unknown', ['links', '0', 'relation'], 'pooled_with'),
                                ('required-not-boolean', ['links', '0', 'required'], 1),
                                ('device-count-zero', selection('accelerator', 'settings', 'device_count'), 0),
                                ('reserved-negative', selection('context_policy', 'settings', 'reserved_output_tokens'), -1)]:
        add('invalid-' + label, [mutation(path, value)], disposition='invalid-contract', error='schemaViolation',
            reason='Reject the exact invalid field type, enum, identifier or bound without coercion.')
    assert len({case['name'] for case in cases}) == len(cases)
    assert {case['disposition'] for case in cases} == {'preserved', 'unresolved', 'unsupported-field', 'invalid-contract'}
    return cases


def encoded_vectors():
    return '[\n' + ',\n'.join(json.dumps(case, ensure_ascii=False, separators=(',', ':')) for case in vectors()) + '\n]\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='regenerate only the synthetic placement vector file')
    args = parser.parse_args()
    expected = encoded_vectors()
    if args.write:
        OUTPUT.write_text(expected)
    else:
        if OUTPUT.read_text() != expected:
            raise SystemExit('Placement vectors are stale; run placement_vectors.py --write')
    print(f'Placement vectors: {len(vectors())}; deterministic generation verified.')
