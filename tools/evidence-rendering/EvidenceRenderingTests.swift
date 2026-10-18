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
            let text = assertRendered(app, id: vector.id, index: index, total: accepted.count, contains: expected)
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
            assertRendered(app, id: "reported-pass-width-\(width)", index: index, total: 2, contains: expected)
            if index == 0 { next(app) }
        }
    }

    func testClaimGradesRequireTheirExistingInspectionAndIndependentSupportInputs() {
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
            let text = assertRendered(app, id: id, index: index, total: inputs.count, contains: [
                "Evidence quality: \(grade)", "Original recorded status: \(original)", source,
                "Component: synthetic.component", "Version: 1.0.0", "Retained snapshot: snapshot.retained",
                "Facts remain pinned to this version."])
            if grade != "Independently verified" { XCTAssertFalse(text.contains("Evidence quality: Independently verified"), id) }
            if index + 1 < inputs.count { next(app) }
        }
    }

    func testCorrectionAndFreshnessNoticesPreserveRetainedIdentityAndRequireARecheck() {
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
            let text = assertRendered(app, id: input.0, index: index, total: inputs.count, contains: common + input.1)
            if input.0 == "correction" { XCTAssertFalse(text.contains("Evidence quality: Independently verified")) }
            if index + 1 < inputs.count { next(app) }
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
                                contains expected: [String], file: StaticString = #filePath, line: UInt = #line) -> String {
        let current = app.staticTexts["evidence-harness-case"]
        let ready = expectation(for: NSPredicate(format: "label == %@", id), evaluatedWith: current)
        wait(for: [ready], timeout: 10)
        XCTAssertEqual(app.staticTexts["evidence-harness-position"].label, "Case \(index + 1) of \(total)", file: file, line: line)
        let content = app.descendants(matching: .any).matching(identifier: "evidence-harness-content").firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 10), file: file, line: line)
        var labels = Set<String>()
        var previous = Set<String>()
        var unchanged = 0
        var settled = false
        // Read the real application's static-text elements. Scroll to materialize
        // lazy/offscreen report content; no expected label is sent to the host.
        for _ in 0..<16 {
            let currentLabels = Set(content.descendants(matching: .staticText).allElementsBoundByIndex.map(\.label))
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
            content.scroll(byDeltaX: 0, deltaY: -450)
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
}
