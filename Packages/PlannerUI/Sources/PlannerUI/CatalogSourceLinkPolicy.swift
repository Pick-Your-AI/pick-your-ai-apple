import Foundation

struct CatalogSourceLink: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let url: URL
    let host: String
    fileprivate init(url: URL, host: String) { self.url = url; self.host = host }
    var description: String { "CatalogSourceLink" }
    var debugDescription: String { description }
}

enum CatalogSourceLinkRejection: Equatable, Sendable {
    case tooLong, malformed, disallowedScheme, disallowedAuthority
}

enum CatalogSourceLinkDecision: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case candidate(CatalogSourceLink)
    case rejected(CatalogSourceLinkRejection)
    var description: String { "CatalogSourceLinkDecision" }
    var debugDescription: String { description }
}

/// A local boundary for explicit, reviewed ASCII HTTPS hosts. The source URI
/// cannot configure its own host approval. This policy neither fetches content
/// nor confers source-use rights, evidence authority or redirect confinement.
struct CatalogSourceLinkPolicy: Sendable {
    enum ConfigurationError: Error { case invalidHost, invalidLimit }
    static let denyAll = CatalogSourceLinkPolicy(hosts: [], maximumBytes: 4_096)
    private let hosts: Set<String>
    let maximumBytes: Int

    init(allowedHosts: Set<String>, maximumBytes: Int = 4_096) throws {
        guard (1...4_096).contains(maximumBytes) else { throw ConfigurationError.invalidLimit }
        guard allowedHosts.allSatisfy(Self.isHost) else { throw ConfigurationError.invalidHost }
        self.init(hosts: Set(allowedHosts.map { $0.lowercased() }), maximumBytes: maximumBytes)
    }

    private init(hosts: Set<String>, maximumBytes: Int) {
        self.hosts = hosts; self.maximumBytes = maximumBytes
    }

    func inspect(_ raw: String) -> CatalogSourceLinkDecision {
        // Bound copying and parser work before inspecting any URL components.
        guard raw.utf8.prefix(maximumBytes + 1).count <= maximumBytes else { return .rejected(.tooLong) }
        let bytes = Array(raw.utf8)
        guard !bytes.isEmpty, bytes.allSatisfy({ (33...126).contains($0) && $0 != 92 }) else {
            return .rejected(.malformed)
        }
        for index in bytes.indices where bytes[index] == 37 {
            guard index + 2 < bytes.count, Self.isHex(bytes[index + 1]), Self.isHex(bytes[index + 2]) else {
                return .rejected(.malformed)
            }
        }
        guard let separator = raw.range(of: "://"),
              raw[..<separator.lowerBound].lowercased() == "https" else { return .rejected(.disallowedScheme) }
        let authority = String(raw[separator.upperBound...].prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        let host: String
        if authority.hasSuffix(":443") { host = String(authority.dropLast(4)) }
        else { host = authority }
        guard Self.isHost(host), hosts.contains(host.lowercased()),
              authority == host || authority == host + ":443" else { return .rejected(.disallowedAuthority) }

        // PlannerUI supports iOS 17/macOS 14. Disable Foundation's automatic
        // repairs and require its parsed representation to preserve this input.
        guard let url = URL(string: raw, encodingInvalidCharacters: false), url.absoluteString == raw,
              let parsed = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parsed.scheme?.lowercased() == "https", parsed.host?.lowercased() == host.lowercased(),
              parsed.user == nil, parsed.password == nil, parsed.port == nil || parsed.port == 443 else {
            return .rejected(.malformed)
        }
        return .candidate(CatalogSourceLink(url: url, host: host))
    }

    private static func isHex(_ value: UInt8) -> Bool {
        (48...57).contains(value) || (65...70).contains(value) || (97...102).contains(value)
    }

    private static func isHost(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 253 else { return false }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        // Require a DNS name rather than a single-label or numeric IP target.
        guard labels.count >= 2, let finalFirst = labels.last?.utf8.first,
              (65...90).contains(finalFirst) || (97...122).contains(finalFirst) else { return false }
        return labels.allSatisfy { label in
            let bytes = Array(label.utf8)
            guard (1...63).contains(bytes.count), let first = bytes.first, let last = bytes.last,
                  Self.isHostLetter(first), Self.isHostLetter(last) else { return false }
            return bytes.allSatisfy { Self.isHostLetter($0) || $0 == 45 }
        }
    }

    private static func isHostLetter(_ value: UInt8) -> Bool {
        (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value)
    }
}

enum CatalogSourceReviewState: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case missing, rejected(CatalogSourceLinkRejection), confirmation(CatalogSourceLink)
    case opening, unavailable, handedOff
    var description: String { "CatalogSourceReviewState" }
    var debugDescription: String { description }
}

struct CatalogSourceReview: Equatable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    let id: UUID
    let sourceIndex: Int
    let state: CatalogSourceReviewState
    var description: String { "CatalogSourceReview" }
    var debugDescription: String { description }
}

struct CatalogSourceOpening: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let id: UUID
    let url: URL
    var description: String { "CatalogSourceOpening" }
    var debugDescription: String { description }
}
