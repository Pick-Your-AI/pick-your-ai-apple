import Foundation
import XCTest
@testable import PlannerCore

final class EvidenceReceiptIdentityTests: XCTestCase {
    private var referencePairs: [(String, String)] {
        let composed = "receipt.caf\u{00e9}"
        let decomposed = "receipt.cafe\u{0301}"
        return [(composed, decomposed), (decomposed, composed)]
    }

    func testInspectionReferenceBytesDistinguishReceiptsAndPresentations() throws {
        for field in 0..<2 {
            for (selected, other) in referencePairs {
                XCTAssertEqual(selected, other)
                XCTAssertNotEqual(Array(selected.utf8), Array(other.utf8))
                var retained = ["https://example.test/claim", "inspection.fixture"]
                var changed = retained
                retained[field] = selected
                changed[field] = other
                let original = try inspection(retained)
                let replacement = try inspection(changed)

                XCTAssertNotEqual(original, replacement)
                XCTAssertNotEqual(ClaimSourceAvailability.inspected(original), .inspected(replacement))
                let before = try presentation(source: .inspected(original))
                let after = try presentation(source: .inspected(replacement))
                XCTAssertNotEqual(before, after)
                XCTAssertEqual(before.displayGrade, .sourceChecked)
                XCTAssertEqual(after.displayGrade, .sourceChecked)
                XCTAssertEqual(Array(original.sourceReference.utf8), Array(retained[0].utf8))
                XCTAssertEqual(Array(original.inspectionReference.utf8), Array(retained[1].utf8))

                let copied = try inspection(retained.map(copyBytes))
                XCTAssertEqual(original, copied)
                XCTAssertEqual(before, try presentation(source: .inspected(copied)))
            }
        }
    }

    func testIndependentSupportReferenceBytesDistinguishReceiptsAndPresentations() throws {
        let source = ClaimSourceAvailability.inspected(try inspection(["source.fixture", "inspection.fixture"]))
        for field in 0..<2 {
            for (selected, other) in referencePairs {
                XCTAssertEqual(selected, other)
                XCTAssertNotEqual(Array(selected.utf8), Array(other.utf8))
                var retained = ["evidence.fixture", "acceptance.fixture"]
                var changed = retained
                retained[field] = selected
                changed[field] = other
                let original = try support(retained)
                let replacement = try support(changed)

                XCTAssertNotEqual(original, replacement)
                let before = try presentation(source: source, support: original)
                let after = try presentation(source: source, support: replacement)
                XCTAssertNotEqual(before, after)
                XCTAssertEqual(before.displayGrade, .independentlyVerified)
                XCTAssertEqual(after.displayGrade, .independentlyVerified)
                XCTAssertEqual(Array(original.evidenceReference.utf8), Array(retained[0].utf8))
                XCTAssertEqual(Array(original.acceptanceReference.utf8), Array(retained[1].utf8))

                let copied = try support(retained.map(copyBytes))
                XCTAssertEqual(original, copied)
                XCTAssertEqual(before, try presentation(source: source, support: copied))
            }
        }
    }

    func testRetrievalMethodRetainsOrdinaryTextEquality() throws {
        for (selected, other) in referencePairs {
            let original = try inspection(["source.fixture", "inspection.fixture"], method: selected)
            let equivalent = try inspection(["source.fixture", "inspection.fixture"], method: other)
            let different = try inspection(["source.fixture", "inspection.fixture"], method: "different retrieval")

            XCTAssertEqual(original, equivalent)
            XCTAssertNotEqual(original, different)
            XCTAssertEqual(try presentation(source: .inspected(original)),
                           try presentation(source: .inspected(equivalent)))
            XCTAssertNotEqual(try presentation(source: .inspected(original)),
                              try presentation(source: .inspected(different)))
            XCTAssertEqual(Array(original.retrievalMethod.utf8), Array(selected.utf8))
            XCTAssertEqual(Array(equivalent.retrievalMethod.utf8), Array(other.utf8))
        }
    }

    func testRecheckPreservesExactReceiptReferencesAndGradeRules() throws {
        for (reference, _) in referencePairs {
            let inspectionReceipt = try inspection([reference, reference])
            let supportReceipt = try support([reference, reference])
            let original = try presentation(source: .inspected(inspectionReceipt), support: supportReceipt)
            let received = original.receiving(.correction(original.identity))

            XCTAssertEqual(received.reviewRequirement, .recheckRequired)
            XCTAssertEqual(received.displayGrade, .unverified)
            guard case .inspected(let retained) = received.source else {
                return XCTFail("Recheck must retain the original source inspection")
            }
            let retainedSupport = try XCTUnwrap(received.independentSupport)
            XCTAssertEqual(Array(retained.sourceReference.utf8), Array(reference.utf8))
            XCTAssertEqual(Array(retained.inspectionReference.utf8), Array(reference.utf8))
            XCTAssertEqual(Array(retainedSupport.evidenceReference.utf8), Array(reference.utf8))
            XCTAssertEqual(Array(retainedSupport.acceptanceReference.utf8), Array(reference.utf8))
            XCTAssertEqual(original.displayGrade, .independentlyVerified)
        }
    }

    private func inspection(_ references: [String], method: String = "rendered text inspected") throws -> SourceInspectionReceipt {
        try SourceInspectionReceipt(sourceReference: references[0], inspectionReference: references[1], retrievalMethod: method)
    }

    private func support(_ references: [String]) throws -> AcceptedIndependentSupport {
        try AcceptedIndependentSupport(evidenceReference: references[0], acceptanceReference: references[1])
    }

    private func presentation(source: ClaimSourceAvailability, support: AcceptedIndependentSupport? = nil) throws -> EvidencePresentation {
        EvidencePresentation(identity: try RetainedEvidenceIdentity(componentID: "component.fixture", componentVersion: "v1", catalogSnapshotID: "catalog.fixture.1"),
                             originalVerificationStatus: .verified, source: source,
                             independentSupport: support, freshness: .versionPinned)
    }

    private func copyBytes(_ value: String) -> String {
        String(decoding: Array(value.utf8), as: UTF8.self)
    }
}
