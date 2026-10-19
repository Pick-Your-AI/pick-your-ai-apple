#!/usr/bin/env python3
"""Generate opt-in Apple context cases with the byte-pinned Research 449 oracle.

The vendored input is copied from verified bytes before import. This tool does not
change frozen-v1 inputs, fetch a producer, certify evidence, or execute Swift.
"""
from __future__ import annotations

import argparse
import base64
from contextlib import contextmanager
from copy import deepcopy
import hashlib
import importlib
import json
from pathlib import Path
import sys
import tempfile
import types

ROOT = Path(__file__).resolve().parent
REFERENCE = ROOT / "context_reference"
OUTPUT = ROOT.parent / "Tests/PlannerTransferTests/Fixtures/context-budget-conformance.json"
REVISION = "449a29be1752a3c545709da466c7d53fc18fef73"
PINNED_PATHS = {
    "LICENSE", "tests/context_budget_binding_prototype.py", "tests/context_budget_prototype.py",
    "tests/t0_answer_state_prototype.py", "tests/t0_known_value_schema.py",
    "tests/selection_quantifier_prototype.py", "tests/fixtures/context-budget-binding.json",
    "tests/fixtures/context-budget-answers.json", "tests/fixtures/context-budget-binding.schema.json",
    "tests/fixtures/t0-answer-states.schema.json",
}


def encode(value):
    return json.dumps(value, ensure_ascii=True, separators=(",", ":"), allow_nan=False).encode()


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


@contextmanager
def reference():
    manifest = json.loads((REFERENCE / "source-manifest.json").read_bytes())
    if manifest["revision"] != REVISION or set(manifest["files"]) != PINNED_PATHS:
        raise ValueError("unexpected context reference manifest")
    copies = {}
    for name, pin in manifest["files"].items():
        path = REFERENCE / name
        if not path.resolve().is_relative_to(REFERENCE.resolve()):
            raise ValueError("context reference leaves its pinned root")
        raw = path.read_bytes()
        blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        if len(raw) != pin["bytes"] or digest(raw) != pin["sha256"] or blob != pin["git_blob"]:
            raise ValueError("context reference identity mismatch")
        copies[name] = raw
    old_modules = {name: value for name, value in sys.modules.items()
                   if name == "tests" or name.startswith("tests.")}
    old_bytecode = sys.dont_write_bytecode
    with tempfile.TemporaryDirectory(prefix="apple-context-reference-") as directory:
        # macOS temporary roots may be reached through a filesystem alias.
        # Compare resolved module paths with the same existing physical root.
        target = Path(directory).resolve(strict=True)
        for name, raw in copies.items():
            path = target / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        # A later copy operation must not invalidate an earlier verification.
        # Admit the entire completed copy set before the first module import.
        for name, raw in copies.items():
            if (target / name).read_bytes() != raw:
                raise ValueError("copied context reference differs")
        for name in old_modules:
            del sys.modules[name]
        package = types.ModuleType("tests")
        package.__path__ = [str(target / "tests")]
        sys.modules["tests"] = package
        sys.dont_write_bytecode = True
        try:
            binding = importlib.import_module("tests.context_budget_binding_prototype")
            reader = importlib.import_module("tests.t0_answer_state_prototype")
            budget = importlib.import_module("tests.context_budget_prototype")
            for name, module in tuple(sys.modules.items()):
                if name.startswith("tests.") and not Path(module.__file__).resolve().is_relative_to(target):
                    raise ValueError("context oracle imported outside verified copy")
            yield binding, reader, budget, copies
        finally:
            for name in tuple(sys.modules):
                if name == "tests" or name.startswith("tests."):
                    del sys.modules[name]
            sys.modules.update(old_modules)
            sys.dont_write_bytecode = old_bytecode


def normalized_answer(name, answer):
    value = None
    if answer.provided:
        if name == "semantics":
            value = {"semantics": answer.value}
        elif name == "input_tokens":
            value = {"lower": str(answer.value["lower"]), "upper": str(answer.value["upper"])}
        else:
            value = {"count": str(answer.value)}
    return {"field": name, "state": answer.state.value, "value": value,
            "source": answer.source, "source_path": answer.source_path}


