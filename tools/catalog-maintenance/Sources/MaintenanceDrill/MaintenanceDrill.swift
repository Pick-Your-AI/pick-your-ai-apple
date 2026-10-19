import Foundation
import PlannerCatalog
import PlannerCore
import PlannerData
import PlannerTransfer

private enum DrillFailure: Error {
    case invariant(String), fixture, arguments, download
}

private func require(_ condition: Bool, _ name: String) throws {
    guard condition else { throw DrillFailure.invariant(name) }
}

/// These five closed, source-qualified synthetic resources are the entire input.
/// The Python entry point validates their exact bytes against the pinned schemas.
/// This allowlist is not a general catalog validator or publication-rights adapter.
private struct Fixtures: Sendable {
    let build: Data
    let a: [CatalogArtifact: Data]
    let b: [CatalogArtifact: Data]

    init() throws {
        func read(_ name: String) throws -> Data {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json",
                                              subdirectory: "Fixtures") else { throw DrillFailure.fixture }
            let bytes = try Data(contentsOf: url)
            guard bytes.count <= 32_768 else { throw DrillFailure.fixture }
            return bytes
        }
        build = try read("build-a")
        a = [.catalog: try read("catalog-a"), .pricebook: try read("pricebook-a")]
        b = [.catalog: try read("catalog-b"), .pricebook: try read("pricebook-b")]
        _ = try BuildTransfer.snapshot(fromDraftJSON: build)
        _ = try Pricebook.decode(a[.pricebook]!)
        _ = try Pricebook.decode(b[.pricebook]!)
    }

    func manifest(_ pair: [CatalogArtifact: Data]) throws -> CacheManifest {
        try CacheManifest(pins: CatalogArtifact.allCases.map { kind in
            let bytes = pair[kind]!
            return ArtifactPin(kind: kind, identity: try JSONDecoder().decode(ArtifactIdentity.self, from: bytes),
                               sha256: try CatalogCache.sha256(bytes))
        })
    }

    func validate(_ kind: CatalogArtifact, _ bytes: Data) throws {
        try require(bytes == a[kind] || bytes == b[kind], "closed-fixture-membership")
    }
}

