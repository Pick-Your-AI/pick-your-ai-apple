import XCTest
import PlannerTransfer
@testable import PlannerUI

final class ComparisonFieldTextTests: XCTestCase {
    func testUserTextCannotImpersonateMissingPrivateEmptyOrTypedValues() {
        let values: [ComparedFieldValue] = [.absent, .hidden, .value(.string("")),
            .value(.bool(true)), .value(.bool(false)), .value(.null),
            .value(.number(0)), .value(.array([])), .value(.object([:]))]
        for value in values {
            let visible = ComparisonFieldText.display(value)
            XCTAssertNotEqual(ComparisonFieldText.display(.value(.string(visible))), visible)
        }
        XCTAssertEqual(Set(values.map(ComparisonFieldText.display)).count, values.count)
    }

    func testOriginalSentinelStringsRemainExplicitText() {
        for text in ["Not set", "Hidden for privacy", "Empty text", "True", "False", "Null value"] {
            XCTAssertEqual(ComparisonFieldText.display(.value(.string(text))), "Text: " + text)
        }
    }

    func testMultilineTextIsPreservedWithoutTruncation() {
        let text = "first line\nsecond line\n" + String(repeating: "long setting ", count: 1_000)
        XCTAssertEqual(ComparisonFieldText.display(.value(.string(text))), "Text: " + text)
    }
}
