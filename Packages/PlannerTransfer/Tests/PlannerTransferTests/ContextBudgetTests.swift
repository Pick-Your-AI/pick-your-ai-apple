import Foundation
import XCTest
@testable import PlannerTransfer

final class ContextBudgetTests: XCTestCase {
    private struct Corpus: Decodable {
        let profile: String
        let referenceRevision: String
        let cases: [RecordCase]
        let numeric: [NumberCase]
        let limits: [LimitCase]
    }
    private struct RecordCase: Decodable {
        let name: String
        let bindingBase64: Data
        let answersBase64: Data
        let activeScopeJson: String?
        let enabled: Bool?
        let evidenceEligible: Bool?
        let nativeSupported: Bool
        let canonicalValid: Bool
        let expected: Expected?
    }
    private struct Expected: Decodable {
        let outcome: String
        let mayNotFit: Bool
        let reason: String
        let checks: [ExpectedCheck]
        let answers: [ExpectedAnswer]
    }
    private struct ExpectedCheck: Decodable { let name: String; let lower: String; let upper: String }
    private struct ExpectedAnswer: Decodable {
        let field: String
        let state: String
        let value: [String: String]?
        let source: String?
        let sourcePath: String?
    }
    private struct NumberCase: Decodable { let token: String; let canonicalValid: Bool }
    private struct LimitCase: Decodable {
        let native: String?
        let `extension`: String?
        let evidenced: Bool
        let ceiling: String?
        let expected: String?
    }

    private func corpus() throws -> Corpus {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "context-budget-conformance", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let value = try decoder.decode(Corpus.self, from: Data(contentsOf: url))
        XCTAssertEqual(value.profile, "apple-context-cd11-0.1-preparation")
        XCTAssertEqual(value.referenceRevision, "449a29be1752a3c545709da466c7d53fc18fef73")
        XCTAssertEqual(value.cases.count, 137)
        XCTAssertEqual(value.numeric.count, 331)
        XCTAssertEqual(value.limits.count, 6)
        XCTAssertEqual(Set(value.cases.map(\.name)).count, value.cases.count)
        return value
    }

    func testPinnedContextRecordsRetainBytesStatesSourcesAndExactOutcomes() throws {
        for row in try corpus().cases {
            do {
                let record = try ContextBudgetRecord.decode(binding: row.bindingBase64, answers: row.answersBase64)
                let scope = try row.activeScopeJson.map { try ContextBudgetScope.decode(Data($0.utf8)) }
                guard row.canonicalValid && row.nativeSupported else {
                    XCTFail("Admitted rejected context case: \(row.name)")
                    continue
                }
                let expected = try XCTUnwrap(row.expected, row.name)
                let actual = record.evaluate(activeScope: scope, enabled: row.enabled, evidenceEligible: row.evidenceEligible)
                XCTAssertEqual(record.originalBytes, row.bindingBase64, row.name)
                XCTAssertEqual(record.answerBytes, row.answersBase64, row.name)
                XCTAssertEqual(actual.outcome.rawValue, expected.outcome, row.name)
                XCTAssertEqual(actual.mayNotFit, expected.mayNotFit, row.name)
                XCTAssertEqual(actual.reason, expected.reason, row.name)
                XCTAssertEqual(actual.checks.count, expected.checks.count, row.name)
                for (check, oracle) in zip(actual.checks, expected.checks) {
                    XCTAssertEqual(check.name, oracle.name, row.name)
                    XCTAssertEqual(check.lower.rawValue, oracle.lower, row.name)
                    XCTAssertEqual(check.upper.rawValue, oracle.upper, row.name)
                }
                XCTAssertEqual(actual.answers.count, 7, row.name)
                XCTAssertEqual(expected.answers.count, 7, row.name)
                for oracle in expected.answers {
                    let field = try XCTUnwrap(ContextBudgetField(rawValue: oracle.field), row.name)
                    let answer = try XCTUnwrap(actual.answers[field], row.name)
                    XCTAssertEqual(answer.field, field, row.name)
                    XCTAssertEqual(answer.state.rawValue, oracle.state, row.name)
                    XCTAssertEqual(answer.requestedPath, "/context/" + oracle.field, row.name)
                    XCTAssertEqual(answer.source.map { Array($0.utf8) }, oracle.source.map { Array($0.utf8) }, row.name)
                    XCTAssertEqual(answer.sourcePath.map { Array($0.utf8) }, oracle.sourcePath.map { Array($0.utf8) }, row.name)
                    let supplied: [String: String]?
                    switch answer.value {
                    case .semantics(let value)?: supplied = ["semantics": value.rawValue]
                    case .count(let value)?: supplied = ["count": value.decimal]
                    case .inputRange(let lower, let upper)?: supplied = ["lower": lower.decimal, "upper": upper.decimal]
                    case nil: supplied = nil
                    }
                    XCTAssertEqual(supplied, oracle.value, row.name)
                }
            } catch {
                XCTAssertFalse(row.canonicalValid && row.nativeSupported, "\(row.name): \(error)")
                XCTAssertTrue(error is ContextBudgetError, "Unexpected error type: \(row.name)")
                if row.canonicalValid && !row.nativeSupported {
                    XCTAssertTrue([ContextBudgetError.unsupportedUnicode, .unsupportedLimit, .unsupportedNumber]
                        .contains(error as? ContextBudgetError ?? .invalidShape), row.name)
                }
            }
        }
    }

