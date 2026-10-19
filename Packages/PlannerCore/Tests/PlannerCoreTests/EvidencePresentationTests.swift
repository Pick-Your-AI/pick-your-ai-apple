import Foundation
import XCTest
@testable import PlannerCore

final class EvidencePresentationTests: XCTestCase {
    private func identity(_ version: String = "v1") throws -> RetainedEvidenceIdentity {
        try RetainedEvidenceIdentity(componentID: "component.fixture", componentVersion: version, catalogSnapshotID: "catalog.fixture.1")
    }
    private func checked() throws -> ClaimSourceAvailability {
        .inspected(try SourceInspectionReceipt(sourceReference: "https://example.test/claim", inspectionReference: "review.fixture.1", retrievalMethod: "rendered text inspected"))
    }
    private func support() throws -> AcceptedIndependentSupport {
        try AcceptedIndependentSupport(evidenceReference: "reproduction.fixture", acceptanceReference: "review.fixture.accepted")
    }
    func testLegacyVerifiedNeverImpliesIndependentSupport() throws {
        let legacy = EvidencePresentation(identity: try identity(), originalVerificationStatus: .verified, source: try checked(), freshness: .versionPinned)
        XCTAssertEqual(legacy.displayGrade, .sourceChecked)
        XCTAssertEqual(legacy.originalVerificationStatus, .verified)
        let unseen = EvidencePresentation(identity: try identity(), originalVerificationStatus: .verified, source: .notInspected, freshness: .versionPinned)
        XCTAssertEqual(unseen.displayGrade, .unverified)
    }
    func testNewSourceCheckedPreservesUnverifiedWireLabel() throws {
        let value = EvidencePresentation(identity: try identity(), originalVerificationStatus: .unverified, source: try checked(), freshness: .versionPinned)
        XCTAssertEqual(value.displayGrade, .sourceChecked)
        XCTAssertEqual(value.originalVerificationStatus, .unverified)
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(value.originalVerificationStatus), as: UTF8.self), #""unverified""#)
    }
    func testIndependentGradeRequiresInspectedSourceAndAcceptedSupport() throws {
        for source in [ClaimSourceAvailability.notInspected, .unavailable, try checked()] {
            let value = EvidencePresentation(identity: try identity(), originalVerificationStatus: .verified, source: source, independentSupport: try support(), freshness: .versionPinned)
            let expected: EvidenceDisplayGrade = source == .notInspected ? .unverified : source == .unavailable ? .unavailable : .independentlyVerified
            XCTAssertEqual(value.displayGrade, expected)
        }
    }
    func testUserSuppliedAndEstimatedRetainMeaningAndMissingRenderIsUnavailable() throws {
        for status in [OriginalVerificationStatus.userSupplied, .estimated] {
            let value = EvidencePresentation(identity: try identity(), originalVerificationStatus: status, source: try checked(), freshness: .versionPinned)
            XCTAssertEqual(value.displayGrade, status == .estimated ? .estimated : .userSupplied)
            let missing = EvidencePresentation(identity: try identity(), originalVerificationStatus: status, source: .unavailable, freshness: .versionPinned)
            XCTAssertEqual(missing.displayGrade, .unavailable)
        }
    }
    func testCurrentStateRetainsOldCaptureDateAndSnapshotWithoutTTL() throws {
        let original = EvidencePresentation(identity: try identity("2001-01-01"), originalVerificationStatus: .unverified, source: try checked(), freshness: .currentState(captureDate: try EvidenceCaptureDate("2001-01-01")))
        let newer = original.receiving(.newerSnapshotAvailable)
        XCTAssertEqual(newer.identity, original.identity)
        XCTAssertEqual(newer.freshness, original.freshness)
        XCTAssertEqual(newer.displayGrade, .sourceChecked)
        XCTAssertEqual(newer.reviewRequirement, .reviewSelectedEvidence)
        XCTAssertEqual(original.receiving(.newerReleaseAvailable).reviewRequirement, .newerVersionNotice)
        XCTAssertEqual(original.reviewRequirement, .none)
    }
    func testCorrectionAndRetractionRequireSelectedTupleRecheckWithoutRewritingHistory() throws {
        let original = EvidencePresentation(identity: try identity(), originalVerificationStatus: .verified, source: try checked(), freshness: .versionPinned)
        for event in [EvidenceChangeEvent.correction(try identity()), .retraction(try identity())] {
            let changed = original.receiving(event)
            XCTAssertEqual(changed.reviewRequirement, .recheckRequired)
            XCTAssertEqual(changed.displayGrade, .unverified)
            XCTAssertEqual(changed.identity, original.identity)
            XCTAssertEqual(changed.originalVerificationStatus, .verified)
            XCTAssertEqual(changed.receiving(.newerReleaseAvailable).reviewRequirement, .recheckRequired)
            XCTAssertEqual(changed.receiving(.newerSnapshotAvailable).reviewRequirement, .recheckRequired)
        }
        XCTAssertEqual(original.receiving(.correction(try identity("unrelated"))).reviewRequirement, .none)
    }
    func testMalformedReceiptsIdentityAndDatesCannotBeConstructed() throws {
        XCTAssertThrowsError(try SourceInspectionReceipt(sourceReference: " ", inspectionReference: "receipt", retrievalMethod: "read"))
        XCTAssertThrowsError(try AcceptedIndependentSupport(evidenceReference: "test", acceptanceReference: "\n"))
        XCTAssertThrowsError(try RetainedEvidenceIdentity(componentID: "id", componentVersion: "", catalogSnapshotID: "snapshot"))
        for date in ["", "0000-01-01", "2025-02-29", "1900-02-29", "2026-13-01", "2026-04-31", "2026-01-00", "2026-1-01", "2026-01-01\n", "２０２６-01-01"] {
            XCTAssertThrowsError(try EvidenceCaptureDate(date), date)
        }
        XCTAssertEqual(try EvidenceCaptureDate("2000-02-29").rawValue, "2000-02-29")
        XCTAssertEqual(try EvidenceCaptureDate("2024-02-29").rawValue, "2024-02-29")
    }

    func testByteDistinctCorrectionTargetsPreserveUnrelatedEvidence() throws {
        for (retained, unrelated) in try byteDistinctIdentityPairs() {
            let original = EvidencePresentation(identity: retained, originalVerificationStatus: .verified,
                source: try checked(), independentSupport: try support(),
                freshness: .currentState(captureDate: try EvidenceCaptureDate("2001-01-01")))
            for prior in [original, original.receiving(.newerSnapshotAvailable)] {
                for event in [EvidenceChangeEvent.correction(unrelated), .retraction(unrelated)] {
                    let received = prior.receiving(event)
                    XCTAssertEqual(received.reviewRequirement, prior.reviewRequirement)
                    XCTAssertEqual(received.displayGrade, .independentlyVerified)
                    assertRetainedHistory(received, matches: prior)
                }
            }
        }
    }

    func testExactCorrectionTargetsRequireRecheckAndPreserveHistory() throws {
        for (retained, unrelated) in try byteDistinctIdentityPairs() {
            let exactCopy = try RetainedEvidenceIdentity(
                componentID: String(decoding: Array(retained.componentID.utf8), as: UTF8.self),
                componentVersion: String(decoding: Array(retained.componentVersion.utf8), as: UTF8.self),
                catalogSnapshotID: String(decoding: Array(retained.catalogSnapshotID.utf8), as: UTF8.self))
            let original = EvidencePresentation(identity: retained, originalVerificationStatus: .verified,
                source: try checked(), independentSupport: try support(), freshness: .versionPinned)
            for event in [EvidenceChangeEvent.correction(exactCopy), .retraction(exactCopy)] {
                let received = original.receiving(event)
                XCTAssertEqual(received.reviewRequirement, .recheckRequired)
                XCTAssertEqual(received.displayGrade, .unverified)
                assertRetainedHistory(received, matches: original)

                let later = received.receiving(.correction(unrelated)).receiving(.retraction(unrelated))
                    .receiving(.newerSnapshotAvailable).receiving(.newerReleaseAvailable)
                XCTAssertEqual(later.reviewRequirement, .recheckRequired)
                XCTAssertEqual(later.displayGrade, .unverified)
                assertRetainedHistory(later, matches: original)
            }
        }
    }

    private func byteDistinctIdentityPairs() throws -> [(RetainedEvidenceIdentity, RetainedEvidenceIdentity)] {
        let composed = "opaque.caf\u{00e9}"
        let decomposed = "opaque.cafe\u{0301}"
        XCTAssertEqual(composed, decomposed)
        XCTAssertFalse(composed.utf8.elementsEqual(decomposed.utf8))
        var pairs: [(RetainedEvidenceIdentity, RetainedEvidenceIdentity)] = []
        for field in 0..<3 {
            for (selected, other) in [(composed, decomposed), (decomposed, composed)] {
                var retained = ["component.fixture", "v1", "catalog.fixture.1"]
                var unrelated = retained
                retained[field] = selected
                unrelated[field] = other
                pairs.append((
                    try RetainedEvidenceIdentity(componentID: retained[0], componentVersion: retained[1],
                                                 catalogSnapshotID: retained[2]),
                    try RetainedEvidenceIdentity(componentID: unrelated[0], componentVersion: unrelated[1],
                                                 catalogSnapshotID: unrelated[2])))
            }
        }
        return pairs
    }

    private func assertRetainedHistory(_ received: EvidencePresentation, matches original: EvidencePresentation,
                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Array(received.identity.componentID.utf8), Array(original.identity.componentID.utf8), file: file, line: line)
        XCTAssertEqual(Array(received.identity.componentVersion.utf8), Array(original.identity.componentVersion.utf8), file: file, line: line)
        XCTAssertEqual(Array(received.identity.catalogSnapshotID.utf8), Array(original.identity.catalogSnapshotID.utf8), file: file, line: line)
        XCTAssertEqual(received.originalVerificationStatus, original.originalVerificationStatus, file: file, line: line)
        XCTAssertEqual(received.source, original.source, file: file, line: line)
        XCTAssertEqual(received.independentSupport, original.independentSupport, file: file, line: line)
        XCTAssertEqual(received.freshness, original.freshness, file: file, line: line)
    }
}
