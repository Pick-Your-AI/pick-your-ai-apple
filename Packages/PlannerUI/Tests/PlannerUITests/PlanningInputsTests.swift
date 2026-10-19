import XCTest
import PlannerCore
@testable import PlannerUI

@MainActor
final class PlanningInputsTests: XCTestCase {
    func testEmptyDraftHasNoAssumedObjectivesOrCatalogChoices() throws {
        let inputs = PlanningInputs()
        for field in PlanningInputField.allCases {
            XCTAssertEqual(inputs[field], "")
            XCTAssertEqual(field.state(of: inputs[field]), .unanswered)
        }
        XCTAssertNil(inputs.workload)
        XCTAssertNil(inputs.deploymentMode)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(inputs)) as? [String: Any])
        XCTAssertEqual(fields["values"] as? [String: String], [:])
        XCTAssertNil(fields["workload"])
        XCTAssertNil(fields["deploymentMode"])
    }

    func testInputVectorsPreserveRawTextAndValidationStateThroughCoding() throws {
        struct Vector: Decodable { let field: String; let raw: String; let state: String }
        struct Vectors: Decodable {
            let synthetic: Bool
            let contract_source: String
            let cases: [Vector]
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "planning-input-vectors", withExtension: "json"))
        let vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
        XCTAssertTrue(vectors.synthetic)
        XCTAssertEqual(vectors.contract_source, "7acbefbf4e4e700231e88be272bc89e3a73dde15")
        XCTAssertEqual(vectors.cases.count, 36)
        XCTAssertEqual(Set(vectors.cases.map(\.field)), Set(PlanningInputField.allCases.map(\.rawValue)))
        for vector in vectors.cases {
            let field = try XCTUnwrap(PlanningInputField(rawValue: vector.field))
            var inputs = PlanningInputs(); inputs[field] = vector.raw
            let decoded = try JSONDecoder().decode(PlanningInputs.self, from: JSONEncoder().encode(inputs))
            XCTAssertTrue(decoded[field].utf8.elementsEqual(vector.raw.utf8), "\(field): \(vector.raw)")
            let state: String
            switch field.state(of: decoded[field]) {
            case .unanswered: state = "unanswered"
            case .supplied: state = "supplied"
            case .invalid: state = "invalid"
            }
            XCTAssertEqual(state, vector.state, "\(field): \(vector.raw)")
        }
    }

    func testBudgetPrecisionAndSpellingRemainIndependentOfCurrency() throws {
        let raw = "1234567890123456789012345678901234567890.123456789012"
        var inputs = PlanningInputs(); inputs[.monthlyBudgetAmount] = raw
        XCTAssertEqual(PlanningInputField.monthlyBudgetAmount.state(of: raw), .supplied)
        XCTAssertEqual(try ContractDecimal(raw).rawValue, raw)
        XCTAssertEqual(PlanningInputField.currency.state(of: inputs[.currency]), .unanswered)
        inputs[.monthlyBudgetAmount] = "0.000"
        XCTAssertEqual(inputs[.monthlyBudgetAmount], "0.000")
        XCTAssertNotEqual(inputs[.monthlyBudgetAmount], "0")
    }

    func testCatalogChoicesRetainCanonicalKindsAndPinsWithoutCopyingDefaults() async throws {
        let choices = try await BundledCatalogPreviewSource().planningInputChoices()
        XCTAssertEqual(choices.count, 2)
        XCTAssertEqual(Set(choices.map(\.reference.kind)), Set(PlanningCatalogKind.allCases))
        var inputs = PlanningInputs()
        for choice in choices {
            let reference = choice.reference
            XCTAssertEqual(reference.catalogSchemaVersion, "1.0.0")
            XCTAssertEqual(reference.catalogID, "catalog.fixture.1")
            XCTAssertEqual(reference.catalogRevision, 1)
            XCTAssertEqual(reference.sha256, BundledCatalogPreviewSource.expectedSHA256)
            XCTAssertEqual(reference.itemVersion, "2026.10-demo")
            XCTAssertTrue(reference.name.contains("FICTIONAL"))
            XCTAssertEqual(choice.declaration, reference.kind == .workload ? "agentic" : "self_hosted")
            XCTAssertTrue(inputs.select(reference, for: reference.kind))
        }
        for field in PlanningInputField.allCases { XCTAssertEqual(inputs[field], "") }
        XCTAssertEqual(inputs.workload?.itemID, "cat.workload.fixture")
        XCTAssertEqual(inputs.deploymentMode?.itemID, "cat.deployment_mode.fixture")
        XCTAssertEqual(try JSONDecoder().decode(PlanningInputs.self, from: JSONEncoder().encode(inputs)), inputs)
    }

    func testWrongKindCannotReplaceAChoiceAndRemovalRestoresUnanswered() async throws {
        let choices = try await BundledCatalogPreviewSource().planningInputChoices()
        let workload = try XCTUnwrap(choices.first { $0.reference.kind == .workload }?.reference)
        let deployment = try XCTUnwrap(choices.first { $0.reference.kind == .deploymentMode }?.reference)
        var inputs = PlanningInputs()
        XCTAssertTrue(inputs.select(workload, for: .workload))
        XCTAssertFalse(inputs.select(deployment, for: .workload))
        XCTAssertEqual(inputs.workload, workload)
        XCTAssertTrue(inputs.select(nil, for: .workload))
        XCTAssertNil(inputs.workload)
        XCTAssertNil(inputs.deploymentMode)
    }

    func testUnsupportedNestedFieldsAndMisplacedCatalogKindsAreRejected() async throws {
        for json in [#"{"values":{"future_field":"preserve"}}"#,
                     #"{"values":{},"future_field":true}"#,
                     #"{"values":{"requests_per_day":0}}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(PlanningInputs.self, from: Data(json.utf8)))
        }
        let choices = try await BundledCatalogPreviewSource().planningInputChoices()
        let deployment = try XCTUnwrap(choices.first { $0.reference.kind == .deploymentMode }?.reference)
        let reference = try JSONSerialization.jsonObject(with: JSONEncoder().encode(deployment))
        let misplaced = try JSONSerialization.data(withJSONObject: ["values": [String: String](), "workload": reference])
        XCTAssertThrowsError(try JSONDecoder().decode(PlanningInputs.self, from: misplaced))
        var extended = try XCTUnwrap(reference as? [String: Any]); extended["future_pin"] = "preserve"
        XCTAssertThrowsError(try JSONDecoder().decode(PlanningCatalogReference.self,
            from: JSONSerialization.data(withJSONObject: extended)))
    }

    func testExactInputTextParticipatesInEqualityAndBoundedUndo() {
        var composed = PlanningInputs(); composed[.region] = "caf\u{00E9}"
        var decomposed = PlanningInputs(); decomposed[.region] = "cafe\u{0301}"
        XCTAssertNotEqual(composed, decomposed)
        let first = EditorContents(title: "", notes: "", inputs: composed)
        let second = EditorContents(title: "", notes: "", inputs: decomposed)
        var history = EditorUndoHistory(); history.record(first)
        XCTAssertEqual(history.undo(second), first)
        XCTAssertEqual(history.redo(first), second)
        var oversized = PlanningInputs()
        oversized[.region] = String(repeating: "x", count: EditorUndoHistory.maximumBytes + 1)
        XCTAssertFalse(history.canUndo(EditorContents(title: "", notes: "", inputs: oversized)))
    }

    func testEditorPayloadVersionsDoNotInventOrDiscardFields() throws {
        let original = Data(#"{"editorVersion":1,"notes":"old notes"}"#.utf8)
        let legacy = try JSONDecoder().decode(EditorPayload.self, from: original)
        XCTAssertEqual(legacy.editorVersion, 1)
        XCTAssertEqual(legacy.notes, "old notes")
        XCTAssertEqual(legacy.planningInputs, PlanningInputs())
        let encodedLegacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertEqual(Set(encodedLegacy.keys), ["editorVersion", "notes"])
        for json in [#"{"editorVersion":2,"notes":"future"}"#,
                     #"{"editorVersion":1,"notes":"old","planningInputs":{"values":{}}}"#,
                     #"{"editorVersion":3,"notes":"future","planningInputs":{"values":{}}}"#,
                     #"{"editorVersion":true,"notes":"future"}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(EditorPayload.self, from: Data(json.utf8)))
        }
    }
}
