import Foundation
import XCTest
@testable import PlannerTransfer

final class DeploymentManifestTests: XCTestCase {
    private func fixture(_ name: String = "deployment-manifest") throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json")))
    }

    private func object(_ name: String = "deployment-manifest") throws -> [String: JSONValue] {
        var parser = try JSONParser(fixture(name))
        return try XCTUnwrap(parser.parse().object)
    }

    private func encoded(_ value: [String: JSONValue], compact: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = compact ? [.sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
        return try encoder.encode(JSONValue.object(value))
    }

    private func build(_ value: [String: JSONValue]) throws -> BuildSnapshot {
        try BuildTransfer.snapshot(fromDraftJSON: encoded(value))
    }

    private func manifest(_ value: [String: JSONValue]) throws -> DeploymentManifest {
        try DeploymentManifest.decode(encoded(value))
    }

    private func replacingSelection(_ value: [String: JSONValue], id: String,
                                    transform: ([String: JSONValue]) -> [String: JSONValue]) -> [String: JSONValue] {
        var result = value
        result["selections"] = .array(value["selections"]!.array!.map { selection in
            guard selection.object!["id"] == .string(id) else { return selection }
            return .object(transform(selection.object!))
        })
        return result
    }

    func testCanonicalManifestRetainsAllReferencesAndRoundTrips() throws {
        let input = try object()
        let value = try DeploymentManifest.decode(fixture())
        XCTAssertEqual(value.id, "manifest.fixture.1")
        XCTAssertEqual(value.buildID, "build.fixture.1")
        XCTAssertEqual(value.buildRevision, 1)
        XCTAssertEqual(value.deploymentTargetSelectionID, "sel_deployment_target")
        XCTAssertEqual(value.status, "proposed")
        XCTAssertEqual(value.approvals, input["approvals"]?.array)
        XCTAssertEqual(value.value, .object(input))
        for key in ["compatibility_report_id", "quality_run_id", "cost_estimate_id", "resource_estimate_id"] {
            XCTAssertEqual(value.value.object?[key], input[key])
        }
        XCTAssertNil(value.value.object?["rollback_artifact_uri"])
        XCTAssertNil(value.value.object?["deployment_reference"])
        XCTAssertEqual(try DeploymentManifest.decode(value.encoded()), value)
    }

    func testSharedReferenceVectorsRetainExplicitCanonicalAndClientBoundaries() throws {
        struct Vector: Decodable {
            let name: String, json: String
            let canonicalValid: Bool, clientValid: Bool
            let clientLimit: String?
        }
        let cases = try JSONDecoder().decode([Vector].self, from: fixture("deployment-manifest-conformance"))
        XCTAssertEqual(cases.count, 133)
        XCTAssertEqual(Set(cases.map(\.name)).count, 133)
        XCTAssertEqual(cases.filter(\.canonicalValid).count, 45)
        XCTAssertEqual(cases.filter(\.clientValid).count, 41)
        XCTAssertEqual(cases.filter { $0.canonicalValid != $0.clientValid }.count, 4)
        for vector in cases {
            if vector.canonicalValid != vector.clientValid { XCTAssertNotNil(vector.clientLimit, vector.name) }
            do {
                let value = try DeploymentManifest.decode(Data(vector.json.utf8))
                XCTAssertTrue(vector.clientValid, vector.name)
                XCTAssertEqual(try DeploymentManifest.decode(value.encoded()), value, vector.name)
            } catch {
                XCTAssertFalse(vector.clientValid, "\(vector.name): \(error)")
            }
        }
    }

    func testReaderPreservesEveryDeclaredStatusWithoutApprovalInference() throws {
        var input = try object()
        let rows: [JSONValue] = [
            .object(["approver_ref": .string("private.fixture.é"), "decision": .string("pending"),
                     "scope": .string("owner"), "approved_at": .string("2024-02-29T09:00:00Z")]),
            .object(["approver_ref": .string("private.fixture.e\u{301}"), "decision": .string("rejected"),
                     "scope": .string("security")]),
            .object(["approver_ref": .string("private.fixture.é"), "decision": .string("approved"),
                     "scope": .string("finance")])
        ]
        input["approvals"] = .array(rows + [rows[0]])
        input["rollback_artifact_uri"] = .string("urn:fixture:rollback:1")
        input["deployment_reference"] = .string("private-declared-reference")
        input["notes"] = .array([.string("é"), .string("e\u{301}"), .string("é")])
        for status in ["proposed", "approved", "rejected", "deployed", "rolled_back"] {
            input["status"] = .string(status)
            let value = try manifest(input)
            XCTAssertEqual(value.status, status)
            XCTAssertEqual(value.approvals, rows + [rows[0]])
            let reopened = try DeploymentManifest.decode(value.encoded())
            XCTAssertEqual(reopened.value, .object(input))
            XCTAssertEqual(reopened.approvals.map { Array($0.object!["approver_ref"]!.string!.utf8) },
                           (rows + [rows[0]]).map { Array($0.object!["approver_ref"]!.string!.utf8) })
            XCTAssertEqual(reopened.value.object!["notes"]!.array!.map { Array($0.string!.utf8) },
                           ["é", "e\u{301}", "é"].map { Array($0.utf8) })
        }
    }

    func testRawDuplicateMembersAndEscapedAliasesRejectBeforeSchema() throws {
        let source = String(decoding: try encoded(object()), as: UTF8.self)
        for (needle, replacement) in [
            (#""build_id":"build.fixture.1""#, #""build_id":"build.fixture.1","\u0062uild_id":"build.other.1""#),
            (#""decision":"pending""#, #""decision":"pending","\u0064ecision":"approved""#)
        ] {
            let duplicate = source.replacingOccurrences(of: needle, with: replacement)
            XCTAssertNotEqual(duplicate, source)
            XCTAssertThrowsError(try DeploymentManifest.decode(Data(duplicate.utf8))) {
                XCTAssertEqual($0 as? TransferError, .duplicateKey)
            }
        }
        XCTAssertEqual(try DeploymentManifest.decode(Data(source.utf8)), try manifest(object()))
    }

    func testByteDepthNodeAndNumericLimitsApplyToTheWholeManifest() throws {
        var exact = try fixture()
        exact.append(Data(repeating: 32, count: BuildTransfer.maximumBytes - exact.count))
        XCTAssertEqual(try DeploymentManifest.decode(exact), try DeploymentManifest.decode(fixture()))
        exact.append(32)
        XCTAssertThrowsError(try DeploymentManifest.decode(exact)) { XCTAssertEqual($0 as? TransferError, .oversized) }
        let deep = Data((String(repeating: "[", count: 50) + "0" + String(repeating: "]", count: 50)).utf8)
        XCTAssertThrowsError(try DeploymentManifest.decode(deep)) { XCTAssertEqual($0 as? TransferError, .tooDeep) }
        var input = try object()
        input["notes"] = .array(Array(repeating: .string(""), count: 16_384))
        let many = try encoded(input)
        XCTAssertLessThan(many.count, BuildTransfer.maximumBytes)
        XCTAssertThrowsError(try DeploymentManifest.decode(many)) { XCTAssertEqual($0 as? TransferError, .tooComplex) }
        let text = String(decoding: try encoded(object()), as: UTF8.self)
        let number = text.replacingOccurrences(of: #""build_revision":1"#, with: #""build_revision":1234567890123456"#)
        XCTAssertNotEqual(number, text)
        XCTAssertThrowsError(try DeploymentManifest.decode(Data(number.utf8))) {
            XCTAssertEqual($0 as? TransferError, .unsupportedNumber)
        }
    }

    func testUnsupportedVersionsAndMissingEvidenceReferencesCannotCreateDefaults() throws {
        for version: JSONValue in [.string("2.0.0"), .number(1), .null] {
            var input = try object(); input["schema_version"] = version
            XCTAssertThrowsError(try manifest(input)) { XCTAssertEqual($0 as? TransferError, .unsupportedVersion) }
        }
        for key in ["compatibility_report_id", "quality_run_id", "cost_estimate_id", "resource_estimate_id", "approvals"] {
            var input = try object(); input.removeValue(forKey: key)
            let bytes = try encoded(input); let before = bytes
            XCTAssertThrowsError(try DeploymentManifest.decode(bytes)) { XCTAssertEqual($0 as? TransferError, .schemaViolation) }
            XCTAssertEqual(bytes, before)
            XCTAssertNil(input[key])
        }
        XCTAssertEqual(try DeploymentManifest.decode(fixture()).status, "proposed")
    }

    func testLateInvalidApprovalIsRejectedWithPrivateInputsUnchangedAndRetryable() throws {
        var input = try object()
        let first = input["approvals"]!.array![0]
        var last = first.object!
        last["approved_at"] = .string("private-invalid-timestamp-do-not-echo")
        input["approvals"] = .array([first, first, .object(last)])
        let bytes = try encoded(input); let original = bytes
        XCTAssertThrowsError(try DeploymentManifest.decode(bytes)) {
            XCTAssertEqual($0 as? TransferError, .schemaViolation)
            XCTAssertFalse(String(describing: $0).contains("private-invalid"))
        }
        XCTAssertEqual(bytes, original)
        input["approvals"] = .array([first, first])
        XCTAssertEqual(try manifest(input).approvals, [first, first])
    }

    func testProposedLocalPairPreservesLocksMonitoringPrivateFieldsAndDeclarations() throws {
        var buildInput = try object("build")
        buildInput["owner_ref"] = .string("private.synthetic.owner")
        buildInput["notes"] = .array([.string("private synthetic planning notes")])
        buildInput = replacingSelection(buildInput, id: "sel_monitoring_stack") { selection in
            var result = selection; result["catalog_item_version"] = .string("private.e\u{301}.version")
            return result
        }
        var manifestInput = try object()
        manifestInput["rollback_artifact_uri"] = .string("file:///private/synthetic/rollback")
        manifestInput["deployment_reference"] = .string("reported-prior-reference-not-verified")
        let savedBuild = try build(buildInput), savedManifest = try manifest(manifestInput)
        let pair = try ProposedDeploymentPlan(build: savedBuild, manifest: savedManifest)
        let output = try pair.encodedLocally()
        let reopenedBuild = try BuildTransfer.snapshot(fromDraftJSON: output.buildJSON)
        let reopenedManifest = try DeploymentManifest.decode(output.manifestJSON)
        XCTAssertEqual(reopenedBuild.value, .object(buildInput))
        XCTAssertEqual(reopenedBuild.locks, savedBuild.locks)
        let monitoring = try XCTUnwrap(reopenedBuild.value.object?["selections"]?.array?.first {
            $0.object?["id"] == .string("sel_monitoring_stack")
        })
        let version = try XCTUnwrap(monitoring.object?["catalog_item_version"]?.string)
        XCTAssertEqual(Array(version.utf8), Array("private.e\u{301}.version".utf8))
        XCTAssertNotEqual(Array(version.utf8), Array("private.é.version".utf8))
        XCTAssertEqual(reopenedManifest.value, .object(manifestInput))
        XCTAssertEqual(pair.build, savedBuild)
        XCTAssertEqual(pair.manifest, savedManifest)
        XCTAssertEqual(reopenedManifest.status, "proposed")
        XCTAssertEqual(reopenedManifest.approvals.first?.object?["decision"], .string("pending"))
    }

    func testProposedHelperDoesNotDowngradeOtherDeclaredStatusesAndCanRetry() throws {
        let savedBuild = try build(object("build"))
        for status in ["approved", "rejected", "deployed", "rolled_back"] {
            var input = try object(); input["status"] = .string(status)
            let value = try manifest(input); let before = value.value
            XCTAssertThrowsError(try ProposedDeploymentPlan(build: savedBuild, manifest: value)) {
                XCTAssertEqual($0 as? ProposedDeploymentPlanError, .notProposed)
            }
            XCTAssertEqual(value.value, before)
            XCTAssertEqual(value.status, status)
        }
        let retry = try ProposedDeploymentPlan(build: savedBuild, manifest: manifest(object()))
        XCTAssertEqual(try DeploymentManifest.decode(retry.encodedLocally().manifestJSON).status, "proposed")
    }

    func testForeignAndStaleBuildBindingsRejectWithoutChangingEitherArtifact() throws {
        let savedBuild = try build(object("build"))
        for (key, value) in [("build_id", JSONValue.string("build.foreign.1")), ("build_revision", .number(2))] {
            var input = try object(); input[key] = value
            let declaration = try manifest(input)
            XCTAssertThrowsError(try ProposedDeploymentPlan(build: savedBuild, manifest: declaration)) {
                XCTAssertEqual($0 as? ProposedDeploymentPlanError, .buildMismatch)
            }
            XCTAssertEqual(declaration.value, .object(input))
            XCTAssertEqual(savedBuild.value, .object(try object("build")))
        }
        var newer = try object("build"); newer["revision"] = .number(2)
        XCTAssertThrowsError(try ProposedDeploymentPlan(build: build(newer), manifest: manifest(object()))) {
            XCTAssertEqual($0 as? ProposedDeploymentPlanError, .buildMismatch)
        }
    }

    func testMissingDisabledWrongKindAndEveryDuplicateTargetIdentityReject() throws {
        let original = try object("build")
        let selections = original["selections"]!.array!
        let target = selections.first { $0.object?["id"] == .string("sel_deployment_target") }!
        let wrong = selections.first { $0.object?["kind"] == .string("monitoring_stack") }!.object!
        var wrongID = wrong; wrongID["id"] = .string("sel_deployment_target")
        var disabled = target.object!; disabled["enabled"] = .bool(false)
        let without = selections.filter { $0.object?["id"] != .string("sel_deployment_target") }
        let variants: [[JSONValue]] = [without, without + [.object(disabled)], without + [.object(wrongID)],
                                       selections + [target], selections + [.object(disabled)],
                                       selections + [.object(wrongID)]]
        for entries in variants {
            var input = original; input["selections"] = .array(entries)
            let snapshot = try build(input) // Prove rejection occurs at binding, not malformed JSON.
            XCTAssertThrowsError(try ProposedDeploymentPlan(build: snapshot, manifest: manifest(object()))) {
                XCTAssertEqual($0 as? ProposedDeploymentPlanError, .targetBinding)
            }
            XCTAssertEqual(snapshot.value, .object(input))
        }
        XCTAssertNoThrow(try ProposedDeploymentPlan(build: build(original), manifest: manifest(object())))
    }

    func testNonprefixedFrozenSelectionIdentityIsAcceptedByExactBinding() throws {
        var input = replacingSelection(try object("build"), id: "sel_deployment_target") { selection in
            var result = selection; result["id"] = .string("target")
            return result
        }
        input["links"] = .array(input["links"]!.array!.map { link in
            var fields = link.object!
            for key in ["from_selection_id", "to_selection_id"] where fields[key] == .string("sel_deployment_target") {
                fields[key] = .string("target")
            }
            return .object(fields)
        })
        var declaration = try object(); declaration["deployment_target_selection_id"] = .string("target")
        let pair = try ProposedDeploymentPlan(build: build(input), manifest: manifest(declaration))
        XCTAssertEqual(pair.manifest.deploymentTargetSelectionID, "target")
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: pair.encodedLocally().buildJSON).value, .object(input))
    }

    func testOptionalTiersAndMonitoringOmissionRemainExplicitWithoutNewSelections() throws {
        let optionalKinds: Set<String> = ["data_source", "knowledge_base", "embedding_model", "vector_database",
            "rag_pipeline", "agent_framework", "tool", "mcp_server", "memory_store", "integration",
            "training_framework", "training_compute", "training_dataset", "fine_tuned_model", "monitoring_stack"]
        for omitted in [false, true] {
            var input = try object("build")
            let all = input["selections"]!.array!
            let removed = Set(all.filter { optionalKinds.contains($0.object!["kind"]!.string!) }
                .map { $0.object!["id"]!.string! })
            input["selections"] = .array(all.compactMap { selection in
                guard optionalKinds.contains(selection.object!["kind"]!.string!) else { return selection }
                if omitted { return nil }
                var fields = selection.object!; fields["enabled"] = .bool(false)
                return .object(fields)
            })
            if omitted {
                input["links"] = .array(input["links"]!.array!.filter { link in
                    !removed.contains(link.object!["from_selection_id"]!.string!) &&
                    !removed.contains(link.object!["to_selection_id"]!.string!)
                })
            }
            let pair = try ProposedDeploymentPlan(build: build(input), manifest: manifest(object()))
            let output = try pair.encodedLocally()
            XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: output.buildJSON).value, .object(input))
            XCTAssertEqual(try DeploymentManifest.decode(output.manifestJSON).status, "proposed")
            XCTAssertEqual(pair.build.locks, input["locks"])
        }
    }

    func testIncompatibleSyntheticTierInputsAndUnverifiedReferencesAreNotEvaluated() throws {
        var input = replacingSelection(try object("build"), id: "sel_vector_database") { selection in
            var result = selection, settings = result["settings"]!.object!
            settings["index_dimension"] = .number(1536) // Fixture embedding declares 768.
            result["settings"] = .object(settings)
            return result
        }
        input["notes"] = .array([.string("Synthetic incompatible embedding/index dimensions; quality and approval unverified.")])
        var declaration = try object()
        declaration["quality_run_id"] = .string("quality.unverified.reference")
        declaration["notes"] = .array([.string("Referenced reports are not supplied or verified by this local pair.")])
        let pair = try ProposedDeploymentPlan(build: build(input), manifest: manifest(declaration))
        let output = try pair.encodedLocally()
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: output.buildJSON).value, .object(input))
        XCTAssertEqual(try DeploymentManifest.decode(output.manifestJSON).value, .object(declaration))
        XCTAssertEqual(pair.manifest.status, "proposed")
        XCTAssertEqual(pair.manifest.approvals.first?.object?["decision"], .string("pending"))
        XCTAssertNil(pair.manifest.value.object?["deployment_reference"])
    }

    func testAllReportedApprovalsCannotPromoteAProposedPlan() throws {
        var input = try object()
        input["approvals"] = .array([.object(["approver_ref": .string("private.synthetic.owner"),
            "decision": .string("approved"), "scope": .string("owner")])])
        let pair = try ProposedDeploymentPlan(build: build(object("build")), manifest: manifest(input))
        let output = try pair.encodedLocally()
        XCTAssertEqual(try DeploymentManifest.decode(output.manifestJSON).status, "proposed")
        XCTAssertEqual(pair.manifest.value, .object(input))
        XCTAssertNil(pair.manifest.approvals.first?.object?["approved_at"])
    }

    func testLocalEncodingExpansionReturnsNoPairAndLeavesInputsRecoverable() throws {
        var input = try object()
        input["notes"] = .array([.string(String(repeating: "/", count: 270_000))])
        let compact = try encoded(input, compact: true)
        XCTAssertLessThan(compact.count, BuildTransfer.maximumBytes)
        XCTAssertGreaterThan(try encoded(input).count, BuildTransfer.maximumBytes)
        let declaration = try DeploymentManifest.decode(compact)
        let savedBuild = try build(object("build"))
        let pair = try ProposedDeploymentPlan(build: savedBuild, manifest: declaration)
        XCTAssertThrowsError(try pair.encodedLocally()) { XCTAssertEqual($0 as? TransferError, .oversized) }
        XCTAssertEqual(pair.build, savedBuild)
        XCTAssertEqual(pair.manifest.value, .object(input))
        XCTAssertEqual(try DeploymentManifest.decode(compact), declaration)
        let retry = try ProposedDeploymentPlan(build: savedBuild, manifest: manifest(object()))
        XCTAssertEqual(try DeploymentManifest.decode(retry.encodedLocally().manifestJSON).status, "proposed")
    }
}
