#if canImport(Darwin)
import Foundation
import XCTest
import PlannerCore
import PlannerData
@testable import PlannerCatalog
@testable import PlannerTransfer

/// Actual URLSession/AsyncBytes and cache composition with intercepted synthetic
/// requests. No request contacts a server or establishes product/source authority.
final class NetworkArtifactRecoveryTests: XCTestCase, @unchecked Sendable {
    private func fixture() throws -> RecoveryFixture {
        let fixture = try RecoveryFixture()
        addTeardownBlock { fixture.close() }
        return fixture
    }

    private func assertPreview(_ fixture: RecoveryFixture, date: Date) async throws {
        let reopened = try fixture.reopenCache()
        let active = try await reopened.load(mode: .syntheticPreview)
        let snapshot = try XCTUnwrap(active)
        XCTAssertEqual(snapshot.manifest, fixture.pair.manifest)
        XCTAssertEqual(snapshot.artifacts, fixture.pair.artifacts)
        XCTAssertEqual(snapshot.cachedAt, date)
        XCTAssertTrue(snapshot.isSynthetic)
        if case .unknown = snapshot.currentChecks {} else {
            XCTFail("A recovered fixture must not imply current compatibility or prices")
        }
        let historical = try await reopened.load(fixture.pair.manifest, mode: .syntheticPreview)
        XCTAssertEqual(historical?.artifacts, fixture.pair.artifacts)
        XCTAssertEqual(historical?.cachedAt, date)
    }

    private func assertRequests(_ fixture: RecoveryFixture, refreshes: Int) {
        let requests = fixture.plan.requests
        XCTAssertEqual(requests.map(\.kind), Array(repeating: ["catalog", "pricebook"], count: refreshes).flatMap { $0 })
        for request in requests {
            XCTAssertEqual(request.method, "GET")
            XCTAssertEqual(request.accept, "application/json")
            XCTAssertFalse(request.hasBody)
            XCTAssertNil(request.authorization)
            XCTAssertNil(request.cookie)
            XCTAssertFalse(request.url.contains(RecoveryFixture.privateDraftMarker))
        }
    }

    private func assertFault(_ fault: RecoveryFixturePlan.Fault,
                             expectedDownload: ArtifactDownloadError? = nil,
                             expectedCache: CatalogCacheError? = nil) async throws {
        let fixture = try fixture()
        try await fixture.refresh(at: RecoveryFixture.originalDate)
        let original = try Data(contentsOf: fixture.envelopeURL)
        fixture.plan.setFault(fault)
        do {
            try await fixture.refresh(at: RecoveryFixture.recoveryDate)
            XCTFail("The injected second-artifact fault was reported as success")
        } catch {
            if let expectedDownload { XCTAssertEqual(error as? ArtifactDownloadError, expectedDownload) }
            if let expectedCache { XCTAssertEqual(error as? CatalogCacheError, expectedCache) }
            XCTAssertFalse(String(describing: error).contains(RecoveryFixture.privateDraftMarker))
            XCTAssertFalse(String(describing: error).contains("private transport detail"))
        }
        XCTAssertEqual(try Data(contentsOf: fixture.envelopeURL), original)
        try await assertPreview(fixture, date: RecoveryFixture.originalDate)
        assertRequests(fixture, refreshes: 2) // No automatic third attempt.

        fixture.plan.setFault(.none)
        try await fixture.refresh(at: RecoveryFixture.recoveryDate)
        try await assertPreview(fixture, date: RecoveryFixture.recoveryDate)
        assertRequests(fixture, refreshes: 3)
    }

    func testTimeoutDuringSecondArtifactPreservesStoredPairAndExplicitRetry() async throws {
        try await assertFault(.timeout, expectedDownload: .transport(URLError.timedOut.rawValue))
    }

    func testThrottledSecondArtifactPreservesStoredPairAndExplicitRetry() async throws {
        try await assertFault(.throttled, expectedDownload: .unexpectedStatus(429))
    }

