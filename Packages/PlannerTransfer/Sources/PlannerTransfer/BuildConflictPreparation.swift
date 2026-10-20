import Foundation

/// Payload-free errors for local preparation. These are not service outcomes.
public enum BuildConflictError: Error, Equatable, Sendable {
    case differentBuild, differentOwner, staleReview
}

/// A private local comparison. Missing values remain distinct from JSON null.
/// Arrays are compared as complete ordered values; no element matching is inferred.
public struct BuildConflictDifference: Equatable, Sendable {
    public let path: String
    public let localValue: JSONValue?
    public let incomingValue: JSONValue?

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.path.utf8.elementsEqual(rhs.path.utf8)
            && lhs.localValue == rhs.localValue && lhs.incomingValue == rhs.incomingValue
    }
}

/// Both schema-validated values remain available in full, including private fields.
/// Matching identity is a local restriction, not proof of ownership or authenticity.
public struct BuildConflictPair: Equatable, Sendable {
    public let local: BuildSnapshot
    public let incoming: BuildSnapshot
    public let differences: [BuildConflictDifference]

    public init(local: BuildSnapshot, incoming: BuildSnapshot) throws {
        guard local.id.utf8.elementsEqual(incoming.id.utf8) else {
            throw BuildConflictError.differentBuild
        }
        guard local.value.object!["owner_ref"] == incoming.value.object!["owner_ref"] else {
            throw BuildConflictError.differentOwner
        }
        self.local = local
        self.incoming = incoming
        self.differences = conflictDifferences(local.value, incoming.value, path: "")
    }
}

/// Keep means select an unchanged value for an uncommitted proposal, not overwrite.
public enum BuildConflictChoice: Equatable, Sendable { case keepLocal, keepIncoming }

/// Issued only by its session. A newer review or cancellation retires this token.
public struct BuildConflictReview: Sendable {
    public let conflict: BuildConflictPair
    fileprivate let sessionID: UUID
    fileprivate let reviewID: UUID
}

/// Preparation retains the selected value AND both originals. It does not increment
/// a revision, generate a fork, merge fields, write a draft, or acknowledge a service.
public struct BuildConflictProposal: Sendable {
    public let conflict: BuildConflictPair
    public let choice: BuildConflictChoice
    public var selected: BuildSnapshot {
        switch choice {
        case .keepLocal: return conflict.local
        case .keepIncoming: return conflict.incoming
        }
    }
}

/// One immutable pair in a caller-owned local editing context. The caller must
/// rotate contextID on editor/account/authority changes, including away-and-back
/// transitions, and supply freshly read values when preparing. The UUID grants no
/// account authority. Durable compare-and-swap and recovery remain caller work.
public actor BuildConflictSession {
    public nonisolated let conflict: BuildConflictPair
    private let contextID: UUID
    private let sessionID = UUID()
    private var activeReviewID: UUID?

    public init(local: BuildSnapshot, incoming: BuildSnapshot, contextID: UUID) throws {
        self.conflict = try BuildConflictPair(local: local, incoming: incoming)
        self.contextID = contextID
    }

    public func beginReview() -> BuildConflictReview {
        let id = UUID()
        activeReviewID = id
        return BuildConflictReview(conflict: conflict, sessionID: sessionID, reviewID: id)
    }

    /// Cancellation retires only the decision token; both snapshots remain retained.
    public func cancelReview() { activeReviewID = nil }

    /// A successful preparation consumes one explicit decision. If a later durable
    /// write fails, begin a new review of the retained pair; never retry an old token.
    public func prepare(_ review: BuildConflictReview, choice: BuildConflictChoice,
                        currentContextID: UUID, currentLocal: BuildSnapshot,
                        currentIncoming: BuildSnapshot) throws -> BuildConflictProposal {
        guard review.sessionID == sessionID, review.reviewID == activeReviewID else {
            throw BuildConflictError.staleReview
        }
        guard currentContextID == contextID, currentLocal == conflict.local,
              currentIncoming == conflict.incoming else {
            activeReviewID = nil
            throw BuildConflictError.staleReview
        }
        activeReviewID = nil
        return BuildConflictProposal(conflict: conflict, choice: choice)
    }
}

private func conflictDifferences(_ local: JSONValue?, _ incoming: JSONValue?,
                                 path: String) -> [BuildConflictDifference] {
    guard local != incoming else { return [] }
    guard case .object(let left)? = local, case .object(let right)? = incoming else {
        return [BuildConflictDifference(path: path, localValue: local, incomingValue: incoming)]
    }
    // Byte-sorted keys avoid Swift String's canonical-equivalence matching. A key
    // with a distinct spelling is a removal/addition, even if it renders identically.
    let lhs = left.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
    let rhs = right.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
    var l = 0, r = 0
    var differences: [BuildConflictDifference] = []
    func child(_ key: String) -> String {
        path + "/" + key.replacingOccurrences(of: "~", with: "~0")
            .replacingOccurrences(of: "/", with: "~1")
    }
    while l < lhs.count || r < rhs.count {
        if l < lhs.count, r < rhs.count, lhs[l].key.utf8.elementsEqual(rhs[r].key.utf8) {
            differences += conflictDifferences(lhs[l].value, rhs[r].value, path: child(lhs[l].key))
            l += 1; r += 1
        } else if l < lhs.count && (r == rhs.count || lhs[l].key.utf8.lexicographicallyPrecedes(rhs[r].key.utf8)) {
            differences += conflictDifferences(lhs[l].value, nil, path: child(lhs[l].key))
            l += 1
        } else {
            differences += conflictDifferences(nil, rhs[r].value, path: child(rhs[r].key))
            r += 1
        }
    }
    return differences
}
