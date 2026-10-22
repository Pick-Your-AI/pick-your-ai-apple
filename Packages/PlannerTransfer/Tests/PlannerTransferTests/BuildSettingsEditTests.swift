import Foundation
import XCTest
import PlannerCore
import PlannerData
@testable import PlannerTransfer

/// Synthetic frozen-v1 inputs. These are proposal/consumer-boundary tests, not
/// an editor journey, live compatibility result, or real credential exercise.
final class BuildSettingsEditTests: XCTestCase, @unchecked Sendable {
    private let later = "2026-10-20T05:55:00Z"
    private let unknown = BuildEditEnvironment(mode: nil, production: nil)

    private func encoded(_ value: JSONValue) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private func fixture(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        var parser = try JSONParser(Data(contentsOf: url))
        return try parser.parse()
    }
    private func build(_ changes: [String: JSONValue] = [:]) throws -> BuildSnapshot {
        var object = try fixture("build").object!
        for (key, value) in changes { object[key] = value }
        return try BuildTransfer.snapshot(fromDraftJSON: encoded(.object(object)))
    }
    private func graph() throws -> DependencyGraph { try DependencyGraph.decode(encoded(fixture("dependency-graph"))) }
    private func field(_ name: String, _ kind: CatalogKind? = .model) throws -> BuildEditableField {
        let fields = try kind.map(BuildEditableField.settings(for:)) ?? BuildEditableField.objectives()
        return try XCTUnwrap(fields.first { $0.name == name })
    }
    private func set(_ name: String, _ json: String, _ kind: CatalogKind? = .model) throws -> BuildFieldChange {
        .set(try field(name, kind), try BuildEditValue(json: Data(json.utf8)))
    }
    private func edit(_ changes: [BuildFieldChange], kind: CatalogKind? = .model,
                      original: BuildSnapshot? = nil, before: BuildEditEnvironment? = nil,
                      after: BuildEditEnvironment? = nil) throws -> BuildSettingsEdit {
        try .prepare(build: original ?? build(), graph: graph(),
            target: kind.map { .selectionSettings(selectionID: "sel_" + $0.rawValue) } ?? .objectives,
            changes: changes, before: before ?? unknown, after: after ?? unknown, updatedAt: later)
    }
    private func settings(_ snapshot: BuildSnapshot, _ kind: CatalogKind = .model) throws -> [String: JSONValue] {
        let row = try XCTUnwrap(snapshot.value.object!["selections"]!.array!.first { $0.object!["kind"] == .string(kind.rawValue) })
        return row.object!["settings"]!.object!
    }
    private func analysisIdentity(_ build: BuildSnapshot) -> AnalysisIdentity {
        let locks = build.locks.object!
        return AnalysisIdentity(buildID: build.id,
            revision: NSDecimalNumber(decimal: build.value.object!["revision"]!.number!).stringValue,
            versionLocks: locks.mapValues { value in
                if let text = value.string { return text }
                return NSDecimalNumber(decimal: value.number!).stringValue
            })
    }

    func testDescriptorsCoverEveryFrozenKindWithoutInventingFieldsOrUnits() throws {
        let validator = try FrozenValidator()
        let definitions = validator.schemas["selection.schema.json"]!.object!["$defs"]!.object!
        XCTAssertEqual(CatalogKind.allCases.count, 29)
        for kind in CatalogKind.allCases {
            let fields = try BuildEditableField.settings(for: kind)
            let source = definitions["settings_" + kind.rawValue]!.object!
            XCTAssertEqual(Set(fields.map(\.name)), Set(source["properties"]!.object!.keys), kind.rawValue)
            XCTAssertEqual(fields.map(\.name), fields.map(\.name).sorted(), kind.rawValue)
            for field in fields {
                XCTAssertEqual(field.scope, .selection(kind))
                XCTAssertEqual(field.definition, source["properties"]!.object![field.name])
                XCTAssertEqual(field.required, source["required"]!.array!.contains(.string(field.name)))
            }
        }
        XCTAssertTrue(try BuildEditableField.settings(for: .deploymentMode).isEmpty)
        XCTAssertEqual(try field("temperature").valueType, .number)
        XCTAssertEqual(try field("temperature").definition.object?["maximum"], .number(2))
        XCTAssertEqual(try field("requested_context_tokens", .contextPolicy).valueType, .integer)
        XCTAssertTrue(try field("requested_context_tokens", .contextPolicy).required)
        XCTAssertEqual(try field("allowed_scopes", .tool).valueType, .array)
    }