    func testDisconnectedSecondArtifactNeverCommitsPartialData() async throws {
        try await assertFault(.disconnect, expectedDownload: .transport(URLError.networkConnectionLost.rawValue))
    }

    func testMalformedSecondArtifactPreservesStoredPairAndExplicitRetry() async throws {
        // Malformed HTTP-200 JSON must fail the original immutable byte pin before
        // a parser or permissive repair can admit it as the complete fixture.
        try await assertFault(.malformed, expectedCache: .digestMismatch)
    }

    func testValidChangedPricebookBytesCannotReplacePinnedPair() async throws {
        let original = try CanonicalFixture.pricebook.data()
        let changed = RecoveryFixturePlan.changedPricebook(original)
        XCTAssertNotEqual(changed, original)
        _ = try Pricebook.decode(changed)
        try await assertFault(.changedPrice, expectedCache: .digestMismatch)
    }

    func testActualRequestCancellationPreservesPairAndNewerDraftRevision() async throws {
        let fixture = try fixture()
        try await fixture.refresh(at: RecoveryFixture.originalDate)
        let original = try Data(contentsOf: fixture.envelopeURL)
        let draftID = UUID()
        let drafts = try DraftStore(url: fixture.draftURL)
        let first = try await drafts.save(id: draftID, expectedRevision: nil, title: "Before request",
                                          payload: CanonicalFixture.build.data())

        fixture.plan.setFault(.suspend)
        let outcome = RecoveryOutcome()
        let task = Task {
            do {
                try await fixture.refresh(at: RecoveryFixture.recoveryDate)
                outcome.finish(.success(()))
            } catch {
                outcome.finish(.failure(error))
            }
        }
        defer { task.cancel() }
        await fulfillment(of: [fixture.plan.suspended], timeout: 5)
        XCTAssertTrue(fixture.plan.didSuspend)
        XCTAssertEqual(try Data(contentsOf: fixture.envelopeURL), original)

        // This is a real local CAS edit while the URLSession request is in flight.
        // The intentionally incomplete draft is not promoted to a BuildSnapshot.
        let newerPayload = Data("{\"private_note\":\"\(RecoveryFixture.privateDraftMarker)\"}".utf8)
        let second = try await drafts.save(id: draftID, expectedRevision: first.revision,
                                           title: RecoveryFixture.privateDraftMarker, payload: newerPayload)
        XCTAssertEqual(second.revision, first.revision + 1)
        do {
            _ = try await drafts.save(id: draftID, expectedRevision: first.revision,
                                      title: "Stale callback", payload: first.payload)
            XCTFail("A stale draft revision overwrote the newer local edit")
        } catch { XCTAssertEqual(error as? DraftStoreError, .conflict) }
        do {
            try await fixture.refresh(at: RecoveryFixture.recoveryDate)
            XCTFail("An overlapping refresh started a second transport")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .incompleteRelease) }
        assertRequests(fixture, refreshes: 2)

        task.cancel()
        await fulfillment(of: [outcome.completed, fixture.plan.stopped], timeout: 5)
        let result = try XCTUnwrap(outcome.result)
        switch result {
        case .success: XCTFail("Canceled network refresh committed")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(fixture.plan.didStopSuspendedRequest)
        XCTAssertEqual(try Data(contentsOf: fixture.envelopeURL), original)
        try await assertPreview(fixture, date: RecoveryFixture.originalDate)
        let reopened = try DraftStore(url: fixture.draftURL)
        let retained = try await reopened.read(id: draftID)
        XCTAssertEqual(retained, second)
        XCTAssertFalse(retained.analysisIsCurrent)
        XCTAssertEqual(retained.payload, newerPayload)

        fixture.plan.setFault(.none)
        try await fixture.refresh(at: RecoveryFixture.recoveryDate)
        try await assertPreview(fixture, date: RecoveryFixture.recoveryDate)
        let afterRetry = try await reopened.read(id: draftID)
        XCTAssertEqual(afterRetry, second)
        XCTAssertFalse(afterRetry.analysisIsCurrent)
        let history = try await reopened.history(id: draftID)
        XCTAssertEqual(history.records.map(\.revision), [second.revision, first.revision])
        XCTAssertEqual(history.unreadableCount, 0)
        assertRequests(fixture, refreshes: 3)
    }
}

