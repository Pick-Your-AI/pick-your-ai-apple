import Foundation
import XCTest
@testable import PlannerCore

final class ContractDecimalTests: XCTestCase {
    func testRejectsMalformedAndNonStringValues() throws {
        for value in ["", "-1", "+1", "01", "00.1", ".1", "1.", "1e2", "NaN", "Infinity", " 1", "1 ", "1\n", "١", "１", "1.0000000000000", "1..0"] {
            XCTAssertThrowsError(try ContractDecimal(value), value)
            let encoded = try JSONEncoder().encode(value)
            XCTAssertThrowsError(try JSONDecoder().decode(ContractDecimal.self, from: encoded), value)
        }
        for json in ["1", "1.25", "null", "true", "{}", "[]"] {
            XCTAssertThrowsError(try JSONDecoder().decode(ContractDecimal.self, from: Data(json.utf8)))
        }
    }

    func testRoundTripPreservesOriginalSpelling() throws {
        for value in ["0", "0.000000000000", "1.2300", "9007199254740993", String(repeating: "9", count: 200) + ".123456789012"] {
            let original = try ContractDecimal(value)
            let encoded = try JSONEncoder().encode(original)
            XCTAssertEqual(try JSONDecoder().decode(String.self, from: encoded), value)
            XCTAssertEqual(try JSONDecoder().decode(ContractDecimal.self, from: encoded).rawValue, value)
        }
    }

    func testNumericEqualityAndHashingIgnoreFractionalSpelling() throws {
        let values = try ["1", "1.0", "1.000000000000"].map { try ContractDecimal($0) }
        XCTAssertEqual(Set(values).count, 1)
        XCTAssertEqual(try ContractDecimal("0.000"), try ContractDecimal("0"))
    }

    func testComparisonPreservesUnboundedPrecision() throws {
        let pairs = [("9007199254740992", "9007199254740993"),
                     ("99999999999999999999999999999999999999", "100000000000000000000000000000000000000"),
                     ("1.000000000001", "1.000000000002"), ("0.9", "1"), ("0", "0.000000000001")]
        for (lower, higher) in pairs {
            let low = try ContractDecimal(lower), high = try ContractDecimal(higher)
            XCTAssertLessThan(low, high)
            XCTAssertGreaterThan(high, low)
            XCTAssertNotEqual(low, high)
        }
    }

    func testExactAdditionCarriesAcrossIntegerAndFraction() throws {
        let cases = [("0.1", "0.2", "0.3"), ("0", "0.000", "0"),
                     ("1.20", "2.030", "3.23"), ("0.999999999999", "0.000000000001", "1"),
                     (String(repeating: "9", count: 200), "1", "1" + String(repeating: "0", count: 200)),
                     ("9007199254740992", "1.000000000001", "9007199254740993.000000000001")]
        for (left, right, expected) in cases {
            let lhs = try ContractDecimal(left), rhs = try ContractDecimal(right)
            XCTAssertEqual((lhs + rhs).rawValue, expected)
            XCTAssertEqual(lhs + rhs, rhs + lhs)
            XCTAssertEqual(try lhs + rhs + ContractDecimal("0"), lhs + rhs)
        }
    }
}
