import Foundation
import XCTest

/// Inspect a running native application through public XCTest UI automation.
/// Expected strings stay in the test process; the host receives only a group ID.
@MainActor
final class EvidenceRenderingTests: XCTestCase {
    private struct VectorBundle: Decodable {
        let lock: [String: String]
        let schema: String
        let cases: [Vector]
    }
    private struct Vector: Decodable {
        let id: String
        let valid: Bool
        let payloadJSON: String
        let outcome: String?
        let severity: String?
        let visibleText: [String]
    }

    private func vectors() throws -> [Vector] {
        let url = try XCTUnwrap(Bundle(for: EvidenceRenderingTests.self).url(forResource: "evidence-vectors", withExtension: "json"))
        let bundle = try JSONDecoder().decode(VectorBundle.self, from: Data(contentsOf: url))
        XCTAssertEqual(bundle.lock["contract_version"], "1.0.0")
        XCTAssertEqual(bundle.schema, "evaluation-report.schema.json")
        XCTAssertEqual(bundle.cases.count, 37)
        XCTAssertEqual(Set(bundle.cases.map(\.id)).count, 37)
        return bundle.cases
    }

    private func launch(_ group: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--evidence-group", group]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "The actual native host must run in the foreground.")
        #if os(macOS)
        // WindowGroup can launch with only its menu bar. Acquire a real window
        // through its standard command before inspecting the selected fixture.
        if app.windows.count == 0 {
            let fileMenu = app.menuBars.menuBarItems["File"]
            XCTAssertTrue(fileMenu.exists, "The native host must expose its File menu.")
            XCTAssertTrue(fileMenu.isEnabled, "The native host must allow opening its File menu.")
            fileMenu.click()
            let newWindow = fileMenu.menus.menuItems["New Window"]
            XCTAssertTrue(newWindow.exists, "The native host must expose New Window.")
            XCTAssertTrue(newWindow.isEnabled, "The native host must allow a new fixture window.")
            if app.windows.count == 0 {
                newWindow.click()
            } else {
                app.typeKey(.escape, modifierFlags: [])
            }
        }
        #endif
        XCTAssertFalse(app.staticTexts["evidence-harness-error"].exists)
        XCTAssertTrue(app.staticTexts["evidence-harness-case"].waitForExistence(timeout: 10))
        return app
    }

    func testSharedEvidenceVectorsRenderReportedOutcomesSeverityAndEveryPresenceState() throws {
        let accepted = try vectors().filter(\.valid)
        XCTAssertEqual(accepted.count, 28)
        let app = launch("shared")
        defer { app.terminate() }
        for (index, vector) in accepted.enumerated() {
            var expected = vector.visibleText
            if let outcome = vector.outcome, let severity = vector.severity {
                expected += ["Reported rule outcome: \(outcome)", "Severity: \(severity)"]
            } else {
                XCTAssertEqual(vector.id, "evidence/no-findings")
            }
            let text = try assertRendered(app, id: vector.id, index: index, total: accepted.count, contains: expected)
            for other in ["pass", "fail", "unknown", "skipped"] where other != vector.outcome {
                XCTAssertFalse(text.contains("Reported rule outcome: \(other)"), vector.id)
            }
            for other in ["error", "warning", "info"] where other != vector.severity {
                XCTAssertFalse(text.contains("Severity: \(other)"), vector.id)
            }
            if index + 1 < accepted.count { next(app) }
        }
    }

