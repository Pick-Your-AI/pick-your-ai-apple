import Foundation
import XCTest
@testable import PlannerTransfer

final class HistoricalQualityComparisonTests: XCTestCase {
    private func fixture(_ name: String) throws -> [String: JSONValue] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        var parser = try JSONParser(Data(contentsOf: url))
        return try XCTUnwrap(parser.parse().object)
    }

    private func build(_ fields: [String: JSONValue]) throws -> BuildSnapshot {
        try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(fields)))
    }

    private func run(_ fields: [String: JSONValue]) throws -> QualityEvaluationRun {
        try QualityEvaluationRun.decode(JSONEncoder().encode(JSONValue.object(fields)))
    }

    private func scenario(_ buildFields: [String: JSONValue],
                          _ runFields: [String: JSONValue]) throws -> HistoricalQualityScenario {
        try HistoricalQualityScenario(build: build(buildFields), run: run(runFields))
    }

    private func selection(_ fields: [String: JSONValue], id: String,
                           change: (inout [String: JSONValue]) -> Void) -> [String: JSONValue] {
        var result = fields
        result["selections"] = .array(fields["selections"]!.array!.map { value in
            var item = value.object!
            if item["id"] == .string(id) { change(&item) }
            return .object(item)
        })
        return result
    }

    private func measurement(_ fields: [String: JSONValue],
                             change: (inout [String: JSONValue]) -> Void) -> [String: JSONValue] {
        var result = fields, row = fields["measurements"]!.array![0].object!
        change(&row)
        result["measurements"] = .array([.object(row)])
        return result
    }

    private func anotherRun(_ fields: [String: JSONValue]) -> [String: JSONValue] {
        var result = fields; result["id"] = .string("quality.synthetic.other"); return result
    }

    func testCanonicalScenarioPreservesWholeInputsAndIndependentSerialization() throws {
        let buildFields = try fixture("build"), runFields = try fixture("quality-evaluation-run")
        let value = try scenario(buildFields, runFields)
        XCTAssertEqual(value.build.value, .object(buildFields))
        XCTAssertEqual(value.run.value, .object(runFields))
        XCTAssertEqual(value.evaluationSuite, buildFields["selections"]!.array!.first {
            $0.object!["id"] == .string("sel_evaluation_suite")
        })
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: value.build.encoded()), value.build)
        XCTAssertEqual(try QualityEvaluationRun.decode(value.run.encoded()), value.run)
        XCTAssertEqual(value.run.notes, ["TEST FIXTURE: synthetic score, not an actual evaluation."])
    }

    func testWrongBuildOrRevisionRejectsAndValidPairRecovers() throws {
        let buildFields = try fixture("build"), original = try fixture("quality-evaluation-run")
        for (key, value) in [("build_id", JSONValue.string("build.synthetic.other")), ("build_revision", .number(2))] {
            var changed = original; changed[key] = value
            let decoded = try run(changed)
            XCTAssertThrowsError(try HistoricalQualityScenario(build: build(buildFields), run: decoded)) {
                XCTAssertEqual($0 as? HistoricalQualityComparisonError, .buildMismatch)
            }
            XCTAssertEqual(decoded.value, .object(changed))
        }
        XCTAssertEqual(try scenario(buildFields, original).run.value, .object(original))
    }

    func testDuplicateSuiteAndUnrelatedSelectionIDsRejectInsteadOfReplacingRows() throws {
        let original = try fixture("build"), runFields = try fixture("quality-evaluation-run")
        for id in ["sel_evaluation_suite", "sel_model"] {
            var changed = original, rows = original["selections"]!.array!
            rows.append(try XCTUnwrap(rows.first { $0.object!["id"] == .string(id) }))
            changed["selections"] = .array(rows)
            let decoded = try build(changed)
            XCTAssertThrowsError(try HistoricalQualityScenario(build: decoded, run: run(runFields))) {
                XCTAssertEqual($0 as? HistoricalQualityComparisonError, .ambiguousSelectionIdentity, id)
            }
            XCTAssertEqual(decoded.value, .object(changed))
        }
        XCTAssertNoThrow(try scenario(original, runFields))
    }

    func testMissingAndWrongKindEvaluationSuiteReferencesReject() throws {
        let buildFields = try fixture("build"), original = try fixture("quality-evaluation-run")
        let cases: [(String, HistoricalQualityComparisonError)] = [
            ("sel_missing", .unknownEvaluationSuite), ("sel_model", .invalidEvaluationSuiteKind),
        ]
        for (id, expected) in cases {
            var changed = original; changed["evaluation_suite_selection_id"] = .string(id)
            let decoded = try run(changed)
            XCTAssertThrowsError(try HistoricalQualityScenario(build: build(buildFields), run: decoded)) {
                XCTAssertEqual($0 as? HistoricalQualityComparisonError, expected)
            }
        }
        XCTAssertNoThrow(try scenario(buildFields, original))
    }

    func testDuplicateMetricNamesRejectEvenWhenTheirUnitsDiffer() throws {
        let buildFields = try fixture("build"), original = try fixture("quality-evaluation-run")
        for unit in ["score", "milliseconds"] {
            var changed = original, row = original["measurements"]!.array![0].object!
            row["unit"] = .string(unit)
            changed["measurements"] = .array(original["measurements"]!.array! + [.object(row)])
            let decoded = try run(changed)
            XCTAssertEqual(decoded.measurements.count, 2)
            XCTAssertThrowsError(try HistoricalQualityScenario(build: build(buildFields), run: decoded)) {
                XCTAssertEqual($0 as? HistoricalQualityComparisonError, .ambiguousMetricIdentity)
            }
            XCTAssertEqual(decoded.value, .object(changed))
        }
    }

    func testCanonicallyEquivalentMetricNamesRemainTwoExactDisplayRows() throws {
        let composed = "metric-\u{00E9}", decomposed = "metric-e\u{0301}"
        XCTAssertEqual(composed, decomposed, "This probe must exercise Swift canonical equality.")
        XCTAssertNotEqual(Data(composed.utf8), Data(decomposed.utf8))
        let buildFields = try fixture("build")
        var runFields = try fixture("quality-evaluation-run")
        let template = runFields["measurements"]!.array![0].object!
        runFields["measurements"] = .array([composed, decomposed].map { metric in
            var row = template; row["metric"] = .string(metric); return .object(row)
        })
        let value = try scenario(buildFields, runFields)
        let result = try HistoricalQualityComparison.compare(value, value)
        XCTAssertEqual(result.measurements.map { Data($0.metric.utf8) }, [Data(decomposed.utf8), Data(composed.utf8)])
        XCTAssertEqual(result.measurements.count, 2)
        XCTAssertTrue(result.measurements.allSatisfy { !$0.hasChanges })
        XCTAssertEqual(result.before.run.value, .object(runFields))
    }

    func testUnchangedRunKeepsEveryMeasurementAndReportedOnlyQualification() throws {
        let value = try scenario(fixture("build"), fixture("quality-evaluation-run"))
        let result = try HistoricalQualityComparison.compare(value, value)
        XCTAssertEqual(result.before, value)
        XCTAssertEqual(result.after, value)
        XCTAssertEqual(result.changedFields, [])
        XCTAssertEqual(result.configuration.differences, [])
        XCTAssertEqual(result.cautions, [.reportedValuesOnly])
        XCTAssertEqual(result.measurements.count, value.run.measurements.count)
        let row = try XCTUnwrap(result.measurements.first)
        XCTAssertEqual(row.before, value.run.measurements[0])
        XCTAssertEqual(row.after, value.run.measurements[0])
        XCTAssertFalse(row.hasChanges)
        XCTAssertTrue(row.cautions.isEmpty)
    }

    func testChangedMeasurementsPreserveContradictoryReportedNumbersAndLabels() throws {
        let buildFields = try fixture("build"), original = try fixture("quality-evaluation-run")
        let left = measurement(original) {
            $0["observed"] = .number(-9); $0["threshold"] = .number(99)
            $0["comparator"] = .string("eq"); $0["passed"] = .bool(true)
        }
        let right = measurement(anotherRun(original)) {
            $0["observed"] = .number(0); $0["threshold"] = .number(100)
            $0["comparator"] = .string("gte"); $0["passed"] = .bool(false)
            $0["unit"] = .string("unreviewed-unit")
        }
        let result = try HistoricalQualityComparison.compare(scenario(buildFields, left), scenario(buildFields, right))
        let row = try XCTUnwrap(result.measurements.first)
        XCTAssertTrue(row.hasChanges)
        XCTAssertEqual(row.before?.observed, -9)
        XCTAssertEqual(row.before?.threshold, 99)
        XCTAssertEqual(row.before?.comparator, .eq)
        XCTAssertEqual(row.before?.passed, true)
        XCTAssertEqual(row.after?.observed, 0)
        XCTAssertEqual(row.after?.passed, false)
        XCTAssertEqual(result.before.run.status, .passed)
        XCTAssertEqual(result.after.run.status, .passed)
        XCTAssertEqual(row.cautions, [.differentUnits, .differentThresholds, .differentComparators])
        XCTAssertEqual(result.before.run.value, .object(left))
        XCTAssertEqual(result.after.run.value, .object(right))
    }

    func testAddedAndRemovedMeasurementsStayAbsentInsteadOfBecomingZero() throws {
        let buildFields = try fixture("build"), original = try fixture("quality-evaluation-run")
        var before = original, after = anotherRun(original)
        func additional(_ metric: String) -> JSONValue {
            var row = original["measurements"]!.array![0].object!
            row["metric"] = .string(metric); row["observed"] = .number(0)
            return .object(row)
        }
        before["measurements"] = .array(original["measurements"]!.array! + [additional("before-only")])
        after["measurements"] = .array(original["measurements"]!.array! + [additional("after-only")])
        let result = try HistoricalQualityComparison.compare(scenario(buildFields, before), scenario(buildFields, after))
        XCTAssertEqual(result.measurements.count, 3)
        let removed = try XCTUnwrap(result.measurements.first { $0.metric == "before-only" })
        let added = try XCTUnwrap(result.measurements.first { $0.metric == "after-only" })
        XCTAssertEqual(removed.before?.observed, 0)
        XCTAssertNil(removed.after)
        XCTAssertEqual(removed.cautions, [.afterAbsent])
        XCTAssertNil(added.before)
        XCTAssertEqual(added.after?.observed, 0)
        XCTAssertEqual(added.cautions, [.beforeAbsent])
        XCTAssertTrue(removed.hasChanges && added.hasChanges)
        XCTAssertFalse(try XCTUnwrap(result.measurements.first { $0.metric == "answer_quality" }).hasChanges)
    }

    func testMetricJoinOrderIsStableWhileOriginalRowOrderRemainsIntact() throws {
        let buildFields = try fixture("build")
        var before = try fixture("quality-evaluation-run")
        let template = before["measurements"]!.array![0].object!
        before["measurements"] = .array(["zeta", "alpha", "middle"].map { metric in
            var row = template; row["metric"] = .string(metric); return .object(row)
        })
        var after = anotherRun(before)
        after["measurements"] = .array(Array(before["measurements"]!.array!.reversed()))
        let result = try HistoricalQualityComparison.compare(scenario(buildFields, before), scenario(buildFields, after))
        XCTAssertEqual(result.measurements.map(\.metric), ["alpha", "middle", "zeta"])
        XCTAssertTrue(result.measurements.allSatisfy { !$0.hasChanges })
        XCTAssertEqual(result.changedFields, [.runID])
        XCTAssertEqual(result.before.run.value, .object(before))
        XCTAssertEqual(result.after.run.value, .object(after))
    }

    func testChangedRecordCannotReuseOneRunIdentityAndRecoveryKeepsInputs() throws {
        let buildFields = try fixture("build"), original = try fixture("quality-evaluation-run")
        let before = try scenario(buildFields, original)
        let mutations = [
            measurement(original) { $0["observed"] = .number(0) },
            original.merging(["notes": .array([.string("PRIVATE-CHANGED-NOTE")])]) { _, new in new },
        ]
        for changed in mutations {
            let rejected = try scenario(buildFields, changed)
            XCTAssertThrowsError(try HistoricalQualityComparison.compare(before, rejected)) {
                XCTAssertEqual($0 as? HistoricalQualityComparisonError, .conflictingRunIdentity)
                XCTAssertFalse(String(describing: $0).contains("PRIVATE-CHANGED-NOTE"))
            }
            let recovered = try HistoricalQualityComparison.compare(before, scenario(buildFields, anotherRun(changed)))
            XCTAssertEqual(recovered.before, before)
            XCTAssertEqual(rejected.run.value, .object(changed))
        }
        XCTAssertEqual(before.run.value, .object(original))
    }

    func testConflictingImmutableBuildRevisionRejectsThenNewRevisionRecovers() throws {
        let originalBuild = try fixture("build"), originalRun = try fixture("quality-evaluation-run")
        var changedBuild = selection(originalBuild, id: "sel_model") { $0["catalog_item_version"] = .string("release-2") }
        var changedRun = anotherRun(originalRun)
        let before = try scenario(originalBuild, originalRun)
        XCTAssertThrowsError(try HistoricalQualityComparison.compare(before, scenario(changedBuild, changedRun))) {
            XCTAssertEqual($0 as? BuildComparisonError, .conflictingRevisionIdentity)
        }
        changedBuild["revision"] = .number(2); changedRun["build_revision"] = .number(2)
        let result = try HistoricalQualityComparison.compare(before, scenario(changedBuild, changedRun))
        XCTAssertEqual(result.configuration.differences.count, 1)
        XCTAssertEqual(result.configuration.differences[0].path, ["selections", "sel_model", "catalog_item_version"])
        XCTAssertTrue(result.cautions.contains(.differentConfigurations))
        XCTAssertEqual(result.before.build.value, .object(originalBuild))
        XCTAssertEqual(result.after.build.value, .object(changedBuild))
    }

    func testReorderedBuildRecordsPreserveIdentityButAmbiguousLinksReject() throws {
        let originalBuild = try fixture("build"), runFields = try fixture("quality-evaluation-run")
        var reordered = originalBuild
        for key in ["selections", "links"] { reordered[key] = .array(Array(originalBuild[key]!.array!.reversed())) }
        let before = try scenario(originalBuild, runFields)
        let result = try HistoricalQualityComparison.compare(before, scenario(reordered, runFields))
        XCTAssertEqual(result.configuration.differences, [])
        XCTAssertEqual(result.after.build.value, .object(reordered))
        var ambiguous = originalBuild
        ambiguous["links"] = .array(originalBuild["links"]!.array! + [originalBuild["links"]!.array![0]])
        XCTAssertThrowsError(try HistoricalQualityComparison.compare(before, scenario(ambiguous, runFields))) {
            XCTAssertEqual($0 as? BuildComparisonError, .ambiguousLinkIdentity)
        }
    }

    func testEveryRecordedFieldChangeRetainsItsOwnBindingAndConditions() throws {
        let originalBuild = try fixture("build"), originalRun = try fixture("quality-evaluation-run")
        var changedBuild = selection(originalBuild, id: "sel_evaluation_suite") {
            $0["catalog_item_version"] = .string("suite-release-2")
        }
        changedBuild["id"] = .string("build.synthetic.other"); changedBuild["revision"] = .number(2)
        var locks = changedBuild["locks"]!.object!
        locks["ruleset_version"] = .string("2.0.0"); changedBuild["locks"] = .object(locks)
        var changedRun = anotherRun(originalRun)
        changedRun["build_id"] = changedBuild["id"]; changedRun["build_revision"] = .number(2)
        changedRun["started_at"] = .string("2026-10-17T09:00:00Z")
        changedRun["finished_at"] = .string("2026-10-17T09:01:00Z")
        changedRun["status"] = .string("incomplete")
        changedRun["evaluator_version"] = .string("evaluator-2")
        changedRun["dataset_revision"] = .string("synthetic-dataset-2")
        changedRun["sample_size"] = .number(101)
        changedRun["artifacts"] = .array([.string("urn:synthetic:retained")])
        changedRun["notes"] = .array([.string("PRIVATE-LOCAL-NOTE")])
        let result = try HistoricalQualityComparison.compare(scenario(originalBuild, originalRun), scenario(changedBuild, changedRun))
        XCTAssertEqual(result.changedFields, HistoricalQualityField.allCases)
        XCTAssertEqual(result.cautions, [.reportedValuesOnly, .differentConfigurations, .differentEvaluationSuites,
                                        .differentEvaluatorVersions, .differentDatasets, .differentSampleSizes,
                                        .afterIncompleteRun])
        XCTAssertEqual(result.before.build.value, .object(originalBuild))
        XCTAssertEqual(result.after.build.value, .object(changedBuild))
        XCTAssertEqual(result.before.run.value, .object(originalRun))
        XCTAssertEqual(result.after.run.value, .object(changedRun))
        XCTAssertTrue(result.measurements.allSatisfy { !$0.hasChanges })
    }

    func testMissingEmptyAndPresentUnitsRemainDistinctOnEachSide() throws {
        let buildFields = try fixture("build"), original = try fixture("quality-evaluation-run")
        let units: [String?] = [nil, "", "score"]
        for beforeUnit in units {
            for afterUnit in units {
                let before = measurement(original) {
                    if let beforeUnit { $0["unit"] = .string(beforeUnit) } else { $0.removeValue(forKey: "unit") }
                }
                let after = measurement(anotherRun(original)) {
                    if let afterUnit { $0["unit"] = .string(afterUnit) } else { $0.removeValue(forKey: "unit") }
                }
                let result = try HistoricalQualityComparison.compare(scenario(buildFields, before), scenario(buildFields, after))
                let row = try XCTUnwrap(result.measurements.first)
                var expected: [HistoricalQualityMeasurementCaution] = []
                if beforeUnit == nil { expected.append(.beforeUnitAbsent) }
                else if beforeUnit == "" { expected.append(.beforeUnitEmpty) }
                if afterUnit == nil { expected.append(.afterUnitAbsent) }
                else if afterUnit == "" { expected.append(.afterUnitEmpty) }
                if beforeUnit != afterUnit { expected.append(.differentUnits) }
                XCTAssertEqual(row.cautions, expected)
                XCTAssertEqual(row.before?.unit, beforeUnit)
                XCTAssertEqual(row.after?.unit, afterUnit)
                XCTAssertEqual(row.hasChanges, beforeUnit != afterUnit)
                XCTAssertEqual(result.cautions, [.reportedValuesOnly])
            }
        }
    }

    func testOpaqueUnicodeVersionsAndUnitsNeverBorrowCanonicalEquality() throws {
        let composed = "release-\u{00E9}", decomposed = "release-e\u{0301}"
        XCTAssertEqual(composed, decomposed)
        XCTAssertNotEqual(Data(composed.utf8), Data(decomposed.utf8))
        let originalBuild = try fixture("build"), originalRun = try fixture("quality-evaluation-run")
        let beforeBuild = selection(originalBuild, id: "sel_evaluation_suite") { $0["catalog_item_version"] = .string(composed) }
        var afterBuild = selection(originalBuild, id: "sel_evaluation_suite") { $0["catalog_item_version"] = .string(decomposed) }
        afterBuild["revision"] = .number(2)
        var beforeRun = measurement(originalRun) { $0["unit"] = .string(composed) }
        var afterRun = measurement(anotherRun(originalRun)) { $0["unit"] = .string(decomposed) }
        for key in ["evaluator_version", "dataset_revision"] {
            beforeRun[key] = .string(composed); afterRun[key] = .string(decomposed)
        }
        afterRun["build_revision"] = .number(2)
        let result = try HistoricalQualityComparison.compare(scenario(beforeBuild, beforeRun), scenario(afterBuild, afterRun))
        XCTAssertTrue(result.cautions.contains(.differentEvaluationSuites))
        XCTAssertTrue(result.cautions.contains(.differentEvaluatorVersions))
        XCTAssertTrue(result.cautions.contains(.differentDatasets))
        XCTAssertEqual(result.measurements[0].cautions, [.differentUnits])
        XCTAssertEqual(Data(result.before.run.datasetRevision.utf8), Data(composed.utf8))
        XCTAssertEqual(Data(result.after.run.datasetRevision.utf8), Data(decomposed.utf8))
        XCTAssertEqual(result.before.run.value, .object(beforeRun))
        XCTAssertEqual(result.after.run.value, .object(afterRun))
    }

    func testIncompleteAndDisabledSuiteLabelsRemainPerSideWithoutNewVerdicts() throws {
        let originalBuild = try fixture("build"), originalRun = try fixture("quality-evaluation-run")
        let disabledBuild = selection(originalBuild, id: "sel_evaluation_suite") { $0["enabled"] = .bool(false) }
        for beforeIncomplete in [true, false] {
            var before = originalRun, after = anotherRun(originalRun)
            before["status"] = .string(beforeIncomplete ? "incomplete" : "failed")
            after["status"] = .string(beforeIncomplete ? "failed" : "incomplete")
            let result = try HistoricalQualityComparison.compare(scenario(disabledBuild, before), scenario(disabledBuild, after))
            XCTAssertEqual(result.cautions, [.reportedValuesOnly,
                                            beforeIncomplete ? .beforeIncompleteRun : .afterIncompleteRun,
                                            .beforeDisabledSuite, .afterDisabledSuite])
            XCTAssertEqual(result.before.run.status, beforeIncomplete ? .incomplete : .failed)
            XCTAssertEqual(result.after.run.status, beforeIncomplete ? .failed : .incomplete)
            XCTAssertTrue(result.before.run.measurements[0].passed)
            XCTAssertTrue(result.after.run.measurements[0].passed)
        }
    }

    func testSupportedNumericValuesStayExactWithoutNarrowingOrRounding() throws {
        var buildFields = try fixture("build"), runFields = try fixture("quality-evaluation-run")
        let large = try XCTUnwrap(Decimal(string: "9000000000000000", locale: Locale(identifier: "en_US_POSIX")))
        let negative = try XCTUnwrap(Decimal(string: "-123456789.012345", locale: Locale(identifier: "en_US_POSIX")))
        let tiny = try XCTUnwrap(Decimal(string: "0.00000000000123456789", locale: Locale(identifier: "en_US_POSIX")))
        buildFields["revision"] = .number(large)
        runFields["build_revision"] = .number(large); runFields["sample_size"] = .number(large)
        runFields = measurement(runFields) { $0["observed"] = .number(negative); $0["threshold"] = .number(tiny) }
        let value = try scenario(buildFields, runFields)
        let result = try HistoricalQualityComparison.compare(value, value)
        XCTAssertEqual(result.before.run.buildRevision, large)
        XCTAssertEqual(result.before.run.sampleSize, large)
        XCTAssertEqual(result.measurements[0].before?.observed, negative)
        XCTAssertEqual(result.measurements[0].after?.threshold, tiny)
        XCTAssertEqual(try QualityEvaluationRun.decode(result.before.run.encoded()), value.run)
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: result.after.build.encoded()), value.build)
    }

    func testDifferentComponentTuplesAndUnmatchedMetricsNeverTransferEvidence() throws {
        let originalBuild = try fixture("build"), originalRun = try fixture("quality-evaluation-run")
        var changedBuild = selection(originalBuild, id: "sel_model") { $0["catalog_item_id"] = .string("cat.model.other") }
        changedBuild = selection(changedBuild, id: "sel_workload") {
            var settings = $0["settings"]!.object!
            settings["avg_input_tokens"] = .number(2048); $0["settings"] = .object(settings)
        }
        changedBuild["id"] = .string("build.synthetic.other")
        var changedRun = measurement(anotherRun(originalRun)) {
            $0["metric"] = .string("latency"); $0["unit"] = .string("ms")
            $0["observed"] = .number(250); $0["threshold"] = .number(1000)
            $0["comparator"] = .string("lte"); $0["passed"] = .bool(false)
        }
        changedRun["build_id"] = changedBuild["id"]
        let result = try HistoricalQualityComparison.compare(scenario(originalBuild, originalRun), scenario(changedBuild, changedRun))
        XCTAssertTrue(result.configuration.differences.contains { $0.path == ["selections", "sel_model", "catalog_item_id"] })
        XCTAssertTrue(result.configuration.differences.contains { $0.path == ["selections", "sel_workload", "settings", "avg_input_tokens"] })
        XCTAssertTrue(result.cautions.contains(.differentConfigurations))
        XCTAssertEqual(result.measurements.count, 2)
        let quality = try XCTUnwrap(result.measurements.first { $0.metric == "answer_quality" })
        let latency = try XCTUnwrap(result.measurements.first { $0.metric == "latency" })
        XCTAssertEqual(quality.before, result.before.run.measurements[0])
        XCTAssertNil(quality.after)
        XCTAssertNil(latency.before)
        XCTAssertEqual(latency.after, result.after.run.measurements[0])
        XCTAssertEqual(result.before.run.buildID, result.before.build.id)
        XCTAssertEqual(result.after.run.buildID, result.after.build.id)
        XCTAssertEqual(result.before.build.value, .object(originalBuild))
        XCTAssertEqual(result.after.run.value, .object(changedRun))
    }

    func testChronologyPrivateArtifactReferencesAndNotesRemainUnverifiedLocalValues() throws {
        let buildFields = try fixture("build")
        var before = try fixture("quality-evaluation-run")
        before["finished_at"] = .string("2026-10-15T00:00:00Z")
        before["notes"] = .array([.string("PRIVATE-NOTE"), .string("")])
        before["artifacts"] = .array([.string("file:///tmp/private.json"), .string("urn:private:record")])
        var after = anotherRun(before); after.removeValue(forKey: "notes")
        let result = try HistoricalQualityComparison.compare(scenario(buildFields, before), scenario(buildFields, after))
        XCTAssertEqual(result.before.run.finishedAt, "2026-10-15T00:00:00Z")
        XCTAssertEqual(result.before.run.notes, ["PRIVATE-NOTE", ""])
        XCTAssertNil(result.after.run.notes)
        XCTAssertEqual(result.before.run.artifacts, ["file:///tmp/private.json", "urn:private:record"])
        XCTAssertEqual(result.changedFields, [.runID, .notes])
        XCTAssertEqual(result.cautions, [.reportedValuesOnly])
        XCTAssertEqual(try QualityEvaluationRun.decode(result.before.run.encoded()).value, .object(before))
        XCTAssertEqual(try QualityEvaluationRun.decode(result.after.run.encoded()).value, .object(after))
    }
}
