import Foundation
import XCTest
import PlannerCore
import PlannerData
@testable import PlannerTransfer

/// All values below are fictional consumer fixtures. They exercise retained
/// policy outcomes, not an evaluator, real price, evidence receipt or quality.
final class SelectionAlternativeTests: XCTestCase, @unchecked Sendable {
    private let later = "2026-10-19T22:00:00Z"
    private let storeIdentity = UUID(), draftIdentity = UUID(), selectionSessionIdentity = UUID()

    private func owner(draftID: UUID? = nil, revision: Int = 1) throws -> AlternativeSelectionOwner {
        try AlternativeSelectionOwner(storeID: storeIdentity, draftID: draftID ?? draftIdentity,
            draftRevision: revision, selectionSessionID: selectionSessionIdentity)
    }

    private func encoded(_ value: JSONValue) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private func fixture(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        var parser = try JSONParser(Data(contentsOf: url))
        return try parser.parse()
    }
    private func build(_ changes: [String: JSONValue] = [:]) throws -> BuildSnapshot {
        var object = try fixture("build").object!
        for (key, value) in changes { object[key] = value }
        return try BuildTransfer.snapshot(fromDraftJSON: encoded(.object(object)))
    }
    private func catalog(version: String = "2026.10-demo", duplicate: Bool = false) throws -> CatalogSnapshot {
        var object = try fixture("catalog").object!
        var items = object["items"]!.array!
        var candidate = try XCTUnwrap(items.first { $0.object?["kind"] == .string("model") }).object!
        candidate["id"] = .string("cat.model.alternative.fixture")
        candidate["name"] = .string("FICTIONAL lower reported cost, unverified evidence")
        candidate["version"] = .string(version)
        items.append(.object(candidate))
        if duplicate { items.append(.object(candidate)) }
        object["items"] = .array(items)
        return try CatalogSnapshot.decode(encoded(.object(object)))
    }
    private func alternative(build selected: BuildSnapshot? = nil, catalog release: CatalogSnapshot? = nil) throws -> SelectionAlternative {
        try .prepare(build: selected ?? build(), catalog: release ?? catalog(), selectionID: "sel_model",
                     candidateID: "cat.model.alternative.fixture", candidateVersion: "2026.10-demo", updatedAt: later)
    }
    private func finding(_ rule: String, _ outcome: String, ids: [String] = ["sel_model"], remediation: String? = "Review the named setting before choosing.") -> JSONValue {
        var object: [String: JSONValue] = [
            "rule_id": .string(rule), "outcome": .string(outcome), "severity": .string("error"),
            "code": .string("FIXTURE_RULE"), "message": .string("FICTIONAL retained rule outcome: " + outcome),
            "selection_ids": .array(ids.map(JSONValue.string)),
            "evidence": .array([.object(["path": .string("selection.spec.fixture"),
                "observed": .null, "expected": .string("qualified input"), "source_version": .string("fixture-evidence-v1")])]),
        ]
        if let remediation { object["remediation"] = .string(remediation) }
        return .object(object)
    }
    private func report(_ build: BuildSnapshot, findings: [JSONValue], changes: [String: JSONValue] = [:]) throws -> EvaluationReport {
        let b = build.value.object!, locks = b["locks"]!.object!
        func count(_ outcome: String) -> Int { findings.filter { $0.object!["outcome"] == .string(outcome) }.count }
        var object: [String: JSONValue] = [
            "schema_version": .string("1.0.0"), "id": .string("evaluation.alternative.fixture.r" + NSDecimalNumber(decimal: b["revision"]!.number!).stringValue),
            "build_id": b["id"]!, "build_revision": b["revision"]!,
            "catalog_snapshot_id": locks["catalog_snapshot_id"]!, "ruleset_id": locks["ruleset_id"]!,
            "ruleset_version": locks["ruleset_version"]!, "dependency_graph_id": locks["dependency_graph_id"]!,
            "dependency_graph_revision": locks["dependency_graph_revision"]!, "evaluated_at": .string(later),
            "result": .string(count("fail") > 0 ? "invalid" : count("unknown") > 0 ? "indeterminate" : "valid"),
            "deployment_readiness": .string("needs_review"), "findings": .array(findings),
            "summary": .object(["passed": .number(Decimal(count("pass"))), "failed": .number(Decimal(count("fail"))),
                "unknown": .number(Decimal(count("unknown"))), "skipped": .number(Decimal(count("skipped")))])
        ]
        for (key, value) in changes { object[key] = value }
        return try EvaluationReport.decode(encoded(.object(object)))
    }
    private func cost(_ build: BuildSnapshot, total: String, changes: [String: JSONValue] = [:]) throws -> CostEstimateRecord {
        var object = try fixture("cost-estimate").object!
        object["id"] = .string("estimate.alternative.fixture.r" + NSDecimalNumber(decimal: build.value.object!["revision"]!.number!).stringValue)
        object["build_revision"] = build.value.object!["revision"]!
        let money = JSONValue.object(["amount": .string(total), "currency": .string("USD")])
        object["subtotal"] = money; object["total"] = money
        var line = object["line_items"]!.array!.first!.object!
        line["selection_id"] = .string("sel_model"); line["quantity"] = .string("1")
        line["meter"] = .string("request"); line["unit_price"] = money; line["amount"] = money
        object["line_items"] = .array([.object(line)])
        for (key, value) in changes { object[key] = value }
        return try CostEstimateRecord.decode(encoded(.object(object)))
    }
    private func evidence(_ item: CatalogItem, checked: Bool) throws -> EvidencePresentation {
        let identity = try RetainedEvidenceIdentity(componentID: item.id, componentVersion: item.version,
                                                   catalogSnapshotID: "catalog.fixture.1")
        let source: ClaimSourceAvailability = checked ? .inspected(try SourceInspectionReceipt(
            sourceReference: "fixture:source", inspectionReference: "fixture:inspection", retrievalMethod: "fictional fixture")) : .notInspected
        return EvidencePresentation(identity: identity, originalVerificationStatus: checked ? .verified : .unverified,
                                    source: source, freshness: .versionPinned)
    }
    private func comparison(_ a: SelectionAlternative? = nil, before: EvaluationReport? = nil,
                            after: EvaluationReport? = nil, beforeCost: CostEstimateRecord? = nil,
                            afterCost: CostEstimateRecord? = nil) throws -> AlternativeComparison {
        let a = try a ?? alternative()
        return try AlternativeComparison(alternative: a, baselineReport: before, candidateReport: after,
            baselineEvidence: nil, candidateEvidence: nil, baselineCost: beforeCost, candidateCost: afterCost)
    }