private final class RecoveryFixture: Sendable {
    static let originalDate = Date(timeIntervalSince1970: 100)
    static let recoveryDate = Date(timeIntervalSince1970: 300)
    static let privateDraftMarker = "PRIVATE-local-draft-106"
    let pair: CanonicalPair
    let plan: RecoveryFixturePlan
    let cache: CatalogCache
    let client: PublicArtifactClient
    let root: URL
    let origin: URL
    var envelopeURL: URL { root.appendingPathComponent("cache/active-preview-v1.json") }
    var draftURL: URL { root.appendingPathComponent("draft.sqlite") }

    init() throws {
        pair = try CanonicalPair()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        origin = try XCTUnwrap(URL(string: "https://recovery-\(UUID().uuidString.lowercased()).example.invalid"))
        plan = RecoveryFixturePlan(pair: pair)
        cache = try CatalogCache(directory: root.appendingPathComponent("cache"), validateContract: CanonicalPair.validate)
        client = try PublicArtifactClient(origin: origin, maximumBytes: 1_048_576,
                                          protocolClasses: [RecoveryFixtureProtocol.self])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        RecoveryFixtureProtocol.registry.register(origin: origin, plan: plan)
    }

    func reopenCache() throws -> CatalogCache {
        try CatalogCache(directory: root.appendingPathComponent("cache"), validateContract: CanonicalPair.validate)
    }

    func refresh(at date: Date) async throws {
        let client = client, origin = origin
        try await cache.refresh(pair.manifest, mode: .syntheticPreview, now: date) { kind in
            try await client.fetch(origin.appendingPathComponent(kind.rawValue))
        }
    }

    func close() {
        RecoveryFixtureProtocol.registry.remove(origin: origin)
        try? FileManager.default.removeItem(at: root)
    }
}

private final class RecoveryOutcome: @unchecked Sendable {
    let completed = XCTestExpectation(description: "The canceled refresh completes")
    private let lock = NSLock()
    private var stored: Result<Void, Error>?
    var result: Result<Void, Error>? { lock.withLock { stored } }
    func finish(_ result: Result<Void, Error>) {
        lock.withLock { stored = result }
        completed.fulfill()
    }
}

private final class RecoveryFixturePlan: @unchecked Sendable {
    enum Fault: Equatable, Sendable { case none, timeout, throttled, disconnect, malformed, changedPrice, suspend }
    struct RequestObservation: Sendable {
        let kind: String
        let method: String?
        let accept: String?
        let hasBody: Bool
        let authorization: String?
        let cookie: String?
        let url: String
    }
    let pair: CanonicalPair
    let suspended = XCTestExpectation(description: "Second request is held after a partial-byte notification")
    let stopped = XCTestExpectation(description: "URLProtocol stopped the suspended request")
    private let lock = NSLock()
    private var fault = Fault.none
    private var observed: [RequestObservation] = []
    private var heldID: UUID?
    private var stoppedID: UUID?
    var requests: [RequestObservation] { lock.withLock { observed } }
    var didSuspend: Bool { lock.withLock { heldID != nil } }
    var didStopSuspendedRequest: Bool { lock.withLock { heldID != nil && heldID == stoppedID } }

