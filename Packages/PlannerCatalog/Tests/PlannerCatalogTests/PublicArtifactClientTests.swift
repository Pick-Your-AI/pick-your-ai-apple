#if canImport(Darwin)
import Foundation
import XCTest
@testable import PlannerCatalog

final class PublicArtifactClientTests: XCTestCase {
    private let origin = URL(string: "https://catalog.example.invalid")!
    private func stream(_ data: Data) -> AsyncThrowingStream<UInt8, Error> {
        AsyncThrowingStream { continuation in
            for byte in data { continuation.yield(byte) }
            continuation.finish()
        }
    }
    func testInvalidConfigurationFailsBeforeSessionCreation() throws {
        for limit in [0, -1, 64 * 1_024 * 1_024 + 1] {
            XCTAssertThrowsError(try PublicArtifactClient(origin: origin, maximumBytes: limit))
        }
        for value in ["http://catalog.example.invalid", "https://user:password@catalog.example.invalid", "https://catalog.example.invalid?token=private"] {
            XCTAssertThrowsError(try PublicArtifactClient(origin: URL(string: value)!))
        }
    }
    func testExactLimitAndOneByteOverflow() async throws {
        let exact = try await PublicArtifactClient.collect(stream(Data([1, 2, 3])), maximumBytes: 3)
        XCTAssertEqual(exact, Data([1, 2, 3]))
        do {
            _ = try await PublicArtifactClient.collect(stream(Data([1, 2, 3, 4])), maximumBytes: 3)
            XCTFail("Oversized stream accepted")
        } catch { XCTAssertEqual(error as? ArtifactDownloadError, .oversized) }
    }
    func testInterruptedStreamDoesNotReturnPartialData() async throws {
        let input = AsyncThrowingStream<UInt8, Error> { continuation in
            continuation.yield(1)
            continuation.finish(throwing: URLError(.networkConnectionLost))
        }
        do {
            _ = try await PublicArtifactClient.collect(input, maximumBytes: 3)
            XCTFail("Partial stream accepted")
        } catch { XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost) }
    }
    func testCancellationDoesNotReturnBufferedBytes() async throws {
        let input = stream(Data([1, 2]))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PublicArtifactClient.collect(input, maximumBytes: 3)
        }
        do { _ = try await task.value; XCTFail("Cancelled stream accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testStatusTypeAndAdvertisedLengthAreCheckedBeforeBody() throws {
        func response(_ status: Int, _ headers: [String: String]) -> HTTPURLResponse {
            HTTPURLResponse(url: origin, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        }
        for status in [301, 401, 404, 429, 500] {
            XCTAssertThrowsError(try PublicArtifactClient.validate(response(status, ["Content-Type": "application/json"]), maximumBytes: 3)) {
                XCTAssertEqual($0 as? ArtifactDownloadError, .unexpectedStatus(status))
            }
        }
        XCTAssertThrowsError(try PublicArtifactClient.validate(response(200, ["Content-Type": "text/html"]), maximumBytes: 3))
        XCTAssertThrowsError(try PublicArtifactClient.validate(response(200, ["Content-Type": "application/json", "Content-Length": "4"]), maximumBytes: 3))
        XCTAssertNoThrow(try PublicArtifactClient.validate(response(200, ["Content-Type": "application/json", "Content-Length": "3"]), maximumBytes: 3))
        XCTAssertNoThrow(try PublicArtifactClient.validate(response(200, ["Content-Type": "application/vnd.test+json"]), maximumBytes: 3))
    }
    func testForbiddenDestinationsNeverReachTransport() async throws {
        let client = try PublicArtifactClient(origin: origin, maximumBytes: 3, protocolClasses: [ArtifactFixtureProtocol.self])
        for value in ["http://catalog.example.invalid/a", "https://other.example.invalid/a", "https://catalog.example.invalid:444/a", "https://user:password@catalog.example.invalid/a", "https://catalog.example.invalid/a?token=private", "https://catalog.example.invalid/a#fragment"] {
            do { _ = try await client.fetch(URL(string: value)!); XCTFail("Forbidden destination accepted") }
            catch { XCTAssertEqual(error as? ArtifactDownloadError, .forbiddenURL) }
        }
    }
    func testURLSessionSuccessOversizeAndRedactedFailure() async throws {
        let client = try PublicArtifactClient(origin: origin, maximumBytes: 3, protocolClasses: [ArtifactFixtureProtocol.self])
        let exact = try await client.fetch(origin.appendingPathComponent("success"))
        XCTAssertEqual(exact, Data("{}".utf8))
        do { _ = try await client.fetch(origin.appendingPathComponent("oversized")); XCTFail("Oversized accepted") }
        catch { XCTAssertEqual(error as? ArtifactDownloadError, .oversized) }
        do { _ = try await client.fetch(origin.appendingPathComponent("timeout")); XCTFail("Timeout accepted") }
        catch {
            XCTAssertEqual(error as? ArtifactDownloadError, .transport(URLError.timedOut.rawValue))
            XCTAssertFalse(String(describing: error).contains("private"))
        }
        // A failed request neither poisons the client nor automatically retries.
        let recovered = try await client.fetch(origin.appendingPathComponent("success"))
        XCTAssertEqual(recovered, Data("{}".utf8))
    }
    func testRedirectDelegateNeverFollowsEvenSameOrigin() async throws {
        let delegate = RefuseArtifactRedirects()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArtifactFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: origin)
        let response = HTTPURLResponse(url: origin, statusCode: 302, httpVersion: nil, headerFields: ["Location": "/other"])!
        let followed = await withCheckedContinuation { continuation in
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: origin.appendingPathComponent("other"))) { request in
                continuation.resume(returning: request != nil)
            }
        }
        XCTAssertFalse(followed)
    }
}

/// Only intercepted synthetic HTTPS requests: these tests never contact a server.
private final class ArtifactFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        if url.lastPathComponent == "timeout" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "private transport details"]))
            return
        }
        let data = Data((url.lastPathComponent == "oversized" ? "1234" : "{}").utf8)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

#endif
