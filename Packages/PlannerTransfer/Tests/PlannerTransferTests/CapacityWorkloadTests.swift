import Foundation
import XCTest
@testable import PlannerTransfer

private final class CapacityWorkloadFixture {
    struct Class {
        var id = "class.one"
        var requests: Any = 1
        var sequences: Any = 4
        var sameScope = true
    }
    let draft: CapacityTestDraft
    var runtime: [String: Any]
    var admissionRuntime: [String: Any]?
    var classes = [Class()]
    var limit: Any = 8
    var units = "sequences"
    var coversAllResident = true
    var fallback = false
    var applicable = true
    var edits: ((CapacityTestDraft) -> Void)?

    init() throws {
        draft = try CapacityTestDraft()
        try draft.serving()
        runtime = draft.runtime()
    }

    func freeze() throws -> (CapacityTestContext, CapacityWorkload) {
        draft.put("/workload/runtime", runtime)
        draft.put("/workload/operation", draft.operation)
        draft.put("/workload/applies", applicable)
        draft.put("/workload/fallback", fallback)
        draft.inventory("/workload/classes", ids: classes.map(\.id))
        for item in classes {
            let prefix = "/workload/classes/" + item.id
            draft.put(prefix + "/requests", item.requests)
            draft.put(prefix + "/sequences", item.sequences)
            draft.put(prefix + "/same-scope", item.sameScope)
        }
        draft.put("/workload/admission/runtime", admissionRuntime ?? runtime)
        draft.put("/workload/admission/limit", limit)
        draft.put("/workload/admission/units", units)
        draft.put("/workload/admission/all-resident", coversAllResident)
        edits?(draft)
        let context = try draft.freeze()
        let binding = try CapacityRuntimeBinding(answer: context.answer("/workload/runtime", .runtimeBinding))
        let domain = try binding.domain ?? .component("sel_model")
        let operation = try context.answer("/workload/operation", .text)
        let applicable = try context.answer("/workload/applies", .boolean)
        let fallback = try context.answer("/workload/fallback", .boolean)
        try context.qualify(applicable, .applicability, domain)
        for value in [binding.answer, operation, fallback] { try context.qualify(value, .workload, domain) }
        let records = try classes.map { item in
            let prefix = "/workload/classes/" + item.id
            let row = try CapacitySequenceClass(id: item.id,
                requests: context.answer(prefix + "/requests", .positiveInteger),
                sequencesPerRequest: context.answer(prefix + "/sequences", .positiveInteger),
                sameScopeAllocation: context.answer(prefix + "/same-scope", .boolean))
            let classDomain = try CapacityDomain.workload(runtime: domain, workloadClass: item.id)
            for answer in row.observations { try context.qualify(answer, .workload, classDomain) }
            return row
        }
        let admission = try CapacitySequenceAdmission(
            binding: CapacityRuntimeBinding(answer: context.answer("/workload/admission/runtime", .runtimeBinding)),
            limit: context.answer("/workload/admission/limit", .positiveInteger),
            units: context.answer("/workload/admission/units", .admissionUnit),
            coversAllResidentKV: context.answer("/workload/admission/all-resident", .boolean))
        for answer in admission.observations { try context.qualify(answer, .workload, domain) }
        let value = try CapacityWorkload(basis: context.basis, graph: context.graph(),
            servingRequirements: XCTUnwrap(context.requirements().first), artifactFacts: context.artifacts(),
            binding: binding, operation: operation, applicable: applicable,
            classes: context.inventory("/workload/classes", records: records,
                                       kind: .workloadStages, scenario: context.basis.operation),
            admission: admission, expandedFallbackCoversAllResident: fallback)
        return (context, value)
    }

    func result(omitting: (CapacityQualification) -> Bool = { _ in false }) throws -> CapacitySequenceResult {
        let (context, value) = try freeze()
        return try value.evaluate(current: context.basis, qualifications: context.qualifications(omitting: omitting))
    }
}

final class CapacityWorkloadTests: XCTestCase {
    func testOneRequestWithFourResidentSequencesExpandsToFour() throws {
        let value = try CapacityWorkloadFixture().result()
        XCTAssertEqual(value.result.outcome, .pass)
        XCTAssertEqual(value.expandedDemand?.decimal, "4")
        XCTAssertEqual(value.residentSequences?.decimal, "4")
        XCTAssertTrue(value.admissionKnown)
        XCTAssertFalse(value.conservativeFallback)
    }

    func testQualifiedSameScopeResidentSequenceAdmissionMayCapDemand() throws {
        let fixture = try CapacityWorkloadFixture()
        fixture.classes = [.init(id: "one", requests: 3, sequences: 4), .init(id: "two", requests: 2, sequences: 3)]
        fixture.limit = 7
        let value = try fixture.result()
        XCTAssertEqual(value.result.outcome, .pass)
        XCTAssertEqual(value.expandedDemand?.decimal, "18")
        XCTAssertEqual(value.residentSequences?.decimal, "7")
        XCTAssertTrue(value.admissionKnown)
    }

