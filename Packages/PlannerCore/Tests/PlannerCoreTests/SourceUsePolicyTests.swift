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
                     rowID: String = "source.fixture-row", recordReference: String = "https://example.test/rights",
                     termsReference: String = "https://example.test/terms") throws -> SourceRightsRow {
        try SourceRightsRow(recordReference: recordReference, recordRevision: revision, rowID: rowID,
                            termsReference: termsReference, termsCheckedDate: date)
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
    func testCanonicallyEquivalentRequestIdentitiesRequireTheirOwnReceipts() throws {
        let composed = "identity.caf\u{00e9}"
        let decomposed = "identity.cafe\u{0301}"
        XCTAssertEqual(composed, decomposed, "The language's text equality intentionally treats these strings as equivalent")
        XCTAssertFalse(composed.utf8.elementsEqual(decomposed.utf8))
        let dimensions: [(String, (String) throws -> SourceUseRequest)] = [
            ("source", { try self.request(source: $0) }),
            ("claim", { try self.request(claim: $0) }),
            ("version", { try self.request(version: $0) }),
            ("snapshot", { try self.request(snapshot: $0) }),
            ("scope", { try self.request(scope: $0) }),
        ]
        for (name, make) in dimensions {
            for (approvedText, otherText) in [(composed, decomposed), (decomposed, composed)] {
                let approved = try make(approvedText), other = try make(otherText)
                let exactCopy = try make(String(decoding: Array(otherText.utf8), as: UTF8.self))
                XCTAssertNotEqual(approved, other, name)
                XCTAssertEqual(other, exactCopy, name)
                XCTAssertEqual(Set([approved, other, exactCopy]).count, 2, name)
                XCTAssertEqual(try SourceUsePolicy.assess(other, rights: [decision(approved)], promotions: [promotion(approved)]),
                               .denied(.noMatchingRightsDecision), name)
                XCTAssertEqual(try SourceUsePolicy.assess(other, rights: [decision(other)], promotions: [promotion(approved)]),
                               .denied(.noMatchingPromotion), name)
                let recovered = try SourceUsePolicy.assess(other, rights: [decision(exactCopy)], promotions: [promotion(exactCopy)])
                guard case .authorized(let audit) = recovered else { return XCTFail("Exact \(name) receipts must recover") }
                XCTAssertEqual(audit.request, other, name)
                XCTAssertEqual(audit.conditionsReceiptReference, "conditions.fixture")
                XCTAssertEqual(audit.promotionReceiptReference, "promotion.fixture")
            }
        }
    }
    func testCanonicallyEquivalentRightsRowsRequireTheirOwnPromotion() throws {
        let composed = "https://example.test/caf\u{00e9}"
        let decomposed = "https://example.test/cafe\u{0301}"
        XCTAssertEqual(composed, decomposed)
        XCTAssertFalse(composed.utf8.elementsEqual(decomposed.utf8))
        let subject = try request()
        let dimensions: [(String, (String) throws -> SourceRightsRow)] = [
            ("record reference", { try self.row(recordReference: $0) }),
            ("row identity", { try self.row(rowID: $0) }),
            ("terms reference", { try self.row(termsReference: $0) }),
        ]
        for (name, make) in dimensions {
            for (approvedText, otherText) in [(composed, decomposed), (decomposed, composed)] {
                let approved = try make(approvedText), other = try make(otherText)
                let exactCopy = try make(String(decoding: Array(otherText.utf8), as: UTF8.self))
                XCTAssertNotEqual(approved, other, name)
                XCTAssertEqual(other, exactCopy, name)
                XCTAssertEqual(Set([approved, other, exactCopy]).count, 2, name)
                XCTAssertEqual(try SourceUsePolicy.assess(subject, rights: [decision(subject, row: other)],
                                                        promotions: [promotion(subject, row: approved)]),
                               .denied(.noMatchingPromotion), name)
                let recovered = try SourceUsePolicy.assess(subject, rights: [decision(subject, row: other)],
                                                          promotions: [promotion(subject, row: exactCopy)])
                guard case .authorized(let audit) = recovered else { return XCTFail("Exact \(name) promotion must recover") }
                XCTAssertEqual(audit.rightsRow, other, name)
            }
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
    func testAuditReceiptReferencesRetainExactUnicodeIdentity() throws {
        let composed = "receipt.caf\u{00e9}"
        let decomposed = "receipt.cafe\u{0301}"
        XCTAssertEqual(composed, decomposed, "Display text equality must not erase receipt identity")
        XCTAssertFalse(composed.utf8.elementsEqual(decomposed.utf8))
        let subject = try request()

        func assess(conditions: String, promotion: String) throws -> SourceUseAssessment {
            try SourceUsePolicy.assess(
                subject,
                rights: [decision(subject, conditions: .satisfied(receiptReference: conditions))],
                promotions: [self.promotion(subject, reference: promotion)]
            )
        }

        for (first, second) in [(composed, decomposed), (decomposed, composed)] {
            for field in ["conditions", "promotion"] {
                let original = try assess(conditions: first, promotion: first)
                let changed = try assess(conditions: field == "conditions" ? second : first,
                                         promotion: field == "promotion" ? second : first)
                let exactCopy = try assess(
                    conditions: String(decoding: Array(first.utf8), as: UTF8.self),
                    promotion: String(decoding: Array(first.utf8), as: UTF8.self)
                )
                guard case .authorized(let originalAudit) = original,
                      case .authorized(let changedAudit) = changed,
                      case .authorized(let copiedAudit) = exactCopy else {
                    return XCTFail("Each independently supplied synthetic receipt must produce an audit")
                }
                XCTAssertNotEqual(originalAudit, changedAudit, field)
                XCTAssertNotEqual(original, changed, field)
                XCTAssertEqual(originalAudit, copiedAudit, field)
                XCTAssertEqual(original, exactCopy, field)
                XCTAssertEqual(originalAudit.request, changedAudit.request, field)
                XCTAssertEqual(originalAudit.rightsRow, changedAudit.rightsRow, field)
                XCTAssertTrue(changedAudit.conditionsReceiptReference.utf8.elementsEqual(
                    (field == "conditions" ? second : first).utf8), field)
                XCTAssertTrue(changedAudit.promotionReceiptReference.utf8.elementsEqual(
                    (field == "promotion" ? second : first).utf8), field)
            }
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