def generate():
    with reference() as (binding, reader, budget, copies):
        original_proposal = copies["tests/fixtures/context-budget-binding.json"]
        original_answers = copies["tests/fixtures/context-budget-answers.json"]
        proposal = json.loads(original_proposal)
        answers = json.loads(original_answers)
        scope = deepcopy(proposal["x_t0_context_budget"]["scope"])
        cases = []

        def case(name, *, answer=None, answer_raw=None, proposal_value=None, proposal_raw=None,
                 selected="bound", enabled=True, eligible=True, native_supported=True, rebind=True):
            raw = answer_raw if answer_raw is not None else encode(answers if answer is None else answer)
            record = deepcopy(proposal if proposal_value is None else proposal_value)
            if rebind:
                record["x_t0_context_budget"]["answer_states_sha256"] = digest(raw)
            wire = proposal_raw if proposal_raw is not None else encode(record)
            active = deepcopy(record["x_t0_context_budget"]["scope"] if selected == "bound" else selected)
            row = {"name": name, "binding_base64": base64.b64encode(wire).decode(),
                   "answers_base64": base64.b64encode(raw).decode(),
                   "active_scope_json": encode(active).decode() if active is not None else None,
                   "enabled": enabled, "evidence_eligible": eligible,
                   "native_supported": native_supported}
            try:
                value = binding.ContextRecord(wire, raw)
                result = value.evaluate(active, enabled=enabled, evidence_eligible=eligible)
                row["canonical_valid"] = True
                row["expected"] = {"outcome": result.outcome.value, "may_not_fit": result.may_not_fit,
                                   "reason": result.reason,
                                   "checks": [{"name": check.name, "lower": check.lower.value,
                                               "upper": check.upper.value} for check in result.checks],
                                   "answers": [normalized_answer(name, answer) for name, answer in result.answers]}
            except (ValueError, UnicodeError, TypeError, OverflowError, RecursionError):
                row["canonical_valid"] = False
                row["expected"] = None
            cases.append(row)

        def changed(field, value=None, state="provided"):
            result = deepcopy(answers)
            record = {"state": state}
            if state == "provided":
                record["value"] = value
            result["x_t0_answer_states"]["answers"]["/context/" + field] = record
            return result

        case("original-pinned-bytes", answer_raw=original_answers, proposal_raw=original_proposal, rebind=False)
        future = deepcopy(proposal)
        future["x_t0_context_budget"]["proposal_version"] = "cd11-0.2"
        case("future-cd11-version-rejected-before-disabled-skip", proposal_value=future, enabled=False)
        future = deepcopy(answers)
        future["x_t0_answer_states"]["proposal_version"] = "cd1-0.2"
        case("future-cd1-version-is-not-implicitly-migrated", answer=future)
        for outer in (True, False):
            extra = deepcopy(proposal)
            (extra if outer else extra["x_t0_context_budget"])["unrecognized"] = True
            case("closed-binding-" + ("root" if outer else "envelope"), proposal_value=extra)
            extra = deepcopy(answers)
            (extra if outer else extra["x_t0_answer_states"])["unrecognized"] = True
            case("closed-answers-" + ("root" if outer else "envelope"), answer=extra)
        absent = deepcopy(proposal)
        del absent["x_t0_context_budget"]["answer_states_sha256"]
        case("missing-required-answer-byte-binding", proposal_value=absent, rebind=False)
        absent = deepcopy(answers)
        del absent["x_t0_answer_states"]["answers"]
        case("missing-required-answer-map", answer=absent)
        case("shared-7000-plus-2000-fails-8000")
        separate = changed("semantics", "separate")
        fields = separate["x_t0_answer_states"]["answers"]
        fields["/context/shared_cap_tokens"] = {"state": "not_applicable"}
        fields["/context/input_cap_tokens"] = {"state": "provided", "value": 8000}
        case("separate-7000-input-2000-output-passes", answer=separate)
        case("disabled-selection", enabled=False)
        case("unknown-activation", enabled=None)
        case("missing-active-scope", selected=None)
        case("unresolved-eligibility", eligible=None)
        case("ineligible-evidence", eligible=False)
        for field in binding.FIELDS:
            for state in ("missing", "unknown", "withheld", "not_applicable"):
                case(f"{field}-{state}", answer=changed(field, state=state))
        for cap in (8999, 9000, 9001):
            case(f"shared-boundary-{cap}", answer=changed("shared_cap_tokens", cap))
        case("straddling-shared-bound", answer=changed("input_tokens", {"lower": 5999, "upper": 6001}))
        case("missing-input-retains-independent-output-check", answer=changed("input_tokens", state="missing"))
        lower_output_cap = changed("output_cap_tokens", 1999)
        lower_output_cap["x_t0_answer_states"]["answers"]["/context/input_tokens"] = {"state": "missing"}
        case("independent-output-failure-dominates-unknown", answer=lower_output_cap)
        case("zero-output-allowed", answer=changed("reserved_output_tokens", 0))
        case("zero-policy-total-is-real-cap", answer=changed("policy_total_cap_tokens", 0))
        case("separate-with-provided-shared-cap-rejected", answer=changed("semantics", "separate"))
        huge = 2**80
        big = changed("input_tokens", {"lower": huge, "upper": huge})
        big["x_t0_answer_states"]["answers"]["/context/shared_cap_tokens"] = {"state": "provided", "value": huge + 2000}
        case("exact-2-to-80-counts-pass", answer=big)
        big["x_t0_answer_states"]["answers"]["/context/shared_cap_tokens"]["value"] -= 1
        case("exact-2-to-80-one-token-over-fails", answer=big)

        for identity in ("selection_id", "operation", "settings_sha256"):
            mismatch = deepcopy(scope)
            mismatch[identity] = "0" * 64 if identity == "settings_sha256" else "different.synthetic"
            case("mismatch-" + identity, selected=mismatch)
        for identity in ("model", "route", "tokenizer"):
            for part in ("id", "version"):
                mismatch = deepcopy(scope); mismatch[identity][part] = "different.synthetic"
                case(f"mismatch-{identity}-{part}", selected=mismatch)
        unicode_scope = deepcopy(proposal)
        unicode_scope["x_t0_context_budget"]["scope"]["route"]["version"] = "caf\u00e9"
        unequal = deepcopy(unicode_scope["x_t0_context_budget"]["scope"])
        unequal["route"]["version"] = "cafe\u0301"
        case("unicode-canonical-equivalence-is-not-route-identity", proposal_value=unicode_scope, selected=unequal)
        case("unicode-exact-route-version", proposal_value=unicode_scope)
        for invalid in ("", "a", "Abc", "abc\n", "_abc", "abc/def"):
            bad = deepcopy(scope); bad["selection_id"] = invalid
            case("invalid-active-id-" + repr(invalid), selected=bad, enabled=False)
        for invalid in ("", "\u00a0", "\u001c", "v1\n", "v\u007f1", "x" * 201):
            bad = deepcopy(proposal); bad["x_t0_context_budget"]["scope"]["route"]["version"] = invalid
            case("invalid-version-" + repr(invalid), proposal_value=bad)

        parent = {"x_t0_answer_states": {"proposal_version": "cd1-0.1", "answers": {
            "/context": {"state": "provided", "source": "synthetic:parent",
                         "value": {name.removeprefix("/context/"): answer["value"]
                                   for name, answer in answers["x_t0_answer_states"]["answers"].items()
                                   if answer["state"] == "provided"}}}}}
        case("provided-parent-retains-source-and-missing-optional", answer=parent)
        for state in ("missing", "unknown", "withheld", "not_applicable"):
            unresolved = {"x_t0_answer_states": {"proposal_version": "cd1-0.1", "answers": {"/context": {"state": state}}}}
            case("unresolved-parent-" + state, answer=unresolved)
        withheld = {"x_t0_answer_states": {"proposal_version": "cd1-0.1", "answers": {
            "/context/input_tokens/z": {"state": "withheld"}, "/context/input_tokens/a": {"state": "withheld"}}}}
        case("withheld-descendant-uses-first-original-path", answer=withheld)
        for value in (None, False, 3, "scalar", []):
            malformed = deepcopy(parent); malformed["x_t0_answer_states"]["answers"]["/context"]["value"] = value
            case("parent-traversal-" + repr(value), answer=malformed)
        empty_parent = deepcopy(parent)
        empty_parent["x_t0_answer_states"]["answers"]["/context"]["value"] = {}
        case("empty-parent-means-missing", answer=empty_parent)
        overlap = deepcopy(parent)
        overlap["x_t0_answer_states"]["answers"]["/context/input_tokens"] = {"state": "missing"}
        case("parent-child-overlap-even-unused", answer=overlap)
        overlap = deepcopy(answers)
        overlap["x_t0_answer_states"]["answers"]["/unused"] = {"state": "provided", "value": {}}
        overlap["x_t0_answer_states"]["answers"]["/unused/\u0301"] = {"state": "withheld"}
        case("unicode-mark-after-separator-retains-parent-child-overlap", answer=overlap)
        escaped = deepcopy(answers)
        escaped["x_t0_answer_states"]["answers"]["/unused~1slash/~0tilde"] = {"state": "unknown"}
        case("escaped-unused-pointer-tokens", answer=escaped)
        for path in ("", "context", "/broken~", "/broken~2"):
            invalid = deepcopy(answers); invalid["x_t0_answer_states"]["answers"][path] = {"state": "missing"}
            case("invalid-unused-pointer-" + path, answer=invalid)
        unused = deepcopy(answers)
        unused["x_t0_answer_states"]["answers"]["/caf\u00e9"] = {"state": "provided", "value": 1}
        unused["x_t0_answer_states"]["answers"]["/cafe\u0301"] = {"state": "provided", "value": 2}
        case("distinct-unicode-unused-keys-survive", answer=unused)
        for invalid in ({"state": "unknown", "value": 1}, {"state": "missing", "source": "synthetic"},
                        {"state": "provided"}, {"state": "provided", "value": 1, "source": "\u00a0"},
                        {"state": "future"}):
            bad = deepcopy(answers); bad["x_t0_answer_states"]["answers"]["/unused"] = invalid
            case("invalid-unused-record-" + encode(invalid).decode(), answer=bad)
        for value in (True, 1.0, "2000", -1, None):
            case("count-kind-" + repr(value), answer=changed("reserved_output_tokens", value))
        for value in ({"lower": 0, "upper": 2}, {"lower": 2, "upper": 1}, {"lower": 1, "upper": 2, "extra": 0}):
            case("invalid-range-" + encode(value).decode(), answer=changed("input_tokens", value))
        case("provided-literal-unknown-semantics", answer=changed("semantics", "unknown"))
        case("zero-shared-cap-rejected", answer=changed("shared_cap_tokens", 0))
        raw = encode(answers)
        case("answer-whitespace-rebound", answer_raw=raw + b" \n")
        case("answer-whitespace-unbound-rejected", answer_raw=original_answers + b" ", rebind=False)
        case("answer-key-order-unbound-rejected", answer_raw=raw, rebind=False)
        case("duplicate-root-key", answer_raw=raw.replace(b'{"x_t0_answer_states":', b'{"x_t0_answer_states":0,"x_t0_answer_states":', 1))
        case("escaped-duplicate-key", answer_raw=raw.replace(b'"proposal_version":', b'"proposal_version":"cd1-0.1","proposal_\\u0076ersion":', 1))
        case("invalid-utf8", answer_raw=b"\xff")
        case("trailing-json", answer_raw=raw + b"null")
        case("disabled-still-validates-record", answer_raw=b"{", enabled=False)
        for token in ("1e0", "1.0", "-0", "9007199254740993", "1e23", "1e400", "0.100000000000000001"):
            token_answer = encode(changed("reserved_output_tokens", 314159))
            case("raw-count-" + token, answer_raw=token_answer.replace(b"314159", token.encode()))
        for token in ("0.1", "1e23", "1e400", "5e-324", "NaN", "Infinity", "9007199254740993.0"):
            unused = deepcopy(answers); unused["x_t0_answer_states"]["answers"]["/unused"] = {"state": "provided", "value": 314159}
            case("unused-numeric-" + token, answer_raw=encode(unused).replace(b"314159", token.encode()))
        surrogate = deepcopy(answers); surrogate["x_t0_answer_states"]["answers"]["/unused"] = {"state": "provided", "value": "\ud800"}
        case("native-unsupported-lone-surrogate", answer=surrogate, native_supported=False)
        deep_path = "/" + "/".join(["a"] * 129)
        deep = deepcopy(answers); deep["x_t0_answer_states"]["answers"][deep_path] = {"state": "missing"}
        case("native-unsupported-pointer-depth", answer=deep, native_supported=False)

        tokens = {"0", "-0", "1", "-1", "1.0", "1e0", "0.1", "-0.1", "0.100000000000000001", "1e23",
                  "1e309", "1e-400", "5e-324", "4e-324", "2.2250738585072014e-308",
                  "1.7976931348623157e308", "1.7976931348623159e308", "9007199254740993",
                  "9007199254740993.0", str(2**80), "NaN", "Infinity", "-Infinity", "01", "+1", "1.", ".1"}
        for exponent in (-324, -308, -100, -22, -1, 0, 1, 15, 16, 22, 23, 100, 308):
            for coefficient in ("1", "2", "5", "9", "10", "11", "15", "99", "100", "1234567890123456", "12345678901234567"):
                for sign in ("", "-"):
                    tokens.add(sign + coefficient + "e" + str(exponent))
        for integer in (2**53 - 1, 2**53, 2**53 + 1, 2**63 - 1, 2**63, 2**80, 10**23, 10**23 - 1):
            for suffix in ("", ".0", "e0"):
                tokens.add(str(integer) + suffix)
        numeric = []
        for token in sorted(tokens):
            raw = b'{"x_t0_answer_states":{"proposal_version":"cd1-0.1","answers":{"/unused":{"state":"provided","value":' + token.encode() + b"}}}}"
            try:
                reader.AnswerIndex(raw)
                valid = True
            except (ValueError, TypeError, OverflowError):
                valid = False
            numeric.append({"token": token, "canonical_valid": valid})
        limits = []
        for native, extension, evidenced, ceiling in (
            (None, 32000, True, 8000), (8000, 32000, False, None), (8000, 32000, True, None),
            (8000, 32000, True, 16000), (8000, None, True, 4000), (huge, huge + 1, True, huge),
        ):
            result = budget.effective_limit(native, extension=extension, extension_evidenced=evidenced, runtime_ceiling=ceiling)
            limits.append({"native": None if native is None else str(native),
                           "extension": None if extension is None else str(extension), "evidenced": evidenced,
                           "ceiling": None if ceiling is None else str(ceiling),
                           "expected": None if result is None else str(result)})
        if len({row["name"] for row in cases}) != len(cases):
            raise ValueError("duplicate context case identity")
        return {"profile": "apple-context-cd11-0.1-preparation", "reference_revision": REVISION,
                "cases": cases, "numeric": numeric, "limits": limits}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    result = generate()
    raw = encode(result) + b"\n"
    if args.write:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_bytes(raw)
    elif OUTPUT.read_bytes() != raw:
        raise SystemExit("context corpus differs from the pinned reference regeneration")
    print(f"Context reference {REVISION}: {len(result['cases'])} records, "
          f"{len(result['numeric'])} numeric tokens, {len(result['limits'])} limit cases; "
          f"{len(raw)} bytes, SHA-256 {digest(raw)}")


if __name__ == "__main__":
    main()