    func testRequestAndStepBatchCapsNeverSilentlyReduceResidentSequences() throws {
        for unit in ["requests", "step_batch"] {
            let fixture = try CapacityWorkloadFixture()
            fixture.units = unit; fixture.limit = 1
            let value = try fixture.result()
            XCTAssertEqual(value.result.outcome, .unknown, unit)
            XCTAssertEqual(value.expandedDemand?.decimal, "4", unit)
            XCTAssertNil(value.residentSequences, unit)
            XCTAssertFalse(value.admissionKnown, unit)
        }
    }

    func testExplicitQualifiedFallbackRetainsExpandedDemandAndUnknownAdmission() throws {
        let fixture = try CapacityWorkloadFixture()
        fixture.units = "requests"; fixture.limit = 1; fixture.fallback = true
        let value = try fixture.result()
        XCTAssertEqual(value.result.outcome, .unknown)
        XCTAssertEqual(value.residentSequences?.decimal, "4")
        XCTAssertTrue(value.conservativeFallback)
        XCTAssertFalse(value.admissionKnown)
        XCTAssertEqual(value.result.assumptions, ["qualified_expanded_demand_fallback"])
    }

    func testUnqualifiedFallbackDoesNotCreateAResidentCount() throws {
        let fixture = try CapacityWorkloadFixture()
        fixture.units = "step_batch"; fixture.fallback = true
        let result = try fixture.result { $0.key.requestedPath == "/workload/fallback" }
        XCTAssertEqual(result.result.outcome, .unknown)
        XCTAssertNil(result.residentSequences)
        XCTAssertFalse(result.conservativeFallback)
    }

    func testEveryOriginalRuntimeTupleMemberScopesAdmission() throws {
        for member in ["build", "instance", "replica", "rank", "admission", "stage"] {
            let fixture = try CapacityWorkloadFixture()
            var changed = fixture.runtime; changed[member] = "different.synthetic"
            fixture.admissionRuntime = changed; fixture.limit = 1; fixture.fallback = true
            let value = try fixture.result()
            XCTAssertEqual(value.result.outcome, .unknown, member)
            XCTAssertEqual(value.residentSequences?.decimal, "4", member)
            XCTAssertFalse(value.admissionKnown, member)
        }
    }

    func testNullableRuntimeMemberAbsenceDiffersFromProvidedIdentity() throws {
        let fixture = try CapacityWorkloadFixture()
        var changed = fixture.runtime; changed["stage"] = NSNull()
        fixture.admissionRuntime = changed
        let value = try fixture.result()
        XCTAssertEqual(value.result.outcome, .unknown)
        XCTAssertNil(value.residentSequences)
    }

    func testSelectedRuntimeMustBeTheServingEngineInTheSameActualGraph() throws {
        let fixture = try CapacityWorkloadFixture()
        try fixture.draft.selection("other_engine", kind: "inference_engine")
        fixture.runtime["id"] = "other_engine"
        let value = try fixture.result()
        XCTAssertEqual(value.result.outcome, .unknown)
        XCTAssertNil(value.expandedDemand)
    }

    func testWrongActualRuntimeKindRetainsAnIndependentFailure() throws {
        let fixture = try CapacityWorkloadFixture()
        fixture.runtime["id"] = "sel_host"
        let value = try fixture.result()
        XCTAssertEqual(value.result.outcome, .fail)
        XCTAssertTrue(value.result.checks.contains { $0.rule == .binding && $0.outcome == .fail })
        XCTAssertNil(value.residentSequences)
    }

    func testRuntimeInputMustExistAndKeepEngineBuildKindBeforeSkipping() throws {
        let missing = try CapacityWorkloadFixture()
        missing.applicable = false; missing.runtime["source_input"] = "absent"
        XCTAssertThrowsError(try missing.freeze()) { XCTAssertEqual($0 as? CapacityError, .danglingReference) }
        let wrong = try CapacityWorkloadFixture()
        wrong.applicable = false; wrong.runtime["source_input"] = "hardware"
        XCTAssertThrowsError(try wrong.freeze()) { XCTAssertEqual($0 as? CapacityError, .invalidDomain) }
    }

    func testServiceRuntimeDoesNotBecomeAQualifiedLocalEngineByLabel() throws {
        let fixture = try CapacityWorkloadFixture()
        fixture.runtime["kind"] = "service_runtime"; fixture.runtime["id"] = "service.synthetic"
        let value = try fixture.result()
        XCTAssertEqual(value.result.outcome, .unknown)
        XCTAssertNil(value.residentSequences)
    }

    func testWrongOperationCannotBorrowCurrentEngineAdmission() throws {
        let fixture = try CapacityWorkloadFixture()
        fixture.edits = { $0.put("/workload/operation", "different.operation") }
        let value = try fixture.result()
        XCTAssertEqual(value.result.outcome, .unknown)
        XCTAssertNil(value.expandedDemand)
    }

