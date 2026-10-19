#!/usr/bin/env python3
"""Generate a separate CD1-0.2 reader corpus from the pinned Research 449 reader.

These are synthetic answer-reading cases, not a released CD-2 wire corpus or
capacity oracle. Normalized memory/workload expectations stay in their typed
policy tests. This tool never imports a mutable external checkout.
"""
from __future__ import annotations

import argparse
import base64
from contextlib import contextmanager
from copy import deepcopy
import hashlib
import importlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import types

ROOT = Path(__file__).resolve().parent
REFERENCE = ROOT / "capacity_reference"
RESOURCE_ROOT = ROOT.parent / "Sources/PlannerTransfer/Resources"
OUTPUT = ROOT.parent / "Tests/PlannerTransferTests/Fixtures/capacity-answer-conformance.json"
REVISION = "449a29be1752a3c545709da466c7d53fc18fef73"
TREE = "6a188a54d269028e5283288d9f6afa1f63ba2163"
PINNED_PATHS = {
    "LICENSE", "tests/t0_answer_attribution_prototype.py", "tests/t0_answer_state_prototype.py",
    "tests/t0_known_value_schema.py", "tests/selection_quantifier_prototype.py",
    "tests/fixtures/t0-answer-attribution.schema.json", "tests/fixtures/t0-answer-states.schema.json",
}
RESOURCE_PINS = {
    "catalog-snapshot.schema.json": {
        "source_path": "contracts/v1/schemas/catalog-snapshot.schema.json",
        "mode": "100644",
        "git_blob": "88af389f4f2b72e38f5c25e4cabd73df2d6c6225",
        "bytes": 760,
        "sha256": "a5af428386768b698d280a18bf99c0e52364ee397a2075685213b3d0762693a4",
    },
}


def encode(value):
    return json.dumps(value, ensure_ascii=True, separators=(",", ":"), allow_nan=False).encode()


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def read_regular_bytes(path):
    """Read the admitted regular descriptor; a FIFO must not wait for a writer."""
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise ValueError("capacity reference input must be a regular file")
        with os.fdopen(descriptor, "rb", closefd=False) as stream:
            raw = stream.read(1024 * 1024 + 1)
        if len(raw) > 1024 * 1024:
            raise ValueError("capacity reference input exceeds its tool bound")
        return raw
    finally:
        os.close(descriptor)


@contextmanager
def reference():
    source = REFERENCE.resolve(strict=True)
    manifest = json.loads(read_regular_bytes(source / "source-manifest.json"))
    if (manifest["revision"] != REVISION or manifest["tree"] != TREE
            or set(manifest["files"]) != PINNED_PATHS
            or manifest.get("consumer_resources") != RESOURCE_PINS):
        raise ValueError("unexpected capacity reference manifest")
    resource_root = RESOURCE_ROOT.resolve(strict=True)
    for name, pin in RESOURCE_PINS.items():
        path = resource_root / name
        if not path.resolve(strict=True).is_relative_to(resource_root):
            raise ValueError("capacity consumer resource leaves its pinned root")
        raw = read_regular_bytes(path)
        blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        if len(raw) != pin["bytes"] or digest(raw) != pin["sha256"] or blob != pin["git_blob"]:
            raise ValueError("capacity consumer resource identity mismatch")
    copies = {}
    for name, pin in manifest["files"].items():
        path = source / name
        if not path.resolve(strict=True).is_relative_to(source):
            raise ValueError("capacity reference leaves its pinned root")
        raw = read_regular_bytes(path)
        blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        if (pin["mode"] != "100644" or len(raw) != pin["bytes"]
                or digest(raw) != pin["sha256"] or blob != pin["git_blob"]):
            raise ValueError("capacity reference identity mismatch")
        copies[name] = raw
    previous = {name: module for name, module in sys.modules.items()
                if name == "tests" or name.startswith("tests.")}
    previous_bytecode = sys.dont_write_bytecode
    with tempfile.TemporaryDirectory(prefix="apple-capacity-reference-") as directory:
        target = Path(directory).resolve(strict=True)
        for name, raw in copies.items():
            path = target / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        # Verify every completed copy after the last write and before any import.
        for name, raw in copies.items():
            if read_regular_bytes(target / name) != raw:
                raise ValueError("copied capacity reference differs")
        try:
            for name in previous:
                del sys.modules[name]
            package = types.ModuleType("tests")
            package.__path__ = [str(target / "tests")]
            sys.modules["tests"] = package
            sys.dont_write_bytecode = True
            reader = importlib.import_module("tests.t0_answer_attribution_prototype")
            for name, module in tuple(sys.modules.items()):
                if (name.startswith("tests.")
                        and not Path(module.__file__).resolve().is_relative_to(target)):
                    raise ValueError("capacity oracle imported outside verified copy")
            yield reader, copies
        finally:
            for name in tuple(sys.modules):
                if name == "tests" or name.startswith("tests."):
                    del sys.modules[name]
            sys.modules.update(previous)
            sys.dont_write_bytecode = previous_bytecode