    init(pair: CanonicalPair) { self.pair = pair }
    func setFault(_ fault: Fault) { lock.withLock { self.fault = fault } }
    func begin(_ request: URLRequest) -> Fault {
        lock.withLock {
            observed.append(RequestObservation(kind: request.url?.lastPathComponent ?? "missing",
                method: request.httpMethod, accept: request.value(forHTTPHeaderField: "Accept"),
                hasBody: request.httpBody != nil || request.httpBodyStream != nil,
                authorization: request.value(forHTTPHeaderField: "Authorization"),
                cookie: request.value(forHTTPHeaderField: "Cookie"), url: request.url?.absoluteString ?? "missing"))
            return request.url?.lastPathComponent == "pricebook" ? fault : .none
        }
    }
    func markSuspended(_ id: UUID) {
        lock.withLock { heldID = id }
        suspended.fulfill()
    }
    func markStopped(_ id: UUID) {
        let isHeld = lock.withLock {
            guard heldID == id, stoppedID == nil else { return false }
            stoppedID = id
            return true
        }
        if isHeld { stopped.fulfill() }
    }
    static func changedPricebook(_ original: Data) -> Data {
        Data(String(decoding: original, as: UTF8.self).replacingOccurrences(of: "\"0.80\"", with: "\"0.81\"").utf8)
    }
}

private final class RecoveryFixtureRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var plans: [String: RecoveryFixturePlan] = [:]
    func register(origin: URL, plan: RecoveryFixturePlan) { lock.withLock { plans[origin.host!] = plan } }
    func remove(origin: URL) { lock.withLock { _ = plans.removeValue(forKey: origin.host!) } }
    func plan(for request: URLRequest) -> RecoveryFixturePlan? {
        lock.withLock { request.url?.host.flatMap { plans[$0] } }
    }
}

/// Registry entries are scoped to a fresh synthetic origin per test. All fixture
/// state is locked. stopLoading forbids further client notifications, including
/// when cancellation races a notification; no late success callback is invented.
private final class RecoveryFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let registry = RecoveryFixtureRegistry()
    private let state = NSRecursiveLock()
    private let identifier = UUID()
    private var stopped = false
    private var plan: RecoveryFixturePlan?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private func notify(_ body: (any URLProtocolClient) -> Void) {
        state.withLock {
            guard !stopped, let client else { return }
            body(client)
        }
    }

    override func startLoading() {
        guard let url = request.url, let fixture = Self.registry.plan(for: request),
              let kind = CatalogArtifact(rawValue: url.lastPathComponent),
              let bytes = fixture.pair.artifacts[kind] else {
            notify { $0.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)) }
            return
        }
        let active = state.withLock {
            guard !stopped else { return false }
            plan = fixture
            return true
        }
        guard active else { return }
        let fault = fixture.begin(request)
        if fault == .timeout {
            notify { $0.urlProtocol(self, didFailWithError: URLError(.timedOut,
                userInfo: [NSLocalizedDescriptionKey: "private transport detail"])) }
            return
        }
        let status = fault == .throttled ? 429 : 200
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else {
            notify { $0.urlProtocol(self, didFailWithError: URLError(.badServerResponse)) }
            return
        }
        notify { $0.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        switch fault {
        case .disconnect:
            notify { $0.urlProtocol(self, didLoad: Data(bytes.prefix(16))) }
            notify { $0.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost,
                userInfo: [NSLocalizedDescriptionKey: "private transport detail"])) }
        case .suspend:
            notify { $0.urlProtocol(self, didLoad: Data(bytes.prefix(16))) }
            state.withLock {
                guard !stopped else { return }
                fixture.markSuspended(identifier)
            }
        default:
            let body: Data
            switch fault {
            case .malformed: body = Data("{\"incomplete\":".utf8)
            case .changedPrice: body = RecoveryFixturePlan.changedPricebook(bytes)
            case .throttled: body = Data("{\"message\":\"private transport detail\"}".utf8)
            default: body = bytes
            }
            notify { $0.urlProtocol(self, didLoad: body) }
            notify { $0.urlProtocolDidFinishLoading(self) }
        }
    }

    override func stopLoading() {
        state.withLock {
            stopped = true
            plan?.markStopped(identifier)
        }
    }
}
#endif
