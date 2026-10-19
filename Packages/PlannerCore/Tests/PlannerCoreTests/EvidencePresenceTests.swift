import Foundation
import XCTest
@testable import PlannerCore

final class EvidencePresenceTests: XCTestCase {
    private struct VectorBundle: Decodable {
        let lock: [String: String]
        let schema: String
        let cases: [Vector]
    }

    private struct Vector: Decodable {
        let id: String
        let valid: Bool
        let payloadJSON: String
        let collection: String?
        let observed: [String]
        let expected: [String]
        let outcome: String?
        let severity: String?
    }

    private func vectors() throws -> [Vector] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "evidence-vectors", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "evidence-vectors", withExtension: "json"))
        let bundle = try JSONDecoder().decode(VectorBundle.self, from: Data(contentsOf: url))
        XCTAssertEqual(bundle.lock["contract_version"], "1.0.0")
        XCTAssertEqual(bundle.schema, "evaluation-report.schema.json")
        XCTAssertEqual(bundle.cases.count, 37)
        XCTAssertEqual(Set(bundle.cases.map(\.id)).count, bundle.cases.count)
        XCTAssertEqual(bundle.cases.filter(\.valid).count, 28)
        return bundle.cases
    }

    private func name(_ presence: EvidenceValuePresence) -> String {
        switch presence {
        case .absent: "absent"
        case .explicitNull: "explicitNull"
        case .literalUnknown: "literalUnknown"
        case .supplied: "supplied"
        }
    }

    private func name(_ presence: EvidenceCollectionPresence) -> String {
        switch presence {
        case .absent: "absent"
        case .empty: "empty"
        case .supplied: "supplied"
        }
    }

    func testSharedEvidenceVectorsPreservePresenceAndSeparateOutcomeFromSeverity() throws {
        let accepted = try vectors().filter(\.valid)
        let outcomePairs = accepted.filter { $0.id.hasPrefix("evidence/outcome/") }
        XCTAssertEqual(Set(outcomePairs.map { "\($0.outcome ?? "")/\($0.severity ?? "")" }).count, 12)
        for vector in accepted {
            let data = Data(vector.payloadJSON.utf8)
            let report = try EvaluationReport.decode(data)
            if let finding = report.findings.first {
                XCTAssertEqual(report.findings.count, 1, vector.id)
                XCTAssertEqual(finding.outcome.rawValue, vector.outcome, vector.id)
                XCTAssertEqual(finding.severity.rawValue, vector.severity, vector.id)
                XCTAssertEqual(name(finding.evidencePresence), vector.collection, vector.id)
                XCTAssertEqual(finding.evidence?.map { name($0.observedPresence) } ?? [], vector.observed, vector.id)
                XCTAssertEqual(finding.evidence?.map { name($0.expectedPresence) } ?? [], vector.expected, vector.id)
            } else {
                XCTAssertEqual(vector.id, "evidence/no-findings")
                XCTAssertNil(vector.outcome)
                XCTAssertNil(vector.severity)
                XCTAssertNil(vector.collection)
            }

            let encoded = try JSONEncoder().encode(report)
            XCTAssertEqual(report, try EvaluationReport.decode(encoded), vector.id)
            let originalObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
            let encodedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
            XCTAssertEqual(originalObject, encodedObject, vector.id)
        }
    }

    func testRejectedEvidenceInputsLeaveThePriorReportIntactAndPermitRecovery() throws {
        let cases = try vectors()
        let priorBytes = Data(try XCTUnwrap(cases.first { $0.id == "evidence/reported-pass-without-support" }).payloadJSON.utf8)
        let prior = try EvaluationReport.decode(priorBytes)
        let priorSerialization = try JSONEncoder().encode(prior)
        let rejected = cases.filter { !$0.valid }
        XCTAssertEqual(rejected.count, 9)
        for vector in rejected {
            XCTAssertThrowsError(try EvaluationReport.decode(Data(vector.payloadJSON.utf8)), vector.id)
            XCTAssertEqual(prior, try EvaluationReport.decode(priorSerialization), vector.id)
            XCTAssertEqual(prior, try EvaluationReport.decode(priorBytes), vector.id)
            XCTAssertEqual(prior.findings.first?.outcome, .pass, vector.id)
            XCTAssertEqual(prior.findings.first?.evidencePresence, .absent, vector.id)
        }
    }

    func testContradictoryEvidenceRetainsBothValuesAndSourceVersionsWithoutResolvingThem() throws {
        let vector = try XCTUnwrap(try vectors().first { $0.id == "evidence/contradictory-evidence" })
        let report = try EvaluationReport.decode(Data(vector.payloadJSON.utf8))
        let finding = try XCTUnwrap(report.findings.first)
        XCTAssertEqual(finding.outcome, .fail)
        XCTAssertEqual(finding.severity, .warning)
        XCTAssertEqual(finding.code, "CONTRADICTORY_EVIDENCE")
        let evidence = try XCTUnwrap(finding.evidence)
        XCTAssertEqual(evidence.map(\.path), ["model.memory", "model.memory"])
        XCTAssertEqual(evidence.map(\.observed), [.number(24), .number(48)])
        XCTAssertEqual(evidence.map(\.expected), [.number(48), .number(24)])
        XCTAssertEqual(evidence.map(\.sourceVersion), ["source-a/1", "source-b/2"])

        let unresolved = try XCTUnwrap(try vectors().first { $0.id == "evidence/unresolved-opposite-claims" })
        let unknown = try XCTUnwrap(try EvaluationReport.decode(Data(unresolved.payloadJSON.utf8)).findings.first)
        XCTAssertEqual(unknown.outcome, .unknown)
        XCTAssertEqual(unknown.severity, .warning)
        XCTAssertEqual(unknown.code, "OPPOSITE_CLAIMS")
        XCTAssertEqual(unknown.evidence?.map(\.observed), [.bool(true), .bool(false)])
        XCTAssertEqual(unknown.evidence?.map(\.sourceVersion), ["source-a/1", "source-b/2"])
    }

    func testPresenceNeverInterpretsSuppliedDataAsSupportOrAComparisonResult() {
        XCTAssertEqual(EvidenceValuePresence(nil), .absent)
        XCTAssertEqual(EvidenceValuePresence(.null), .explicitNull)
        XCTAssertEqual(EvidenceValuePresence(.string("unknown")), .literalUnknown)
        let values: [EvaluationJSONValue] = [.bool(false), .number(0), .string(""), .string("pass"),
                                            .string("not_applicable"), .string("null"), .string("Unknown"),
                                            .string("line\n\u{0000}next"), .array([]), .object(["detail": .string("unknown")])]
        for value in values {
            XCTAssertEqual(EvidenceValuePresence(value), .supplied)
        }
    }
}
