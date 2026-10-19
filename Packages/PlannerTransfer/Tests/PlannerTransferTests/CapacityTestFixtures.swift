import Foundation
import XCTest
@testable import PlannerTransfer

/// Synthetic originals and explicit caller assessments; none is a provider, hardware or source attestation.
final class CapacityTestDraft {
    var build: [String: Any]
    var catalog: [String: Any]
    private let exampleBuild: [String: Any]
    var entries: [String: [String: Any]] = [:]
    var meanings: [(id: String, role: CapacityRole)] = []
    var required: [(id: String, effective: String)] = []
    var rows: [String] = []
    var conditionKinds: [(selection: String, id: String, kind: CapacityConditionKind)] = []
    var artifactIDs: [String] = []
    var extraInputs: [CapacityInput] = []
    var selectedCatalog: String? = "catalog"
    var operation = "inference"

    init() throws {
        func example(_ name: String) throws -> [String: Any] {
            let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }
        exampleBuild = try example("build")
        build = exampleBuild; catalog = try example("catalog")
        build["name"] = "SYNTHETIC Apple capacity receiving regression"
        build["selections"] = [[String: Any]](); build["links"] = [[String: Any]]()
    }

    func put(_ path: String, _ value: Any, assumption: Bool = true, source: String? = "preset:apple-capacity-test") {
        var record: [String: Any] = ["state": "provided", "value": value, "assumption": assumption]
        if let source { record["source"] = source }
        entries[path] = record
    }
    func state(_ path: String, _ state: CapacityAnswerState) {
        precondition(state != .provided)
        entries[path] = ["state": state.rawValue]
    }
    func selection(_ id: String, kind: String, enabled: Bool = true, catalogKind: String? = nil) throws {
        var selections = try XCTUnwrap(build["selections"] as? [[String: Any]])
        if selections.contains(where: { ($0["id"] as? String) == id }) { return }
        let templates = try XCTUnwrap(exampleBuild["selections"] as? [[String: Any]])
        var selected = try XCTUnwrap(templates.first { ($0["kind"] as? String) == kind })
        let items = try XCTUnwrap(catalog["items"] as? [[String: Any]])
        let item = try XCTUnwrap(items.first { ($0["kind"] as? String) == (catalogKind ?? kind) })
        selected["id"] = id; selected["enabled"] = enabled
        selected["catalog_item_id"] = item["id"]; selected["catalog_item_version"] = item["version"]
        selections.append(selected); build["selections"] = selections
    }
    func editSelection(_ id: String, _ edit: (inout [String: Any]) -> Void) throws {
        var selections = try XCTUnwrap(build["selections"] as? [[String: Any]])
        let index = try XCTUnwrap(selections.firstIndex { ($0["id"] as? String) == id })
        edit(&selections[index]); build["selections"] = selections
    }
    func link(_ id: String, from: String, to: String, role: CapacityRole) throws {
        var links = try XCTUnwrap(build["links"] as? [[String: Any]])
        links.append(["id": id, "from_selection_id": from, "to_selection_id": to, "relation": role.relation])
        build["links"] = links; meanings.append((id, role))
        put("/links/" + id + "/role", role.rawValue); put("/links/" + id + "/operation", operation)
    }
    func serving(_ id: String = "sel_model", kind: String = "model", runtimeOperator: String = "self",
                 capacity: String = "dedicated_instances", exposed: Bool = true,
                 engine: String? = "sel_engine", host: String? = "sel_host", devices: [String] = ["sel_gpu"]) throws {
        try selection(id, kind: kind)
        if let engine {
            try selection(engine, kind: "inference_engine")
            try link("link." + id + ".engine", from: id, to: engine, role: .engine)
        }
        if let host {
            try selection(host, kind: "hosting_platform")
            try link("link." + id + ".host", from: id, to: host, role: .host)
        }
        for device in devices {
            try selection(device, kind: device.contains("cpu") ? "compute_profile" : "accelerator")
            try link("link." + id + "." + device, from: id, to: device, role: .device)
        }
        required.append((id, id)); rows.append(id)
        put("/requires/" + id + "/engine", engine != nil)
        put("/requires/" + id + "/host", host != nil)
        put("/requires/" + id + "/devices", !devices.isEmpty)
        put("/deployment/" + id + "/operator", runtimeOperator)
        put("/deployment/" + id + "/capacity", capacity)
        put("/deployment/" + id + "/exposed", exposed)
        put("/components/" + id + "/applies", runtimeOperator == "self" || exposed)
        put("/components/" + id + "/placement", "always")
    }
    func condition(_ selection: String, id: String, kind: CapacityConditionKind,
                   satisfied: Bool, applicable: Bool = true) {
        conditionKinds.append((selection, id, kind))
        put("/conditions/" + selection + "/" + id + "/applies", applicable)
        put("/conditions/" + selection + "/" + id + "/satisfied", satisfied)
    }
    func artifact(_ id: String, kind: String, baseVersion: String = "2026.10-demo") {
        artifactIDs.append(id)
        put("/artifacts/" + id + "/kind", kind); put("/artifacts/" + id + "/version", baseVersion)
        put("/artifacts/" + id + "/required", kind == "adapter")
    }
    func runtime(id: String = "sel_engine", kind: String = "model_engine", instance: String = "instance.1",
                 replica: String? = "replica.1", rank: String? = "rank.0", admission: String? = "admission.1",
                 stage: String? = "stage.1", build: String = "engine-build.1", source: String = "engines") -> [String: Any] {
        ["kind": kind, "id": id, "build": build, "source_input": source, "instance": instance,
         "replica": replica as Any? ?? NSNull(), "rank": rank as Any? ?? NSNull(),
         "admission": admission as Any? ?? NSNull(), "stage": stage as Any? ?? NSNull()]
    }
    func trace(_ path: String, quantity: String = "0", unit: String = "bytes", rounding: String = "exact") {
        put(path, ["source_quantity": quantity, "source_unit": unit,
                   "method": "synthetic-normalized-source", "rounding": rounding])
    }
    func range(_ path: String, lower: String? = nil, upper: String? = nil) {
        if let lower { put(path + "/lower", lower) }
        if let upper { put(path + "/upper", upper) }
        trace(path + "/trace", quantity: upper ?? lower ?? "unresolved")
    }
    func budget(_ path: String, capacity: String, reserve: String = "0") {
        range(path + "/capacity", lower: capacity); range(path + "/reserve", upper: reserve)
        put(path + "/reservation", "synthetic-explicit-reserve"); put(path + "/basis", "before_reserve")
    }
    func inventory(_ path: String, ids: [String], complete: Bool = true) {
        put(path + "/ids", ids); put(path + "/complete", complete)
    }

