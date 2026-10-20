import Foundation
import XCTest

/// Native observations of the production CostCoverageView. The separate host
/// receives a synthetic group ID, never expected labels or test outcomes.
@MainActor
final class CostRenderingTests: XCTestCase {
    private let common = ["Synthetic fixture — not real pricing", "Estimates are not exact quotes."]

    func testMostExpensiveRateRemovalKeepsBudgetUnknownAndRecoveryVisible() throws {
        let app = launch("rate-removal")
        defer { app.terminate() }
        let complete = ["Reported complete estimate", "Reported total", "USD 110",
                        "Above estimated budget", "The eligible 30-day estimate is above the limit."]
        let partial = ["Partial cost estimate", "Reported amount for priced costs", "USD 20",
                       "Selections without rates (1)", "sel.expensive", "Budget status unknown",
                       "Cost coverage is incomplete or unknown."]
        for (index, id) in ["rate-complete", "rate-removed", "rate-recovered"].enumerated() {
            let isPartial = index == 1
            let text = try assertRendered(app, id: id, index: index, total: 3,
                contains: common + (isPartial ? partial : complete) + ["30-day limit: USD 100"],
                money: [isPartial ? "USD 20" : "USD 110", "USD 100"])
            XCTAssertFalse(text.contains("Within estimated budget"), id)
            if isPartial {
                XCTAssertFalse(text.contains("Reported complete estimate"), id)
                XCTAssertFalse(text.contains("Above estimated budget"), id)
                XCTAssertFalse(text.contains("Reported total"), id)
            } else {
                XCTAssertFalse(text.contains("Partial cost estimate"), id)
                XCTAssertFalse(text.contains("sel.expensive"), id)
            }
            if index < 2 { next(app) }
        }
    }

    func testMissingZeroExpiredUnsupportedMixedAndStaleCostsRemainQualified() throws {
        let inputs: [(String, [String], String?)] = [
            ("absent", ["Cost estimate unavailable", "Amount unknown"], nil),
            ("missing-total", ["Cost coverage unknown", "Amount unknown", "No total amount is available."], nil),
            ("partial-zero", ["Partial cost estimate", "sel.expensive"], "USD 0.0000"),
            ("unknown-zero", ["Cost coverage unknown"], "USD 0.0000"),
            ("complete-zero", ["Reported complete estimate", "Within estimated budget",
                              "This is an estimate, not a price guarantee."], "USD 0.0000"),
            ("unsupported", ["Partial cost estimate", "Unsupported usage meters (1)",
                             "meter.synthetic.unsupported"], "USD 20"),
            ("expired", ["Reported complete estimate", "Rate conditions have expired",
                         "The supplied rate conditions have expired."], "USD 110"),
            ("unverified", ["Reported complete estimate", "Rate applicability is unverified",
                            "Rate applicability has not been established."], "USD 110"),
            ("mixed-currency", ["Cost estimate needs review",
                "Estimate currency: USD; reported amount currency: EUR",
                "The estimate and budget currencies do not match. No currency conversion is applied."], "EUR 110"),
            ("stale", ["Cost estimate unavailable for this revision", "Amount unknown",
                       "The estimate does not match the selected build and revision."], nil),
        ]
        let app = launch("boundaries")
        defer { app.terminate() }
        for (index, input) in inputs.enumerated() {
            let (id, expected, amount) = input
            let budget = id == "complete-zero" ? [] : ["Budget status unknown"]
            let text = try assertRendered(app, id: id, index: index, total: inputs.count,
                contains: common + expected + budget + ["30-day limit: USD 100"],
                money: [amount, "USD 100"].compactMap { $0 })
            if id != "complete-zero" {
                XCTAssertFalse(text.contains("Within estimated budget"), id)
                XCTAssertFalse(text.contains("Above estimated budget"), id)
            }
            if amount == nil {
                XCTAssertFalse(text.contains("USD 0"), id)
                XCTAssertFalse(text.contains("USD 110"), id)
                XCTAssertFalse(text.contains("Reported total"), id)
            }
            if id == "partial-zero" || id == "unknown-zero" || id == "unsupported" {
                XCTAssertFalse(text.contains("Reported complete estimate"), id)
            }
            if id == "stale" {
                for hidden in ["sel.stale", "meter.stale", "Rates reported current"] {
                    XCTAssertFalse(text.contains(hidden), id)
                }
            }
            if index + 1 < inputs.count { next(app) }
        }
    }