    func testObjectivesResolveExactCommonDefinitionsAndRequiredFields() throws {
        let fields = try BuildEditableField.objectives()
        XCTAssertEqual(fields.count, 9)
        XCTAssertEqual(Set(fields.filter(\.required).map(\.name)), ["region", "currency", "data_classification"])
        let common = try FrozenValidator().schemas["common.schema.json"]!.object!["$defs"]!.object!
        XCTAssertEqual(try field("currency", nil).definition, common["currency"])
        XCTAssertEqual(try field("monthly_budget_amount", nil).definition, common["decimal"])
        XCTAssertEqual(try field("monthly_budget_amount", nil).valueType, .string)
        XCTAssertFalse(fields.contains { ["owner_ref", "locks", "revision", "policy"].contains($0.name) })
    }

    func testSelectionEditPreservesEveryUnrelatedValueAndSerializesExactly() throws {
        let original = try build(["lifecycle": .string("ready"), "name": .string("Private e\u{301}"),
            "extensions": .object(["x_private": .object(["notes": .string("Keep local only")])])])
        let e = try edit([set("temperature", "0.75"), set("max_output_tokens", "1024")], original: original)
        var restored = e.proposed.value.object!
        var rows = restored["selections"]!.array!
        let index = try XCTUnwrap(rows.firstIndex { $0.object!["id"] == .string("sel_model") })
        var row = rows[index].object!
        var values = row["settings"]!.object!
        XCTAssertEqual(values["temperature"], .number(Decimal(string: "0.75")!))
        XCTAssertEqual(values["max_output_tokens"], .number(1024))
        for key in e.changedFieldNames where key != "lifecycle" { values[key] = try settings(original)[key] }
        row["settings"] = .object(values); rows[index] = .object(row); restored["selections"] = .array(rows)
        XCTAssertEqual(restored["revision"], .number(2)); XCTAssertEqual(restored["lifecycle"], .string("draft"))
        XCTAssertEqual(restored["updated_at"], .string(later))
        for key in ["revision", "updated_at", "lifecycle"] { restored[key] = original.value.object![key] }
        XCTAssertEqual(.object(restored), original.value)
        XCTAssertEqual(e.original, original); XCTAssertEqual(e.proposed.locks, original.locks)
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: e.proposed.encoded()), e.proposed)
        XCTAssertEqual(e.changedFieldNames, ["temperature", "max_output_tokens", "lifecycle"])
        XCTAssertEqual(e.lifecycleBefore, "ready"); XCTAssertEqual(e.lifecycleAfter, "draft")
        XCTAssertTrue(e.lifecycleChanges)
    }

    func testDeployedAndArchivedBuildsAreRefusedAndEditableLifecyclesAreDemotedVisibly() throws {
        let schemaValues = try FrozenValidator().schemas["build.schema.json"]!.object!["properties"]!.object!["lifecycle"]!
            .object!["enum"]!.array!.map { $0.string! }
        XCTAssertEqual(schemaValues, ["draft", "validated", "ready", "deployed", "archived"])
        for lifecycle in ["deployed", "archived"] {
            let original = try build(["lifecycle": .string(lifecycle)])
            XCTAssertThrowsError(try edit([set("temperature", "0.75")], original: original)) {
                XCTAssertEqual($0 as? BuildSettingsEditError, .lifecycleNotEditable)
            }
            XCTAssertEqual(original.value.object!["lifecycle"], .string(lifecycle))
            XCTAssertEqual(original.value.object!["revision"], .number(1))
        }
        for (lifecycle, demoted) in [("draft", false), ("validated", true), ("ready", true)] {
            let original = try build(["lifecycle": .string(lifecycle)])
            let e = try edit([set("temperature", "0.75")], original: original)
            XCTAssertEqual(e.lifecycleBefore, lifecycle)
            XCTAssertEqual(e.lifecycleAfter, "draft")
            XCTAssertEqual(e.lifecycleChanges, demoted)
            XCTAssertEqual(e.proposed.value.object!["lifecycle"], .string("draft"))
            XCTAssertEqual(e.changedFieldNames, demoted ? ["temperature", "lifecycle"] : ["temperature"])
        }
    }

    func testObjectiveMoneyPreservesDecimalSpellingAndRequiresFullRecheck() throws {
        let e = try edit([set("monthly_budget_amount", "\"1000.000000000001\"", nil),
                          set("currency", "\"EUR\"", nil)], kind: nil)
        XCTAssertEqual(e.proposed.value.object?["objectives"]?.object?["monthly_budget_amount"], .string("1000.000000000001"))
        XCTAssertEqual(e.proposed.value.object?["objectives"]?.object?["currency"], .string("EUR"))
        XCTAssertEqual(e.proposed.value.object?["selections"], e.original.value.object?["selections"])
        guard case .objectivesRequireFullRecheck = e.impact else { return XCTFail("Objective edit needs full recheck") }
        for bad in ["1000", "\"1e3\"", "\"-1\"", "\"01.00\"", "\"0.0000000000001\""] {
            XCTAssertThrowsError(try edit([set("monthly_budget_amount", bad, nil)], kind: nil))
        }
        for bad in ["\"usd\"", "\"US\"", "\"USD\\n\""] {
            XCTAssertThrowsError(try edit([set("currency", bad, nil)], kind: nil))
        }
    }

    func testInclusiveExclusiveAndIntegerBoundsRejectInsteadOfClamping() throws {
        for good in ["0", "2"] { XCTAssertNoThrow(try edit([set("temperature", good)])) }
        for bad in ["-0.0001", "2.0001", "true", "\"1\""] { XCTAssertThrowsError(try edit([set("temperature", bad)])) }
        XCTAssertNoThrow(try edit([set("top_p", "1")]))
        for bad in ["0", "1.0001", "false"] { XCTAssertThrowsError(try edit([set("top_p", bad)])) }
        for bad in ["0", "1.5", "true"] { XCTAssertThrowsError(try edit([set("max_output_tokens", bad)])) }
        XCTAssertNoThrow(try edit([set("requests_per_day", "0", nil)], kind: nil))
        XCTAssertThrowsError(try edit([set("max_latency_ms", "0", nil)], kind: nil))
        XCTAssertThrowsError(try edit([set("max_concurrency", "1.25", nil)], kind: nil))
    }

    func testEnumsBooleansAndArrayUniquenessKeepTheirOriginalTypes() throws {
        for bad in ["\"FP16\"", "\"auto\"", "null"] { XCTAssertThrowsError(try edit([set("precision", bad)])) }
        XCTAssertNoThrow(try edit([set("precision", "\"int4\"")]))
        XCTAssertNoThrow(try edit([set("enabled", "false", .tool)], kind: .tool))
        for bad in ["0", "\"false\"", "null"] { XCTAssertThrowsError(try edit([set("enabled", bad, .tool)], kind: .tool)) }
        XCTAssertNoThrow(try edit([set("allowed_scopes", "[]", .tool)], kind: .tool))
        for bad in ["[\"a\",\"a\"]", "[1]", "\"a\"", "null"] {
            XCTAssertThrowsError(try edit([set("allowed_scopes", bad, .tool)], kind: .tool))
        }
    }

    func testAllCredentialReferenceFieldsRejectRawValuesWithoutEchoingThem() throws {
        var count = 0
        for kind in CatalogKind.allCases {
            for field in try BuildEditableField.settings(for: kind) where field.definition.object?["pattern"] == .string("^secret://[A-Za-z0-9/_:.-]+$") {
                count += 1
                let good = BuildFieldChange.set(field, try BuildEditValue(json: Data("\"secret://fixture/account:read.v1\"".utf8)))
                let e = try edit([good], kind: kind)
                XCTAssertEqual(try settings(e.proposed, kind)[field.name], .string("secret://fixture/account:read.v1"))
                for raw in ["RAW_FIXTURE_PASSWORD", "secret://", "secret://fixture\\n", "secret://user@host"] {
                    do {
                        _ = try edit([.set(field, BuildEditValue(json: Data(("\"" + raw + "\"").utf8)))], kind: kind)
                        XCTFail("Credential reference accepted invalid shape")
                    } catch {
                        XCTAssertEqual(error as? TransferError, .schemaViolation)
                        XCTAssertFalse(String(describing: error).contains("RAW_FIXTURE_PASSWORD"))
                    }
                }
            }
        }
        XCTAssertEqual(count, 12)
    }

    func testURIsAndLiteralFreeTextHaveDifferentFrozenAdmission() throws {
        XCTAssertNoThrow(try edit([set("api_base_url", "\"https://example.invalid/v1\"", .modelProvider)], kind: .modelProvider))
        for bad in ["\"missing-scheme\"", "\"https://example.invalid/a b\"", "\"https://example.invalid/%xx\""] {
            XCTAssertThrowsError(try edit([set("api_base_url", bad, .modelProvider)], kind: .modelProvider))
        }
        // A free-text region has no general secret detector. This is deliberately
        // distinct from the contract's named credential-reference fields.
        let e = try edit([set("region", "\"unclassified literal fixture\"", .modelProvider)], kind: .modelProvider)
        XCTAssertEqual(try settings(e.proposed, .modelProvider)["region"], .string("unclassified literal fixture"))
    }

    func testRemovalPreservesAbsentVersusNullAndZeroWithoutDefaults() throws {
        let removed = try edit([.remove(field("temperature"))])
        XCTAssertNil(try settings(removed.proposed)["temperature"])
        XCTAssertThrowsError(try edit([set("temperature", "null")]))
        let zero = try edit([set("temperature", "0")])
        XCTAssertEqual(try settings(zero.proposed)["temperature"], .number(0))
        let absent = try edit([.remove(field("monthly_budget_amount", nil))], kind: nil)
        XCTAssertNil(absent.proposed.value.object?["objectives"]?.object?["monthly_budget_amount"])
        XCTAssertThrowsError(try edit([.remove(field("credential_ref"))])) { XCTAssertEqual($0 as? BuildSettingsEditError, .unchangedValues) }
    }

    func testRequiredSelectionAndObjectiveFieldsCannotBeRemoved() throws {
        for (kind, name) in [(CatalogKind.contextPolicy, "requested_context_tokens"), (.contextPolicy, "reserved_output_tokens"),
                             (.accelerator, "device_count"), (.computeProfile, "instances"),
                             (.vectorDatabase, "index_dimension"), (.vectorDatabase, "similarity_metric")] {
            XCTAssertThrowsError(try edit([.remove(field(name, kind))], kind: kind)) { XCTAssertEqual($0 as? BuildSettingsEditError, .requiredField) }
        }
        for name in ["region", "currency", "data_classification"] {
            XCTAssertThrowsError(try edit([.remove(field(name, nil))], kind: nil)) { XCTAssertEqual($0 as? BuildSettingsEditError, .requiredField) }
        }
    }

    func testScopeDuplicateAndEmptyChangesRejectAtomically() throws {
        XCTAssertThrowsError(try edit([])) { XCTAssertEqual($0 as? BuildSettingsEditError, .emptyChanges) }
        XCTAssertThrowsError(try edit([set("currency", "\"EUR\"", nil)])) { XCTAssertEqual($0 as? BuildSettingsEditError, .fieldScopeMismatch) }
        XCTAssertThrowsError(try edit([set("precision", "\"int4\"", .inferenceEngine)])) { XCTAssertEqual($0 as? BuildSettingsEditError, .fieldScopeMismatch) }
        XCTAssertThrowsError(try edit([set("temperature", "1"), .remove(field("temperature"))])) { XCTAssertEqual($0 as? BuildSettingsEditError, .duplicateField) }
        let original = try build()
        XCTAssertThrowsError(try edit([set("temperature", "1"), set("max_output_tokens", "0")], original: original))
        XCTAssertEqual(original, try build())
    }

    func testSemanticNoOpCreatesNoNewRevisionButChangedLexicalTextIsPreserved() throws {
        XCTAssertThrowsError(try edit([set("temperature", "0.40")])) { XCTAssertEqual($0 as? BuildSettingsEditError, .unchangedValues) }
        let unchanged = try edit([set("temperature", "0.40"), set("precision", "\"int8\"")])
        XCTAssertEqual(unchanged.changedFieldNames, ["precision"])
        let lexical = try edit([set("monthly_budget_amount", "\"1000.000\"", nil)], kind: nil)
        XCTAssertEqual(lexical.proposed.value.object?["objectives"]?.object?["monthly_budget_amount"], .string("1000.000"))
    }

    func testDisabledSelectionRetainsItsIdentityRoleLinksAndDisabledState() throws {
        let original = try build(); var rows = original.value.object!["selections"]!.array!
        let index = try XCTUnwrap(rows.firstIndex { $0.object!["id"] == .string("sel_model") })
        var row = rows[index].object!; row["enabled"] = .bool(false); row["role"] = .string("secondary"); rows[index] = .object(row)
        let disabled = try build(["selections": .array(rows)])
        let e = try edit([set("temperature", "0.8")], original: disabled)
        var after = e.proposed.value.object!["selections"]!.array![index].object!
        after["settings"] = row["settings"]
        XCTAssertEqual(after, row)
        XCTAssertEqual(e.proposed.value.object?["links"], disabled.value.object?["links"])
    }

    func testMissingAndAmbiguousSelectionIdentitiesCannotChooseAnArbitraryRecord() throws {
        let original = try build(), g = try graph(), change = try set("temperature", "1")
        for id in ["sel_model ", "sel_MODEL", "missing"] {
            XCTAssertThrowsError(try BuildSettingsEdit.prepare(build: original, graph: g,
                target: .selectionSettings(selectionID: id), changes: [change], before: unknown, after: unknown, updatedAt: later)) {
                XCTAssertEqual($0 as? BuildSettingsEditError, .missingSelection)
            }
        }
        var rows = original.value.object!["selections"]!.array!; rows.append(rows[0])
        let duplicate = try build(["selections": .array(rows)])
        XCTAssertThrowsError(try edit([change], original: duplicate)) { XCTAssertEqual($0 as? BuildSettingsEditError, .ambiguousSelectionIdentity) }
    }

    func testGraphMustMatchBothPinnedIDAndRevision() throws {
        let original = try build()
        for (key, value) in [("dependency_graph_id", JSONValue.string("dependencies.other")), ("dependency_graph_revision", .number(2))] {
            var locks = original.locks.object!; locks[key] = value
            XCTAssertThrowsError(try edit([set("temperature", "1")], original: build(["locks": .object(locks)]))) {
                XCTAssertEqual($0 as? BuildSettingsEditError, .graphMismatch)
            }
        }
    }

    func testDirectGraphParticipationRetainsActiveInactiveAndUnknownDistinctions() throws {
        let g = try graph()
        let index = try XCTUnwrap(g.edges.firstIndex { $0.dependentKind == .accelerator && $0.dependsOnKind == .model })
        let cases: [(BuildEditEnvironment, DependencyInvalidation.Activity?)] = [
            (.init(mode: .selfHosted, production: false), .active), (.init(mode: .api, production: false), nil),
            (.init(mode: nil, production: nil), .unknown)]
        for (environment, expected) in cases {
            let e = try edit([set("temperature", "1")], before: environment, after: environment)
            guard case .selection(let impact) = e.impact else { return XCTFail("Selection graph preview missing") }
            XCTAssertEqual(impact.graphID, g.id); XCTAssertEqual(impact.graphRevision, g.revision)
            XCTAssertEqual(impact.participants.changedKinds, [.model])
            let participation = impact.participants.participatingEdges.first { $0.edgeIndex == index }
            XCTAssertEqual(participation?.before, expected); XCTAssertEqual(participation?.after, expected)
            XCTAssertTrue(impact.participants.affectedSelectionIDs.contains("sel_model"))
        }
    }

    func testCallerResolvedBeforeAfterEnvironmentIsNotInferredFromSelectionText() throws {
        let before = BuildEditEnvironment(mode: .api, production: nil)
        let after = BuildEditEnvironment(mode: .selfHosted, production: true)
        let e = try edit([set("requests_per_day", "201", .workload)], kind: .workload, before: before, after: after)
        XCTAssertEqual(e.beforeEnvironment, before); XCTAssertEqual(e.afterEnvironment, after)
        guard case .selection(let impact) = e.impact else { return XCTFail("Selection graph preview missing") }
        XCTAssertTrue(impact.participants.participatingEdges.contains { $0.before == .inactive && $0.after == .active })
        XCTAssertTrue(impact.participants.participatingEdges.contains { $0.before == .unknown && $0.after == .active })
        XCTAssertEqual(try settings(e.proposed)["serving_mode"], .string("weights"))
    }

    func testTimestampRevisionAndWholeBuildBoundsStillApplyAfterAValidFieldEdit() throws {
        XCTAssertThrowsError(try BuildSettingsEdit.prepare(build: build(), graph: graph(), target: .objectives,
            changes: [set("region", "\"region-next\"", nil)], before: unknown, after: unknown, updatedAt: "2026-02-30T00:00:00Z"))
        let nearBoundary = try build(["revision": .number(Decimal(string: "9007199254740990")!)])
        XCTAssertThrowsError(try edit([set("temperature", "1")], original: nearBoundary)) {
            XCTAssertEqual($0 as? TransferError, .unsupportedNumber)
        }
        let large = "\"" + String(repeating: "x", count: BuildTransfer.maximumBytes - 1000) + "\""
        XCTAssertThrowsError(try edit([set("region", large, nil)], kind: nil)) { XCTAssertEqual($0 as? TransferError, .oversized) }
    }

    func testValueAdmissionRejectsMalformedDuplicateDeepAndUnsupportedNumbers() throws {
        let bad: [(String, TransferError)] = [
            ("NaN", .malformed), ("{} trailing", .malformed), ("{\"a\":1,\"\\u0061\":2}", .duplicateKey),
            ("9007199254740992", .unsupportedNumber), ("0.0000000000001", .unsupportedNumber),
            ("1.1234567890123456", .unsupportedNumber), (String(repeating: "[", count: 50) + "0" + String(repeating: "]", count: 50), .tooDeep)]
        for (raw, expected) in bad {
            XCTAssertThrowsError(try BuildEditValue(json: Data(raw.utf8))) { XCTAssertEqual($0 as? TransferError, expected) }
        }
        XCTAssertThrowsError(try BuildEditValue(json: Data(repeating: 32, count: BuildTransfer.maximumBytes + 1))) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        XCTAssertEqual(try BuildEditValue(json: Data("1e-12".utf8)).value, .number(Decimal(string: "0.000000000001")!))
    }

    func testOldCostRecordCanRemainHistoricalButCannotAttachToNewRevision() throws {
        let e = try edit([set("temperature", "1")])
        let cost = try CostEstimateRecord.decode(encoded(fixture("cost-estimate")))
        XCTAssertNoThrow(try HistoricalCostScenario(build: e.original, estimate: cost))
        XCTAssertThrowsError(try HistoricalCostScenario(build: e.proposed, estimate: cost)) {
            XCTAssertEqual($0 as? HistoricalCostComparisonError, .buildMismatch)
        }
    }

    func testSelectingCommittedRevisionRetiresCurrentAndLateAnalysisResponses() async throws {
        let e = try edit([set("temperature", "1")])
        let old = analysisIdentity(e.original), next = analysisIdentity(e.proposed)
        let store = AnalysisStore<String>()
        let request = await store.begin(for: old)
        let received = await store.receive("synthetic old response", identity: old, for: request)
        XCTAssertTrue(received)
        // This explicit receiving action belongs after the caller's successful
        // durable save. Preparing a proposal itself does not mutate the store.
        await store.select(next)
        let state = await store.state
        XCTAssertEqual(state, .unavailable(identity: next, reason: .notRequested))
        let late = await store.receive("late old response", identity: old, for: request)
        XCTAssertFalse(late)
        let retry = await store.begin(for: next)
        let mismatched = await store.receive("old response on new request", identity: old, for: retry)
        XCTAssertFalse(mismatched)
    }

    func testRejectedAndUncommittedEditsLeaveDurableBytesAndHistoryUntouched() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.sqlite"), id = UUID(), original = try build()
        let store = try DraftStore(url: url)
        let saved = try await store.save(id: id, expectedRevision: nil, title: original.name, payload: original.encoded())
        for change in [try set("temperature", "3"), try set("credential_ref", "\"RAW_FIXTURE_SECRET\"")] {
            XCTAssertThrowsError(try edit([change], original: original))
        }
        _ = try edit([set("temperature", "1")], original: original)
        let reopened = try await DraftStore(url: url).read(id: id)
        let history = try await store.history(id: id)
        XCTAssertEqual(reopened, saved); XCTAssertEqual(history.records, [saved])
        XCTAssertFalse(reopened.analysisIsCurrent)
    }

    func testExplicitCompareAndSaveReopensExactProposalAndPreservesOldRevision() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.sqlite"), id = UUID(), e = try edit([set("temperature", "1")])
        let store = try DraftStore(url: url)
        let old = try await store.save(id: id, expectedRevision: nil, title: e.original.name, payload: e.original.encoded())
        let next = try await store.save(id: id, expectedRevision: old.revision, title: e.proposed.name, payload: e.proposed.encoded())
        let reopened = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(reopened, next); XCTAssertEqual(next.revision, 2); XCTAssertFalse(next.analysisIsCurrent)
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: reopened.payload), e.proposed)
        let history = try await store.history(id: id)
        XCTAssertEqual(history.records.map(\.revision), [2, 1]); XCTAssertEqual(history.records.last, old)
    }

    func testConcurrentSaveRejectsStaleProposalWithoutOverwritingOrRetrying() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.sqlite"), id = UUID(), original = try build()
        let store = try DraftStore(url: url)
        let old = try await store.save(id: id, expectedRevision: nil, title: original.name, payload: original.encoded())
        let proposal = try edit([set("temperature", "1")], original: original)
        let other = try edit([set("precision", "\"int4\"")], original: original)
        let winner = try await DraftStore(url: url).save(id: id, expectedRevision: old.revision,
            title: other.proposed.name, payload: other.proposed.encoded())
        do {
            _ = try await store.save(id: id, expectedRevision: old.revision, title: proposal.proposed.name, payload: proposal.proposed.encoded())
            XCTFail("Stale proposal replaced newer save")
        } catch { XCTAssertEqual(error as? DraftStoreError, .conflict) }
        let final = try await store.read(id: id), history = try await store.history(id: id)
        XCTAssertEqual(final, winner); XCTAssertEqual(history.records.count, 2)
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: final.payload), other.proposed)
    }
}
