import Foundation
import XCTest
@testable import PlannerCore

final class EvidenceCaptureDatePresentationTests: XCTestCase {
    private func localized(_ raw: String, _ locale: String = "en_US") throws -> String {
        let date = try EvidenceCaptureDate(raw)
        let result = date.presentation(locale: Locale(identifier: locale))
        XCTAssertEqual(result.canonicalDate, raw)
        XCTAssertEqual(date.rawValue, raw)
        return try XCTUnwrap(result.localizedDate, "The admitted date must have an exact localized display: \(raw), \(locale)")
    }

    func testEnglishAndGermanDateOrdersRetainTheSameCanonicalDay() throws {
        XCTAssertEqual(try localized("2024-01-02", "en_US"), "January 2, 2024")
        XCTAssertEqual(try localized("2024-01-02", "en_GB"), "2 January 2024")
        XCTAssertEqual(try localized("2024-01-02", "de_DE"), "2. Januar 2024")
    }

    func testArabicNumberingLeavesTheASCIIRecordUnchanged() throws {
        let text = try localized("2024-01-02", "ar_EG@numbers=arab")
        XCTAssertTrue(text.contains("٢"))
        XCTAssertTrue(text.contains("يناير"))
        XCTAssertTrue(text.contains("٢٠٢٤"))
        XCTAssertFalse(text.contains("2024-01-02"))
    }

    func testLocaleCalendarPreferencesCannotReplaceTheGregorianYear() throws {
        for locale in ["en_US@calendar=buddhist", "en_US@calendar=japanese", "th_TH@calendar=buddhist"] {
            let text = try localized("2024-01-02", locale)
            XCTAssertTrue(text.contains("2024"), "\(locale): \(text)")
            XCTAssertFalse(text.contains("2567"), "A Buddhist year cannot replace the Gregorian capture year.")
            XCTAssertFalse(text.localizedCaseInsensitiveContains("reiwa"))
        }
    }

    func testDatesAcrossTheHistoricalGregorianSwitchAreNotNormalized() throws {
        for day in [4, 5, 10, 14, 15, 16] {
            let raw = "1582-10-\(day < 10 ? "0" : "")\(day)"
            XCTAssertEqual(try localized(raw), "October \(day), 1582")
        }
    }

    func testProlepticLeapDaysAndBothAdmittedYearLimits() throws {
        for (raw, expected) in [
            ("0001-01-01", "January 1, 1"),
            ("1500-02-28", "February 28, 1500"),
            ("1600-02-29", "February 29, 1600"),
            ("1900-02-28", "February 28, 1900"),
            ("2000-02-29", "February 29, 2000"),
            ("2400-02-29", "February 29, 2400"),
            ("9999-12-31", "December 31, 9999"),
        ] {
            XCTAssertEqual(try localized(raw), expected, raw)
        }
    }

    func testAlternatingLocalesCannotReuseAnotherLocalesLabel() throws {
        let date = try EvidenceCaptureDate("2024-01-02")
        let original = date.presentation(locale: Locale(identifier: "en_US"))
        for _ in 0..<4 {
            XCTAssertEqual(try localized(date.rawValue, "en_GB"), "2 January 2024")
            XCTAssertEqual(try localized(date.rawValue, "de_DE"), "2. Januar 2024")
            XCTAssertEqual(date.presentation(locale: Locale(identifier: "en_US")), original)
        }
        XCTAssertEqual(date.rawValue, "2024-01-02")
    }

    func testFormattingCannotChangeTheEvidenceIdentityGradeOrRecheckState() throws {
        let identity = try RetainedEvidenceIdentity(componentID: "synthetic.component", componentVersion: "1.0.0",
                                                    catalogSnapshotID: "snapshot.retained")
        let source = try SourceInspectionReceipt(sourceReference: "synthetic:claim", inspectionReference: "synthetic:read",
                                                 retrievalMethod: "synthetic fixture")
        let date = try EvidenceCaptureDate("2024-01-02")
        let original = EvidencePresentation(identity: identity, originalVerificationStatus: .verified,
            source: .inspected(source), freshness: .currentState(captureDate: date))
        let correction = original.receiving(.correction(identity))
        for locale in ["en_US", "en_GB", "de_DE", "ar_EG@numbers=arab", "th_TH@calendar=buddhist"] {
            _ = try localized(date.rawValue, locale)
            XCTAssertEqual(original.identity, identity)
            XCTAssertEqual(original.source, .inspected(source))
            XCTAssertEqual(original.freshness, .currentState(captureDate: date))
            XCTAssertEqual(original.displayGrade, .sourceChecked)
            XCTAssertEqual(original.reviewRequirement, .none)
            XCTAssertEqual(correction.originalVerificationStatus, .verified)
            XCTAssertEqual(correction.displayGrade, .unverified)
            XCTAssertEqual(correction.reviewRequirement, .recheckRequired)
            XCTAssertEqual(correction.freshness, original.freshness)
        }
    }
}
