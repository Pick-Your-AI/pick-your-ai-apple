import UIKit
import XCTest

/// This closed Debug collection contains fictional declarations only. Every
/// selection below is made through the mounted catalog/detail controls.
final class ComponentComparisonJourneyTests: XCTestCase {
    private let fixtureHash = "7d5e39193254ad2830f74628aec91a8d95bd782329550f0438d717e4e92dd69e"
    private let recorded = "Recorded declaration; not independently assessed"
    private let missing = "Unknown: not recorded"
    private let notApplicable = "Not applicable: this field is not defined for this component kind"

    @MainActor
    func testComparisonRetainsExactUnitsVersionsAndLimitRecovery() throws {
        try exerciseComparison(accessibilitySize: false)
    }

    @MainActor
    func testComparisonAtAccessibilitySizeRetainsNavigationAndCompleteValues() throws {
        try exerciseComparison(accessibilitySize: true)
    }

    @MainActor
    private func exerciseComparison(accessibilitySize: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--comparison-examples-v1"]
        if accessibilitySize { app.launchArguments.append("--comparison-accessibility3") }
        let tablet = UIDevice.current.userInterfaceIdiom == .pad
        XCUIDevice.shared.orientation = tablet ? .landscapeLeft : .portrait
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        app.launch()
        tap(app.buttons.matching(NSPredicate(format: "label == %@", "Demo catalog")).firstMatch)
        let clear = app.buttons["catalogClearFilters"]
        reveal(clear, in: app, container: "catalogList")
        if clear.isEnabled { tap(clear) }
        let search = app.textFields["catalogSearch"]
        reveal(search, in: app, container: "catalogList")
        tap(search)
        search.typeText("FICTIONAL\n")
        wait(app.keyboards.firstMatch, predicate: "exists == false")
        let sort = app.segmentedControls["catalogSort"].buttons["Kind"]
        reveal(sort, in: app, container: "catalogList")
        tap(sort)
        let kinds = app.buttons["catalogKinds"]
        reveal(kinds, in: app, container: "catalogList")
        tap(kinds)
        for kind in ["compute_profile", "storage"] {
            let row = app.switches["catalogKind-\(kind)"]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            XCTAssertEqual(row.value as? String, "0")
            let native = row.descendants(matching: .switch)
            XCTAssertEqual(native.count, 1)
            XCTAssertTrue(row.frame.contains(native.element.frame))
            tap(native.element)
            wait(native.element, predicate: "value == '1'")
            wait(row, predicate: "value == '1'")
        }
        tap(app.buttons["catalogKindFiltersDone"])
        assertText(app, id: "catalogResultCount", expected: "Showing 5 of 5 results", container: "catalogList")

        addVersion(1, count: 1, in: app)
        addVersion(2, count: 2, in: app)
        openComparison(app, count: 2)
        assertSelections([1, 2], in: app)
        capture(app, checkpoint: "two-selected")
        closeComparison(app)
        assertFilters(app)
        addVersion(3, count: 3, in: app)
        openComparison(app, count: 3)
        capture(app, checkpoint: "three-selected")
        closeComparison(app)
        addVersion(4, count: 4, in: app)
        openComparison(app, count: 4)
        let selected = assertSelections([1, 2, 3, 4], in: app)

        selectSection("Recorded specifications", in: app)
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription])
        let scroll = app.descendants(matching: .any).matching(identifier: "componentComparisonScroll").firstMatch
        let expectedLayout = !accessibilitySize && tablet ? "componentComparisonAlignedFields" : "componentComparisonStackedFields"
        let layout = app.descendants(matching: .any).matching(identifier: expectedLayout).firstMatch
        XCTAssertTrue(layout.waitForExistence(timeout: 10))
        if !accessibilitySize && tablet { XCTAssertGreaterThanOrEqual(scroll.frame.width, 900) }
        if !tablet { XCTAssertLessThan(scroll.frame.width, 900) }
        let disk = assertCells(app, section: "Recorded specifications", field: "disk_gb",
                               states: [recorded, missing, notApplicable, notApplicable], values: ["0", nil, nil, nil])
        let network = assertCells(app, section: "Recorded specifications", field: "network_gbps",
                                  states: [missing, recorded, notApplicable, notApplicable], values: [nil, "0", nil, nil])
        let region = assertCells(app, section: "Recorded specifications", field: "region",
                                 states: [recorded, recorded, "Unknown: explicitly recorded as unknown", "Unknown: empty text recorded"],
                                 values: ["\"fixture-east\"", "\"fixture-west\"", "\"unknown\"", "\"\""])
        capture(app, checkpoint: "four-exact-states")

        selectSection("Evidence and additional conditions", in: app)
        let units = ["milliseconds/request", "seconds/request", "tokens/second", "requests/second"]
        var conditions: [[String: Any]] = []
        for index in 0..<4 {
            let id = "componentComparisonValue-Evidence and additional conditions/extensions-\(index)"
            let text = app.staticTexts[id]
            reveal(text, in: app)
            let data = try XCTUnwrap(text.label.data(using: .utf8))
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let entry = try XCTUnwrap(object["x_comparison_example"] as? [String: Any])
            XCTAssertEqual(entry["unit"] as? String, units[index])
            XCTAssertEqual(entry["amount"] as? Int, index == 0 ? 1000 : 1)
            XCTAssertEqual(entry["offering"] as? String, "unqualified-fixture-v\(index + 1)")
            XCTAssertEqual(entry["effective_at"] as? String, "2026-10-19T00:00:00Z")
            XCTAssertEqual(entry["workload"] as? String, "fictional-128-input-tokens")
            XCTAssertEqual(entry["region"] as? String, ["fixture-east", "fixture-west", "unknown", ""][index])
            conditions.append(entry)
        }
        assertText(app, id: "componentComparisonDifference-Evidence and additional conditions/extensions",
                   expected: "Recorded declarations differ")
        try app.performAccessibilityAudit(for: [.textClipped, .sufficientElementDescription])
        capture(app, checkpoint: "complete-unit-conditions")

        selectSection("Identity and conditions", in: app)
        let differences = app.buttons["componentComparisonDifferences"]
        reveal(differences, in: app)
        tap(differences)
        XCTAssertEqual(differences.value as? String, "Differences only")
        XCTAssertFalse(app.staticTexts["componentComparisonValue-Identity and conditions/status-0"].exists)
        assertText(app, id: "componentComparisonDifference-Identity and conditions/version", expected: "Recorded declarations differ")
        reveal(differences, in: app)
        tap(differences)
        XCTAssertEqual(differences.value as? String, "All fields")
        assertCells(app, section: "Identity and conditions", field: "billing_class",
                    states: Array(repeating: "Unknown: explicitly recorded as unknown", count: 4),
                    values: Array(repeating: "\"unknown\"", count: 4))
        selectSection("License declarations", in: app)
        assertCells(app, section: "License declarations", field: "commercial_use_allowed",
                    states: Array(repeating: recorded, count: 4), values: ["false", "true", "false", "false"])
        let inspect = app.buttons["componentComparisonInspect-0"]
        reveal(inspect, in: app)
        tap(inspect)
        let complete = app.staticTexts["componentComparisonCompleteRecord"]
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        let item = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(complete.label.data(using: .utf8))) as? [String: Any])
        XCTAssertEqual(item["id"] as? String, "cat.comparison.compute")
        XCTAssertEqual(item["version"] as? String, "fixture-v1")
        XCTAssertEqual((item["spec"] as? [String: Any])?["disk_gb"] as? Int, 0)
        let provenance = try XCTUnwrap(item["provenance"] as? [[String: Any]])
        XCTAssertEqual(provenance.count, 1)
        XCTAssertEqual(provenance[0]["verification_status"] as? String, "unverified")
        XCTAssertEqual(provenance[0]["checked_at"] as? String, "2026-10-19T00:00:00Z")
        XCTAssertNil(provenance[0]["source_url"])
        XCTAssertEqual(provenance[0]["notes"] as? String,
                       "FICTIONAL COMPARISON EXAMPLE. These declarations are not measurements, vendor facts, rates or evidence of support.")
        capture(app, checkpoint: "complete-record")
        tap(app.buttons["componentComparisonInspectionDone"])
        wait(complete, predicate: "exists == false")
        closeComparison(app)
        assertFilters(app)

        addVersion(5, count: 4, rejected: true, in: app)
        openComparison(app, count: 4)
        XCTAssertEqual(assertSelections([1, 2, 3, 4], in: app), selected)
        capture(app, checkpoint: "fifth-rejected")
        let remove = app.buttons["componentComparisonRemove-1"]
        reveal(remove, in: app)
        tap(remove)
        assertText(app, id: "componentComparisonCount", expected: "3 of 4 components selected")
        closeComparison(app)
        addVersion(5, count: 4, in: app)
        openComparison(app, count: 4)
        let recovered = assertSelections([1, 3, 4, 5], in: app)
        capture(app, checkpoint: "remove-and-recover")
        let clearComparison = app.buttons["componentComparisonClear"]
        reveal(clearComparison, in: app)
        tap(clearComparison)
        assertText(app, id: "componentComparisonCount", expected: "0 of 4 components selected")
        XCTAssertTrue(app.staticTexts["componentComparisonEmpty"].exists)
        XCTAssertFalse(app.buttons["componentComparisonInspect-0"].exists)
        capture(app, checkpoint: "empty-recovery")
        // Each audit covers only its actual visible checkpoint. The retained
        // full hierarchies and recordings remain necessary for broader review.
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription])
        closeComparison(app)
        assertFilters(app)

        let matrix: [String: Any] = [
            "schema_version": 1, "scenario": accessibilitySize ? "accessibility3" : "default",
            "fixture_sha256": fixtureHash, "catalog_id": "catalog.comparison.examples.v1",
            "catalog_revision": 1, "captured_at": "2026-10-19T00:00:00Z",
            "device": tablet ? "ipad" : "iphone", "layout": expectedLayout,
            "dynamic_type": accessibilitySize ? "accessibility3-subtree" : "system-default",
            "selected": selected, "recovered": recovered, "disk_gb": disk, "network_gbps": network,
            "region": region, "conditions": conditions, "final_count": app.buttons["catalogOpenComparison"].label,
            "query": search.value as? String ?? "", "kind_sort_selected": sort.isSelected,
            "active_kinds": app.staticTexts["catalogActiveKinds"].label,
            "accessibility_audits": ["visible-field-navigation:hitRegion,sufficientElementDescription",
                                      "visible-conditions:textClipped,sufficientElementDescription",
                                      "visible-empty-controls:hitRegion,sufficientElementDescription"]
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: matrix, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "comparison-matrix"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func addVersion(_ version: Int, count: Int, rejected: Bool = false, in app: XCUIApplication) {
        let id = version <= 2 ? "compute" : version <= 4 ? "storage" : "control"
        let row = app.buttons["catalogItem-cat.comparison.\(id)-fixture-v\(version)"]
        reveal(row, in: app, container: "catalogList")
        tap(row)
        XCTAssertTrue(app.staticTexts["catalogDetailReady"].waitForExistence(timeout: 10))
        assertText(app, id: "catalogDetailHash", expected: fixtureHash, container: "catalogDetailsForm")
        let add = app.buttons["catalogDetailAddToComparison"]
        reveal(add, in: app, container: "catalogDetailsForm")
        tap(add)
        assertText(app, id: "catalogDetailComparisonCount", expected: "\(count) of 4 components selected", container: "catalogDetailsForm")
        if rejected {
            assertText(app, id: "catalogDetailComparisonNotice",
                       expected: "A comparison holds two to four components. Remove one before adding another.", container: "catalogDetailsForm")
        }
        tap(app.navigationBars["Component details"].buttons["Done"])
        wait(app.staticTexts["catalogDetailReady"], predicate: "exists == false")
    }

    @MainActor
    private func openComparison(_ app: XCUIApplication, count: Int) {
        let open = app.buttons["catalogOpenComparison"]
        reveal(open, in: app, container: "catalogList")
        tap(open)
        assertText(app, id: "componentComparisonCount", expected: "\(count) of 4 components selected")
    }

    @MainActor
    private func closeComparison(_ app: XCUIApplication) {
        tap(app.buttons["componentComparisonDone"])
        wait(app.buttons["componentComparisonDone"], predicate: "exists == false")
    }

    @MainActor
    private func assertFilters(_ app: XCUIApplication) {
        let search = app.textFields["catalogSearch"]
        reveal(search, in: app, container: "catalogList")
        XCTAssertEqual(search.value as? String, "FICTIONAL")
        XCTAssertTrue(app.segmentedControls["catalogSort"].buttons["Kind"].isSelected)
        XCTAssertEqual(app.staticTexts["catalogActiveKinds"].label, "Compute Profile, Storage")
    }

    @discardableResult @MainActor
    private func assertSelections(_ versions: [Int], in app: XCUIApplication) -> [[String: String]] {
        versions.enumerated().map { index, version in
            let name = "\"FICTIONAL Comparison fixture-v\(version)\""
            let value = "\"fixture-v\(version)\""
            let id = "\"cat.comparison.\(version <= 2 ? "compute" : version <= 4 ? "storage" : "control")\""
            // Reveal the real pin once per card; read every exact metadata
            // label through the accessibility tree without rescrolling the same
            // card for each adjacent value. Matrix cells are revealed separately.
            reveal(app.staticTexts["componentComparisonPin-\(index)"], in: app)
            for (prefix, expected) in [
                ("componentComparisonName", name), ("componentComparisonID", id),
                ("componentComparisonVersion", value), ("componentComparisonPin", "\"\(fixtureHash)\""),
                ("componentComparisonCatalogID", "\"catalog.comparison.examples.v1\""),
                ("componentComparisonCatalogVersion", "Revision 1; schema 1.0.0"),
                ("componentComparisonCatalogCaptured", "\"2026-10-19T00:00:00Z\"")
            ] {
                let matches = app.staticTexts.matching(identifier: "\(prefix)-\(index)")
                XCTAssertEqual(matches.count, 1)
                XCTAssertEqual(matches.element.label, expected)
            }
            return ["name": app.staticTexts["componentComparisonName-\(index)"].label,
                    "id": app.staticTexts["componentComparisonID-\(index)"].label,
                    "version": app.staticTexts["componentComparisonVersion-\(index)"].label,
                    "sha256": app.staticTexts["componentComparisonPin-\(index)"].label]
        }
    }

    @discardableResult @MainActor
    private func assertCells(_ app: XCUIApplication, section: String, field: String,
                             states: [String], values: [String?]) -> [[String: Any]] {
        states.indices.map { index in
            let key = "\(section)/\(field)-\(index)"
            let state = app.staticTexts["componentComparisonState-\(key)"]
            reveal(state, in: app)
            XCTAssertEqual(state.label, states[index])
            let value = app.staticTexts["componentComparisonValue-\(key)"]
            if let expected = values[index] {
                reveal(value, in: app)
                XCTAssertEqual(value.label, expected)
            } else { XCTAssertFalse(value.exists) }
            return ["state": state.label, "value": values[index] == nil ? NSNull() : value.label as Any]
        }
    }

    @MainActor
    private func selectSection(_ section: String, in app: XCUIApplication) {
        let control = app.buttons["componentComparisonSection-\(section)"]
        reveal(control, in: app)
        tap(control)
        XCTAssertEqual(control.value as? String, "Selected section")
        XCTAssertTrue(control.isSelected)
    }

    @MainActor
    private func assertText(_ app: XCUIApplication, id: String, expected: String, container: String = "componentComparisonScroll") {
        let matches = app.staticTexts.matching(identifier: id)
        let element = matches.element
        reveal(element, in: app, container: container)
        XCTAssertEqual(matches.count, 1)
        wait(element, predicate: NSPredicate(format: "label == %@", expected).predicateFormat)
        XCTAssertEqual(element.label, expected)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, container: String = "componentComparisonScroll") {
        let scroll = app.descendants(matching: .any).matching(identifier: container).firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            XCTAssertTrue(scroll.isHittable)
            if element.exists {
                let target = element.frame, bounds = scroll.frame
                guard target.midY.isFinite, bounds.midY.isFinite, target.height > 0, bounds.height > 0 else {
                    XCTFail("Comparison scroll geometry is unavailable"); return
                }
                let above = target.midY < bounds.midY
                if abs(target.midY - bounds.midY) > bounds.height {
                    if above { scroll.swipeDown(velocity: .slow) } else { scroll.swipeUp(velocity: .slow) }
                } else {
                    let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.65 : 0.35))
                    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
                }
            } else { scroll.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reveal \(element.identifier)")
    }

    @MainActor
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        wait(element, predicate: "hittable == true AND enabled == true")
        element.tap()
    }

    @MainActor
    private func wait(_ element: XCUIElement, predicate: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, checkpoint: String) {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "comparison-accessibility-\(checkpoint)"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "comparison-screen-\(checkpoint)"
        image.lifetime = .keepAlways
        add(image)
    }
}
