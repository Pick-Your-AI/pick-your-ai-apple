import Foundation
import XCTest
@testable import PlannerTransfer

final class CapacityAnswerTests: XCTestCase {
    private struct Corpus: Decodable {
        let profile: String
        let referenceRevision: String
        let fields: [String]
        let cases: [Record]
    }
    private struct Record: Decodable {
        let name: String
        let field: String
        let path: String
        let originalBase64: Data
        let originalSha256: String
        let nativeSupported: Bool
        let readerValid: Bool
        let consumerValid: Bool
        let expected: Expected?
    }
    private struct Expected: Decodable {
        let state: String
        let source: String?
        let sourcePath: String?
        let assumption: Bool?
        let value: Node?
    }
    private struct Node: Decodable {
        let kind: String
        let text: String?
        let decimal: String?
        let flag: Bool?
        let items: [Node]?
        let members: [Member]?
    }
    private struct Member: Decodable { let key: String; let value: Node }

    private func corpus() throws -> Corpus {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "capacity-answer-conformance", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(Corpus.self, from: Data(contentsOf: url))
        XCTAssertEqual(result.profile, "apple-capacity-cd1-0.2-reader-preparation")
        XCTAssertEqual(result.referenceRevision, "449a29be1752a3c545709da466c7d53fc18fef73")
        XCTAssertEqual(result.cases.count, 249)
        XCTAssertEqual(Set(result.cases.map(\.name)).count, 249)
        XCTAssertEqual(Set(result.fields).count, 16)
        XCTAssertEqual(result.cases.filter(\.readerValid).count, 125)
        XCTAssertEqual(result.cases.filter(\.consumerValid).count, 123)
        XCTAssertEqual(result.cases.filter { $0.consumerValid && $0.nativeSupported }.count, 120)
        XCTAssertEqual(result.cases.filter { $0.readerValid != $0.consumerValid }.map(\.name),
                       ["positive-integer-token-1.0", "positive-integer-token-1e0"])
        return result
    }

    private func compare(_ actual: CapacityAnswerValue, _ expected: Node, _ name: String) throws {
        switch expected.kind {
        case "null": XCTAssertEqual(actual.kind, .null, name)
        case "boolean": XCTAssertEqual(actual.boolean, expected.flag, name)
        case "integer":
            XCTAssertEqual(actual.kind, .number, name)
            XCTAssertTrue(actual.isIntegerToken, name)
            XCTAssertEqual(actual.originalNumberToken, expected.decimal, name)
        case "string":
            XCTAssertEqual(actual.kind, .string, name)
            XCTAssertEqual(actual.string.map { Data($0.utf8) }, expected.text.map { Data($0.utf8) }, name)
        case "array":
            let values = try XCTUnwrap(actual.array, name)
            let expected = try XCTUnwrap(expected.items, name)
            XCTAssertEqual(values.count, expected.count, name)
            for (value, node) in zip(values, expected) { try compare(value, node, name) }
        case "object":
            let members = try XCTUnwrap(expected.members, name)
            XCTAssertEqual(actual.objectKeys?.map { Data($0.utf8) }, members.map { Data($0.key.utf8) }, name)
            for member in members {
                try compare(XCTUnwrap(actual.value(forExactKey: member.key), name), member.value, name)
            }
        default: XCTFail("Unexpected expected value kind in \(name)")
        }
    }

    func testPinnedCD1AttributionCorpusPreservesOriginalBytesAndExactObservations() throws {
        for row in try corpus().cases {
            do {
                let index = try CapacityAnswerIndex(originalBytes: row.originalBase64,
                                                    declaredSHA256: row.originalSha256)
                let field = try XCTUnwrap(CapacityAnswerField(rawValue: row.field), row.name)
                let answer = try index.read(path: row.path, as: field)
                guard row.consumerValid && row.nativeSupported else {
                    XCTFail("Admitted unsupported selected profile case: \(row.name)")
                    continue
                }
                let expected = try XCTUnwrap(row.expected, row.name)
                XCTAssertEqual(index.originalBytes, row.originalBase64, row.name)
                XCTAssertEqual(index.originalSHA256, row.originalSha256, row.name)
                XCTAssertEqual(answer.originalSHA256, row.originalSha256, row.name)
                XCTAssertEqual(answer.field, field, row.name)
                XCTAssertEqual(Data(answer.requestedPath.utf8), Data(row.path.utf8), row.name)
                XCTAssertEqual(answer.state.rawValue, expected.state, row.name)
                XCTAssertEqual(answer.assumption, expected.assumption, row.name)
                XCTAssertEqual(answer.presetSource.map { Data($0.utf8) },
                               expected.source.map { Data($0.utf8) }, row.name)
                XCTAssertEqual(answer.sourcePath.map { Data($0.utf8) },
                               expected.sourcePath.map { Data($0.utf8) }, row.name)
                if let value = expected.value {
                    try compare(XCTUnwrap(answer.value, row.name), value, row.name)
                } else {
                    XCTAssertNil(answer.value, row.name)
                }
            } catch {
                XCTAssertFalse(row.consumerValid && row.nativeSupported, "\(row.name): \(error)")
                XCTAssertTrue(error is CapacityError, row.name)
                if row.consumerValid && !row.nativeSupported {
                    XCTAssertTrue([CapacityError.unsupportedNativeLimit, .unsupportedNativeNumber,
                                   .unsupportedNativeUnicode].contains(error as? CapacityError ?? .invalidShape), row.name)
                }
            }
        }
    }

