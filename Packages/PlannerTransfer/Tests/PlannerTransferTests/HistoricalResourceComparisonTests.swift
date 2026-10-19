import Foundation
import XCTest
@testable import PlannerTransfer

final class HistoricalResourceComparisonTests: XCTestCase {
    private typealias Mutation = (path: [String], value: JSONValue?)

    private func fixture(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        var parser = try JSONParser(Data(contentsOf: url))
        return try parser.parse()
    }

    private func replacing(_ value: JSONValue, path: ArraySlice<String>,
                           with replacement: JSONValue?) throws -> JSONValue {
        guard let key = path.first else { return try XCTUnwrap(replacement) }
        if var object = value.object {
            if path.count == 1 { object[key] = replacement }
            else { object[key] = try replacing(XCTUnwrap(object[key]), path: path.dropFirst(), with: replacement) }
            return .object(object)
        }
        var array = try XCTUnwrap(value.array)
        let index = try XCTUnwrap(Int(key))
        guard array.indices.contains(index) else { throw TransferError.malformed }
        array[index] = try replacing(array[index], path: path.dropFirst(), with: replacement)
        return .array(array)
    }

    private func modified(_ value: JSONValue, _ changes: [Mutation]) throws -> JSONValue {
        try changes.reduce(value) { try replacing($0, path: $1.path[...], with: $1.value) }
    }

    private func input(_ name: String, _ changes: [Mutation]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(modified(fixture(name), changes))
    }

    private func build(_ changes: [Mutation] = []) throws -> BuildSnapshot {
        try BuildTransfer.snapshot(fromDraftJSON: input("build", changes))
    }

    private func estimate(_ changes: [Mutation] = []) throws -> ResourceEstimate {
        try ResourceEstimate.decode(input("resource-estimate", changes))
    }

    private func scenario(buildChanges: [Mutation] = [], estimateChanges: [Mutation] = []) throws -> HistoricalResourceScenario {
        try HistoricalResourceScenario(build: build(buildChanges), estimate: estimate(estimateChanges))
    }

    private func later(buildChanges: [Mutation] = [], estimateChanges: [Mutation] = []) throws -> HistoricalResourceScenario {
        try scenario(buildChanges: buildChanges,
                     estimateChanges: [(["id"], .string("resources.fixture.2"))] + estimateChanges)
    }

    private func row(_ changes: [Mutation] = []) throws -> JSONValue {
        let original = try XCTUnwrap(fixture("resource-estimate").object?["estimates"]?.array?.first)
        return try modified(original, changes)
    }

    private func selectionChange(_ id: String, path: [String], value: JSONValue) throws -> Mutation {
        let selections = try XCTUnwrap(fixture("build").object?["selections"]?.array)
        let index = try XCTUnwrap(selections.firstIndex { $0.object?["id"]?.string == id })
        return (["selections", String(index)] + path, value)
    }

    private func group(_ comparison: HistoricalResourceComparison,
                       metric: String = "inference.estimated_required_vram_gb") throws -> HistoricalResourceMetricGroup {
        try XCTUnwrap(comparison.metricGroups.first { $0.metric == metric })
    }