    func testLargeTextCompactAndWideLayoutsRetainExactMoneyAndBoundedMissingCosts() throws {
        let inputs: [(String, [String], [String])] = [
            ("compact-exact", ["Reported complete estimate", "Above estimated budget"], [
                "USD 123456789012345678901234567890.123456789013",
                "USD 123456789012345678901234567890.123456789012"]),
            ("compact-partial", ["Partial cost estimate", "sel.expensive", "Budget status unknown"], ["USD 20", "USD 100"]),
            ("wide-partial-details", ["Partial cost estimate", "Budget status unknown", "Unsupported usage meters (22)",
                "Showing the first 20 of 22. These missing costs prevent a conclusive budget result."]
                + (0..<20).map { String(format: "meter.synthetic.%02d", $0) }, ["USD 20", "USD 100"]),
            ("wide-recovered", ["Reported complete estimate", "Above estimated budget"], ["USD 110", "USD 100"]),
        ]
        let app = launch("layout")
        defer { app.terminate() }
        for (index, input) in inputs.enumerated() {
            let text = try assertRendered(app, id: input.0, index: index, total: inputs.count,
                contains: common + input.1 + input.2, money: input.2)
            XCTAssertFalse(text.contains("Within estimated budget"), input.0)
            if input.0.contains("partial") {
                XCTAssertFalse(text.contains("Reported complete estimate"), input.0)
                XCTAssertFalse(text.contains("Above estimated budget"), input.0)
            }
            if input.0 == "wide-partial-details" {
                XCTAssertFalse(text.contains("meter.synthetic.20"))
                XCTAssertFalse(text.contains("meter.synthetic.21"))
            }
            if index + 1 < inputs.count { next(app) }
        }
    }

    private func launch(_ group: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--cost-group", group]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        #if os(macOS)
        if app.windows.count == 0 {
            let fileMenu = app.menuBars.menuBarItems["File"]
            XCTAssertTrue(fileMenu.exists)
            XCTAssertTrue(fileMenu.isEnabled)
            fileMenu.click()
            let newWindow = fileMenu.menus.menuItems["New Window"]
            XCTAssertTrue(newWindow.exists)
            XCTAssertTrue(newWindow.isEnabled)
            if app.windows.count == 0 { newWindow.click() }
            else { app.typeKey(.escape, modifierFlags: []) }
        }
        #endif
        XCTAssertFalse(app.staticTexts["cost-harness-error"].exists)
        XCTAssertTrue(app.staticTexts["cost-harness-case"].waitForExistence(timeout: 10))
        return app
    }

    private func next(_ app: XCUIApplication) {
        let button = app.buttons["cost-harness-next"]
        XCTAssertTrue(button.isEnabled)
        #if os(macOS)
        button.click()
        #else
        button.tap()
        #endif
    }

