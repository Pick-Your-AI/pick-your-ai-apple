import Foundation
import PlannerTransfer
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A source selected by the caller. File URLs come from an explicit Files action;
/// artifact URI strings inside a record are never opened by this boundary.
public enum T6ArtifactSource: Sendable {
    case bytes(Data)
    case file(URL)
}

public struct T6ArtifactInputs: Sendable {
    public let quality: T6ArtifactSource?
    public let manifest: T6ArtifactSource?
    public init(quality: T6ArtifactSource? = nil, manifest: T6ArtifactSource? = nil) {
        self.quality = quality; self.manifest = manifest
    }
}

public enum T6ManifestIssue: String, Sendable {
    case notSupplied, unreadableOrIncomplete, notProposed, buildMismatch, targetBinding
}

/// Immutable local inspection. A decoded declaration is retained even when it
/// cannot form a proposed plan. Local artifacts are private and have no exporter.
public struct T6ReviewContent: Equatable, Sendable {
    public let build: BuildSnapshot
    public let guidance: T6QualityGuidance
    public let manifest: DeploymentManifest?
    public let manifestIssue: T6ManifestIssue?
    public let localArtifacts: ProposedDeploymentPlan.LocalArtifacts?
}

struct T6ArtifactPreparation: Sendable {
    let prepare: @Sendable (BuildSnapshot, T6ArtifactInputs) async throws -> T6ReviewContent

    static let live = Self { build, inputs in
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let quality = try inputs.quality.map(read)
            let manifest = try inputs.manifest.map(read)
            let result = try evaluate(build: build, quality: quality, manifest: manifest)
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler(operation: {
            let result = await worker.result
            try Task.checkCancellation()
            return try result.get()
        }, onCancel: { worker.cancel() })
    }

    static func evaluate(build: BuildSnapshot, quality: Data?, manifest: Data?) throws -> T6ReviewContent {
        let run = try quality.map(QualityEvaluationRun.decode)
        let guidance = try T6QualityGuidance(build: build, run: run)
        guard let manifest else {
            return T6ReviewContent(build: build, guidance: guidance, manifest: nil,
                                   manifestIssue: .notSupplied, localArtifacts: nil)
        }
        let declaration: DeploymentManifest
        do { declaration = try DeploymentManifest.decode(manifest) }
        catch {
            try Task.checkCancellation()
            return T6ReviewContent(build: build, guidance: guidance, manifest: nil,
                                   manifestIssue: .unreadableOrIncomplete, localArtifacts: nil)
        }
        let issue: T6ManifestIssue?
        let artifacts: ProposedDeploymentPlan.LocalArtifacts?
        do {
            let plan = try ProposedDeploymentPlan(build: build, manifest: declaration)
            artifacts = try plan.encodedLocally(); issue = nil
        } catch let error as ProposedDeploymentPlanError {
            artifacts = nil
            switch error {
            case .notProposed: issue = .notProposed
            case .buildMismatch: issue = .buildMismatch
            case .targetBinding: issue = .targetBinding
            }
        }
        return T6ReviewContent(build: build, guidance: guidance, manifest: declaration,
                               manifestIssue: issue, localArtifacts: artifacts)
    }

    private static func read(_ source: T6ArtifactSource) throws -> Data {
        try Task.checkCancellation()
        switch source {
        case .bytes(let bytes):
            guard bytes.count <= BuildTransfer.maximumBytes else { throw TransferError.oversized }
            return bytes
        case .file(let url):
            guard url.isFileURL else { throw TransferError.malformed }
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { return -1 }
                return open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
            }
            guard descriptor >= 0 else { throw TransferError.malformed }
            defer { _ = close(descriptor) }
            var info = stat()
            guard fstat(descriptor, &info) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw TransferError.malformed }
            guard info.st_size >= 0, info.st_size <= off_t(BuildTransfer.maximumBytes) else { throw TransferError.oversized }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            var bytes = Data()
            while bytes.count <= BuildTransfer.maximumBytes {
                try Task.checkCancellation()
                let chunk = try handle.read(upToCount: min(65_536, BuildTransfer.maximumBytes + 1 - bytes.count)) ?? Data()
                if chunk.isEmpty { break }
                bytes.append(chunk)
            }
            guard bytes.count <= BuildTransfer.maximumBytes else { throw TransferError.oversized }
            return bytes
        }
    }
}

/// PlannerTransfer keeps its convenience accessors internal. These uniquely
/// named local projections use only its public enum cases and add no wire API.
extension JSONValue {
    var t6Object: [String: JSONValue]? {
        if case .object(let value) = self { value } else { nil }
    }
    var t6Array: [JSONValue]? {
        if case .array(let value) = self { value } else { nil }
    }
}
