import Foundation

/// Display-only interpretation of research #41's accepted #127 mapping
/// (92111483b8d52b1b05152391b2d73e9f59ca2fba). This does not alter frozen v1,
/// determine compatibility, validate legal rights, or certify external evidence.
public enum OriginalVerificationStatus: String, Codable, Sendable {
    case verified, userSupplied = "user_supplied", estimated, unverified
}

public enum EvidenceDisplayGrade: Equatable, Sendable {
    case independentlyVerified, sourceChecked, userSupplied, estimated, unverified, unavailable
}

public enum EvidencePresentationError: Error, Equatable {
    case missingIdentity, missingReceipt, invalidCaptureDate
}

/// Exact retained historical identity; event handling never replaces this tuple.
public struct RetainedEvidenceIdentity: Equatable, Sendable {
    public let componentID: String
    public let componentVersion: String
    public let catalogSnapshotID: String

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.componentID.utf8.elementsEqual(rhs.componentID.utf8) &&
        lhs.componentVersion.utf8.elementsEqual(rhs.componentVersion.utf8) &&
        lhs.catalogSnapshotID.utf8.elementsEqual(rhs.catalogSnapshotID.utf8)
    }

    public init(componentID: String, componentVersion: String, catalogSnapshotID: String) throws {
        guard [componentID, componentVersion, catalogSnapshotID].allSatisfy(nonblankEvidenceText) else {
            throw EvidencePresentationError.missingIdentity
        }
        self.componentID = componentID
        self.componentVersion = componentVersion
        self.catalogSnapshotID = catalogSnapshotID
    }
}

private func nonblankEvidenceText(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// An intake assertion that the actual cited claim text was read, not merely
/// that a URL responded. Keep extraction/capture method with the source receipt.
public struct SourceInspectionReceipt: Equatable, Sendable {
    public let sourceReference: String
    public let inspectionReference: String
    public let retrievalMethod: String
    public init(sourceReference: String, inspectionReference: String, retrievalMethod: String) throws {
        guard [sourceReference, inspectionReference, retrievalMethod].allSatisfy(nonblankEvidenceText) else {
            throw EvidencePresentationError.missingReceipt
        }
        self.sourceReference = sourceReference
        self.inspectionReference = inspectionReference
        self.retrievalMethod = retrievalMethod
    }
}

/// Supplied only after receiving review accepts independent corroboration or
/// reproduction for this claim. Nonempty references are not verified by this
/// library; ingestion remains responsible for resolving the actual receipts.
public struct AcceptedIndependentSupport: Equatable, Sendable {
    public let evidenceReference: String
    public let acceptanceReference: String
    public init(evidenceReference: String, acceptanceReference: String) throws {
        guard [evidenceReference, acceptanceReference].allSatisfy(nonblankEvidenceText) else {
            throw EvidencePresentationError.missingReceipt
        }
        self.evidenceReference = evidenceReference
        self.acceptanceReference = acceptanceReference
    }
}

public enum ClaimSourceAvailability: Equatable, Sendable {
    case notInspected, unavailable
    case inspected(SourceInspectionReceipt)
}

/// An immutable Gregorian capture date, retained without time-based expiry.
public struct EvidenceCaptureDate: Equatable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) throws {
        let bytes = Array(rawValue.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
              let year = Int(rawValue.prefix(4)), year > 0,
              let month = Int(rawValue.dropFirst(5).prefix(2)), (1...12).contains(month),
              let day = Int(rawValue.suffix(2)) else { throw EvidencePresentationError.invalidCaptureDate }
        let leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[month - 1]).contains(day) else { throw EvidencePresentationError.invalidCaptureDate }
        self.rawValue = rawValue
    }
}

public enum EvidenceFreshness: Equatable, Sendable {
    /// Version is supplied by the retained component identity; no TTL applies.
    case versionPinned
    /// Unversioned hosted facts use their capture date and retained snapshot.
    case currentState(captureDate: EvidenceCaptureDate)
}

public enum EvidenceChangeEvent: Equatable, Sendable {
    case newerReleaseAvailable
    case newerSnapshotAvailable
    case correction(RetainedEvidenceIdentity)
    case retraction(RetainedEvidenceIdentity)
}
public enum EvidenceReviewRequirement: Equatable, Sendable {
    case none, newerVersionNotice, reviewSelectedEvidence, recheckRequired
}

public struct EvidencePresentation: Equatable, Sendable {
    public let identity: RetainedEvidenceIdentity
    public let originalVerificationStatus: OriginalVerificationStatus
    public let source: ClaimSourceAvailability
    public let independentSupport: AcceptedIndependentSupport?
    public let freshness: EvidenceFreshness
    public let reviewRequirement: EvidenceReviewRequirement

    public init(identity: RetainedEvidenceIdentity, originalVerificationStatus: OriginalVerificationStatus,
                source: ClaimSourceAvailability, independentSupport: AcceptedIndependentSupport? = nil,
                freshness: EvidenceFreshness) {
        self.identity = identity
        self.originalVerificationStatus = originalVerificationStatus
        self.source = source
        self.independentSupport = independentSupport
        self.freshness = freshness
        reviewRequirement = .none
    }

    public var displayGrade: EvidenceDisplayGrade {
        // A missing/unrendered claim cannot gain a checked or verified badge.
        if source == .unavailable { return .unavailable }
        if reviewRequirement == .recheckRequired { return .unverified }
        guard case .inspected = source else {
            switch originalVerificationStatus {
            case .userSupplied: return .userSupplied
            case .estimated: return .estimated
            case .verified, .unverified: return .unverified
            }
        }
        if independentSupport != nil { return .independentlyVerified }
        switch originalVerificationStatus {
        case .userSupplied: return .userSupplied
        case .estimated: return .estimated
        case .verified, .unverified: return .sourceChecked
        }
    }

    /// Produces a review state, never an invalidated build or rewritten snapshot.
    /// Once a recheck is required, unrelated availability notices cannot clear it.
    public func receiving(_ event: EvidenceChangeEvent) -> Self {
        let next: EvidenceReviewRequirement
        switch event {
        case .newerReleaseAvailable: next = .newerVersionNotice
        case .newerSnapshotAvailable: next = .reviewSelectedEvidence
        case .correction(let affected), .retraction(let affected):
            next = affected == identity ? .recheckRequired : .none
        }
        let priorities: [EvidenceReviewRequirement] = [.none, .newerVersionNotice, .reviewSelectedEvidence, .recheckRequired]
        let retained = priorities.firstIndex(of: reviewRequirement) ?? 0
        let incoming = priorities.firstIndex(of: next) ?? 0
        return Self(copying: self, reviewRequirement: priorities[max(retained, incoming)])
    }

    private init(copying original: Self, reviewRequirement: EvidenceReviewRequirement) {
        identity = original.identity
        originalVerificationStatus = original.originalVerificationStatus
        source = original.source
        independentSupport = original.independentSupport
        freshness = original.freshness
        self.reviewRequirement = reviewRequirement
    }
}