    private func assertRendered(_ app: XCUIApplication, id: String, index: Int, total: Int,
                                contains expected: [String], money: [String],
                                file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let current = app.staticTexts["cost-harness-case"]
        #if os(macOS)
        let ready = expectation(for: NSPredicate(format: "value == %@", id), evaluatedWith: current)
        #else
        let ready = expectation(for: NSPredicate(format: "label == %@", id), evaluatedWith: current)
        #endif
        wait(for: [ready], timeout: 10)
        let position = app.staticTexts["cost-harness-position"]
        #if os(macOS)
        let positionText = try XCTUnwrap(position.value as? String, file: file, line: line)
        #else
        let positionText = position.label
        #endif
        XCTAssertEqual(positionText, "Case \(index + 1) of \(total)", file: file, line: line)
        let matches = app.scrollViews.matching(identifier: "cost-harness-content")
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(matches.count, 1, file: file, line: line)
        let content = matches.element
        XCTAssertGreaterThan(content.frame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(content.frame.height, 0, file: file, line: line)
        var labels = Set<String>()
        var previous = Set<String>()
        var unchanged = 0
        var settled = false
        for _ in 0..<16 {
            let staticLabels = Set(try content.descendants(matching: .staticText).allElementsBoundByIndex.flatMap {
                try renderedStaticText($0, file: file, line: line)
            })
            #if os(macOS)
            // Combined SwiftUI accessibility elements expose their rendered
            // amount, budget and missing-cost text as Other labels on macOS.
            // Keep the query inside the verified production viewport; empty
            // container labels cannot supply any expected content.
            let combinedLabels = content.descendants(matching: .other).allElementsBoundByIndex
                .map(\.label).filter { !$0.isEmpty }
            let currentLabels = staticLabels.union(combinedLabels)
            #else
            let currentLabels = staticLabels
            #endif
            labels.formUnion(currentLabels)
            unchanged = currentLabels == previous ? unchanged + 1 : 0
            previous = currentLabels
            let text = labels.sorted().joined(separator: "\n")
            if !text.isEmpty && expected.allSatisfy({ text.contains($0) }) && unchanged >= 2 {
                settled = true
                break
            }
            #if os(macOS)
            content.scroll(byDeltaX: 0, deltaY: -450)
            #else
            let window = app.windows.firstMatch
            XCTAssertTrue(window.exists, file: file, line: line)
            let windowFrame = window.frame
            let intersection = content.frame.intersection(windowFrame)
            let visible = try XCTUnwrap(
                !intersection.isNull && !intersection.isEmpty ? intersection : nil,
                "The native cost viewport has no visible window intersection: \(id)",
                file: file, line: line)
            // The explicit 820-point fixture can extend beyond a compact
            // window. Both drag endpoints stay inside the observed portion.
            let origin = window.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: visible.midX - windowFrame.minX,
                dy: visible.minY + visible.height * 0.8 - windowFrame.minY))
            let finish = origin.withOffset(CGVector(dx: visible.midX - windowFrame.minX,
                dy: visible.minY + visible.height * 0.2 - windowFrame.minY))
            start.press(forDuration: 0.05, thenDragTo: finish)
            #endif
        }
        let text = labels.sorted().joined(separator: "\n")
        XCTAssertTrue(settled, "Bounded native cost scan did not settle: \(id); actual native text: \(text)",
                      file: file, line: line)
        XCTAssertFalse(text.isEmpty, "No native cost text was rendered: \(id)", file: file, line: line)
        for value in expected {
            XCTAssertTrue(text.contains(value), "\(id): missing \(value); actual native text: \(text)", file: file, line: line)
        }
        for value in money {
            // A prefix such as USD 20 must not accept a different USD 200 amount.
            let pattern = "(?<![A-Z0-9.])" + NSRegularExpression.escapedPattern(for: value) + "(?![0-9.])"
            XCTAssertNotNil(text.range(of: pattern, options: .regularExpression),
                "\(id): exact recorded amount missing: \(value); actual native text: \(text)", file: file, line: line)
        }
        return text
    }

    private func renderedStaticText(_ element: XCUIElement, file: StaticString, line: UInt) throws -> [String] {
        #if os(macOS)
        let label = element.label
        let rawValue = element.value
        var strings = label.isEmpty ? [] : [label]
        if let rawValue {
            let value = try XCTUnwrap(rawValue as? String,
                "Native static text has a non-String value: \(element.identifier)", file: file, line: line)
            if !value.isEmpty { strings.append(value) }
        }
        _ = try XCTUnwrap(strings.first,
            "Native static text has no readable label or value: \(element.identifier)", file: file, line: line)
        return strings
        #else
        return [element.label]
        #endif
    }
}