private actor DownloadBoundary {
    private var reached = false
    private var waiter: CheckedContinuation<Void, Never>?
    func arrive() {
        reached = true
        waiter?.resume()
        waiter = nil
    }
    func wait() async {
        if reached { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

@main @MainActor
private struct MaintenanceDrill {
    private static let draftID = UUID(uuidString: "00121212-1212-4121-8121-121212121212")!
    private static let neighbourID = UUID(uuidString: "00212121-2121-4212-8212-212121212121")!

    static func main() async {
        do {
            let args = CommandLine.arguments
            guard args.count == 4, ["portable", "native"].contains(args[1]),
                  ["seed", "maintain", "reopen", "exact-target"].contains(args[2]) else {
                throw DrillFailure.arguments
            }
            let root = URL(fileURLWithPath: args[3], isDirectory: true)
            let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            try require(values.isDirectory == true && values.isSymbolicLink != true, "isolated-existing-directory")
            let fixtures = try Fixtures()
            var result: [String: Any]
            if args[2] == "exact-target" {
                result = try targetProbe()
            } else {
                result = try await run(mode: args[1], phase: args[2], root: root, fixtures: fixtures)
            }
            result["format"] = 1
            result["classification"] = "synthetic-only"
            result["mode"] = args[1]
            result["phase"] = args[2]
            result["status"] = "passed"
            let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            FileHandle.standardOutput.write(bytes + Data([10]))
        } catch {
            // Domain error descriptions, database paths and payloads are not diagnostics.
            let code: String
            switch error {
            case DrillFailure.invariant(let name): code = "invariant:\(name)"
            case CatalogCacheError.unsupportedHashPlatform: code = "unsupportedHashPlatform"
            default: code = String(describing: type(of: error))
            }
            let bytes = try? JSONSerialization.data(withJSONObject: ["status": "failed", "error": code],
                                                   options: [.sortedKeys])
            FileHandle.standardError.write((bytes ?? Data("failure".utf8)) + Data([10]))
            exit(1)
        }
    }

    private static func run(mode: String, phase: String, root: URL, fixtures: Fixtures) async throws -> [String: Any] {
        // A new executable process opens this store for every phase.
        let store = try DraftStore(url: root.appendingPathComponent("drafts.sqlite"))
        if phase == "seed" {
            _ = try await store.save(id: draftID, expectedRevision: nil, title: "FICTIONAL retained build",
                                     payload: fixtures.build)
            _ = try await store.save(id: neighbourID, expectedRevision: nil, title: "FICTIONAL unaffected draft",
                                     payload: Data("{\"synthetic\":\"unrelated\"}".utf8))
        }
        let draft = try await store.read(id: draftID)
        let neighbour = try await store.read(id: neighbourID)
        let history = try await store.history(id: draftID)
        let neighbourHistory = try await store.history(id: neighbourID)
        try require(draft.payload == fixtures.build && draft.revision == 1, "retained-payload-and-revision")
        try require(history.records.count == 1 && history.records[0].payload == fixtures.build
                    && history.unreadableCount == 0, "retained-history")
        try require(neighbour.payload == Data("{\"synthetic\":\"unrelated\"}".utf8) && neighbour.revision == 1
                    && neighbourHistory.records.count == 1 && neighbourHistory.unreadableCount == 0,
                    "unaffected-neighbour")
        try require(!draft.analysisIsCurrent && !neighbour.analysisIsCurrent, "durability-is-not-current-analysis")
        let base = try presentation(from: draft.payload)
        var output: [String: Any] = [
            "draft": record(draft), "neighbour": record(neighbour),
            "history": history.records.map(record), "neighbour_history": neighbourHistory.records.map(record),
            "baseline": evidence(base), "warnings": try observations(base: base, phase: phase),
            "catalog_cache": ["status": "unexecuted", "reason": "portable-scope-does-not-emulate-CryptoKit"]
        ]
        if mode == "native" {
            output["catalog_cache"] = try await cachePhase(phase: phase, root: root, fixtures: fixtures)
        }
        return output
    }

    private static func record(_ value: DraftRecord) -> [String: Any] {
        ["id": value.id.uuidString, "revision": value.revision, "title": value.title,
         "payload_base64": value.payload.base64EncodedString(),
         "restored_from": value.restoredFrom.map { $0 as Any } ?? NSNull(),
         "analysis_is_current": value.analysisIsCurrent]
    }

    private static func presentation(from payload: Data) throws -> EvidencePresentation {
        let snapshot = try BuildTransfer.snapshot(fromDraftJSON: payload)
        guard case let .object(object) = snapshot.value,
              case let .array(selections)? = object["selections"],
              case let .object(selection)? = selections.first(where: {
                  guard case let .object(value) = $0,
                        case let .string(id)? = value["catalog_item_id"] else { return false }
                  return id == "cat.compute_profile.fixture"
              }),
              case let .string(componentID)? = selection["catalog_item_id"],
              case let .string(version)? = selection["catalog_item_version"],
              case let .object(locks) = snapshot.locks,
              case let .string(catalog)? = locks["catalog_snapshot_id"] else { throw DrillFailure.fixture }
        let identity = try RetainedEvidenceIdentity(componentID: componentID, componentVersion: version,
                                                    catalogSnapshotID: catalog)
        // These explicit test receipts exercise a grade transition. They are not
        // assertions of actual inspection, independent measurement or approval.
        return EvidencePresentation(identity: identity, originalVerificationStatus: .verified,
            source: .inspected(try SourceInspectionReceipt(sourceReference: "synthetic:claim",
                inspectionReference: "synthetic:fixture-read", retrievalMethod: "closed local fixture")),
            independentSupport: try AcceptedIndependentSupport(evidenceReference: "synthetic:independent",
                acceptanceReference: "synthetic:receiving-fixture"),
            freshness: .currentState(captureDate: try EvidenceCaptureDate("2026-10-16")))
    }

    private static func evidence(_ value: EvidencePresentation) -> [String: Any] {
        ["component_id": value.identity.componentID, "component_version": value.identity.componentVersion,
         "catalog_snapshot_id": value.identity.catalogSnapshotID,
         "original_status": value.originalVerificationStatus.rawValue,
         "display_grade": String(describing: value.displayGrade),
         "review_requirement": String(describing: value.reviewRequirement)]
    }

    private static func observations(base: EvidencePresentation, phase: String) throws -> [[String: Any]] {
        if phase == "seed" { return [] }
        let corrected = base.receiving(.correction(base.identity))
        let retracted = base.receiving(.retraction(base.identity))
        let laterNotice = retracted.receiving(.newerSnapshotAvailable).receiving(.newerReleaseAvailable)
        let unrelated = try RetainedEvidenceIdentity(componentID: "cat.storage.fixture",
            componentVersion: base.identity.componentVersion, catalogSnapshotID: base.identity.catalogSnapshotID)
        let ignored = base.receiving(.retraction(unrelated))
        let outcomes = [corrected, retracted, laterNotice]
        for value in outcomes {
            try require(value.identity == base.identity && value.source == base.source
                        && value.independentSupport == base.independentSupport
                        && value.originalVerificationStatus == base.originalVerificationStatus,
                        "notice-retains-historical-record")
            try require(value.displayGrade == .unverified && value.reviewRequirement == .recheckRequired,
                        "affected-record-requires-recheck")
        }
        try require(ignored == base, "unrelated-retraction-does-not-target-saved-record")
        return zip(["correction", "retraction", "later-notices", "unrelated-retraction"],
                   outcomes + [ignored]).map { name, value in evidence(value).merging(["event": name]) { _, new in new } }
    }

    /// Permanent adversarial receiving control. Main 78aa has a known failure here;
    /// the existing #348 owner supplies its correction. This drill changes no policy.
    private static func targetProbe() throws -> [String: Any] {
        let original = try RetainedEvidenceIdentity(componentID: "cat.compute_profile.fixture",
            componentVersion: "\u{00e9}", catalogSnapshotID: "catalog.fixture.maintenance.1")
        let other = try RetainedEvidenceIdentity(componentID: original.componentID,
            componentVersion: "e\u{0301}", catalogSnapshotID: original.catalogSnapshotID)
        let base = EvidencePresentation(identity: original, originalVerificationStatus: .unverified,
                                       source: .notInspected, freshness: .versionPinned)
        let received = base.receiving(.correction(other))
        try require(received.reviewRequirement == .none, "byte-distinct-target-owner-348")
        return ["target_version_utf8": Array(original.componentVersion.utf8),
                "other_version_utf8": Array(other.componentVersion.utf8), "observed": evidence(received)]
    }

    private static func cachePhase(phase: String, root: URL, fixtures: Fixtures) async throws -> [String: Any] {
        let a = try fixtures.manifest(fixtures.a)
        let b = try fixtures.manifest(fixtures.b)
        let cache = try CatalogCache(directory: root.appendingPathComponent("catalog-cache"),
                                    maximumArtifactBytes: 32_768, maximumCachedPairs: 3,
                                    maximumCacheBytes: 262_144, validateContract: fixtures.validate)
        var controls: [String] = []
        if phase == "seed" {
            try await cache.refresh(a, mode: .syntheticPreview, now: Date(timeIntervalSince1970: 1_792_141_200)) {
                fixtures.a[$0]!
            }
        }
        if phase == "maintain" {
            let before = try await cache.load(mode: .syntheticPreview)
            do {
                try await cache.refresh(b, mode: .syntheticPreview) { kind in
                    if kind == .pricebook { throw DrillFailure.download }
                    return fixtures.b[kind]!
                }
                throw DrillFailure.invariant("failed-download-was-accepted")
            } catch DrillFailure.download { controls.append("pricebook-download-failure") }
            let failed = try await cache.load(mode: .syntheticPreview)
            try require(failed?.artifacts == before?.artifacts && failed?.cachedAt == before?.cachedAt,
                        "failed-download-retains-active-pair")
            let boundary = DownloadBoundary()
            let pending = Task {
                try await cache.refresh(b, mode: .syntheticPreview) { kind in
                    if kind == .pricebook {
                        await boundary.arrive()
                        try await Task.sleep(for: .seconds(30))
                    }
                    return fixtures.b[kind]!
                }
            }
            await boundary.wait()
            pending.cancel()
            do {
                try await pending.value
                throw DrillFailure.invariant("cancelled-refresh-was-accepted")
            } catch is CancellationError { controls.append("cancelled-second-artifact") }
            let cancelled = try await cache.load(mode: .syntheticPreview)
            try require(cancelled?.artifacts == before?.artifacts && cancelled?.cachedAt == before?.cachedAt,
                        "cancellation-retains-active-pair")
            try await cache.refresh(b, mode: .syntheticPreview, now: Date(timeIntervalSince1970: 1_792_227_600)) {
                fixtures.b[$0]!
            }
        }
        let active = try await cache.load(mode: .syntheticPreview)
        let retained = try await cache.load(a, mode: .syntheticPreview)
        try require(active?.artifacts == (phase == "seed" ? fixtures.a : fixtures.b), "active-complete-pair")
        try require(retained?.artifacts == fixtures.a, "exact-original-historical-bytes")
        try require(active?.isSynthetic == true && retained?.isSynthetic == true, "synthetic-cache-boundary")
        guard let active, let retained else { throw DrillFailure.invariant("missing-cache") }
        do {
            _ = try await cache.load(mode: .production)
            throw DrillFailure.invariant("production-promotion-was-accepted")
        } catch CatalogCacheError.productionReceiptUnavailable { controls.append("production-denied") }
        return [
            "status": "passed", "controls": controls, "current_checks": String(describing: active.currentChecks),
            "active": try cacheRecord(active), "retained": try cacheRecord(retained)
        ]
    }

    private static func cacheRecord(_ value: CachedCatalog) throws -> [String: Any] {
        let manifest = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value.manifest))
        return ["manifest": manifest, "is_synthetic": value.isSynthetic,
                "cached_at": value.cachedAt.timeIntervalSince1970,
                "catalog_base64": value.artifacts[.catalog]!.base64EncodedString(),
                "pricebook_base64": value.artifacts[.pricebook]!.base64EncodedString()]
    }
}
