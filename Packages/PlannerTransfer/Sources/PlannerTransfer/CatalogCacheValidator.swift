import Foundation
import PlannerCatalog
import PlannerCore

/// Frozen-v1 whole-artifact validation for the existing public preview pair cache.
/// Hashing and retention use the original Data; validation neither rewrites it
/// nor grants source-use, publication, graph, pricing or currentness authority.
/// A catalog is also rejected as a whole when an item reference resolves to
/// exactly one item of a different kind or to more than one item (see `CatalogReferenceIntegrity`).
public enum FrozenCatalogCacheValidator {
    public static func validate(_ artifact: CatalogArtifact, _ data: Data) throws {
        switch artifact {
        case .catalog:
            try CatalogReferenceIntegrity.validate(CatalogSnapshot.decode(data))
        case .pricebook:
            _ = try Pricebook.decode(data)
        }
    }

    /// Pass as `CatalogCache(isReplaceableRetainedFailure:)`. A retained pair that fails
    /// only the reference policy is never served, but a refresh may replace it, because
    /// that policy was added after pairs may already have been admitted without it.
    /// Structural, digest, identity and storage failures keep blocking refresh.
    public static func isReplaceableRetainedFailure(_ error: any Error) -> Bool {
        error is CatalogReferenceRejection
    }
}