    func testMissingClassScopeOrCoverageDoesNotGuessASequenceTotal() throws {
        for path in ["/workload/classes/class.one/same-scope", "/workload/classes/complete",
                     "/workload/classes/ids", "/workload/classes/class.one/requests"] {
            let fixture = try CapacityWorkloadFixture()
            fixture.edits = { $0.state(path, .unknown) }
            let value = try fixture.result()
            XCTAssertEqual(value.result.outcome, .unknown, path)
            XCTAssertNil(value.residentSequences, path)
        }
    }

    func testKnownCrossScopeClassCannotBeAddedToCurrentResidentDemand() throws {
        let fixture = try CapacityWorkloadFixture()
        fixture.classes = [.init(id: "current", requests: 1, sequences: 4),
                           .init(id: "different-stage", requests: 9, sequences: 9, sameScope: false)]
        let value = try fixture.result()
        XCTAssertEqual(value.result.outcome, .unknown)
        XCTAssertNil(value.expandedDemand)
    }

    func testProvidedClassInventoryMustExactlyMatchAllOfferedRecords() throws {
        let mismatch = try CapacityWorkloadFixture()
        mismatch.edits = { $0.put("/workload/classes/ids", ["another"]) }
        XCTAssertThrowsError(try mismatch.freeze()) { XCTAssertEqual($0 as? CapacityError, .contradictoryInput) }
        let duplicate = try CapacityWorkloadFixture()
        duplicate.classes = [.init(), .init()]
        XCTAssertThrowsError(try duplicate.freeze())
        let empty = try CapacityWorkloadFixture()
        empty.classes = []
        XCTAssertEqual(try empty.result().result.outcome, .unknown)
    }

    func testAllResidentCoverageIsRequiredEvenForSequenceUnits() throws {
        let fixture = try CapacityWorkloadFixture()
        fixture.coversAllResident = false
        let value = try fixture.result()
        XCTAssertEqual(value.result.outcome, .unknown)
        XCTAssertNil(value.residentSequences)
        XCTAssertFalse(value.admissionKnown)
    }

    func testAdmissionAndDemandQualificationAreIndependent() throws {
        for path in ["/workload/admission/limit", "/workload/admission/runtime",
                     "/workload/classes/class.one/requests", "/workload/runtime"] {
            let fixture = try CapacityWorkloadFixture()
            let value = try fixture.result { $0.key.requestedPath == path }
            XCTAssertEqual(value.result.outcome, .unknown, path)
            XCTAssertNil(value.residentSequences, path)
        }
    }

    func testKnownDisabledWorkloadSkipsAfterCompleteRecordAdmission() throws {
        let fixture = try CapacityWorkloadFixture()
        fixture.applicable = false
        let value = try fixture.result()
        XCTAssertEqual(value.result.outcome, .skipped)
        XCTAssertNil(value.expandedDemand)
        // Integral floating-token negatives use the raw oracle corpus; JSONSerialization can normalize them.
        for invalid in [0, -1, true, "1"] as [Any] {
            let bad = try CapacityWorkloadFixture()
            bad.applicable = false; bad.classes[0].requests = invalid
            XCTAssertThrowsError(try bad.freeze())
        }
    }

    func testExactDemandCanExceedBothBinary64AndUInt64Ranges() throws {
        let fixture = try CapacityWorkloadFixture()
        fixture.classes[0].requests = UInt64.max
        fixture.classes[0].sequences = 4
        fixture.limit = UInt64.max
        let value = try fixture.result()
        XCTAssertEqual(value.expandedDemand?.decimal, "73786976294838206460")
        XCTAssertEqual(value.residentSequences?.decimal, "18446744073709551615")
        XCTAssertEqual(value.result.outcome, .pass)
        let huge = try CapacityCount(decimal: "1208925819614629174706176")
        XCTAssertEqual(try huge.multiplied(by: CapacityCount(decimal: "4")).decimal, "4835703278458516698824704")
        XCTAssertEqual(try huge.adding(CapacityCount(decimal: "1")).decimal, "1208925819614629174706177")
    }

    func testAChangedOriginalBasisCannotReusePriorDemandOrQualifications() throws {
        let fixture = try CapacityWorkloadFixture()
        let (original, workload) = try fixture.freeze()
        let changed = try CapacityWorkloadFixture()
        changed.draft.build["name"] = "different original bytes"
        let (current, _) = try changed.freeze()
        let value = try workload.evaluate(current: current.basis, qualifications: original.qualifications())
        XCTAssertEqual(value.result.outcome, .unknown)
        XCTAssertNil(value.residentSequences)
        XCTAssertEqual(value.result.basisSHA256, current.basis.sha256)
    }

    func testUnresolvedAttributionNeverBecomesQualifiedByItsPresetName() throws {
        let fixture = try CapacityWorkloadFixture()
        fixture.edits = { $0.state("/workload/applies", .unknown) }
        let value = try fixture.result()
        XCTAssertEqual(value.result.outcome, .unknown)
        XCTAssertNil(value.residentSequences)
        XCTAssertFalse(String(describing: value).contains("sel_model"))
        XCTAssertFalse(String(reflecting: value).contains("preset:"))
    }
}
