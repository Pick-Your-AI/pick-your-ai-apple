#!/usr/bin/env python3
"""Export synthetic report/evidence inputs for Swift decoding and real UI rendering.

Schema acceptance is checked by the unchanged, manifest-pinned reference validator.
Display expectations describe only reported fields and evidence presence. They are
not compatibility, conflict resolution or independently verified source claims.
"""
import argparse
import copy
import json
from pathlib import Path
import shutil
import tempfile

import run as reference


HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parent.parent
OUTPUTS = (
    REPOSITORY / "Packages/PlannerCore/Tests/PlannerCoreTests/Fixtures/evidence-vectors.json",
    REPOSITORY / "Packages/PlannerUI/Tests/PlannerUITests/Fixtures/evidence-vectors.json",
)


def bundle(root):
    manifest = reference.verify_source(root)
    dependencies = reference.versions()
    # Validate the bytes actually consumed, including a source change between
    # the initial verification and copy. The disposable copy contains only the
    # manifest and its covered files, never unrelated source scripts.
    with tempfile.TemporaryDirectory() as directory:
        snapshot = Path(directory)
        (snapshot / "IMPORT_MANIFEST.json").write_bytes(
            reference.read_regular_bytes(root / "IMPORT_MANIFEST.json"))
        reference.copy_verified_source(root, snapshot, manifest)
        reference.verify_source(snapshot)
        return verified_bundle(snapshot, dependencies)