    func freeze() throws -> CapacityTestContext {
        for selection in try XCTUnwrap(build["selections"] as? [[String: Any]]) {
            let id = try XCTUnwrap(selection["id"] as? String), path = "/conditions/" + id
            if entries[path + "/ids"] == nil {
                put(path + "/ids", conditionKinds.filter { $0.selection == id }.map { $0.id })
            }
            if entries[path + "/complete"] == nil { put(path + "/complete", true) }
        }
        if entries["/graph/complete"] == nil { put("/graph/complete", true) }
        if entries["/serving/complete"] == nil { put("/serving/complete", true) }
        let originalAnswers: [String: Any] = [
            "x_t0_answer_states": ["proposal_version": "cd1-0.2", "answers": entries]
        ]
        func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
        var inputs = [
            try CapacityInput(name: "answers", kind: .answers, originalBytes: json(originalAnswers)),
            try CapacityInput(name: "catalog", kind: .catalog, originalBytes: json(catalog))
        ]
        for (name, kind, value) in [
            ("normalization", CapacityInputKind.normalization, #"{"synthetic_policy":"normalization-v1"}"#),
            ("source-policy", .sourcePolicy, #"{"synthetic_policy":"explicit-test-assessments"}"#),
            ("qualification", .qualification, #"{"synthetic_evidence":"no-device-or-provider-run"}"#),
            ("engines", .engineBuilds, #"{"synthetic_build":"engine-build.1"}"#),
            ("hardware", .hardware, #"{"synthetic_hardware":"test-only"}"#),
            ("deployment", .deployment, #"{"synthetic_deployment":"test-only"}"#),
            ("workload", .workloadStages, #"{"synthetic_stages":"test-only"}"#)
        ] {
            inputs.append(try CapacityInput(name: name, kind: kind, originalBytes: Data(value.utf8)))
        }
        inputs += extraInputs
        let basis = try CapacityBasis(originalBuildBytes: json(build), operation: operation,
            normalizationPolicy: "normalization", sourcePolicy: "source-policy",
            inputs: inputs, catalogInputName: selectedCatalog)
        return try CapacityTestContext(draft: self, basis: basis, inputs: inputs)
    }
}

final class CapacityTestContext {
    let draft: CapacityTestDraft
    let basis: CapacityBasis
    let inputs: [CapacityInput]
    let answers: CapacityAnswers
    var claims: [String: CapacityQualification] = [:]

    init(draft: CapacityTestDraft, basis: CapacityBasis, inputs: [CapacityInput]) throws {
        self.draft = draft; self.basis = basis; self.inputs = inputs
        answers = try CapacityAnswers(basis: basis, inputName: "answers")
    }
    func answer(_ path: String, _ field: CapacityAnswerField) throws -> CapacityBoundAnswer {
        try answers.read(path: path, as: field)
    }
    func qualify(_ answer: CapacityBoundAnswer, _ fact: CapacityFact, _ domain: CapacityDomain,
                 eligibility: CapacityEligibility = .qualified, resolved: Bool? = true, checked: Bool = false) throws {
        let key = try answer.qualificationKey(fact: fact, domain: domain)
        let input = try XCTUnwrap(basis.input(named: "qualification"))
        claims[key.sha256] = try CapacityQualification(key: key, eligibility: eligibility, evidenceInputName: input.name,
            evidenceSHA256: input.sha256, conflictRankResolved: resolved, checkedOnly: checked)
    }
    func qualifications(omitting omit: (CapacityQualification) -> Bool = { _ in false }) throws -> CapacityQualifications {
        try CapacityQualifications(claims.keys.sorted().compactMap { claims[$0] }.filter { !omit($0) })
    }
    func coverage(_ path: String, _ kind: CapacityCoverageKind, owner: String? = nil,
                  scenario: String? = nil) throws -> CapacityCoverage {
        let value = try CapacityCoverage(kind: kind, owner: owner ?? basis.buildID,
                                        scenario: scenario, claim: answer(path, .boolean))
        try qualify(value.claim, .coverage, value.domain)
        return value
    }
    func graph() throws -> CapacityGraph {
        let meanings = try draft.meanings.map { item in
            let role = try answer("/links/" + item.id + "/role", .role)
            let operation = try answer("/links/" + item.id + "/operation", .text)
            let domain = try CapacityDomain.link(item.id)
            try qualify(role, .role, domain); try qualify(operation, .operation, domain)
            return try CapacityLinkMeaning(linkID: item.id, role: role, operation: operation)
        }
        return try CapacityGraph(basis: basis, meanings: meanings,
            coverage: coverage("/graph/complete", .roleBindings, scenario: basis.operation))
    }
    func requirements() throws -> [CapacityServingRequirements] {
        try draft.required.map { item in
            let engine = try answer("/requires/" + item.id + "/engine", .boolean)
            let host = try answer("/requires/" + item.id + "/host", .boolean)
            let devices = try answer("/requires/" + item.id + "/devices", .boolean)
            try qualify(engine, .applicability, .role(selection: item.effective, role: CapacityRole.engine.rawValue))
            try qualify(host, .applicability, .role(selection: item.effective, role: CapacityRole.host.rawValue))
            try qualify(devices, .applicability, .role(selection: item.effective, role: CapacityRole.device.rawValue))
            return try CapacityServingRequirements(selectionID: item.id, engine: engine, host: host, devices: devices)
        }
    }
    func artifacts() throws -> [CapacityArtifactFacts] {
        try draft.artifactIDs.map { id in
            let kind = try answer("/artifacts/" + id + "/kind", .artifactKind)
            let version = try answer("/artifacts/" + id + "/version", .text)
            let required = try answer("/artifacts/" + id + "/required", .boolean)
            let domain = try CapacityDomain.component(id)
            try qualify(kind, .compatibility, domain); try qualify(version, .compatibility, domain)
            try qualify(required, .applicability, .role(selection: id, role: CapacityRole.base.rawValue))
            return try CapacityArtifactFacts(selectionID: id, artifactKind: kind, baseVersion: version, baseRequired: required)
        }
    }
    func conditions() throws -> [CapacitySupportCondition] {
        try draft.conditionKinds.map { item in
            let prefix = "/conditions/" + item.selection + "/" + item.id
            let applies = try answer(prefix + "/applies", .boolean), satisfied = try answer(prefix + "/satisfied", .boolean)
            let condition = try CapacitySupportCondition(selectionID: item.selection, conditionID: item.id,
                                                          kind: item.kind, applicable: applies, satisfied: satisfied)
            try qualify(applies, .applicability, condition.domain); try qualify(satisfied, .compatibility, condition.domain)
            return condition
        }
    }
    func conditionInventories() throws -> [CapacityConditionInventory] {
        try basis.selections.map { selected in
            let prefix = "/conditions/" + selected.id
            let complete = try coverage(prefix + "/complete", .supportConditions, owner: selected.id, scenario: basis.operation)
            let ids = try answer(prefix + "/ids", .textSet)
            try qualify(ids, .inventory, complete.domain)
            return try CapacityConditionInventory(ids: ids, coverage: complete)
        }
    }
    func deployment() throws -> CapacityDeployment {
        let rows = try draft.rows.map { id in
            let prefix = "/deployment/" + id, domain = try CapacityDomain.component(id)
            let runtimeOperator = try answer(prefix + "/operator", .runtimeOperator)
            let capacity = try answer(prefix + "/capacity", .capacityMode), exposed = try answer(prefix + "/exposed", .boolean)
            try qualify(runtimeOperator, .runtimeOperator, domain); try qualify(capacity, .capacityMode, domain)
            try qualify(exposed, .localVisibility, domain)
            return try CapacityDeploymentRow(selectionID: id, runtimeOperator: runtimeOperator,
                                              capacityMode: capacity, exposedHardware: exposed)
        }
        return try CapacityDeployment(basis: basis, graph: graph(), rows: rows,
            artifactFacts: artifacts(), conditions: conditions(), conditionCoverage: conditionInventories(),
            servingCoverage: coverage("/serving/complete", .servingComponents, scenario: basis.operation),
            requirements: requirements())
    }
    func range(_ path: String, domain: CapacityDomain) throws -> CapacityByteRange {
        let lower = try draft.entries[path + "/lower"] == nil ? nil : answer(path + "/lower", .byteCount)
        let upper = try draft.entries[path + "/upper"] == nil ? nil : answer(path + "/upper", .byteCount)
        let trace = try answer(path + "/trace", .quantityTrace)
        for bound in [lower, upper].compactMap({ $0 }) { try qualify(bound, .byteBound, domain) }
        try qualify(trace, .normalization, domain)
        return try CapacityByteRange(lower: lower, upper: upper, trace: trace)
    }
    func budget(_ path: String, domain: CapacityDomain) throws -> CapacityBudget {
        let reservation = try answer(path + "/reservation", .text), interpretation = try answer(path + "/basis", .reserveBasis)
        try qualify(reservation, .normalization, domain); try qualify(interpretation, .normalization, domain)
        return try CapacityBudget(capacity: range(path + "/capacity", domain: domain),
            reserve: range(path + "/reserve", domain: domain), interpretation: interpretation, reservationTrace: reservation)
    }
    func inventory<Record: CapacityIdentifiedRecord>(_ path: String, records: [Record],
        kind: CapacityCoverageKind, scenario: String? = nil) throws -> CapacityRecords<Record> {
        let complete = try coverage(path + "/complete", kind, scenario: scenario)
        let ids = try answer(path + "/ids", .textSet); try qualify(ids, .inventory, complete.domain)
        return try CapacityRecords(ids: ids, records: records, coverage: complete)
    }
}
