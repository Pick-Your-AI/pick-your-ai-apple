import Foundation

public enum ClientEnvironment: String, Sendable {
    case preview, staging, production
}

/// Established by the transport/catalog adapter after validating the response's
/// environment identity. A caller-supplied label alone is not authentication.
public enum ResponseDataEnvironment: Sendable {
    case synthetic, staging, production
}

/// Deliberately carries no rejected URL or response body, which may contain secrets.
public enum RuntimeConfigurationError: Error, Equatable {
    case missingBuildIdentity, unsupportedContractVersion, previewEndpointForbidden
    case missingEndpoint, invalidEndpoint, wrongResponseEnvironment
}

public struct RuntimeDiagnostics: Equatable, Sendable {
    public let environment: ClientEnvironment
    public let buildIdentity: String
    public let contractVersion: String
}

/// Local configuration policy, not a new service wire protocol. No default live
/// endpoint or preview fallback exists. Bundle wiring and authenticated transport
/// must supply configuration and validated response identity explicitly.
public struct RuntimeConfiguration: Equatable, Sendable {
    public let environment: ClientEnvironment
    public let endpoint: URL?
    public let diagnostics: RuntimeDiagnostics

    public init(environment: ClientEnvironment, endpoint: String?,
                buildIdentity: String, contractVersion: String) throws {
        guard !buildIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuntimeConfigurationError.missingBuildIdentity
        }
        guard contractVersion == "1.0.0" else {
            throw RuntimeConfigurationError.unsupportedContractVersion
        }
        let parsedEndpoint: URL?
        if environment == .preview {
            guard endpoint == nil else { throw RuntimeConfigurationError.previewEndpointForbidden }
            parsedEndpoint = nil
        } else {
            guard let endpoint, !endpoint.isEmpty else { throw RuntimeConfigurationError.missingEndpoint }
            // Parse without URL's automatic repair of malformed input. Credentials,
            // query parameters and fragments belong outside endpoint configuration.
            guard Self.hasStrictEndpointSyntax(endpoint),
                  let components = URLComponents(string: endpoint),
                  components.string == endpoint,
                  components.scheme?.lowercased() == "https",
                  let host = components.host, !host.isEmpty,
                  components.user == nil, components.password == nil,
                  components.query == nil, components.fragment == nil,
                  components.port.map({ (1...65535).contains($0) }) ?? true,
                  let url = components.url else { throw RuntimeConfigurationError.invalidEndpoint }
            parsedEndpoint = url
        }
        self.environment = environment
        self.endpoint = parsedEndpoint
        diagnostics = RuntimeDiagnostics(environment: environment, buildIdentity: buildIdentity,
                                         contractVersion: contractVersion)
    }

    private static func hasStrictEndpointSyntax(_ endpoint: String) -> Bool {
        let bytes = Array(endpoint.utf8)
        guard bytes.allSatisfy({ (33...126).contains($0) }) else { return false }
        let hex: (UInt8) -> Bool = { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
        for index in bytes.indices where bytes[index] == 37 {
            guard index + 2 < bytes.count, hex(bytes[index + 1]), hex(bytes[index + 2]) else { return false }
        }
        guard let delimiter = endpoint.range(of: "://") else { return false }
        let authority = endpoint[delimiter.upperBound...].prefix(while: { $0 != "/" && $0 != "?" && $0 != "#" })
        let portText: Substring?
        if authority.first == "[" {
            guard let closing = authority.firstIndex(of: "]") else { return false }
            let suffix = authority[authority.index(after: closing)...]
            guard suffix.isEmpty || suffix.first == ":" else { return false }
            portText = suffix.isEmpty ? nil : suffix.dropFirst()
        } else {
            portText = authority.lastIndex(of: ":").map { authority[authority.index(after: $0)...] }
        }
        if let portText {
            guard !portText.isEmpty, portText.utf8.allSatisfy({ (48...57).contains($0) }),
                  let port = Int(portText), (1...65535).contains(port) else { return false }
        }
        return true
    }

    public func requireMatchingResponse(_ response: ResponseDataEnvironment) throws {
        switch (environment, response) {
        case (.preview, .synthetic), (.staging, .staging), (.production, .production): return
        default: throw RuntimeConfigurationError.wrongResponseEnvironment
        }
    }
}