    func testOriginalCD1NumericTokenAdmissionMatchesPinnedOracle() throws {
        for row in try corpus().numeric {
            let wire = Data(("{\"unused\":" + row.token + "}").utf8)
            do {
                _ = try ContextWire.parse(wire)
                XCTAssertTrue(row.canonicalValid, "Admitted unsupported original token: \(row.token)")
            } catch {
                XCTAssertFalse(row.canonicalValid, "Rejected exact supported token: \(row.token): \(error)")
            }
        }
    }

    func testEffectiveLimitRequiresExplicitExtensionEvidenceAndRetainsNativeAbsence() throws {
        for row in try corpus().limits {
            let native = try row.native.map { try ContextTokenCount(decimal: $0) }
            let extended = try row.`extension`.map { try ContextTokenCount(decimal: $0) }
            let ceiling = try row.ceiling.map { try ContextTokenCount(decimal: $0) }
            XCTAssertEqual(ContextTokenCount.effectiveLimit(native: native, extensionLimit: extended,
                           extensionEvidenced: row.evidenced, runtimeCeiling: ceiling)?.decimal, row.expected)
        }
    }

    func testExactUTF8ObjectKeysAndScopeVersionsAvoidCanonicalEquivalence() throws {
        let wire = try ContextWire.parse(Data("{\"caf\u{00e9}\":1,\"cafe\u{0301}\":2}".utf8))
        guard case .object(let fields) = wire else { return XCTFail("Expected object") }
        XCTAssertEqual(fields.count, 2)
        let first = try ContextBudgetReference(id: "model.synthetic", version: "caf\u{00e9}")
        let second = try ContextBudgetReference(id: "model.synthetic", version: "cafe\u{0301}")
        XCTAssertNotEqual(first, second)
        XCTAssertThrowsError(try ContextWire.parse(Data("{\"key\":1,\"k\\u0065y\":2}".utf8))) {
            XCTAssertEqual($0 as? ContextBudgetError, .duplicateKey)
        }
    }

    func testNativeLimitsRejectBeforeConsumptionAndValidRecoveryStillWorks() throws {
        let tooLarge = Data(repeating: 32, count: 512 * 1024 + 1)
        let tooDeep = Data((String(repeating: "[", count: 48) + "0" + String(repeating: "]", count: 48)).utf8)
        let tooMany = Data(("[" + Array(repeating: "0", count: 16_384).joined(separator: ",") + "]").utf8)
        let tooLong = Data(String(repeating: "9", count: 4097).utf8)
        for bytes in [tooLarge, tooDeep, tooMany, tooLong] {
            XCTAssertThrowsError(try ContextWire.parse(bytes)) { XCTAssertEqual($0 as? ContextBudgetError, .unsupportedLimit) }
        }
        let row = try XCTUnwrap(corpus().cases.first { $0.name == "original-pinned-bytes" })
        let record = try ContextBudgetRecord.decode(binding: row.bindingBase64, answers: row.answersBase64)
        XCTAssertEqual(record.evaluate(activeScope: record.scope, enabled: true, evidenceEligible: true).outcome, .fail)
        let largest = try ContextTokenCount(decimal: String(repeating: "9", count: 4096))
        XCTAssertEqual(largest.decimal.count, 4096)
        XCTAssertThrowsError(try ContextTokenCount(decimal: "1.0"))
        XCTAssertThrowsError(try ContextTokenCount(decimal: "-1"))
    }

    func testRetainedCopiesAndAutomaticDescriptionsDoNotLeakOriginalSources() throws {
        let row = try XCTUnwrap(corpus().cases.first { $0.name == "provided-parent-retains-source-and-missing-optional" })
        var original = row.answersBase64
        let record = try ContextBudgetRecord.decode(binding: row.bindingBase64, answers: original)
        original.removeAll()
        XCTAssertEqual(record.answerBytes, row.answersBase64)
        let result = record.evaluate(activeScope: record.scope, enabled: true, evidenceEligible: true)
        let answer = try XCTUnwrap(result.answers[.inputTokens])
        XCTAssertEqual(answer.source, "synthetic:parent")
        let descriptions = [String(describing: record), String(reflecting: record),
                            String(describing: answer), String(reflecting: answer),
                            String(describing: record.scope), String(reflecting: record.scope),
                            String(describing: result), String(reflecting: result)]
        for text in descriptions {
            XCTAssertFalse(text.contains("synthetic:parent"))
            XCTAssertFalse(text.contains("selection.synthetic-model"))
            XCTAssertFalse(text.contains("settings_sha256"))
        }
        XCTAssertEqual(String(describing: ContextBudgetError.answerBytesMismatch), "ContextBudgetError.answerBytesMismatch")
    }
}