    func testScenarioRetainsCompleteOriginalRowsAndTheirOwnOrderedSelections() throws {
        let source = try scenario()
        XCTAssertEqual(source.rows.map(\.record), source.estimate.estimates)
        let selections = try XCTUnwrap(source.build.value.object?["selections"]?.array)
        for bound in source.rows {
            XCTAssertEqual(bound.selections.map { $0.object?["id"]?.string }, bound.selectionIDs.map { Optional($0) })
            for (id, selected) in zip(bound.selectionIDs, bound.selections) {
                XCTAssertEqual(selected, selections.first { $0.object?["id"]?.string == id })
            }
        }
        let first = try XCTUnwrap(source.rows.first)
        XCTAssertEqual(first.metric, "inference.estimated_required_vram_gb")
        XCTAssertEqual(first.reportedValue, "20.0")
        XCTAssertEqual(first.unit, "gb")
        XCTAssertEqual(first.estimatorID, "fixture.estimator")
        XCTAssertEqual(first.estimatorVersion, "0.0-fixture")
        XCTAssertEqual(first.reportedConfidence, "estimated")
        XCTAssertNil(first.sourceURI)
        XCTAssertEqual(try ResourceEstimate.decode(source.estimate.encoded()), source.estimate)
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: source.build.encoded()), source.build)
    }

    func testIdenticalHistoricalRecordStillKeepsEveryRowWithoutQualification() throws {
        let source = try scenario()
        let result = try HistoricalResourceComparison.compare(source, source)
        XCTAssertEqual(result.before, source)
        XCTAssertEqual(result.after, source)
        XCTAssertEqual(result.configuration.differences, [])
        XCTAssertEqual(result.changedFields, [])
        XCTAssertEqual(result.cautions, [.reportedValuesOnly])
        XCTAssertEqual(result.metricGroups.map(\.metric), [
            "inference.estimated_peak_per_device_vram_gb", "inference.estimated_required_vram_gb",
        ])
        XCTAssertEqual(result.metricGroups.flatMap(\.beforeRows).count, source.rows.count)
        XCTAssertTrue(result.metricGroups.allSatisfy { $0.beforeRows == $0.afterRows && $0.beforeRows.count == 1 })
    }

    func testForeignBuildOrRevisionRejectsThenRecoversOnlyWithMatchingSnapshot() throws {
        let mismatches: [([Mutation], [Mutation])] = [
            ([(["build_id"], .string("build.other.fixture"))], [(["id"], .string("build.other.fixture"))]),
            ([(["build_revision"], .number(2))], [(["revision"], .number(2))]),
        ]
        for (estimateChanges, buildChanges) in mismatches {
            let record = try estimate(estimateChanges)
            let original = record.value
            XCTAssertThrowsError(try HistoricalResourceScenario(build: build(), estimate: record)) {
                XCTAssertEqual($0 as? HistoricalResourceComparisonError, .buildMismatch)
            }
            let recovered = try HistoricalResourceScenario(build: build(buildChanges), estimate: record)
            XCTAssertEqual(recovered.estimate.value, original)
            XCTAssertEqual(recovered.rows.count, record.estimates.count)
        }
    }

    func testEveryDuplicateBuildSelectionRejectsEvenWhenNotReferencedByRows() throws {
        let original = try XCTUnwrap(fixture("build").object?["selections"]?.array)
        for id in ["sel_model", "sel_workload"] {
            let duplicate = try XCTUnwrap(original.first { $0.object?["id"]?.string == id })
            for changed in [false, true] {
                let extra = changed ? try modified(duplicate, [(["catalog_item_version"], .string("other-version"))]) : duplicate
                XCTAssertThrowsError(try scenario(buildChanges: [(["selections"], .array(original + [extra]))])) {
                    XCTAssertEqual($0 as? HistoricalResourceComparisonError, .ambiguousSelectionIdentity)
                }
            }
        }
        XCTAssertEqual(try scenario().rows.count, 2)
    }

    func testLateUnknownReferenceRejectsWholeScenarioAndPreservesRecovery() throws {
        let original = try estimate()
        let changed = try estimate([(["estimates", "1", "selection_ids"],
                                     .array([.string("sel_model"), .string("sel_private_missing")]))])
        let saved = try build()
        XCTAssertThrowsError(try HistoricalResourceScenario(build: saved, estimate: changed)) {
            XCTAssertEqual($0 as? HistoricalResourceComparisonError, .unknownSelection)
            XCTAssertFalse(String(describing: $0).contains("private_missing"))
        }
        XCTAssertEqual(changed.estimates.count, 2)
        XCTAssertEqual(try HistoricalResourceScenario(build: saved, estimate: original).estimate, original)
        XCTAssertEqual(saved, try build())
    }

    func testChangedComponentTupleAndSettingsStayBoundToTheirOwnRevision() throws {
        let before = try scenario()
        let after = try later(buildChanges: [
            (["revision"], .number(2)),
            try selectionChange("sel_model", path: ["catalog_item_id"], value: .string("cat.model.other")),
            try selectionChange("sel_model", path: ["catalog_item_version"], value: .string("different-model-version")),
            try selectionChange("sel_model", path: ["settings", "precision"], value: .string("fp32")),
        ], estimateChanges: [(["build_revision"], .number(2))])
        let result = try HistoricalResourceComparison.compare(before, after)
        let rows = try group(result)
        let left = try XCTUnwrap(rows.beforeRows.first?.selections.first?.object)
        let right = try XCTUnwrap(rows.afterRows.first?.selections.first?.object)
        XCTAssertEqual(left["catalog_item_id"], .string("cat.model.fixture"))
        XCTAssertEqual(right["catalog_item_id"], .string("cat.model.other"))
        XCTAssertEqual(right["catalog_item_version"], .string("different-model-version"))
        XCTAssertEqual(right["settings"]?.object?["precision"], .string("fp32"))
        XCTAssertEqual(rows.beforeRows.first?.reportedValue, "20.0")
        XCTAssertEqual(rows.afterRows.first?.reportedValue, "20.0")
        XCTAssertTrue(result.configuration.differences.contains { $0.path == ["selections", "sel_model", "catalog_item_version"] })
        XCTAssertEqual(result.cautions, [.reportedValuesOnly, .differentBuildRevisions])
        XCTAssertEqual(result.before, before)
        XCTAssertEqual(result.after, after)
    }

    func testRepeatedMetricsMultipleEstimatorsAndIdenticalRowsAreNeverDiscardedOrPaired() throws {
        let first = try row()
        let second = try row([(["estimator_id"], .string("another-estimator")),
                              (["estimator_version"], .string("2")),
                              (["selection_ids"], .array([.string("sel_accelerator")])),
                              (["value"], .string("0.000"))])
        let other = try row([(["metric"], .string("compute.estimated_gpu_power_w")), (["unit"], .string("watt"))])
        let before = try scenario(estimateChanges: [(["estimates"], .array([first, other, second, first]))])
        let after = try later(estimateChanges: [(["estimates"], .array([second, first]))])
        let result = try HistoricalResourceComparison.compare(before, after)
        let rows = try group(result)
        XCTAssertEqual(rows.beforeRows.map(\.record), [first, second, first])
        XCTAssertEqual(rows.afterRows.map(\.record), [second, first])
        XCTAssertEqual(rows.beforeRows[1].selectionIDs, ["sel_accelerator"])
        XCTAssertEqual(rows.beforeRows[1].selections.first?.object?["id"], .string("sel_accelerator"))
        XCTAssertEqual(result.before.estimate.estimates, [first, other, second, first])
        XCTAssertEqual(result.after.estimate.estimates, [second, first])
        XCTAssertEqual(result.cautions, [.reportedValuesOnly, .unmatchedMetrics, .beforeRepeatedMetrics, .afterRepeatedMetrics])
    }

    func testUnmatchedMetricsRemainEmptySidesRatherThanZeroOrRecomputedEvidence() throws {
        let before = try scenario()
        let zero = try row([(["metric"], .string("training.estimated_gpu_hours")),
                            (["unit"], .string("gpu_hour")), (["value"], .string("0.000"))])
        let after = try later(estimateChanges: [(["estimates"], .array([zero]))])
        let result = try HistoricalResourceComparison.compare(before, after)
        XCTAssertEqual(result.metricGroups.count, 3)
        let added = try group(result, metric: "training.estimated_gpu_hours")
        XCTAssertTrue(added.beforeRows.isEmpty)
        XCTAssertEqual(added.afterRows.map(\.reportedValue), ["0.000"])
        let removed = try group(result)
        XCTAssertEqual(removed.beforeRows.map(\.reportedValue), ["20.0"])
        XCTAssertTrue(removed.afterRows.isEmpty)
        XCTAssertEqual(result.cautions, [.reportedValuesOnly, .unmatchedMetrics])
    }

    func testMetricOrderingIsStableWhileOriginalRowOrderRemainsVisible() throws {
        let metrics = ["training.estimated_gpu_hours", "inference.estimated_tokens_per_second",
                       "inference.estimated_required_vram_gb", "compute.estimated_gpu_power_w",
                       "inference.estimated_peak_per_device_vram_gb"]
        let rows = try metrics.map { try row([(["metric"], .string($0))]) }
        let before = try scenario(estimateChanges: [(["estimates"], .array(rows))])
        let reversed = Array(rows.reversed())
        let after = try later(estimateChanges: [(["estimates"], .array(reversed))])
        let result = try HistoricalResourceComparison.compare(before, after)
        XCTAssertEqual(result.metricGroups.map(\.metric), metrics.sorted())
        XCTAssertTrue(result.metricGroups.allSatisfy { $0.beforeRows == $0.afterRows })
        XCTAssertEqual(result.before.rows.map(\.record), rows)
        XCTAssertEqual(result.after.rows.map(\.record), reversed)
        XCTAssertEqual(result.changedFields, [.estimateID, .estimates])
        XCTAssertEqual(result.cautions, [.reportedValuesOnly])
    }

    func testDecimalSpellingContradictoryUnitsAndReportedConfidenceAreNotReinterpreted() throws {
        let values = ["0", "0.0", "20.000", "0.000000000001", "9007199254740993.123456789012",
                      String(repeating: "9", count: 300) + ".000000000001"]
        let rows = try values.map { try row([(["value"], .string($0)), (["unit"], .string("watt")),
                                           (["confidence"], .string("verified")), (["assumptions"], .array([]))]) }
        let source = try scenario(estimateChanges: [(["estimates"], .array(rows))])
        let result = try HistoricalResourceComparison.compare(source, source)
        let reported = try group(result).beforeRows
        XCTAssertEqual(reported.map(\.reportedValue), values)
        XCTAssertTrue(reported.allSatisfy { $0.unit == "watt" && $0.reportedConfidence == "verified" && $0.assumptions.isEmpty })
        XCTAssertEqual(result.cautions, [.reportedValuesOnly, .beforeRepeatedMetrics, .afterRepeatedMetrics])
        XCTAssertEqual(try ResourceEstimate.decode(source.estimate.encoded()).estimates, rows)
    }

    func testOptionalSourceAndPrivateAssumptionPresenceStayLocalAndExact() throws {
        let before = try scenario(estimateChanges: [(["estimates", "0", "assumptions"], .array([]))])
        let after = try later(estimateChanges: [
            (["estimates", "0", "source_uri"], .string("https://example.invalid/synthetic-proof")),
            (["estimates", "0", "assumptions"], .array([.string(""), .string("SYNTHETIC private local note"), .string("")])),
        ])
        let rows = try group(HistoricalResourceComparison.compare(before, after))
        XCTAssertNil(rows.beforeRows.first?.sourceURI)
        XCTAssertEqual(rows.beforeRows.first?.assumptions, [])
        XCTAssertEqual(rows.afterRows.first?.sourceURI, "https://example.invalid/synthetic-proof")
        XCTAssertEqual(rows.afterRows.first?.assumptions, ["", "SYNTHETIC private local note", ""])
        XCTAssertNil(rows.beforeRows.first?.record.object?["source_uri"])
        XCTAssertEqual(rows.afterRows.first?.record, after.estimate.estimates.first)
    }

    func testAnyChangedEstimateContentCannotReuseItsHistoricalIdentity() throws {
        let before = try scenario()
        let rows = try XCTUnwrap(fixture("resource-estimate").object?["estimates"]?.array)
        let changes: [Mutation] = [
            (["generated_at"], .string("2026-10-18T09:00:00Z")),
            (["estimates", "0", "value"], .string("20.00")),
            (["estimates", "0", "confidence"], .string("verified")),
            (["estimates", "0", "source_uri"], .string("https://example.invalid/synthetic-proof")),
            (["estimates"], .array(Array(rows.reversed()))),
        ]
        for change in changes {
            let conflicting = try scenario(estimateChanges: [change])
            XCTAssertThrowsError(try HistoricalResourceComparison.compare(before, conflicting)) {
                XCTAssertEqual($0 as? HistoricalResourceComparisonError, .conflictingEstimateIdentity)
            }
            let recovered = try later(estimateChanges: [change])
            XCTAssertEqual(try HistoricalResourceComparison.compare(before, recovered).after, recovered)
        }
        let newerBuild = try scenario(buildChanges: [(["revision"], .number(2))],
                                      estimateChanges: [(["build_revision"], .number(2))])
        XCTAssertThrowsError(try HistoricalResourceComparison.compare(before, newerBuild)) {
            XCTAssertEqual($0 as? HistoricalResourceComparisonError, .conflictingEstimateIdentity)
        }
        XCTAssertEqual(before, try scenario())
    }

    func testCanonicallyEquivalentUnicodeRecordChangesRejectInBothDirections() throws {
        let composed = "caf\u{00E9}"
        let decomposed = "cafe\u{0301}"
        for path in [["estimator_id"], ["estimator_version"], ["assumptions", "0"]] {
            for (left, right) in [(composed, decomposed), (decomposed, composed)] {
                let before = try scenario(estimateChanges: [(["estimates", "0"] + path, .string(left))])
                let conflict = try scenario(estimateChanges: [(["estimates", "0"] + path, .string(right))])
                XCTAssertThrowsError(try HistoricalResourceComparison.compare(before, conflict)) {
                    XCTAssertEqual($0 as? HistoricalResourceComparisonError, .conflictingEstimateIdentity)
                }
                let after = try later(estimateChanges: [(["estimates", "0"] + path, .string(right))])
                let rows = try group(HistoricalResourceComparison.compare(before, after))
                XCTAssertNotEqual(rows.beforeRows.first?.record, rows.afterRows.first?.record)
                let actualBefore = try XCTUnwrap(rows.beforeRows.first)
                let actualAfter = try XCTUnwrap(rows.afterRows.first)
                let first = path[0] == "estimator_id" ? actualBefore.estimatorID :
                    path[0] == "estimator_version" ? actualBefore.estimatorVersion : actualBefore.assumptions[0]
                let second = path[0] == "estimator_id" ? actualAfter.estimatorID :
                    path[0] == "estimator_version" ? actualAfter.estimatorVersion : actualAfter.assumptions[0]
                XCTAssertEqual(Array(first.utf8), Array(left.utf8))
                XCTAssertEqual(Array(second.utf8), Array(right.utf8))
            }
        }
    }

    func testConflictingSavedRevisionRejectsEvenWithDifferentEstimateIdentity() throws {
        let before = try scenario()
        let after = try later(buildChanges: [(["name"], .string("SYNTHETIC changed saved name"))])
        XCTAssertThrowsError(try HistoricalResourceComparison.compare(before, after)) {
            XCTAssertEqual($0 as? BuildComparisonError, .conflictingRevisionIdentity)
        }
        let recovered = try later(buildChanges: [(["revision"], .number(2)), (["name"], .string("SYNTHETIC changed saved name"))],
                                  estimateChanges: [(["build_revision"], .number(2))])
        XCTAssertEqual(try HistoricalResourceComparison.compare(before, recovered).after, recovered)
    }

    func testBuildOrderingAndExplicitReferenceOrderingRetainTheirDistinctMeanings() throws {
        let before = try scenario()
        let selections = try XCTUnwrap(fixture("build").object?["selections"]?.array)
        let links = try XCTUnwrap(fixture("build").object?["links"]?.array)
        let reorderedBuild = try scenario(buildChanges: [(["selections"], .array(Array(selections.reversed()))),
                                                        (["links"], .array(Array(links.reversed())))])
        let same = try HistoricalResourceComparison.compare(before, reorderedBuild)
        XCTAssertEqual(same.configuration.differences, [])
        XCTAssertEqual(same.changedFields, [])
        XCTAssertEqual(same.before.rows, same.after.rows)
        XCTAssertEqual(same.after.build, reorderedBuild.build)
        let reversedIDs = Array(before.rows[0].selectionIDs.reversed())
        let reorderedReferences = try later(estimateChanges: [(["estimates", "0", "selection_ids"], .array(reversedIDs.map(JSONValue.string)))])
        let changed = try group(HistoricalResourceComparison.compare(before, reorderedReferences))
        XCTAssertEqual(changed.afterRows[0].selectionIDs, reversedIDs)
        XCTAssertEqual(changed.afterRows[0].selections, Array(before.rows[0].selections.reversed()))
        XCTAssertEqual(changed.beforeRows[0].selections, before.rows[0].selections)
    }

    func testDuplicateLinksStillRejectAcrossDifferentBuilds() throws {
        let before = try scenario()
        let links = try XCTUnwrap(fixture("build").object?["links"]?.array)
        let after = try later(buildChanges: [(["id"], .string("build.other.fixture")),
                                            (["links"], .array(links + [try XCTUnwrap(links.first)]))],
                              estimateChanges: [(["build_id"], .string("build.other.fixture"))])
        XCTAssertThrowsError(try HistoricalResourceComparison.compare(before, after)) {
            XCTAssertEqual($0 as? BuildComparisonError, .ambiguousLinkIdentity)
        }
        let recovered = try later(buildChanges: [(["id"], .string("build.other.fixture"))],
                                  estimateChanges: [(["build_id"], .string("build.other.fixture"))])
        XCTAssertEqual(try HistoricalResourceComparison.compare(before, recovered).configuration.differences, [])
    }

    func testStructuralPrivacyProjectionRemainsSeparateFromOriginalLocalRecords() throws {
        let rowReferences: Mutation = (["estimates", "0", "selection_ids"], .array([.string("sel_vector_database")]))
        let before = try scenario(estimateChanges: [rowReferences])
        let after = try later(buildChanges: [(["revision"], .number(2)),
            try selectionChange("sel_vector_database", path: ["settings", "index_name"], value: .string("SYNTHETIC-PRIVATE-INDEX")),
        ], estimateChanges: [(["build_revision"], .number(2)), rowReferences])
        let result = try HistoricalResourceComparison.compare(before, after)
        let difference = try XCTUnwrap(result.configuration.differences.first)
        XCTAssertEqual(result.configuration.differences.count, 1)
        XCTAssertEqual(difference.path, ["selections", "sel_vector_database", "settings", "index_name"])
        XCTAssertEqual(difference.before, .hidden)
        XCTAssertEqual(difference.after, .hidden)
        XCTAssertFalse(String(describing: result.configuration).contains("SYNTHETIC-PRIVATE-INDEX"))
        let rows = try group(result)
        XCTAssertEqual(rows.afterRows.first?.selections.first?.object?["settings"]?.object?["index_name"], .string("SYNTHETIC-PRIVATE-INDEX"))
        XCTAssertEqual(rows.afterRows.first?.record, after.estimate.estimates.first)
        XCTAssertEqual(result.cautions, [.reportedValuesOnly, .differentBuildRevisions])
    }

    func testStructuralDifferenceBudgetStillRejectsWithoutPartialComparisonAndRecovers() throws {
        let before = try scenario()
        let original = try XCTUnwrap(fixture("build").object?["selections"]?.array)
        let template = try XCTUnwrap(original.first)
        var added = original
        for index in 0..<400 {
            added.append(try modified(template, [(["id"], .string("sel_extra_\(index)"))]))
        }
        let excessive = try later(buildChanges: [(["revision"], .number(2)), (["selections"], .array(added))],
                                  estimateChanges: [(["build_revision"], .number(2))])
        XCTAssertThrowsError(try HistoricalResourceComparison.compare(before, excessive)) {
            XCTAssertEqual($0 as? BuildComparisonError, .tooManyDifferences)
        }
        let recovered = try later(buildChanges: [(["revision"], .number(2))], estimateChanges: [(["build_revision"], .number(2))])
        XCTAssertEqual(try HistoricalResourceComparison.compare(before, recovered).configuration.differences, [])
        XCTAssertEqual(excessive.build.value.object?["selections"]?.array?.count, original.count + 400)
    }

    func testChangedIdentityLocksAndTimestampAreDisclosedWithoutRebindingEvidence() throws {
        let before = try scenario()
        let after = try later(buildChanges: [(["id"], .string("build.other.fixture")), (["revision"], .number(9)),
                                            (["locks", "catalog_snapshot_id"], .string("catalog.fixture.other"))],
                              estimateChanges: [(["build_id"], .string("build.other.fixture")), (["build_revision"], .number(9)),
                                                (["generated_at"], .string("2026-10-18T08:30:00+02:00")),
                                                (["estimates", "0", "value"], .string("25.000"))])
        let result = try HistoricalResourceComparison.compare(before, after)
        XCTAssertEqual(result.changedFields, HistoricalResourceField.allCases)
        XCTAssertEqual(result.cautions, [.reportedValuesOnly, .differentBuilds, .differentBuildRevisions, .differentBuildLocks])
        XCTAssertEqual(result.configuration.before.id, before.build.id)
        XCTAssertEqual(result.configuration.after.id, after.build.id)
        XCTAssertEqual(result.before.estimate.generatedAt, "2026-10-16T09:00:00Z")
        XCTAssertEqual(result.after.estimate.generatedAt, "2026-10-18T08:30:00+02:00")
        XCTAssertEqual(try group(result).beforeRows.first?.reportedValue, "20.0")
        XCTAssertEqual(try group(result).afterRows.first?.reportedValue, "25.000")
    }
}