    func testProposalChangesOnlyTheSelectedCatalogReferenceAndDraftRevision() throws {
        let original = try build(["lifecycle": .string("ready"), "name": .string("Private original e\u{301}")])
        let a = try alternative(build: original)
        var restored = a.proposed.value.object!, old = original.value.object!
        var selections = restored["selections"]!.array!
        let index = try XCTUnwrap(selections.firstIndex { $0.object!["id"] == .string("sel_model") })
        let target = selections[index].object!
        XCTAssertEqual(target["catalog_item_id"], .string("cat.model.alternative.fixture"))
        XCTAssertEqual(target["role"], .string("primary"))
        selections[index] = old["selections"]!.array![index]
        restored["selections"] = .array(selections)
        XCTAssertEqual(restored["revision"], .number(2)); XCTAssertEqual(restored["lifecycle"], .string("draft"))
        for key in ["revision", "updated_at", "lifecycle"] { restored[key] = old[key] }
        XCTAssertEqual(.object(restored), original.value)
        XCTAssertEqual(a.original, original)
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: a.proposed.encoded()), a.proposed)
    }

    func testRejectsWrongCatalogMissingCandidateAndCrossKindReplacement() throws {
        let a = try alternative()
        var locks = a.original.locks.object!; locks["catalog_snapshot_id"] = .string("catalog.other")
        XCTAssertThrowsError(try alternative(build: build(["locks": .object(locks)]))) { XCTAssertEqual($0 as? SelectionAlternativeError, .catalogMismatch) }
        for (id, error) in [("cat.missing.fixture", SelectionAlternativeError.missingCatalogItem),
                            ("cat.accelerator.fixture", .differentKind), ("cat.model.fixture", .unchangedCandidate)] {
            XCTAssertThrowsError(try SelectionAlternative.prepare(build: a.original, catalog: a.catalog, selectionID: "sel_model",
                candidateID: id, candidateVersion: "2026.10-demo", updatedAt: later)) { XCTAssertEqual($0 as? SelectionAlternativeError, error) }
        }
    }

    func testDuplicateIdentitiesAndDisabledOrWorkloadSlotsReject() throws {
        XCTAssertThrowsError(try alternative(catalog: catalog(duplicate: true))) { XCTAssertEqual($0 as? SelectionAlternativeError, .ambiguousCatalogIdentity) }
        let a = try alternative(); var selections = a.original.value.object!["selections"]!.array!
        selections.append(selections[0])
        XCTAssertThrowsError(try alternative(build: build(["selections": .array(selections)]))) { XCTAssertEqual($0 as? SelectionAlternativeError, .ambiguousSelectionIdentity) }
        selections.removeLast()
        let index = try XCTUnwrap(selections.firstIndex { $0.object!["id"] == .string("sel_model") })
        var row = selections[index].object!; row["enabled"] = .bool(false); selections[index] = .object(row)
        XCTAssertThrowsError(try alternative(build: build(["selections": .array(selections)]))) { XCTAssertEqual($0 as? SelectionAlternativeError, .disabledSelection) }
        for id in ["sel_workload", "sel_deployment_mode"] {
            XCTAssertThrowsError(try SelectionAlternative.prepare(build: a.original, catalog: a.catalog, selectionID: id,
                candidateID: a.candidateItem.id, candidateVersion: a.candidateItem.version, updatedAt: later)) { XCTAssertEqual($0 as? SelectionAlternativeError, .differentWorkloadBasis) }
        }
    }

    func testCandidateVersionIdentityIsExactUTF8() throws {
        let release = try catalog(version: "fixture-e\u{301}")
        XCTAssertThrowsError(try SelectionAlternative.prepare(build: build(), catalog: release, selectionID: "sel_model",
            candidateID: "cat.model.alternative.fixture", candidateVersion: "fixture-é", updatedAt: later)) { XCTAssertEqual($0 as? SelectionAlternativeError, .missingCatalogItem) }
        let a = try SelectionAlternative.prepare(build: build(), catalog: release, selectionID: "sel_model",
            candidateID: "cat.model.alternative.fixture", candidateVersion: "fixture-e\u{301}", updatedAt: later)
        XCTAssertEqual(Array(a.candidateItem.version.utf8), Array("fixture-e\u{301}".utf8))
    }

    func testLowerReportedCostKeepsWeakerEvidenceAndOriginalRuleTradeoffs() throws {
        let a = try alternative()
        let before = try report(a.original, findings: [finding("rule.inherited", "fail"), finding("rule.changed", "fail"), finding("rule.unknown", "unknown"), finding("rule.skipped", "skipped")])
        let after = try report(a.proposed, findings: [finding("rule.inherited", "fail"), finding("rule.changed", "pass"), finding("rule.unknown", "unknown"), finding("rule.skipped", "skipped")])
        let c = try AlternativeComparison(alternative: a, baselineReport: before, candidateReport: after,
            baselineEvidence: evidence(a.currentItem, checked: true), candidateEvidence: evidence(a.candidateItem, checked: false),
            baselineCost: cost(a.original, total: "100.000"), candidateCost: cost(a.proposed, total: "60.00"))
        XCTAssertEqual(c.reportedCostRelation, .lower)
        XCTAssertEqual(c.baselineEvidence?.displayGrade, .sourceChecked)
        XCTAssertEqual(c.candidateEvidence?.displayGrade, .unverified)
        XCTAssertEqual(c.baselineCost?.estimate.total.amount, "100.000")
        XCTAssertEqual(c.candidateCost?.estimate.total.amount, "60.00")
        XCTAssertEqual(c.findingChanges.map(\.transition), [.reportedResolved, .persistingFailure, .unchanged, .unchanged])
        XCTAssertEqual(c.findingChanges[1].after?.selectionIDs, ["sel_model"])
        XCTAssertEqual(c.findingChanges[1].after?.evidence?.first?.sourceVersion, "fixture-evidence-v1")
        XCTAssertEqual(c.candidateReport, after); XCTAssertEqual(c.baselineReport, before)
        XCTAssertTrue(c.costNotice.contains("not a verified cheaper")); XCTAssertTrue(c.evidenceNotice.contains("not model quality"))
        XCTAssertEqual(a.original, try build())
    }

    func testMissingSkippedAndUnknownFindingsDoNotBecomeResolvedOrCandidateCaused() throws {
        let a = try alternative()
        let before = try report(a.original, findings: [finding("rule.absent", "fail"), finding("rule.skipped", "fail"), finding("rule.unknown", "fail")])
        let after = try report(a.proposed, findings: [finding("rule.new", "fail"), finding("rule.skipped", "skipped"), finding("rule.unknown", "unknown", remediation: nil)])
        let c = try comparison(a, before: before, after: after)
        XCTAssertEqual(c.findingChanges.map(\.transition), [.notReportedAfter, .notReportedBefore, .changed, .changed])
        XCTAssertTrue(c.gaps.contains(.candidateSafeNextStepMissing))
        let missing = try comparison(a, after: after)
        XCTAssertTrue(missing.findingChanges.allSatisfy { $0.transition == .baselineUnavailable })
        XCTAssertTrue(missing.gaps.contains(.baselineEvaluationUnavailable))
        XCTAssertEqual(missing.reportedCostRelation, .notComparable)
    }

    func testReportPinsParticipantsAndDuplicateFindingsAreValidatedIndependently() throws {
        let a = try alternative()
        let bad: [String: JSONValue] = ["build_id": .string("build.foreign"), "build_revision": .number(1),
            "catalog_snapshot_id": .string("catalog.foreign"), "ruleset_id": .string("rules.foreign"),
            "ruleset_version": .string("2.0.0"), "dependency_graph_id": .string("dependencies.foreign"), "dependency_graph_revision": .number(2)]
        for (key, value) in bad {
            let wrong = try report(a.proposed, findings: [], changes: [key: value])
            XCTAssertThrowsError(try comparison(a, after: wrong)) { XCTAssertEqual($0 as? SelectionAlternativeError, .reportMismatch) }
        }
        let foreign = try report(a.proposed, findings: [finding("rule.foreign", "fail", ids: ["sel_missing"])])
        XCTAssertThrowsError(try comparison(a, after: foreign)) { XCTAssertEqual($0 as? SelectionAlternativeError, .unknownFindingParticipant) }
        let duplicate = try report(a.proposed, findings: [finding("rule.duplicate", "fail"), finding("rule.duplicate", "pass")])
        XCTAssertThrowsError(try comparison(a, after: duplicate)) { XCTAssertEqual($0 as? SelectionAlternativeError, .ambiguousFindingIdentity) }
        let original = try report(a.original, findings: [])
        let reusedID = try report(a.proposed, findings: [], changes: ["id": .string(original.id)])
        XCTAssertThrowsError(try comparison(a, before: original, after: reusedID)) { XCTAssertEqual($0 as? SelectionAlternativeError, .conflictingReportIdentity) }
    }

    func testFindingTextAndEvidenceVersionsUseExactUTF8() throws {
        let a = try alternative()
        for key in ["message", "remediation", "path", "source_version", "observed", "expected"] {
            var beforeFinding = finding("rule.literal", "unknown").object!, afterFinding = beforeFinding
            if key == "message" || key == "remediation" {
                beforeFinding[key] = .string("fixture-e\u{301}"); afterFinding[key] = .string("fixture-é")
            } else {
                var beforeEvidence = beforeFinding["evidence"]!.array!.first!.object!, afterEvidence = beforeEvidence
                beforeEvidence[key] = .string("fixture-e\u{301}"); afterEvidence[key] = .string("fixture-é")
                beforeFinding["evidence"] = .array([.object(beforeEvidence)])
                afterFinding["evidence"] = .array([.object(afterEvidence)])
            }
            let before = try report(a.original, findings: [.object(beforeFinding)])
            let c = try comparison(a, before: before, after: report(a.proposed, findings: [.object(afterFinding)]))
            XCTAssertEqual(c.findingChanges.map(\.transition), [.changed], key)
            let unchanged = try comparison(a, before: before, after: report(a.proposed, findings: [.object(beforeFinding)]))
            XCTAssertEqual(unchanged.findingChanges.map(\.transition), [.unchanged], key)
            if key == "source_version" {
                XCTAssertEqual(Array(try XCTUnwrap(c.findingChanges.first?.before?.evidence?.first?.sourceVersion).utf8), Array("fixture-e\u{301}".utf8))
                XCTAssertEqual(Array(try XCTUnwrap(c.findingChanges.first?.after?.evidence?.first?.sourceVersion).utf8), Array("fixture-é".utf8))
            }
        }
    }

    func testEvidenceMustMatchItsActualComponentAndRetainsRetraction() throws {
        let a = try alternative(), originalEvidence = try evidence(a.currentItem, checked: true)
        XCTAssertThrowsError(try AlternativeComparison(alternative: a, baselineReport: nil, candidateReport: nil,
            baselineEvidence: nil, candidateEvidence: originalEvidence, baselineCost: nil, candidateCost: nil)) { XCTAssertEqual($0 as? SelectionAlternativeError, .evidenceMismatch) }
        let candidate = try evidence(a.candidateItem, checked: true)
        let retracted = candidate.receiving(.retraction(candidate.identity))
        let c = try AlternativeComparison(alternative: a, baselineReport: nil, candidateReport: nil,
            baselineEvidence: originalEvidence, candidateEvidence: retracted, baselineCost: nil, candidateCost: nil)
        XCTAssertEqual(c.candidateEvidence?.displayGrade, .unverified)
        XCTAssertTrue(c.gaps.contains(.candidateEvidenceNeedsRecheck))
    }

    func testPartialMissingAndInconsistentReportedTotalsAreNeverRanked() throws {
        let a = try alternative(), before = try cost(a.original, total: "100.00")
        let variants: [[String: JSONValue]] = [
            ["coverage": .string("partial")], ["coverage": .string("unknown")],
            ["unpriced_selection_ids": .array([.string("sel_model")])], ["period_days": .number(31)],
            ["currency": .string("EUR")], ["subtotal": .object(["amount": .string("1"), "currency": .string("USD")])],
            ["tax": .object(["amount": .string("1"), "currency": .string("USD")])]
        ]
        for changes in variants {
            let c = try comparison(a, beforeCost: before, afterCost: cost(a.proposed, total: "0", changes: changes))
            XCTAssertEqual(c.reportedCostRelation, .notComparable)
            XCTAssertNotNil(c.costComparison)
        }
        XCTAssertEqual(try comparison(a, beforeCost: before).reportedCostRelation, .notComparable)
        let arithmetic = try comparison(a, beforeCost: before, afterCost: cost(a.proposed, total: "0",
            changes: ["tax": .object(["amount": .string("1"), "currency": .string("USD")])]))
        XCTAssertTrue(arithmetic.gaps.contains(.candidateReportedCostArithmeticMismatch))
    }

    func testReportedDecimalOrderingPreservesDigitsBeyondFloatingPointPrecision() throws {
        let a = try alternative()
        let before = try cost(a.original, total: "999999999999999999999999999999999999.000000000002")
        let after = try cost(a.proposed, total: "999999999999999999999999999999999999.000000000001")
        XCTAssertEqual(try comparison(a, beforeCost: before, afterCost: after).reportedCostRelation, .lower)
        XCTAssertEqual(try comparison(a, beforeCost: cost(a.original, total: "1.000"), afterCost: cost(a.proposed, total: "1")).reportedCostRelation, .equal)
        XCTAssertEqual(try comparison(a, beforeCost: cost(a.original, total: "1"), afterCost: cost(a.proposed, total: "2")).reportedCostRelation, .higher)
    }

    func testConfirmationIsExplicitSingleUseAndForeignSessionsCannotConfirm() async throws {
        let c = try comparison(), a = c.alternative, session = AlternativeReplacementSession(), foreign = AlternativeReplacementSession()
        let local = try owner(), review = await session.present(c, owner: local)
        do { _ = try await foreign.confirm(review, currentOwner: local, currentBuild: a.original, currentCatalog: a.catalog, currentComparison: c); XCTFail("foreign confirmation") }
        catch { XCTAssertEqual(error as? SelectionAlternativeError, .staleConfirmation) }
        let selected = try await session.confirm(review, currentOwner: local, currentBuild: a.original, currentCatalog: a.catalog, currentComparison: c)
        XCTAssertEqual(selected, a.proposed)
        do { _ = try await session.confirm(review, currentOwner: local, currentBuild: a.original, currentCatalog: a.catalog, currentComparison: c); XCTFail("duplicate confirmation") }
        catch { XCTAssertEqual(error as? SelectionAlternativeError, .staleConfirmation) }
    }

    func testDismissalAndSameContentReopeningRejectOldCallbacksWithoutRetiringNewReview() async throws {
        let c = try comparison(), a = c.alternative, session = AlternativeReplacementSession()
        let local = try owner(), old = await session.present(c, owner: local); await session.invalidate()
        let current = await session.present(c, owner: local)
        do { _ = try await session.confirm(old, currentOwner: local, currentBuild: a.original, currentCatalog: a.catalog, currentComparison: c); XCTFail("retired callback") }
        catch { XCTAssertEqual(error as? SelectionAlternativeError, .staleConfirmation) }
        let result = try await session.confirm(current, currentOwner: local, currentBuild: a.original, currentCatalog: a.catalog, currentComparison: c)
        XCTAssertEqual(result, a.proposed)
    }

    func testBuildCatalogAndNewAssessmentChangesRevokeConfirmation() async throws {
        let c = try comparison(), a = c.alternative
        var objectives = a.original.value.object!["objectives"]!.object!; objectives["currency"] = .string("EUR")
        let changedBuild = try build(["objectives": .object(objectives)])
        var catalogObject = a.catalog.value.object!; catalogObject["revision"] = .number(2)
        let changedCatalog = try CatalogSnapshot.decode(encoded(.object(catalogObject)))
        let cases = [(changedBuild, a.catalog, c), (a.original, changedCatalog, c), (a.original, a.catalog, try comparison(a))]
        let local = try owner()
        for (build, catalog, latest) in cases {
            let session = AlternativeReplacementSession(), review = await session.present(c, owner: local)
            do { _ = try await session.confirm(review, currentOwner: local, currentBuild: build, currentCatalog: catalog, currentComparison: latest); XCTFail("stale context") }
            catch { XCTAssertEqual(error as? SelectionAlternativeError, .staleConfirmation) }
            do { _ = try await session.confirm(review, currentOwner: local, currentBuild: a.original, currentCatalog: a.catalog, currentComparison: c); XCTFail("failed token revived") }
            catch { XCTAssertEqual(error as? SelectionAlternativeError, .staleConfirmation) }
        }
    }

    func testSameWireSnapshotCannotCrossLocalStoreDraftRevisionOrSelectionSession() async throws {
        let c = try comparison(), a = c.alternative, local = try owner()
        let changed = try [
            AlternativeSelectionOwner(storeID: UUID(), draftID: local.draftID, draftRevision: 1, selectionSessionID: local.selectionSessionID),
            AlternativeSelectionOwner(storeID: local.storeID, draftID: UUID(), draftRevision: 1, selectionSessionID: local.selectionSessionID),
            AlternativeSelectionOwner(storeID: local.storeID, draftID: local.draftID, draftRevision: 2, selectionSessionID: local.selectionSessionID),
            AlternativeSelectionOwner(storeID: local.storeID, draftID: local.draftID, draftRevision: 1, selectionSessionID: UUID())]
        for current in changed {
            let session = AlternativeReplacementSession(), review = await session.present(c, owner: local)
            do { _ = try await session.confirm(review, currentOwner: current, currentBuild: a.original, currentCatalog: a.catalog, currentComparison: c); XCTFail("foreign local owner") }
            catch { XCTAssertEqual(error as? SelectionAlternativeError, .staleConfirmation) }
        }
        XCTAssertThrowsError(try AlternativeSelectionOwner(storeID: local.storeID, draftID: local.draftID, draftRevision: 0, selectionSessionID: local.selectionSessionID)) {
            XCTAssertEqual($0 as? SelectionAlternativeError, .invalidLocalOwner)
        }
    }

    func testPreviewAndDismissalPreserveDurableSelectionUntilConfirmedCAS() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("draft.sqlite"), id = UUID()
        let c = try comparison(), a = c.alternative
        let original = try await DraftStore(url: url).save(id: id, expectedRevision: nil, title: "Fixture", payload: a.original.encoded())
        let session = AlternativeReplacementSession(), local = try owner(draftID: id, revision: original.revision)
        _ = await session.present(c, owner: local)
        let afterPreview = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(afterPreview, original)
        await session.invalidate()
        let afterDismissal = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(afterDismissal, original)
        let review = await session.present(c, owner: local)
        let actual = try await DraftStore(url: url).read(id: id)
        let proposed = try await session.confirm(review, currentOwner: owner(draftID: id, revision: actual.revision), currentBuild: BuildTransfer.snapshot(fromDraftJSON: actual.payload),
            currentCatalog: a.catalog, currentComparison: c)
        let beforeSave = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(beforeSave, original)
        let saved = try await DraftStore(url: url).save(id: id, expectedRevision: actual.revision, title: actual.title, payload: proposed.encoded())
        XCTAssertEqual(saved.revision, original.revision + 1)
        XCTAssertFalse(saved.analysisIsCurrent)
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: saved.payload), a.proposed)
        let history = try await DraftStore(url: url).history(id: id)
        XCTAssertEqual(history.records.count, 2)
        XCTAssertTrue(history.records.contains { $0.payload == original.payload })
    }

    func testConcurrentDurableEditWinsAfterConfirmationWithoutAutomaticRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("draft.sqlite"), id = UUID(), c = try comparison(), a = c.alternative
        let original = try await DraftStore(url: url).save(id: id, expectedRevision: nil, title: "Fixture", payload: a.original.encoded())
        let session = AlternativeReplacementSession(), local = try owner(draftID: id, revision: original.revision)
        let review = await session.present(c, owner: local)
        let proposed = try await session.confirm(review, currentOwner: local, currentBuild: a.original, currentCatalog: a.catalog, currentComparison: c)
        let concurrent = try await DraftStore(url: url).save(id: id, expectedRevision: original.revision, title: "Newer owner edit", payload: original.payload)
        do { _ = try await DraftStore(url: url).save(id: id, expectedRevision: original.revision, title: original.title, payload: proposed.encoded()); XCTFail("stale write") }
        catch { XCTAssertEqual(error as? DraftStoreError, .conflict) }
        let actual = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(actual, concurrent)
        XCTAssertEqual(actual.payload, original.payload)
        let history = try await DraftStore(url: url).history(id: id)
        XCTAssertEqual(history.records.count, 2)
    }
}
