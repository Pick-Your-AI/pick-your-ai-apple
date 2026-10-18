import Foundation
import XCTest
@testable import PlannerCore

final class SharedReportVectorTests: XCTestCase {
    private struct VectorBundle: Decodable {
        let lock: [String: String]
        let schema: String
        let cases: [Vector]
    }
    private struct Vector: Decodable {
        let id: String
        let valid: Bool
        let payloadJSON: String
    }

    func testIdenticalCanonicalReportVectors() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "evaluation-vectors", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "evaluation-vectors", withExtension: "json"))
        let bundle = try JSONDecoder().decode(VectorBundle.self, from: Data(contentsOf: url))
        XCTAssertEqual(bundle.lock["contract_version"], "1.0.0")
        XCTAssertEqual(bundle.schema, "evaluation-report.schema.json")
        XCTAssertFalse(bundle.cases.isEmpty)
        XCTAssertEqual(Set(bundle.cases.map(\.id)).count, bundle.cases.count)
        XCTAssertTrue(bundle.cases.contains { $0.valid })
        XCTAssertTrue(bundle.cases.contains { !$0.valid })
        for vector in bundle.cases {
            let data = Data(vector.payloadJSON.utf8)
            if !vector.valid {
                XCTAssertThrowsError(try EvaluationReport.decode(data), vector.id)
                continue
            }
            do {
                let report = try EvaluationReport.decode(data)
                XCTAssertEqual(report, try EvaluationReport.decode(JSONEncoder().encode(report)), vector.id)
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertEqual(report.result.rawValue, object["result"] as? String, vector.id)
                XCTAssertEqual(report.deploymentReadiness.rawValue, object["deployment_readiness"] as? String, vector.id)
                let findings = try XCTUnwrap(object["findings"] as? [[String: Any]])
                XCTAssertEqual(report.findings.count, findings.count, vector.id)
                for (decoded, input) in zip(report.findings, findings) {
                    XCTAssertEqual(decoded.outcome.rawValue, input["outcome"] as? String, vector.id)
                    XCTAssertEqual(decoded.severity.rawValue, input["severity"] as? String, vector.id)
                }
                if vector.id.hasPrefix("evaluation-report/outcome/") {
                    let evidence = try XCTUnwrap(report.findings.first?.evidence)
                    XCTAssertEqual(evidence.count, 3, vector.id)
                    XCTAssertNil(evidence.first?.observed, vector.id)
                    XCTAssertEqual(evidence.dropFirst().first?.observed, .null, vector.id)
                    XCTAssertEqual(evidence.last?.observed, .string("unknown"), vector.id)
                }
            } catch {
                XCTFail("\(vector.id): expected canonical acceptance, got \(error)")
            }
        }
    }
}
