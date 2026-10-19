"""Deterministic frozen-ruleset syntax vectors, never evaluated policy decisions.

Each case contains the exact JSON text consumed by both reference and Swift
decoders. Most mutations use one unchanged canonical rule to keep aggregate work
bounded; separate cases retain all 45 source rules and deliberate repeated IDs.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests/PlannerTransferTests/Fixtures"
OUTPUT = FIXTURES / "ruleset-conformance.json"


def vectors():
    source = json.loads((FIXTURES / "ruleset.json").read_text())
    schema = json.loads((ROOT / "Sources/PlannerTransfer/Resources/ruleset.schema.json").read_text())
    base = deepcopy(source)
    base["rules"] = base["rules"][:1]
    cases = []

    def add(name, path=(), value=None, *, operation="set", valid=False, canonical=None):
        from catalog_vectors import apply_vector
        mutation = {"operation": operation, "path": list(path)}
        if operation == "set":
            mutation["json"] = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        payload = apply_vector(base, mutation)
        cases.append(dict(name=name, canonicalValid=valid if canonical is None else canonical,
                          clientValid=valid,
                          json=json.dumps(payload, ensure_ascii=False, separators=(",", ":"))))

    add("complete-canonical-ruleset", value=source, valid=True)
    add("single-canonical-rule", operation="none", valid=True)
    for key in schema["required"]:
        add("missing-" + key, [key], operation="remove")
        add("null-" + key, [key])
    for i, root in enumerate((None, True, 1, "rules", [])):
        add("wrong-root-" + str(i), value=root)
    add("unknown-envelope-field", ["future_field"], True)
    add("unsupported-schema-version", ["schema_version"], "2.0.0")
    for name, value in (("short", "ab"), ("uppercase", "Rules.valid"), ("spaces", "rules invalid")):
        add("invalid-id-" + name, ["id"], value)
    add("maximum-id", ["id"], "r" * 120, valid=True)
    add("oversized-id", ["id"], "r" * 121)
    for name, value in (("empty", ""), ("partial", "1.0"), ("prefix", "v1.0.0"), ("number", 1)):
        add("invalid-version-" + name, ["version"], value)
    add("supported-semver-prerelease", ["version"], "1.0.0-test.1", valid=True)
    add("unsupported-semver-build-metadata", ["version"], "1.0.0+fixture")
    for name, value in (("date", "2026-10-18"), ("impossible", "2026-02-30T00:00:00Z"),
                        ("no-zone", "2026-10-18T00:00:00"), ("type", True)):
        add("invalid-published-at-" + name, ["published_at"], value)
    add("timestamp-offset", ["published_at"], "2024-02-29T12:34:56.123+05:30", valid=True)
    add("timestamp-lowercase", ["published_at"], "2026-10-18t12:34:56z", valid=True)
    for name, value in (("empty", []), ("object", {}), ("null-rule", [None]), ("boolean-rule", [True])):
        add("invalid-rules-" + name, ["rules"], value)
    rule = schema["properties"]["rules"]["items"]
    prefix = ["rules", "0"]
    for key in rule["required"]:
        add("rule-missing-" + key, prefix + [key], operation="remove")
        add("rule-null-" + key, prefix + [key])
    add("rule-unknown-field", prefix + ["future_field"], True)
    for field in ("id", "message", "remediation", "owner"):
        add("rule-empty-" + field, prefix + [field], "")
        add("rule-wrong-type-" + field, prefix + [field], True)
    add("optional-owner-absent", prefix + ["owner"], operation="remove", valid=True)
    for field in ("severity", "on_unknown"):
        for value in rule["properties"][field]["enum"]:
            add(field + "-" + value, prefix + [field], value, valid=True)
        add(field + "-unknown", prefix + [field], "approved")
    kinds = rule["properties"]["affected_kinds"]["items"]["enum"]
    for kind in kinds:
        add("affected-kind-" + kind, prefix + ["affected_kinds"], [kind], valid=True)
    for name, value in (("empty", []), ("duplicate", [kinds[0], kinds[0]]),
                        ("unknown", ["future_kind"]), ("type", [True])):
        add("affected-kinds-" + name, prefix + ["affected_kinds"], value)

    literal = {"literal": None}
    exists = {"op": "exists", "value": literal}
    binary_ops = schema["$defs"]["expression"]["oneOf"][0]["properties"]["op"]["enum"]
    expressions = [{"op": op, "left": literal, "right": {"literal": False}} for op in binary_ops]
    expressions += [exists, {"op": "all", "args": [exists]}, {"op": "any", "args": [exists]},
                    {"op": "not", "arg": exists}, {"op": "implies", "if": exists, "then": exists}]
    for field in ("applies_when", "assert"):
        for expression in expressions:
            location = prefix + [field]
            name = field + "-" + expression["op"]
            add(name, location, expression, valid=True)
            for key in expression:
                missing = deepcopy(expression); del missing[key]
                add(name + "-missing-" + key, location, missing)
            extra = deepcopy(expression); extra["future_field"] = True
            add(name + "-unknown-field", location, extra)
        for name, value in (("empty-all", {"op": "all", "args": []}),
                            ("empty-any", {"op": "any", "args": []}),
                            ("invalid-nested", {"op": "not", "arg": {"op": "execute"}}),
                            ("mixed-forms", {"op": "exists", "value": literal, "arg": exists}),
                            ("wrong-root", True)):
            add(field + "-" + name, prefix + [field], value)

    operand_forms = schema["$defs"]["operand"]["oneOf"]
    operands = [(name, {"literal": value}) for name, value in
                (("null", None), ("false", False), ("number", 1.25), ("decimal-string", "1.000000000001"),
                 ("empty-array", []), ("array", [None, False, "unknown"]), ("object", {"unknown": None}))]
    operands += [("metric-" + value, {"metric": value})
                 for value in operand_forms[1]["properties"]["metric"]["enum"]]
    reference = operand_forms[2]["properties"]["ref"]["properties"]
    operands += [("scope-" + scope, {"ref": {"scope": scope, "pointer": "/"}})
                 for scope in reference["scope"]["enum"]]
    operands += [("ref-kind-" + kind, {"ref": {"scope": "catalog", "pointer": "/spec", "kind": kind}})
                 for kind in kinds]
    operands += [("ref-selection", {"ref": {"scope": "selection", "pointer": "/id",
                                          "role": "primary", "selection_id": "selection_fixture"}})]
    for name, operand in operands:
        add("operand-" + name, prefix + ["assert"], {"op": "exists", "value": operand}, valid=True)
    invalid_operands = [None, True, {}, {"literal": 1, "metric": "tools.mutating_count"},
                        {"metric": "invented"}, {"ref": {}},
                        {"ref": {"scope": "unknown", "pointer": "/"}},
                        {"ref": {"scope": "build", "pointer": "relative"}},
                        {"ref": {"scope": "selection", "pointer": "/", "role": "Primary"}},
                        {"ref": {"scope": "selection", "pointer": "/", "selection_id": ""}},
                        {"ref": {"scope": "catalog", "pointer": "/", "future_field": True}}]
    for index, operand in enumerate(invalid_operands):
        add("invalid-operand-" + str(index), prefix + ["assert"], {"op": "exists", "value": operand})
    one = deepcopy(base["rules"][0]); two = deepcopy(one); two["message"] = "Different synthetic statement."
    add("ordered-duplicate-identities", ["rules"], [one, two, one], valid=True)
    # Canonical syntax validity is separate from the existing client's numeric
    # and strict terminal-newline representation limits.
    for name, value in (("large", 9007199254740993), ("small", 1e-13)):
        add("unsupported-literal-" + name, prefix + ["assert"],
            {"op": "exists", "value": {"literal": value}}, canonical=True)
    add("unsupported-terminal-newline-id", ["id"], "rules.valid\n", canonical=True)
    assert len({case["name"] for case in cases}) == len(cases)
    return cases


def encoded_vectors():
    return "[\n" + ",\n".join(json.dumps(case, ensure_ascii=False, separators=(",", ":"))
                            for case in vectors()) + "\n]\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="regenerate only synthetic ruleset vectors")
    args = parser.parse_args()
    expected = encoded_vectors()
    if args.write:
        OUTPUT.write_text(expected)
    else:
        assert OUTPUT.read_text() == expected, "Ruleset vectors are stale; run ruleset_vectors.py --write"
    print(f"Ruleset vectors: {len(vectors())}; deterministic generation verified.")