    func testReportedPassAndReadyRemainSeparateFromMissingEvidenceOnCompactAndWideViews() throws {
        let vector = try XCTUnwrap(try vectors().first { $0.id == "evidence/reported-pass-without-support" })
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(vector.payloadJSON.utf8)) as? [String: Any])
        let buildID = try XCTUnwrap(report["build_id"] as? String)
        let revision = try XCTUnwrap(report["build_revision"] as? Int)
        let snapshot = try XCTUnwrap(report["catalog_snapshot_id"] as? String)
        let expected = vector.visibleText + ["Reported compatibility: valid", "Reported readiness: ready",
            "Missing or unknown observations do not establish compatibility.",
            "Build: \(buildID), revision \(revision)", "Catalog snapshot: \(snapshot)"]
        let app = launch("report-size")
        defer { app.terminate() }
        for (index, width) in [375, 820].enumerated() {
            try assertRendered(app, id: "reported-pass-width-\(width)", index: index, total: 2, contains: expected)
            if index == 0 { next(app) }
        }
    }

    func testClaimGradesRequireTheirExistingInspectionAndIndependentSupportInputs() throws {
        let inputs = [
            ("not-inspected", "verified", "Unverified", "Source claim has not been inspected."),
            ("support-without-inspection", "verified", "Unverified", "Source claim has not been inspected."),
            ("inspected", "verified", "Source checked", "Inspected source: synthetic:claim"),
            ("independent", "unverified", "Independently verified", "Inspected source: synthetic:claim"),
            ("user-supplied", "user_supplied", "User supplied", "Source claim has not been inspected."),
            ("estimated", "estimated", "Estimated", "Source claim has not been inspected."),
            ("unavailable", "verified", "Unavailable", "Source claim is unavailable."),
        ]
        let app = launch("claims")
        defer { app.terminate() }
        for (index, input) in inputs.enumerated() {
            let (id, original, grade, source) = input
            let text = try assertRendered(app, id: id, index: index, total: inputs.count, contains: [
                "Evidence quality: \(grade)", "Original recorded status: \(original)", source,
                "Component: synthetic.component", "Version: 1.0.0", "Retained snapshot: snapshot.retained",
                "Facts remain pinned to this version."])
            if grade != "Independently verified" { XCTAssertFalse(text.contains("Evidence quality: Independently verified"), id) }
            if index + 1 < inputs.count { next(app) }
        }
    }

    func testCorrectionAndFreshnessNoticesPreserveRetainedIdentityAndRequireARecheck() throws {
        let common = ["Version: 1.0.0", "Retained snapshot: snapshot.retained", "Current-state facts as of 2024-01-02"]
        let inputs = [
            ("newer-release", ["A newer version is available. The retained selection has not changed."]),
            ("newer-snapshot", ["A newer snapshot is available. Review the evidence for this selection."]),
            ("correction", ["Evidence quality: Unverified", "Original recorded status: verified",
                            "Selected evidence changed. A recheck is required."]),
        ]
        let app = launch("notices")
        defer { app.terminate() }
        for (index, input) in inputs.enumerated() {
            let text = try assertRendered(app, id: input.0, index: index, total: inputs.count, contains: common + input.1)
            if input.0 == "correction" { XCTAssertFalse(text.contains("Evidence quality: Independently verified")) }
            if index + 1 < inputs.count { next(app) }
        }
    }

    func testCaptureDateLocaleChangesPreserveGregorianDayAndRetainedEvidence() throws {
        let inputs: [(String, String, [String])] = [
            ("date-us-honolulu", "2024-01-02", ["January 2, 2024"]),
            ("date-gb-kiritimati", "2024-01-02", ["2 January 2024"]),
            ("date-de-berlin", "2024-01-02", ["2. Januar 2024"]),
            ("date-ar-calendar", "2024-01-02", ["٢", "يناير", "٢٠٢٤"]),
            ("date-th-calendar", "2024-01-02", ["มกราคม", "2024"]),
            ("date-gregorian-switch", "1582-10-10", ["October 10, 1582"]),
            ("date-first-year", "0001-01-01", ["January 1, 1"]),
            ("date-leap-day", "2000-02-29", ["29 February 2000"]),
            ("date-last-year", "9999-12-31", ["December 31, 9999"]),
            ("date-locale-recovery", "2024-01-02", ["January 2, 2024"]),
        ]
        let app = launch("dates")
        defer { app.terminate() }
        for (index, input) in inputs.enumerated() {
            let correction = input.0 == "date-locale-recovery"
            let expected = ["Capture date (Gregorian):", "Current-state facts as of \(input.1)",
                "Original recorded status: verified", "Component: synthetic.component", "Version: 1.0.0",
                "Retained snapshot: snapshot.retained", "Inspected source: synthetic:claim",
                "Evidence quality: \(correction ? "Unverified" : "Source checked")"] + input.2
            let text = try assertRendered(app, id: input.0, index: index, total: inputs.count, contains: expected)
            let label = try renderedStaticText(app.staticTexts["claim-capture-date"], file: #filePath, line: #line)
                .joined(separator: "\n")
            for component in input.2 { XCTAssertTrue(label.contains(component), "\(input.0): \(label)") }
            XCTAssertFalse(text.contains("Evidence quality: Independently verified"))
            XCTAssertFalse(text.contains("Facts remain pinned to this version."))
            if input.0 == "date-th-calendar" { XCTAssertFalse(label.contains("2567")) }
            if correction {
                XCTAssertTrue(text.contains("Selected evidence changed. A recheck is required."))
            } else {
                XCTAssertFalse(text.contains("Selected evidence changed. A recheck is required."))
            }
            if index + 1 < inputs.count { next(app) }
        }
    }

    func testVisibleBuildAnalysisNeverRendersRetainedReportsForOtherRevisionsOrRetiredRequests() throws {
        let modes = ["current", "foreign-visible", "pending-retry", "cancelled", "failed", "disconnected", "cleared"]
        let app = launch("analysis-state")
        defer { app.terminate() }
        for (index, mode) in modes.enumerated() {
            XCTAssertTrue(app.staticTexts["analysis-scenario-ready"].waitForExistence(timeout: 10))
            let expected: [String]
            if mode == "current" {
                expected = ["Analysis for the visible build revision", "Build: build.fixture.1, revision 1",
                            "Reported compatibility: valid", "Reported readiness: ready",
                            "Missing or unknown observations do not establish compatibility."]
            } else if mode == "pending-retry" {
                expected = ["Analysis pending for this build revision",
                            "Compatibility and readiness remain unknown until a matching report arrives."]
            } else {
                expected = ["Current analysis unavailable", "Compatibility and readiness are unknown."]
            }
            let text = try assertRendered(app, id: "analysis-\(mode)", index: index, total: modes.count,
                contains: expected + ["Synthetic analysis scenario ready: \(mode)"])
            if mode != "current" {
                for forbidden in ["Reported compatibility:", "Reported readiness:", "Build: build.fixture.1",
                                  "Analysis for the visible build revision"] {
                    XCTAssertFalse(text.contains(forbidden), "\(mode): retained report leaked into a noncurrent presentation")
                }
                XCTAssertFalse(app.scrollViews["evaluation-report"].exists, mode)
            }
            if index + 1 < modes.count { next(app) }
        }
    }

    private func next(_ app: XCUIApplication) {
        let button = app.buttons["evidence-harness-next"]
        XCTAssertTrue(button.isEnabled)
        #if os(macOS)
        button.click()
        #else
        button.tap()
        #endif
    }

    @discardableResult
    private func assertRendered(_ app: XCUIApplication, id: String, index: Int, total: Int,
                                contains expected: [String], file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let current = app.staticTexts["evidence-harness-case"]
        #if os(macOS)
        let ready = expectation(for: NSPredicate(format: "value == %@", id), evaluatedWith: current)
        #else
        let ready = expectation(for: NSPredicate(format: "label == %@", id), evaluatedWith: current)
        #endif
        wait(for: [ready], timeout: 10)
        let position = app.staticTexts["evidence-harness-position"]
        #if os(macOS)
        let rawPosition = position.value
        let positionText = try XCTUnwrap(rawPosition as? String,
            "The native case position must have a String value; actual: \(String(describing: rawPosition))", file: file, line: line)
        #else
        let positionText = position.label
        #endif
        XCTAssertEqual(positionText, "Case \(index + 1) of \(total)", file: file, line: line)
        let content = app.descendants(matching: .any).matching(identifier: "evidence-harness-content").firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 10), file: file, line: line)
        var labels = Set<String>()
        var previous = Set<String>()
        var unchanged = 0
        var settled = false
        // Read the real application's static-text elements. Scroll to materialize
        // lazy/offscreen report content; no expected text is sent to the host.
        for _ in 0..<16 {
            let currentLabels = Set(try content.descendants(matching: .staticText).allElementsBoundByIndex.flatMap {
                try renderedStaticText($0, file: file, line: line)
            })
            labels.formUnion(currentLabels)
            unchanged = currentLabels == previous ? unchanged + 1 : 0
            previous = currentLabels
            let text = labels.sorted().joined(separator: "\n")
            // Continue after finding the positive labels so later materialized
            // text also participates in the negative outcome/grade assertions.
            if !text.isEmpty && expected.allSatisfy({ text.contains($0) }) && unchanged >= 2 {
                settled = true
                break
            }
            #if os(macOS)
            // The report's vertical viewport can cover the harness's horizontal
            // viewport. Keep collecting all content, but scroll the owning view.
            let reports = content.scrollViews.matching(identifier: "evaluation-report")
            let reportCount = reports.count
            XCTAssertLessThanOrEqual(reportCount, 1,
                "The native fixture must expose at most one evaluation-report scroll view.", file: file, line: line)
            let scrollTarget = reportCount == 1 ? reports.element : content
            scrollTarget.scroll(byDeltaX: 0, deltaY: -450)
            #else
            content.swipeUp(velocity: .slow)
            #endif
        }
        let text = labels.sorted().joined(separator: "\n")
        XCTAssertTrue(settled, "The bounded native content scan did not settle: \(id)", file: file, line: line)
        XCTAssertFalse(text.isEmpty, "No actual native accessibility text was rendered: \(id)", file: file, line: line)
        for value in expected {
            XCTAssertTrue(text.contains(value), "\(id): missing \(value); actual native text: \(text)", file: file, line: line)
        }
        return text
    }

    private func renderedStaticText(_ element: XCUIElement, file: StaticString, line: UInt) throws -> [String] {
        #if os(macOS)
        // Actual AppKit snapshots expose body strings as values and some
        // headings as labels. Preserve both observations for all assertions.
        let label = element.label
        let rawValue = element.value
        var strings = label.isEmpty ? [] : [label]
        if let rawValue {
            let value = try XCTUnwrap(rawValue as? String,
                "Static text \(element.identifier) has a non-String value (\(type(of: rawValue))); label: \(label); value: \(rawValue)",
                file: file, line: line)
            if !value.isEmpty { strings.append(value) }
        }
        _ = try XCTUnwrap(strings.first,
            "Static text \(element.identifier) has no usable label or String value; label: \(label); value: \(String(describing: rawValue))",
            file: file, line: line)
        return strings
        #else
        return [element.label]
        #endif
    }
}
