/// Describes only the presence and JSON type of a reported evidence value.
/// A supplied value is not a checked fact, a rule outcome or independent support.
/// In particular, this projection never computes a compatibility verdict.
public enum EvidenceValuePresence: Equatable, Sendable {
    case absent
    case explicitNull
    case literalUnknown
    case supplied

    public init(_ value: EvaluationJSONValue?) {
        switch value {
        case nil: self = .absent
        case .null?: self = .explicitNull
        case .string("unknown")?: self = .literalUnknown
        default: self = .supplied
        }
    }
}

/// Absence of the optional evidence collection is distinct from an explicitly
/// empty collection. Neither supplies a rule result or proves completeness.
public enum EvidenceCollectionPresence: Equatable, Sendable {
    case absent
    case empty
    case supplied

    public init(_ evidence: [EvaluationEvidence]?) {
        guard let evidence else { self = .absent; return }
        self = evidence.isEmpty ? .empty : .supplied
    }
}

public extension EvaluationEvidence {
    var observedPresence: EvidenceValuePresence { EvidenceValuePresence(observed) }
    var expectedPresence: EvidenceValuePresence { EvidenceValuePresence(expected) }
}

public extension EvaluationFinding {
    var evidencePresence: EvidenceCollectionPresence { EvidenceCollectionPresence(evidence) }
}
