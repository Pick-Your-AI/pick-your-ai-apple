import Foundation
import XCTest
@testable import PlannerCore

final class ExactDecimalFormatterTests: XCTestCase {
    func testArbitraryIntegerPrecisionAndSmallestFractionRemainExact() throws {
        let raw = String(repeating: "1234567890", count: 20) + ".000000000001"
        let amount = try ContractDecimal(raw)
        let formatter = try ExactDecimalFormatter(locale: Locale(identifier: "en_US"))
        XCTAssertEqual(formatter.string(from: amount), raw)
        XCTAssertEqual(amount.rawValue, raw)
    }

    func testDecimalCommaDoesNotInsertGroupingOrDiscardZeros() throws {
        let amount = try ContractDecimal("1234567890.123400000000")
        for identifier in ["de_DE", "fr_FR"] {
            let formatter = try ExactDecimalFormatter(locale: Locale(identifier: identifier))
            XCTAssertEqual(formatter.string(from: amount), "1234567890,123400000000", identifier)
        }
        XCTAssertEqual(amount.rawValue, "1234567890.123400000000")
    }

    func testArabicAndPersianNumeralsRetainAllDigitsAndTheirLogicalOrder() throws {
        let amount = try ContractDecimal("1234567890.001200000001")
        let arabic = try ExactDecimalFormatter(locale: Locale(identifier: "ar_EG@numbers=arab"))
        let persian = try ExactDecimalFormatter(locale: Locale(identifier: "fa_IR@numbers=arabext"))
        XCTAssertEqual(arabic.string(from: amount), "١٢٣٤٥٦٧٨٩٠٫٠٠١٢٠٠٠٠٠٠٠١")
        XCTAssertEqual(persian.string(from: amount), "۱۲۳۴۵۶۷۸۹۰٫۰۰۱۲۰۰۰۰۰۰۰۱")
        XCTAssertEqual(amount.rawValue, "1234567890.001200000001")
    }

    func testAbsentFractionAndExplicitZeroPrecisionStayDistinct() throws {
        let formatter = try ExactDecimalFormatter(locale: Locale(identifier: "ar_EG@numbers=arab"))
        for (raw, display) in [("0", "٠"), ("0.0", "٠٫٠"),
                               ("0.000000000000", "٠٫٠٠٠٠٠٠٠٠٠٠٠٠")] {
            XCTAssertEqual(formatter.string(from: try ContractDecimal(raw)), display)
        }
    }

    func testAlgorithmicNumeralsFailWithoutChangingDataAndAnotherLocaleRecovers() throws {
        let amount = try ContractDecimal("19.000000000001")
        let originalBytes = try JSONEncoder().encode(amount)
        for identifier in ["en_US@numbers=roman", "zh_Hans_CN@numbers=hans"] {
            XCTAssertThrowsError(try ExactDecimalFormatter(locale: Locale(identifier: identifier))) {
                XCTAssertEqual($0 as? ExactDecimalFormatter.FormattingError, .unsupportedNumberingSystem)
            }
        }
        let supported = try ExactDecimalFormatter(locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(supported.string(from: amount), "19,000000000001")
        XCTAssertEqual(try JSONEncoder().encode(amount), originalBytes)
    }

    func testCurrencyIdentityNeverSelectsSymbolsOrMinorUnitRounding() throws {
        let formatter = try ExactDecimalFormatter(locale: Locale(identifier: "de_DE"))
        let amount = try ContractDecimal("9007199254740993.123456789012")
        for code in ["USD", "JPY", "KWD", "XXX"] {
            let money = try ContractMoney(amount: amount, currency: code)
            let display = formatter.presentation(for: money)
            XCTAssertEqual(display.amount, "9007199254740993,123456789012")
            XCTAssertEqual(display.currencyCode, code)
            XCTAssertEqual(money.amount.rawValue, "9007199254740993.123456789012")
            XCTAssertEqual(money.currency, code)
        }
    }

    func testLocaleChangesCannotChangeArithmeticOrCanonicalEncoding() throws {
        let original = try ContractDecimal("9007199254740993.000000000001")
        let increment = try ContractDecimal("0.000000000001")
        let sum = original + increment
        let encoder = JSONEncoder()
        let originalBytes = try encoder.encode(original)
        let sumBytes = try encoder.encode(sum)
        XCTAssertEqual(sum.rawValue, "9007199254740993.000000000002")
        for identifier in ["en_US", "de_DE", "fr_FR", "en_IN", "ar_EG@numbers=arab", "fa_IR@numbers=arabext"] {
            let formatter = try ExactDecimalFormatter(locale: Locale(identifier: identifier))
            XCTAssertFalse(formatter.string(from: original).isEmpty)
            XCTAssertFalse(formatter.string(from: sum).isEmpty)
            XCTAssertEqual(original + increment, sum)
            XCTAssertEqual(try encoder.encode(original), originalBytes)
            XCTAssertEqual(try encoder.encode(sum), sumBytes)
        }
    }

    func testSeparateLocaleValuesAreSafeToShareAcrossTasks() async throws {
        let english = try ExactDecimalFormatter(locale: Locale(identifier: "en_US"))
        let german = try ExactDecimalFormatter(locale: Locale(identifier: "de_DE"))
        let amount = try ContractDecimal("123.450000000001")
        let results = await withTaskGroup(of: String.self) { group in
            for index in 0..<40 {
                group.addTask { (index.isMultiple(of: 2) ? english : german).string(from: amount) }
            }
            var values: [String] = []
            for await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(results.filter { $0 == "123.450000000001" }.count, 20)
        XCTAssertEqual(results.filter { $0 == "123,450000000001" }.count, 20)
    }
}
