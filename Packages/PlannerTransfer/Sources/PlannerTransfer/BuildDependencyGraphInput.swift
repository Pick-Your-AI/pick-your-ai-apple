import Foundation
import PlannerCatalog

public enum BuildDependencyGraphInputError: Error, Equatable, Sendable {
    case resourceUnavailable, oversizedResource, hashingUnavailable
    case artifactMismatch, graphLockMismatch
}

/// An explicitly selected frozen synthetic input, never a general graph resolver.
/// The exact bytes remain local. This value grants no publisher, compatibility,
/// source-use, durable-write or native editor-session authority.
public struct BuildDependencyGraphInput: Sendable {
    public enum Qualification: Equatable, Sendable {
        case frozenSyntheticFixture
    }

    public let graph: DependencyGraph
    public let originalBytes: Data
    public let sha256: String
    public let qualification: Qualification

    // Independently pinned by source-manifest.json to the exact Research 7acbef
    // example. A hash computed from an arbitrary response cannot replace this pin.
    private static let fixtureSHA256 = "e9b3bca19a9cf8241fd74f6618824882a3413649822add88be1ac93cb3f1bacc"

    private init(graph: DependencyGraph, bytes: Data, sha256: String) {
        self.graph = graph
        originalBytes = bytes
        self.sha256 = sha256
        qualification = .frozenSyntheticFixture
    }

    /// Explicit opt-in to the bundled synthetic graph. A foreign Build lock is
    /// unavailable; there is no latest, demo, network or alternative-graph fallback.
    public static func bundledSynthetic(for build: BuildSnapshot) throws -> Self {
        guard let url = Bundle.module.url(forResource: "dependency-graph", withExtension: "json",
                                          subdirectory: "SyntheticInputs") else {
            throw BuildDependencyGraphInputError.resourceUnavailable
        }
        return try admitBundledSyntheticBytes(readResource(url), for: build)
    }

    /// Shared by the real bundle entry point and adversarial tests. The expected
    /// source pin is fixed above; callers cannot supply a hash, graph or approval.
    static func admitBundledSyntheticBytes(_ bytes: Data, for build: BuildSnapshot) throws -> Self {
        guard bytes.count <= BuildTransfer.maximumBytes else {
            throw BuildDependencyGraphInputError.oversizedResource
        }
        let digest: String
        do { digest = try CatalogCache.sha256(bytes) }
        catch { throw BuildDependencyGraphInputError.hashingUnavailable }
        guard digest.utf8.elementsEqual(fixtureSHA256.utf8) else {
            throw BuildDependencyGraphInputError.artifactMismatch
        }
        let graph = try DependencyGraph.decode(bytes)
        guard build.locks.object?["dependency_graph_id"] == .string(graph.id),
              build.locks.object?["dependency_graph_revision"] == .number(graph.revision) else {
            throw BuildDependencyGraphInputError.graphLockMismatch
        }
        return Self(graph: graph, bytes: bytes, sha256: digest)
    }

    /// Read one bounded resource descriptor. No caller-provided path, mutation or
    /// serialization participates in admission; the complete original hash follows.
    private static func readResource(_ url: URL) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var bytes = Data()
            while bytes.count <= BuildTransfer.maximumBytes {
                let remaining = BuildTransfer.maximumBytes + 1 - bytes.count
                guard let chunk = try handle.read(upToCount: min(16_384, remaining)),
                      !chunk.isEmpty else { break }
                bytes.append(chunk)
            }
            guard bytes.count <= BuildTransfer.maximumBytes else {
                throw BuildDependencyGraphInputError.oversizedResource
            }
            return bytes
        } catch let error as BuildDependencyGraphInputError {
            throw error
        } catch {
            throw BuildDependencyGraphInputError.resourceUnavailable
        }
    }
}