    func testDeclaredByteIdentityRejectsChangedWhitespaceAndRecoversWithoutNormalization() throws {
        let row = try XCTUnwrap(corpus().cases.first { $0.name == "text-provided" })
        var altered = row.originalBase64
        altered.append(32)
        XCTAssertThrowsError(try CapacityAnswerIndex(originalBytes: altered, declaredSHA256: row.originalSha256)) {
            XCTAssertEqual($0 as? CapacityError, .declaredBytesMismatch)
        }
        let independent = try CapacityAnswerIndex(originalBytes: altered)
        XCTAssertNotEqual(independent.originalSHA256, row.originalSha256)
        XCTAssertEqual(independent.originalBytes, altered)
        let recovered = try CapacityAnswerIndex(originalBytes: row.originalBase64, declaredSHA256: row.originalSha256)
        altered.removeAll()
        XCTAssertEqual(recovered.originalBytes, row.originalBase64)
        XCTAssertEqual(try recovered.read(path: row.path, as: .text).state, .provided)
        for malformed in ["", "a", String(repeating: "A", count: 64), String(repeating: "0", count: 63)] {
            XCTAssertThrowsError(try CapacityAnswerIndex(originalBytes: row.originalBase64, declaredSHA256: malformed)) {
                XCTAssertEqual($0 as? CapacityError, .invalidIdentity)
            }
        }
    }

    func testCausalPathsKeepDirectAncestorWithheldAndAbsentDistinct() throws {
        let cases = try corpus().cases
        for (name, cause) in [
            ("text-provided", CapacityAnswerCause.direct),
            ("ancestor-child", .ancestor),
            ("ancestor-missing", .ancestor),
            ("withheld-descendant-uses-lexical-source-path", .withheldDescendant),
            ("empty-answer-map-is-missing", .none),
            ("empty-key-direct", .direct),
            ("empty-key-ancestor", .ancestor),
        ] {
            let row = try XCTUnwrap(cases.first { $0.name == name })
            let index = try CapacityAnswerIndex(originalBytes: row.originalBase64)
            let answer = try index.read(path: row.path, as: .text)
            XCTAssertEqual(answer.cause, cause, name)
            if answer.state != .provided {
                XCTAssertNil(answer.assumption, name)
                XCTAssertNil(answer.presetSource, name)
            }
        }
    }

    func testNativeAdmissionLimitsAndExactLargeCountsStaySeparateFromCanonicalPolicy() throws {
        let tooLarge = Data(repeating: 32, count: 512 * 1024 + 1)
        XCTAssertThrowsError(try CapacityAnswerIndex(originalBytes: tooLarge)) {
            XCTAssertEqual($0 as? CapacityError, .unsupportedNativeLimit)
        }
        let records = (0...CapacityAnswerIndex.maximumAnswers).map {
            "\"/value\($0)\":{\"state\":\"missing\"}"
        }.joined(separator: ",")
        let many = Data(("{\"x_t0_answer_states\":{\"proposal_version\":\"cd1-0.2\",\"answers\":{" + records + "}}}").utf8)
        XCTAssertThrowsError(try CapacityAnswerIndex(originalBytes: many)) {
            XCTAssertEqual($0 as? CapacityError, .unsupportedNativeLimit)
        }
        let values = try corpus().cases
        let row = try XCTUnwrap(values.first { $0.name == "positive-integer-token-1208925819614629174706176" })
        let index = try CapacityAnswerIndex(originalBytes: row.originalBase64)
        XCTAssertEqual(try index.read(path: "/value", as: .positiveInteger).value?.originalNumberToken,
                       "1208925819614629174706176")
        let largest = try CapacityByteCount(decimal: String(repeating: "9", count: 4096))
        XCTAssertEqual(largest.decimal.count, 4096)
        XCTAssertThrowsError(try largest.adding(CapacityByteCount(decimal: "1"))) {
            XCTAssertEqual($0 as? CapacityError, .unsupportedNativeLimit)
        }
        XCTAssertEqual(try CapacityByteCount(decimal: "3").adding(CapacityByteCount(decimal: "4")).decimal, "7")
    }

    func testAutomaticDescriptionsDoNotExposeExplicitOriginalAttribution() throws {
        let row = try XCTUnwrap(corpus().cases.first { $0.name == "ancestor-child" })
        let index = try CapacityAnswerIndex(originalBytes: row.originalBase64)
        let answer = try index.read(path: row.path, as: .text)
        XCTAssertEqual(answer.presetSource, "preset:parent")
        XCTAssertEqual(answer.value?.string, "retained")
        for text in [String(describing: index), String(reflecting: index),
                     String(describing: answer), String(reflecting: answer),
                     String(describing: try XCTUnwrap(answer.value)), String(reflecting: try XCTUnwrap(answer.value))] {
            XCTAssertFalse(text.contains("preset:parent"))
            XCTAssertFalse(text.contains("retained"))
            XCTAssertFalse(text.contains("/parent"))
        }
        XCTAssertEqual(String(describing: CapacityError.declaredBytesMismatch), "CapacityError.declaredBytesMismatch")
    }
}
