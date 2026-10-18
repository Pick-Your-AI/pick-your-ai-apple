import Foundation
import PlannerTransfer

/// Immutable preparation inputs cross the worker boundary. Production uses the
/// same frozen transfer validator; the internal dependency permits controlled
/// scheduling tests without an alternate import format or unchecked snapshot.
struct ImportedBuildPreparation: Sendable {
    struct ExportRequest: Sendable {
        let snapshot: BuildSnapshot
        let publicAlias: String
        let markedSynthetic: Bool
        let sourceRevision: String?
    }
    let preview: @Sendable (Data) throws -> ImportPreview
    let export: @Sendable (ExportRequest) throws -> Data
    let compare: @Sendable (BuildSnapshot, BuildSnapshot) throws -> BuildComparison

    init(preview: @escaping @Sendable (Data) throws -> ImportPreview,
         export: @escaping @Sendable (ExportRequest) throws -> Data,
         compare: @escaping @Sendable (BuildSnapshot, BuildSnapshot) throws -> BuildComparison = {
             try BuildComparison.compare($0, $1)
         }) {
        self.preview = preview; self.export = export; self.compare = compare
    }

    static let live = Self(preview: { try BuildTransfer.preview($0) }, export: { request in
        var data = try BuildTransfer.export(request.snapshot, publicOwnerAlias: request.publicAlias)
        if request.markedSynthetic {
            guard let sourceRevision = request.sourceRevision else { throw TransferError.unsupportedVersion }
            let projected = try BuildTransfer.snapshot(fromDraftJSON: data)
            let envelope = JSONValue.object([
                "format": .string("pickyour.ai/build-export"), "formatVersion": .number(1),
                "exportedAt": .string(ISO8601DateFormatter().string(from: Date())),
                "contract": .object(["version": .string("1.0.0"), "sourceSha": .string(sourceRevision)]),
                "dataMode": .string("fixture"), "build": projected.value
            ])
            data = try JSONEncoder().encode(envelope)
            // Revalidate the final envelope and its total byte bound too.
            _ = try BuildTransfer.preview(data)
        }
        return data
    })
}