def verified_bundle(root, dependencies):
    original = reference.read(root / "examples/evaluation-report.json")
    base = copy.deepcopy(original)
    base["findings"] = [copy.deepcopy(original["findings"][0])]
    # Preserve the supplied summary. Frozen v1 does not require its counts to be
    # recomputed from this partial synthetic finding list by the client decoder.
    cases = []

    def add(label, payload, valid, collection=None, observed=(), expected=(), text=()):
        finding = (payload.get("findings") or [{}])[0]
        cases.append({
            "id": "evidence/" + label,
            "schema": "evaluation-report.schema.json",
            "payload": payload,
            "valid": valid,
            "collection": collection,
            "observed": list(observed),
            "expected": list(expected),
            "outcome": finding.get("outcome") if valid else None,
            "severity": finding.get("severity") if valid else None,
            "visibleText": list(text),
        })

    for outcome in ("pass", "fail", "unknown", "skipped"):
        for severity in ("error", "warning", "info"):
            changed = copy.deepcopy(base)
            finding = changed["findings"][0]
            finding["outcome"] = outcome
            finding["severity"] = severity
            finding["evidence"] = [
                {"path": "absent"},
                {"path": "null", "observed": None, "expected": None},
                {"path": "literal", "observed": "unknown", "expected": "unknown"},
            ]
            add("outcome/" + outcome + "/" + severity, changed, True, "supplied",
                ("absent", "explicitNull", "literalUnknown"),
                ("absent", "explicitNull", "literalUnknown"),
                ("Observed: not provided (unanswered)", "Observed: explicit null",
                 'Observed: literal string "unknown"'))

    changed = copy.deepcopy(base)
    changed["findings"][0].pop("evidence", None)
    add("absent-collection", changed, True, "absent",
        text=("Evidence was not provided. Support is unknown.",))
    changed = copy.deepcopy(base)
    changed["findings"][0]["evidence"] = []
    add("empty-collection", changed, True, "empty",
        text=("The evidence list is empty. Support is unknown.",))

    changed = copy.deepcopy(base)
    changed["result"] = "valid"
    changed["deployment_readiness"] = "ready"
    changed["findings"][0]["outcome"] = "pass"
    changed["findings"][0].pop("evidence", None)
    add("reported-pass-without-support", changed, True, "absent",
        text=("Reported rule outcome: pass", "Evidence was not provided. Support is unknown."))

    changed = copy.deepcopy(base)
    changed.update(result="valid", deployment_readiness="ready", findings=[])
    add("no-findings", changed, True,
        text=("No findings were supplied. This does not establish a pass.",))

    changed = copy.deepcopy(base)
    finding = changed["findings"][0]
    finding.update(outcome="fail", severity="warning", code="CONTRADICTORY_EVIDENCE",
                   message="The synthetic producer resolved eligible numeric disagreement conservatively; the reported rule failed.")
    finding["evidence"] = [
        {"path": "model.memory", "observed": 24, "expected": 48, "source_version": "source-a/1"},
        {"path": "model.memory", "observed": 48, "expected": 24, "source_version": "source-b/2"},
    ]
    add("contradictory-evidence", changed, True, "supplied", ("supplied", "supplied"),
        ("supplied", "supplied"), (finding["message"], "Observed: 24", "Observed: 48",
                                    'Source version: "source-a/1"', 'Source version: "source-b/2"'))

    changed = copy.deepcopy(base)
    finding = changed["findings"][0]
    finding.update(outcome="unknown", severity="warning", code="OPPOSITE_CLAIMS",
                   message="The synthetic producer reports equally ranked opposite yes/no claims; a reproducible test is required.")
    finding["evidence"] = [
        {"path": "engine.support", "observed": True, "expected": True, "source_version": "source-a/1"},
        {"path": "engine.support", "observed": False, "expected": True, "source_version": "source-b/2"},
    ]
    add("unresolved-opposite-claims", changed, True, "supplied", ("supplied", "supplied"),
        ("supplied", "supplied"), (finding["message"], "Observed: true", "Observed: false"))

    for label, code, message in (
        ("not-applicable-reason", "NOT_APPLICABLE", "The synthetic component is not applicable to this rule."),
        ("skipped-without-applicability", "SKIPPED_INPUT", "Evaluation was skipped; applicability is not established."),
    ):
        changed = copy.deepcopy(base)
        finding = changed["findings"][0]
        finding.update(outcome="skipped", severity="info", code=code, message=message, evidence=[])
        add(label, changed, True, "empty", text=("Reported rule outcome: skipped", message))

    for label, value, display in (
        ("false-is-data", False, "false"),
        ("zero-is-data", 0, "0"),
        ("empty-string", "", '""'),
        ("literal-not-applicable", "not_applicable", '"not_applicable"'),
        ("literal-pass", "pass", '"pass"'),
        ("literal-null-string", "null", '"null"'),
        ("nested-unknown", {"detail": "unknown"}, '{"detail":"unknown"}'),
        ("escaped-controls", "line\n\u0000next", '"line\\n\\u0000next"'),
    ):
        changed = copy.deepcopy(base)
        finding = changed["findings"][0]
        finding["outcome"] = "unknown"
        finding["evidence"] = [{"path": "synthetic", "observed": value}]
        add(label, changed, True, "supplied", ("supplied",), ("absent",),
            ("Observed: " + display, "Reported rule outcome: unknown"))

    for version in ("0.9.0", "1.0.1", "2.0.0"):
        changed = copy.deepcopy(base)
        changed["schema_version"] = version
        add("unsupported-version/" + version, changed, False)
    for field in ("outcome", "severity", "message"):
        changed = copy.deepcopy(base)
        del changed["findings"][0][field]
        add("missing-finding/" + field, changed, False)
    changed = copy.deepcopy(base)
    changed["findings"][0]["is_verified"] = True
    add("unsupported-verification-field", changed, False)
    changed = copy.deepcopy(base)
    changed["findings"][0]["evidence"] = [{"path": "synthetic", "verified": True}]
    add("unsupported-evidence-field", changed, False)
    changed = copy.deepcopy(base)
    changed["findings"][0]["evidence"] = None
    add("null-collection", changed, False)

    # Append consumer explanation cases without changing the original 37
    # presence/conflict inputs. These are synthetic producer statements, not
    # an approved rule, navigation target or client-generated corrective action.
    for index, (label, outcome, action, selections) in enumerate((
        ("reported-action", "fail",
         "Compare **reported** limits for [sel_z_limit](fixture:only); keep the selection until review is complete.",
         ["sel_z_limit", "sel_a_model"]),
        ("absent-action", "unknown", None, ["sel_unresolved"]),
        ("empty-action", "fail", "", []),
        ("whitespace-action", "unknown", "\t \n\r\u00a0", ["sel_model", "sel_engine"]),
    ), start=1):
        changed = copy.deepcopy(base)
        changed.update(id="evaluation.explanation." + label,
                       build_id="build.explanation.fixture", build_revision=7,
                       catalog_snapshot_id="catalog.explanation.fixture",
                       ruleset_id="rules.explanation." + label,
                       ruleset_version=f"2.3.4-draft.{index}",
                       result="invalid" if outcome == "fail" else "indeterminate",
                       deployment_readiness="needs_review",
                       summary={"passed": 0, "failed": int(outcome == "fail"),
                                "unknown": int(outcome == "unknown"), "skipped": 0})
        finding = changed["findings"][0]
        finding.update(rule_id="rule.explanation." + label,
                       outcome=outcome, severity="warning", code="SYNTHETIC_EXPLANATION",
                       message="Synthetic finding: inspect the recorded inputs for " + label + ".",
                       selection_ids=selections, evidence=[])
        if action is None:
            finding.pop("remediation", None)
        else:
            finding["remediation"] = action
        visible = [
            "Reported ruleset: " + changed["ruleset_id"],
            "Reported ruleset version: " + changed["ruleset_version"],
            finding["rule_id"], finding["message"],
        ]
        if selections:
            visible += [f"Reported participant selection {position}: {selection}"
                        for position, selection in enumerate(selections, start=1)]
        else:
            visible.append("Reported participant selections: none supplied.")
        if label == "reported-action":
            visible.append("Reported remediation: " + action)
        else:
            visible.append("No corrective action is described in this finding. Review its evidence before changing a setting.")
        add("explanation/" + label, changed, True, "empty", text=visible)

    results = reference.schema_results(root, cases)
    failures = [result["id"] for result in results if not result["passed"]]
    if failures:
        raise ValueError("Evidence expectation differs from the frozen schema: " + ", ".join(failures))
    ids = [case["id"] for case in cases]
    if len(ids) != len(set(ids)):
        raise ValueError("Repeated evidence vector ID")
    for case in cases:
        case["payloadJSON"] = json.dumps(case.pop("payload"), sort_keys=True, separators=(",", ":"))
        del case["schema"]
    return {"lock": reference.LOCK, "schema": "evaluation-report.schema.json",
            "fixture_sha256": reference.digest(root / "examples/evaluation-report.json"),
            "dependencies": dependencies, "cases": cases}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract-root", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = bundle(args.contract_root.resolve())
    content = (json.dumps(result, indent=2, sort_keys=True) + "\n").encode()
    for path in OUTPUTS:
        if args.check:
            if path.read_bytes() != content:
                parser.exit(1, "Evidence vector bytes differ: " + str(path) + "\n")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    accepted = sum(case["valid"] for case in result["cases"])
    print(f"PASS {len(result['cases'])} shared evidence vectors: {accepted} accepted, "
          f"{len(result['cases']) - accepted} rejected; exact Core/UI bytes agree")


if __name__ == "__main__":
    main()
