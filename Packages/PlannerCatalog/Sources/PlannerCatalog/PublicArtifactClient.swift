#if canImport(Darwin)
import Foundation

/// Diagnostics carry no URL, headers, response body, or transport description.
public enum ArtifactDownloadError: Error, Equatable, Sendable {
    case invalidConfiguration, forbiddenURL, invalidResponse, unexpectedStatus(Int)
    case unsupportedContentType, oversized, transport(Int)
}

/// Public, credential-free JSON artifact transport. It does not establish source-use
/// rights, authenticate a publisher, or validate contracts: CatalogCache still checks
/// the exact digest, identity, and receiving validator before activation.
public final class PublicArtifactClient: Sendable {
    private let origin: URL
    private let maximumBytes: Int
    private let session: URLSession

    public convenience init(origin: URL, maximumBytes: Int = 8 * 1_024 * 1_024) throws {
        try self.init(origin: origin, maximumBytes: maximumBytes, protocolClasses: nil)
    }

    // Test-only protocol interception; public callers cannot install an alternate
    // trust delegate, shared cookie jar, credential store, or persistent cache.
    init(origin: URL, maximumBytes: Int, protocolClasses: [AnyClass]?) throws {
        guard Self.isPublicHTTPS(origin), origin.query == nil,
              maximumBytes > 0, maximumBytes <= 64 * 1_024 * 1_024 else {
            throw ArtifactDownloadError.invalidConfiguration
        }
        self.origin = origin
        self.maximumBytes = maximumBytes
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.protocolClasses = protocolClasses
        session = URLSession(configuration: configuration, delegate: RefuseArtifactRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    /// No retries occur automatically. A caller can retry a failed refresh using the
    /// original immutable pins; CatalogCache retains its last complete pair meanwhile.
    public func fetch(_ url: URL) async throws -> Data {
        guard Self.isPublicHTTPS(url), url.query == nil,
              url.host?.lowercased() == origin.host?.lowercased(),
              (url.port ?? 443) == (origin.port ?? 443) else {
            throw ArtifactDownloadError.forbiddenURL
        }
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() } // Also stop oversized/invalid bodies immediately.
            guard let response = response as? HTTPURLResponse, response.url == url else {
                throw ArtifactDownloadError.invalidResponse
            }
            try Self.validate(response, maximumBytes: maximumBytes)
            return try await Self.collect(bytes, maximumBytes: maximumBytes)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ArtifactDownloadError {
            throw error
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
            throw ArtifactDownloadError.transport(error.errorCode)
        } catch {
            throw ArtifactDownloadError.invalidResponse
        }
    }

    static func validate(_ response: HTTPURLResponse, maximumBytes: Int) throws {
        guard response.statusCode == 200 else { throw ArtifactDownloadError.unexpectedStatus(response.statusCode) }
        guard let mime = response.mimeType?.lowercased(), mime == "application/json" ||
              (mime.hasPrefix("application/") && mime.hasSuffix("+json")) else {
            throw ArtifactDownloadError.unsupportedContentType
        }
        guard response.expectedContentLength <= maximumBytes else { throw ArtifactDownloadError.oversized }
    }

    static func collect<S: AsyncSequence>(_ sequence: S, maximumBytes: Int) async throws -> Data where S.Element == UInt8 {
        var result = Data()
        for try await byte in sequence {
            try Task.checkCancellation()
            guard result.count < maximumBytes else { throw ArtifactDownloadError.oversized }
            result.append(byte)
        }
        try Task.checkCancellation()
        return result
    }

    private static func isPublicHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host ?? "").isEmpty &&
        url.user == nil && url.password == nil && url.fragment == nil &&
        (url.port.map { (1...65535).contains($0) } ?? true)
    }
}

final class RefuseArtifactRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

#endif
