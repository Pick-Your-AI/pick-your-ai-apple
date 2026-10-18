import Foundation
import CryptoKit
import PlannerTransfer

/// A local record of copied snapshot bytes, not authenticated source identity,
/// ownership or permission to reuse any evidence. It never enters a wire export.
public struct LocalForkSource: Codable, Equatable, Sendable {
    public let buildID: String
    public let revision: Int
    public let snapshotSHA256: String

    nonisolated static func capture(_ snapshot: BuildSnapshot) throws -> Self {
        guard case .object(let fields) = snapshot.value,
              case .number(let number)? = fields["revision"] else {
            throw TransferError.malformed
        }
        // Frozen ingress already restricts integers to JavaScript's safe range.
        let revision = NSDecimalNumber(decimal: number).intValue
        let bytes = try snapshot.encoded()
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let source = Self(buildID: snapshot.id, revision: revision, snapshotSHA256: digest)
        try source.validate()
        return source
    }

    nonisolated func validate() throws {
        guard buildID.range(of: #"\A[a-z][a-z0-9._:-]{2,119}\z"#, options: .regularExpression) != nil,
              (1...9_007_199_254_740_991).contains(revision),
              snapshotSHA256.range(of: #"\A[0-9a-f]{64}\z"#, options: .regularExpression) != nil else {
            throw TransferError.unsupportedVersion
        }
    }
}

enum LocalForkError: Error { case lineageLimit }
