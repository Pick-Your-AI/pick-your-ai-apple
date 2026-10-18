import Foundation
import XCTest
@testable import PlannerCore

final class EvaluationReportTests: XCTestCase {
    private func fixture() throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "evaluation-report", withExtension: "json", subdirectory: "Fixtures") ?? Bundle.module.url(forResource: "evaluation-report", withExtension: "json")))
    }
    private func object() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
    }
    private func decode(_ object: [String: Any]) throws -> EvaluationReport {
        try EvaluationReport.decode(JSONSerialization.data(withJSONObject: object))
    }
    func testFixtureRoundTripPreservesReadinessAndSeverity() throws {
        let report = try EvaluationReport.decode(fixture())
        XCTAssertEqual(report.result, .valid)
        XCTAssertEqual(report.deploymentReadiness, .needsReview)
        XCTAssertEqual(report.summary.passed, 41)
        XCTAssertEqual(report.findings.filter { $0.outcome == .skipped }.count, 4)
        XCTAssertEqual(report.findings.first?.severity, .error)
        XCTAssertEqual(report, try EvaluationReport.decode(JSONEncoder().encode(report)))
    }
    func testEveryRequiredReportFieldRejectsMissingAndNull() throws {
        let original = try object()
        for key in original.keys {
            var missing = original; missing.removeValue(forKey: key)
            XCTAssertThrowsError(try decode(missing), key)
            var null = original; null[key] = NSNull()
            XCTAssertThrowsError(try decode(null), key)
        }
    }
    func testEveryRequiredNestedFieldRejectsMissingAndNull() throws {
        let original = try object()
        let first = try XCTUnwrap((original["findings"] as? [[String: Any]])?.first)
        for key in ["rule_id", "outcome", "severity", "code", "message", "selection_ids"] {
            for null in [false, true] {
                var finding = first
                if null { finding[key] = NSNull() } else { finding.removeValue(forKey: key) }
                var report = original; report["findings"] = [finding]
                XCTAssertThrowsError(try decode(report), key)
            }
        }
        for key in ["passed", "failed", "unknown", "skipped"] {
            for null in [false, true] {
                var summary = try XCTUnwrap(original["summary"] as? [String: Any])
                if null { summary[key] = NSNull() } else { summary.removeValue(forKey: key) }
                var report = original; report["summary"] = summary
                XCTAssertThrowsError(try decode(report), key)
            }
        }
    }
    func testRejectsInvalidRootValues() throws {
        for (key, value) in [("schema_version", "2.0.0" as Any), ("id", "ab"),
                             ("build_revision", 0), ("dependency_graph_revision", 1.5),
                             ("ruleset_version", "1.0"), ("evaluated_at", "tomorrow"),
                             ("result", "success"), ("deployment_readiness", "valid"),
                             ("unexpected", true)] {
            var report = try object(); report[key] = value
            XCTAssertThrowsError(try decode(report), key)
        }
    }
    func testFindingValidationAndUnknownObjects() throws {
        let original = try object()
        let first = try XCTUnwrap((original["findings"] as? [[String: Any]])?.first)
        for (key, value) in [("outcome", "valid" as Any), ("severity", "critical"),
                             ("rule_id", "A.B"), ("code", "lowercase"), ("message", ""),
                             ("selection_ids", ["sel_a", "sel_a"]), ("remediation", NSNull()),
                             ("evidence", NSNull()), ("extra", true)] {
            var finding = first; finding[key] = value
            var report = original; report["findings"] = [finding]
            XCTAssertThrowsError(try decode(report), key)
        }
        for evidence in [["extra": true] as [String: Any], ["path": NSNull()],
                         ["path": "", "extra": true], ["path": "", "source_version": NSNull()]] {
            var finding = first; finding["evidence"] = [evidence]
            var report = original; report["findings"] = [finding]
            XCTAssertThrowsError(try decode(report))
        }
        for summary in [["passed": -1, "failed": 0, "unknown": 0, "skipped": 0],
                        ["passed": 0, "failed": 0, "unknown": 0, "skipped": 0, "extra": 0]] {
            var report = original; report["summary"] = summary
            XCTAssertThrowsError(try decode(report))
        }
    }
    func testPreservesUnknownResultAndArbitraryEvidenceIncludingNull() throws {
        var report = try object(); report["result"] = "indeterminate"; report["deployment_readiness"] = "blocked"
        var finding = try XCTUnwrap((report["findings"] as? [[String: Any]])?.first)
        finding["outcome"] = "unknown"
        finding["evidence"] = [["path": "", "observed": NSNull(), "expected": ["values": [true, "x", 1.25] as [Any]]], ["path": "absent"]]
        report["findings"] = [finding]
        let decoded = try decode(report)
        XCTAssertEqual(decoded.result, .indeterminate)
        XCTAssertEqual(decoded.findings[0].outcome, .unknown)
        XCTAssertEqual(decoded.findings[0].evidence?[0].observed, .null)
        XCTAssertNil(decoded.findings[0].evidence?[1].observed)
        XCTAssertEqual(decoded, try EvaluationReport.decode(JSONEncoder().encode(decoded)))
        // No invented summary/findings consistency rule: this DTO preserves the report.
        XCTAssertEqual(decoded.summary.passed, 41)
    }
    func testRejectsUnsupportedEvidenceNumbersBeforeRounding() throws {
        let base = try object()
        var finding = try XCTUnwrap((base["findings"] as? [[String: Any]])?.first)
        finding["evidence"] = [["path": "", "observed": "NUMBER_TOKEN"]]
        var report = base; report["findings"] = [finding]
        let template = String(data: try JSONSerialization.data(withJSONObject: report), encoding: .utf8)!
        for number in ["123456789012345678901234567890123456789012345", "1e999", "1e-999", "1.00000000000000000000000000000000000000000001"] {
            let data = Data(template.replacingOccurrences(of: "\"NUMBER_TOKEN\"", with: number).utf8)
            XCTAssertThrowsError(try EvaluationReport.decode(data)) { error in
                XCTAssertEqual(error as? EvaluationBoundaryError, .unsupportedNumber)
            }
        }
    }
    func testEvidenceNestingLimit() throws {
        var value: Any = "leaf"
        for _ in 0..<34 { value = [value] }
        var report = try object()
        var finding = try XCTUnwrap((report["findings"] as? [[String: Any]])?.first)
        finding["evidence"] = [["path": "", "observed": value]]; report["findings"] = [finding]
        XCTAssertThrowsError(try decode(report))
    }
    func testStrictGregorianTimestampValidation() throws {
        let invalid = [
            "2026-02-30T00:00:00Z", "2026-02-29T00:00:00Z", "1900-02-29T00:00:00Z",
            "2026-04-31T00:00:00Z", "2026-00-01T00:00:00Z", "2026-13-01T00:00:00Z",
            "2026-01-00T00:00:00Z", "0000-01-01T00:00:00Z", "2026-01-01T24:00:00Z",
            "2026-01-01T00:60:00Z", "2026-01-01T00:00:61Z", "2026-01-01T00:00:00+24:00",
            "2026-01-01T00:00:00-00:60", "2026-01-01T00:00:00Z trailing",
            "2016-12-31T23:59:60Z" // Valid leap second, explicitly unsupported client representation.
        ]
        for timestamp in invalid {
            var report = try object(); report["evaluated_at"] = timestamp
            XCTAssertThrowsError(try decode(report), timestamp)
        }
        for timestamp in ["2024-02-29T23:59:59Z", "2000-02-29T00:00:00Z",
                          "2026-01-31t01:02:03.123456789z", "2026-12-31T23:59:59-23:59",
                          "2026-01-01T00:00:00+05:30"] {
            var report = try object(); report["evaluated_at"] = timestamp
            XCTAssertEqual(try decode(report).evaluatedAt, timestamp)
        }
    }
    func testPayloadSizeBoundBeforeParsing() throws {
        let oversized = Data(repeating: 0xff, count: EvaluationReport.maximumPayloadBytes + 1)
        XCTAssertThrowsError(try EvaluationReport.decode(oversized)) { error in
            XCTAssertEqual(error as? EvaluationBoundaryError, .payloadTooLarge)
        }
        var atLimit = try fixture()
        atLimit.append(Data(repeating: 0x20, count: EvaluationReport.maximumPayloadBytes - atLimit.count))
        XCTAssertEqual(try EvaluationReport.decode(atLimit).result, .valid)
    }

    func testEvidenceExponentRoundTripsWithoutLosingPrecision() throws {
        var report = try object()
        var finding = try XCTUnwrap((report["findings"] as? [[String: Any]])?.first)
        finding["evidence"] = [["path": "", "observed": "NUMBER_TOKEN"]]
        report["findings"] = [finding]
        let template = String(data: try JSONSerialization.data(withJSONObject: report), encoding: .utf8)!
        for number in ["1e20", "1e-20", "1e100", "1e-100", "-123456789012345", "123456789012345e-100", "0.0000000000000000000000000000000000000000000"] {
            let data = Data(template.replacingOccurrences(of: "\"NUMBER_TOKEN\"", with: number).utf8)
            let decoded = try EvaluationReport.decode(data)
            XCTAssertEqual(decoded, try EvaluationReport.decode(JSONEncoder().encode(decoded)), number)
        }
    }

}