TEXT = {"type": "string", "minLength": 1}
NULLABLE_TEXT = {"type": ["string", "null"]}
RUNTIME = {
    "type": "object", "additionalProperties": False,
    "required": ["kind", "id", "build", "source_input", "instance",
                 "replica", "rank", "admission", "stage"],
    "properties": {
        "kind": {"enum": ["model_engine", "service_runtime"]},
        **{key: TEXT for key in ("id", "build", "source_input", "instance")},
        **{key: {"anyOf": [TEXT, {"type": "null"}]}
           for key in ("replica", "rank", "admission", "stage")},
    },
}
TRACE = {
    "type": "object", "additionalProperties": False,
    "required": ["source_quantity", "source_unit", "method", "rounding"],
    "properties": {
        **{key: TEXT for key in ("source_quantity", "source_unit", "method")},
        "rounding": {"enum": ["exact", "outward"]},
    },
}
SCHEMAS = {
    "boolean": {"type": "boolean"},
    "text": TEXT,
    "nullableText": NULLABLE_TEXT,
    "textSet": {"type": "array", "items": TEXT, "uniqueItems": True},
    "byteCount": {"type": "string", "pattern": "^(0|[1-9][0-9]*)$",
                  "not": {"pattern": "[^0-9]"}},
    "positiveInteger": {"type": "integer", "minimum": 1},
    "placement": {"enum": ["always", "on_demand"]},
    "residency": {"enum": ["resident", "excluded"]},
    "reserveBasis": {"enum": ["before_reserve", "after_reserve"]},
    "admissionUnit": {"enum": ["sequences", "requests", "step_batch"]},
    "runtimeBinding": RUNTIME,
    "runtimeOperator": {"enum": ["self", "provider"]},
    "capacityMode": {"enum": ["shared", "reserved_throughput", "dedicated_instances"]},
    "artifactKind": {"enum": ["adapter", "full"]},
    "role": {"enum": ["host", "device", "serving_engine", "base_artifact",
                      "speculative_draft", "other"]},
    "quantityTrace": TRACE,
}
RUNTIME_VALUE = {
    "kind": "model_engine", "id": "selection.engine", "build": "synthetic-v1",
    "source_input": "engine-builds", "instance": "runtime.one",
    "replica": None, "rank": "rank.0", "admission": None, "stage": "decode",
}
TRACE_VALUE = {"source_quantity": "18", "source_unit": "byte",
               "method": "exact.synthetic", "rounding": "exact"}
SAMPLES = {
    "boolean": True, "text": "literal unknown is free text", "nullableText": None,
    "textSet": ["device.a", "device.b"], "byteCount": "18", "positiveInteger": 4,
    "placement": "always", "residency": "resident", "reserveBasis": "before_reserve",
    "admissionUnit": "sequences", "runtimeBinding": RUNTIME_VALUE,
    "runtimeOperator": "self", "capacityMode": "shared", "artifactKind": "full",
    "role": "serving_engine", "quantityTrace": TRACE_VALUE,
}


def provided(value, *, assumption=True, source="preset:apple-capacity-fixture"):
    result = {"state": "provided", "value": value, "assumption": assumption}
    if source is not None:
        result["source"] = source
    return result


def document(records):
    return {"x_t0_answer_states": {"proposal_version": "cd1-0.2", "answers": records}}


