import Foundation
import PlannerCatalog

/// The frozen, whole-artifact Ruleset boundary for an existing RulesetCache.
/// Cache hashing and retention use the original Data; this adapter never encodes
/// a replacement payload or grants policy, publisher or currentness authority.
public enum FrozenRulesetCacheValidator {
    public static func identity(for data: Data) throws -> RulesetIdentity {
        let ruleset = try Ruleset.decode(data)
        // Successful whole-artifact decoding already requires this exact version.
        return RulesetIdentity(schemaVersion: "1.0.0", id: ruleset.id,
                               version: ruleset.version, publishedAt: ruleset.publishedAt)
    }
}
