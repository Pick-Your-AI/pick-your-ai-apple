import Foundation

/// Configuration failures contain no rejected bundle values or endpoint text.
public enum BundleRuntimeConfigurationError: Error, Equatable {
    case missingEnvironment, unknownEnvironment, bundleEnvironmentMismatch
    case invalidBuildMetadata, invalidEndpointValue
}

extension RuntimeConfiguration {
    /// Read the built application's explicit Info.plist values. Process
    /// environment and launch arguments cannot select a different environment.
    /// These development bundle identifiers are not App Store registrations.
    public static func fromBundleInfo(_ information: [String: Any]) throws -> RuntimeConfiguration {
        guard let label = information["PlannerEnvironment"] as? String, !label.isEmpty else {
            throw BundleRuntimeConfigurationError.missingEnvironment
        }
        guard let environment = ClientEnvironment(rawValue: label) else {
            throw BundleRuntimeConfigurationError.unknownEnvironment
        }
        let expectedBundleID: String
        switch environment {
        case .preview: expectedBundleID = "invalid.pickyourai.localpreview"
        case .staging: expectedBundleID = "invalid.pickyourai.staging"
        case .production: expectedBundleID = "invalid.pickyourai.production"
        }
        guard information["CFBundleIdentifier"] as? String == expectedBundleID else {
            throw BundleRuntimeConfigurationError.bundleEnvironmentMismatch
        }
        // Only bounded numeric version metadata enters displayed diagnostics.
        // Unexpanded settings and arbitrary strings cannot be echoed to the UI.
        guard let version = information["CFBundleShortVersionString"] as? String,
              version.range(of: #"\A[0-9]{1,6}(\.[0-9]{1,6}){0,2}\z"#, options: .regularExpression) != nil,
              let build = information["CFBundleVersion"] as? String,
              build.range(of: #"\A[0-9]{1,9}\z"#, options: .regularExpression) != nil else {
            throw BundleRuntimeConfigurationError.invalidBuildMetadata
        }
        let endpoint: String?
        if let value = information["PlannerServiceEndpoint"] {
            guard let text = value as? String else {
                throw BundleRuntimeConfigurationError.invalidEndpointValue
            }
            endpoint = text.isEmpty ? nil : text
        } else {
            endpoint = nil
        }
        return try RuntimeConfiguration(environment: environment, endpoint: endpoint,
            buildIdentity: "\(version) (\(build))", contractVersion: information["PlannerContractVersion"] as? String ?? "")
    }
}
