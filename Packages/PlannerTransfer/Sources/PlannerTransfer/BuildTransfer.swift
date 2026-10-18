import Foundation

/// A validated immutable wire snapshot. Schema validity does not imply compatibility, readiness, or ownership.
public struct BuildSnapshot: Sendable, Equatable {
    public let value: JSONValue
    fileprivate init(_ value: JSONValue) { self.value = value }
    public var id: String { value.object!["id"]!.string! }
    public var name: String { value.object!["name"]!.string! }
    public var locks: JSONValue { value.object!["locks"]! }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        // Normalization can expand compact input beyond the reopening bounds.
        // Local serialization preserves private fields; it is not a sharing API.
        var parser = try JSONParser(data)
        guard try parser.parse() == value else { throw TransferError.unsupportedNumber }
        return data
    }
}

/// A preview has no repository or network authority. The UI must explicitly confirm a fork.
public struct ImportPreview: Sendable {
    public let snapshot: BuildSnapshot
    public let usesSyntheticData: Bool?
    /// Always returns a newly identified draft; source identity never becomes an update target.
    /// Owner is supplied by the local identity boundary, never trusted from the import.
    public func fork(localOwner: String, timestamp: String) throws -> BuildSnapshot {
        guard !localOwner.isEmpty, FrozenValidator.timestamp(timestamp) else { throw TransferError.invalidFork }
        var object = snapshot.value.object!
        object["id"] = .string("build." + UUID().uuidString.lowercased())
        object["revision"] = .number(1)
        object["owner_ref"] = .string(localOwner)
        object["lifecycle"] = .string("draft")
        object["created_at"] = .string(timestamp)
        object["updated_at"] = .string(timestamp)
        let value = JSONValue.object(object)
        try FrozenValidator().validateBuild(value)
        return BuildSnapshot(value)
    }
}

public enum BuildTransfer {
    public static let maximumBytes = 512 * 1024
    /// Transition boundary for incomplete local drafts. Never inserts missing fields/defaults or mutates input.
    public static func snapshot(fromDraftJSON data: Data) throws -> BuildSnapshot {
        var parser = try JSONParser(data)
        let value = try parser.parse()
        try FrozenValidator().validateBuild(value)
        return BuildSnapshot(value)
    }
    /// Accepts frozen-v1 bare snapshots or the existing web export envelope (format version 1).
    /// Secret references/private fields are rejected, not echoed in diagnostics or silently imported.
    public static func preview(_ data: Data) throws -> ImportPreview {
        var parser = try JSONParser(data)
        let root = try parser.parse()
        var candidate = root
        var synthetic: Bool?
        if let envelope = root.object, envelope["format"] != nil {
            guard Set(envelope.keys) == Set(["format", "formatVersion", "exportedAt", "contract", "dataMode", "build"]),
                  envelope["format"] == .string("pickyour.ai/build-export"), envelope["formatVersion"] == .number(1),
                  let contract = envelope["contract"]?.object, Set(contract.keys) == Set(["version", "sourceSha"]),
                  contract["version"] == .string("1.0.0"),
                  let sha = contract["sourceSha"]?.string,
                  sha.range(of: #"\A[0-9a-f]{40}\z"#, options: .regularExpression) != nil,
                  let date = envelope["exportedAt"]?.string, FrozenValidator.timestamp(date),
                  let mode = envelope["dataMode"]?.string, ["fixture", "http"].contains(mode),
                  let build = envelope["build"] else { throw TransferError.unsupportedVersion }
            candidate = build; synthetic = mode == "fixture"
        }
        try rejectSensitive(candidate)
        try FrozenValidator().validateBuild(candidate)
        return ImportPreview(snapshot: BuildSnapshot(candidate), usesSyntheticData: synthetic)
    }
    /// Minimal bare-snapshot projection readable by the web consumer. Private owner/notes/extensions
    /// are removed; a caller-supplied public alias is required because frozen v1 requires owner_ref.
    /// Visible free text (including name/settings) needs user review before sharing.
    public static func export(_ snapshot: BuildSnapshot, publicOwnerAlias: String) throws -> Data {
        guard !publicOwnerAlias.isEmpty else { throw TransferError.sensitiveContent }
        var object = projected(snapshot.value).object!
        object["owner_ref"] = .string(publicOwnerAlias)
        let value = JSONValue.object(object)
        try rejectSensitive(value)
        try FrozenValidator().validateBuild(value)
        let data = try BuildSnapshot(value).encoded()
        guard data.count <= maximumBytes else { throw TransferError.oversized }
        return data
    }
    private static func projected(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let object):
            return .object(object.filter { !["notes", "extensions", "owner_ref"].contains($0.key) }.mapValues(projected))
        case .array(let array): return .array(array.map(projected))
        default: return value
        }
    }
    private static func rejectSensitive(_ value: JSONValue) throws {
        switch value {
        case .object(let object):
            for (key, child) in object {
                let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
                if ["notes", "extensions", "account_ref", "encryption_key_ref", "approval_ticket", "index_name", "endpoint", "api_base_url", "weights_uri", "artifact_uri"].contains(key) || ["secret", "password", "credential", "apikey", "authorization", "accesstoken", "refreshtoken"].contains(where: normalized.contains) { throw TransferError.sensitiveContent }
                try rejectSensitive(child)
            }
        case .array(let array): for child in array { try rejectSensitive(child) }
        case .string(let string):
            if string.lowercased().contains("secret://") { throw TransferError.sensitiveContent }
        default: break
        }
    }
}