def lossless(value):
    """Expected values do not round arbitrary Python integers through JSON numbers."""
    if value is None:
        return {"kind": "null"}
    if type(value) is bool:
        return {"kind": "boolean", "flag": value}
    if type(value) is int:
        return {"kind": "integer", "decimal": str(value)}
    if type(value) is float:
        return {"kind": "floating", "decimal": repr(value)}
    if type(value) is str:
        return {"kind": "string", "text": value}
    if type(value) is list:
        return {"kind": "array", "items": [lossless(item) for item in value]}
    if type(value) is dict:
        return {"kind": "object", "members": [
            {"key": key, "value": lossless(value[key])}
            for key in sorted(value, key=lambda key: key.encode("utf-8"))]}
    raise TypeError("unexpected oracle value")


def generate():
    cases = []
    with reference() as (reader, _):
        def case(name, *, field="text", path="/value", records=None, value=None, raw=None,
                 native_supported=True):
            if raw is None:
                raw = encode(value if value is not None else document(
                    records if records is not None else {"/value": provided("synthetic")}))
            row = {
                "name": name, "field": field, "path": path,
                "original_base64": base64.b64encode(raw).decode(),
                "original_sha256": digest(raw), "native_supported": native_supported,
            }
            try:
                index = reader.AttributedAnswerIndex(raw)
                answer = index.read(path, SCHEMAS[field])
                if index.original_bytes != raw:
                    raise AssertionError("oracle changed the original input")
                row["reader_valid"] = True
                # JSON Schema treats 1.0 as integer. The selected count consumer
                # separately requires an original integer token, as CD-2's typed
                # request/sequence count profile does. Preserve both observations.
                row["consumer_valid"] = not (answer.provided and field == "positiveInteger"
                    and (type(answer.value) is not int or answer.value <= 0))
                row["expected"] = {
                    "state": answer.state.value, "source": answer.source,
                    "source_path": answer.source_path, "assumption": answer.assumption,
                    "value": lossless(answer.value) if answer.provided else None,
                }
            except (ValueError, UnicodeError, TypeError, OverflowError, RecursionError):
                row.update(reader_valid=False, consumer_valid=False, expected=None)
            cases.append(row)

        assert set(SCHEMAS) == set(SAMPLES) and len(SAMPLES) == 16
        for field, sample in SAMPLES.items():
            for state in ("provided", "unknown", "missing", "withheld", "not_applicable"):
                record = provided(sample) if state == "provided" else {"state": state}
                case(f"{field}-{state}", field=field, records={"/value": record})
        case("empty-answer-map-is-missing", records={})
        case("empty-free-text-is-invalid", records={"/value": provided("")})
        case("literal-unknown-remains-free-text", records={"/value": provided("unknown")})
        case("nullable-empty-text-is-provided", field="nullableText", records={"/value": provided("")})
        case("empty-set-is-provided", field="textSet", records={"/value": provided([])})
        case("exact-unicode-set-members-remain-distinct", field="textSet",
             records={"/value": provided(["caf\u00e9", "cafe\u0301"])})
        case("duplicate-set-member-rejected", field="textSet",
             records={"/value": provided(["same", "same"])})
        for assumption in (True, False):
            for source in (None, "preset:A", "preset:" + "A" * 64):
                case(f"attribution-{assumption}-{source}",
                     records={"/value": provided("value", assumption=assumption, source=source)})
        for source in ("preset:", "synthetic:old", "preset:-bad", "preset:A\n",
                       "preset:" + "A" * 65, "preset:\u00e9", "", 1, None):
            item = provided("value")
            item["source"] = source
            case("invalid-source-" + repr(source), records={"/value": item})
        for assumption in (None, 0, 1, "true"):
            item = provided("value"); item["assumption"] = assumption
            case("invalid-assumption-" + repr(assumption), records={"/value": item})
        absent = provided("value"); del absent["assumption"]
        case("provided-requires-explicit-assumption", records={"/value": absent})
        for state in ("unknown", "missing", "withheld", "not_applicable"):
            for extra, value in (("value", "unused"), ("source", "preset:A"), ("assumption", False)):
                case(f"unresolved-{state}-forbids-{extra}",
                     records={"/value": {"state": state, extra: value}})

        parent = provided({"child": "retained", "array": ["zero", "one"],
                           "": {"leaf": "empty-key"}, "caf\u00e9": "nfc", "cafe\u0301": "nfd"},
                          assumption=False, source="preset:parent")
        for suffix in ("child", "array/0", "array/1", "array/2", "array/" + "9" * 200,
                       "missing", "/leaf", "caf\u00e9", "cafe\u0301"):
            case("ancestor-" + suffix, path="/parent/" + suffix, records={"/parent": parent})
        for suffix in ("array/01", "array/-", "array/-1", "array/+1", "child/after-scalar"):
            case("invalid-traversal-" + suffix, path="/parent/" + suffix, records={"/parent": parent})
        for state in ("unknown", "missing", "withheld", "not_applicable"):
            case("unresolved-parent-" + state, path="/parent/child",
                 records={"/parent": {"state": state}})
        case("withheld-descendant-uses-lexical-source-path", path="/parent",
             records={"/parent/z": {"state": "withheld"}, "/parent/a": {"state": "withheld"}})
        case("nonwithheld-descendant-does-not-provide-parent", path="/parent",
             records={"/parent/child": provided("retained")})
        case("empty-key-direct", path="/", records={"/": provided("empty")})
        case("empty-key-ancestor", path="//child", records={"/": provided({"child": "empty"})})
        case("escaped-slash-and-tilde", path="/parent/a~1b/~0", records={
            "/parent": provided({"a/b": {"~": "escaped"}})})
        case("exact-unicode-record-keys-nfc", path="/caf\u00e9", records={
            "/caf\u00e9": provided("nfc"), "/cafe\u0301": provided("nfd")})
        case("exact-unicode-record-keys-nfd", path="/cafe\u0301", records={
            "/caf\u00e9": provided("nfc"), "/cafe\u0301": provided("nfd")})
        for path in ("", "root", "/bad~", "/bad~2", "/bad~01~"):
            case("invalid-request-pointer-" + repr(path), path=path)
        for path in ("", "bad", "/bad~", "/bad~2"):
            case("invalid-unused-record-pointer-" + repr(path), records={
                "/value": provided("retained"), path: {"state": "missing"}})
        for first, second in (("/parent", "/parent/child"), ("/", "//child"),
                              ("/e", "/e/\u0301"), ("/a~1b", "/a~1b/child")):
            case("overlap-" + first, records={
                first: {"state": "missing"}, second: {"state": "withheld"}})
        case("duplicate-decoded-key", raw=b'{"x_t0_answer_states":{"proposal_version":"cd1-0.2","answers":{"/value":{"state":"missing"},"/\\u0076alue":{"state":"missing"}}}}')
        case("duplicate-unused-value-key", raw=b'{"x_t0_answer_states":{"proposal_version":"cd1-0.2","answers":{"/value":{"state":"provided","value":"ok","assumption":false},"/unused":{"state":"provided","assumption":true,"value":{"a":1,"\\u0061":2}}}}}')
        for version in ("cd1-0.1", "cd1-0.3", "CD1-0.2", "cd1-0.2\n"):
            changed = document({"/value": provided("kept")})
            changed["x_t0_answer_states"]["proposal_version"] = version
            case("unsupported-profile-" + repr(version), value=changed)
        for at in ("root", "envelope", "record"):
            changed = document({"/value": provided("kept")})
            target = changed if at == "root" else changed["x_t0_answer_states"]
            if at == "record":
                target = target["answers"]["/value"]
            target["unrecognized"] = True
            case("closed-" + at, value=changed)
        for name, value in (("root-array", []), ("root-null", None), ("root-empty", {}),
                            ("missing-answer-map", {"x_t0_answer_states": {"proposal_version": "cd1-0.2"}})):
            case(name, raw=encode(value))
        case("unused-malformed-provided-record", records={
            "/value": provided("kept"), "/unused": {"state": "provided", "value": True}})
        case("unused-malformed-state", records={
            "/value": provided("kept"), "/unused": {"state": "future"}})
        for raw in (b"\xff", b"{}", b'{"x_t0_answer_states":', b"\xef\xbb\xbf{}"):
            case("invalid-wire-" + raw.hex(), raw=raw)

        for token in ("0", "-0", "-1", "1", "2", str(2**80), str(2**128),
                      "1.0", "1e0", "1.5", "true", '"1"', "1e23"):
            base = encode(document({"/value": provided("__TOKEN__")}))
            case("positive-integer-token-" + token, field="positiveInteger",
                 raw=base.replace(b'"__TOKEN__"', token.encode()))
        for value in ("0", "1", "18", str(2**80), "00", "01", "-1", "+1", "1.0", "1e3",
                      " 1", "1 ", "1\n", "\u0661", "", 1, 1.0, True, None):
            case("byte-count-" + repr(value), field="byteCount", records={"/value": provided(value)})
        for token in ("0.1", "0.10000000000000001", "1e23", "9007199254740993.0",
                      "1e309", "1e-400", "NaN", "Infinity", "-Infinity"):
            raw = encode(document({"/value": provided("kept"), "/unused": provided("__TOKEN__")}))
            case("unused-original-number-" + token, raw=raw.replace(b'"__TOKEN__"', token.encode()))
        raw = encode(document({"/value": provided("kept"), "/unused": provided("__TOKEN__")}))
        case("native-exponent-bound", raw=raw.replace(b'"__TOKEN__"', b"0e10001"), native_supported=False)
        case("native-pointer-component-bound", path="/" + "/".join(["p"] * 129),
             records={}, native_supported=False)
        case("native-bytecount-digit-bound", field="byteCount",
             records={"/value": provided("1" + "0" * 4096)}, native_supported=False)
        case("lone-surrogate-is-not-attribution-utf8", records={"/value": provided("\ud800")})

        for member in RUNTIME_VALUE:
            changed = deepcopy(RUNTIME_VALUE); del changed[member]
            case("runtime-missing-" + member, field="runtimeBinding",
                 records={"/value": provided(changed)})
        for member in ("replica", "rank", "admission", "stage"):
            changed = deepcopy(RUNTIME_VALUE); changed[member] = ""
            case("runtime-empty-" + member, field="runtimeBinding",
                 records={"/value": provided(changed)})
        for member in ("unrecognized", "kind"):
            changed = deepcopy(RUNTIME_VALUE); changed[member] = "future"
            case("runtime-invalid-" + member, field="runtimeBinding",
                 records={"/value": provided(changed)})
        for member in TRACE_VALUE:
            changed = deepcopy(TRACE_VALUE); del changed[member]
            case("trace-missing-" + member, field="quantityTrace",
                 records={"/value": provided(changed)})
        changed = deepcopy(TRACE_VALUE); changed["rounding"] = "nearest"
        case("trace-forbids-unselected-rounding", field="quantityTrace",
             records={"/value": provided(changed)})
        for field in ("placement", "residency", "reserveBasis", "admissionUnit",
                      "runtimeOperator", "capacityMode", "artifactKind", "role"):
            case(field + "-literal-unknown-is-not-an-enum", field=field,
                 records={"/value": provided("unknown")})

    names = [row["name"] for row in cases]
    if len(names) != len(set(names)):
        raise AssertionError("duplicate capacity answer case identity")
    return {
        "profile": "apple-capacity-cd1-0.2-reader-preparation",
        "reference_revision": REVISION,
        "scope": "Pinned answer-reader observations plus explicit integer-token consumer restriction; not a CD-2 memory/workload oracle.",
        "fields": list(SCHEMAS),
        "cases": cases,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    value = generate()
    encoded = json.dumps(value, ensure_ascii=True, indent=2, allow_nan=False).encode() + b"\n"
    if args.write:
        OUTPUT.write_bytes(encoded)
    elif read_regular_bytes(OUTPUT) != encoded:
        raise ValueError("stale capacity answer vectors")
    cases = value["cases"]
    print(f"Verified 7 pinned CD1-0.2 reference files, 1 canonical consumer schema and {len(cases)} synthetic answer cases: "
          f"{sum(row['reader_valid'] for row in cases)} reader-valid, "
          f"{sum(row['consumer_valid'] and row['native_supported'] for row in cases)} native-profile-valid; "
          "no memory/workload policy or Swift execution inferred.")


if __name__ == "__main__":
    main()
