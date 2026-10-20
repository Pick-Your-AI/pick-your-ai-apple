import Foundation
import PlannerCatalog
import PlannerCore

/// Frozen-v1 whole-artifact validation for the existing public preview pair cache.
/// Hashing and retention use the original Data; validation neither rewrites it
/// nor grants source-use, publication, graph, pricing or currentness authority.
public enum FrozenCatalogCacheValidator {
    public static func validate(_ artifact: CatalogArtifact, _ data: Data) throws {
        switch artifact {
        case .catalog:
            _ = try CatalogSnapshot.decode(data)
        case .pricebook:
            _ = try Pricebook.decode(data)
        }
    }
}
