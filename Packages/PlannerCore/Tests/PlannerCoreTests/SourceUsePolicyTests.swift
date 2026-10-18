import XCTest
@testable import PlannerCore

final class SourceUsePolicyTests: XCTestCase {
    private func request(source: String = "source.fixture", claim: String = "claim.fixture", version: String = "v1",
                         snapshot: String = "snapshot.fixture", digest: String = String(repeating: "a", count: 64),
                         operation: SourceUseOperation = .appleDisplay, scope: String = "metadata-only",
                         kind: SourceMaterialKind = .production) throws -> SourceUseRequest {
        try SourceUseRequest(sourceID: source, claimID: claim, sourceVersion: version, snapshotID: snapshot,
                             claimSHA256: digest, operation: operation, scopeID: scope, materialKind: kind)
    }
    private func row(revision: String = String(repeating: "b", count: 40), date: String = "2026-10-16",
                     rowID: String = "source.fixture-row") throws -> SourceRightsRow {
        try SourceRightsRow(recordReference: "https://example.test/rights", recordRevision: revision, rowID: rowID,
                            termsReference: "https://example.test/terms", termsCheckedDate: date)
    }
    private func decision(_ request: SourceUseRequest, row: SourceRightsRow? = nil,
                          disposition: SourceRightsDisposition = .permitted,
                          conditions: SourceUseConditions = .satisfied(receiptReference: "conditions.fixture")) throws -> SourceRightsDecision {
        SourceRightsDecision(request: request, row: try row ?? self.row(), disposition: disposition, conditions: conditions)
    }
    private func promotion(_ request: SourceUseRequest, row: SourceRightsRow? = nil,
                           reference: String = "promotion.fixture", disposition: SourcePromotionDisposition = .accepted) throws -> SourcePromotionReceipt {
        SourcePromotionReceipt(request: request, rightsRow: try row ?? self.row(), receiptReference: reference, disposition: disposition)
    }
    func testExactApprovalProducesTraceableAudit() throws {
        let subject = try request()
        let result = try SourceUsePolicy.assess(subject, rights: [decision(subject)], promotions: [promotion(subject)])
        guard case .authorized(let audit) = result else { return XCTFail("Expected the exact synthetic approval scenario to authorize") }
        XCTAssertEqual(audit.request, subject)
        XCTAssertEqual(audit.rightsRow, try row())
        XCTAssertEqual(audit.conditionsReceiptReference, "conditions.fixture")
        XCTAssertEqual(audit.promotionReceiptReference, "promotion.fixture")
    }
    func testPublicSourceAndMergedResearchCannotSubstituteForRightsOrPromotion() throws {
        let publicSource = try request(source: "https://public.example.test/data")
        XCTAssertEqual(SourceUsePolicy.assess(publicSource, rights: [], promotions: []), .denied(.noMatchingRightsDecision))
        XCTAssertEqual(try SourceUsePolicy.assess(publicSource, rights: [decision(publicSource)], promotions: []), .denied(.noMatchingPromotion))
        XCTAssertEqual(try SourceUsePolicy.assess(publicSource, rights: [decision(publicSource)], promotions: [promotion(publicSource, reference: "merged-research", disposition: .pending)]), .denied(.promotionNotAccepted))
    }
    func testEveryIdentityAndScopeDimensionMustMatch() throws {
        let original = try request()
        let changed = try [request(source: "another-source"), request(claim: "upstream-measurement"), request(version: "v2"),
                           request(snapshot: "another-snapshot"), request(digest: String(repeating: "c", count: 64)),
                           request(scope: "standalone-price-comparison")]
        for candidate in changed {
            XCTAssertEqual(try SourceUsePolicy.assess(candidate, rights: [decision(original)], promotions: [promotion(original)]), .denied(.noMatchingRightsDecision))
            XCTAssertEqual(try SourceUsePolicy.assess(candidate, rights: [decision(candidate)], promotions: [promotion(original)]), .denied(.noMatchingPromotion))
        }
    }
    func testDisplayNeverGrantsOfflineExportOrAutomatedRetrieval() throws {
        let display = try request()
        for operation in [SourceUseOperation.offlineCache, .export, .automatedRetrieval] {
            let candidate = try request(operation: operation)
            XCTAssertEqual(try SourceUsePolicy.assess(candidate, rights: [decision(display)], promotions: [promotion(display)]), .denied(.noMatchingRightsDecision))
            let permitted = try SourceUsePolicy.assess(candidate, rights: [decision(candidate)], promotions: [promotion(candidate)])
            guard case .authorized = permitted else { return XCTFail("Exact operation receipt should match") }
        }
    }
    func testUnknownDeniedAndRevokedExcludeEvenWithPromotion() throws {
        let subject = try request()
        for (disposition, denial) in [(SourceRightsDisposition.unknown, SourceUseDenial.rightsUnknown), (.denied, .rightsDenied), (.revoked, .rightsRevoked)] {
            XCTAssertEqual(try SourceUsePolicy.assess(subject, rights: [decision(subject, disposition: disposition)], promotions: [promotion(subject)]), .denied(denial))
        }
    }
    func testConditionsAndProductionReviewMustBeExplicitlySatisfied() throws {
        let subject = try request()
        for conditions in [SourceUseConditions.unknown, .unsatisfied, .satisfied(receiptReference: " \n")] {
            XCTAssertEqual(try SourceUsePolicy.assess(subject, rights: [decision(subject, conditions: conditions)], promotions: [promotion(subject)]), .denied(.conditionsUnverified))
        }
        for state in [SourcePromotionDisposition.pending, .rejected] {
            XCTAssertEqual(try SourceUsePolicy.assess(subject, rights: [decision(subject)], promotions: [promotion(subject, disposition: state)]), .denied(.promotionNotAccepted))
        }
        XCTAssertEqual(try SourceUsePolicy.assess(subject, rights: [decision(subject)], promotions: [promotion(subject, reference: "")]), .denied(.promotionNotAccepted))
        XCTAssertEqual(try SourceUsePolicy.assess(subject, rights: [decision(subject)], promotions: [promotion(subject, disposition: .revoked)]), .denied(.promotionRevoked))
    }
    func testChangedRightsRowRequiresNewExactPromotionAndRecovery() throws {
        let subject = try request()
        for updated in [try row(revision: String(repeating: "c", count: 40)), try row(date: "2026-10-17"), try row(rowID: "different-scope-row")] {
            XCTAssertEqual(try SourceUsePolicy.assess(subject, rights: [decision(subject, row: updated)], promotions: [promotion(subject)]), .denied(.noMatchingPromotion))
            let recovered = try SourceUsePolicy.assess(subject, rights: [decision(subject, row: updated)], promotions: [promotion(subject, row: updated)])
            guard case .authorized(let audit) = recovered else { return XCTFail("Updated exact promotion must permit recovery") }
            XCTAssertEqual(audit.rightsRow, updated)
        }
    }
    func testConflictsAndRevocationsCannotBeOverriddenByArrayOrder() throws {
        let subject = try request()
        let allowed = try decision(subject), revoked = try decision(subject, disposition: .revoked)
        for decisions in [[allowed, revoked], [revoked, allowed]] {
            XCTAssertEqual(try SourceUsePolicy.assess(subject, rights: decisions, promotions: [promotion(subject)]), .denied(.rightsRevoked))
        }
        XCTAssertEqual(try SourceUsePolicy.assess(subject, rights: [allowed, allowed], promotions: [promotion(subject)]), .denied(.conflictingRightsDecisions))
        let approved = try promotion(subject), withdrawn = try promotion(subject, disposition: .revoked)
        for approvals in [[approved, withdrawn], [withdrawn, approved]] {
            XCTAssertEqual(SourceUsePolicy.assess(subject, rights: [allowed], promotions: approvals), .denied(.promotionRevoked))
        }
        XCTAssertEqual(SourceUsePolicy.assess(subject, rights: [allowed], promotions: [approved, approved]), .denied(.conflictingPromotions))
    }
    func testSyntheticMaterialIsNeverProductionAuthorization() throws {
        let synthetic = try request(kind: .syntheticFixture)
        let real = try request()
        XCTAssertEqual(SourceUsePolicy.assess(synthetic, rights: [], promotions: []), .syntheticOnly)
        XCTAssertEqual(try SourceUsePolicy.assess(synthetic, rights: [decision(synthetic)], promotions: [promotion(synthetic)]), .syntheticOnly)
        XCTAssertEqual(try SourceUsePolicy.assess(real, rights: [decision(synthetic)], promotions: [promotion(synthetic)]), .denied(.noMatchingRightsDecision))
    }
    func testKnownFrozenDemoIdentitiesCannotBeRelabeledAsProduction() throws {
        let candidates = try FrozenV1SyntheticSourceIdentities.identifiers.flatMap { id in
            try [request(source: id), request(claim: id), request(snapshot: id)]
        } + FrozenV1SyntheticSourceIdentities.componentVersions.map { try request(version: $0) }
        for candidate in candidates {
            XCTAssertEqual(try SourceUsePolicy.assess(candidate, rights: [decision(candidate)], promotions: [promotion(candidate)]), .denied(.syntheticIdentity))
        }
        // No guessed wildcard: a similar spelling is not a known fixture. It
        // still requires its own real intake receipts and exact approval.
        let similar = try request(claim: "cat.model.fixture-reviewed")
        XCTAssertEqual(SourceUsePolicy.assess(similar, rights: [], promotions: []), .denied(.noMatchingRightsDecision))
    }
    func testInvalidIdentityFingerprintRevisionAndDateRejected() throws {
        XCTAssertThrowsError(try request(source: " \n"))
        XCTAssertThrowsError(try request(claim: ""))
        XCTAssertThrowsError(try request(digest: "digest"))
        XCTAssertThrowsError(try request(digest: String(repeating: "A", count: 64)))
        XCTAssertThrowsError(try row(revision: "main"))
        for date in ["2026-02-29", "1900-02-29", "0000-01-01", "2026-01-01\n", "2026-04-31", "2026-00-01", "2026-01-00"] {
            XCTAssertThrowsError(try row(date: date), date)
        }
        XCTAssertEqual(try row(date: "2000-02-29").termsCheckedDate, "2000-02-29")
    }
}
