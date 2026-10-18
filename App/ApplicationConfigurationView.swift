import SwiftUI
import PlannerCore

/// Construct local libraries only after the built bundle configuration passes.
/// No process environment, launch argument or preview fallback is consulted.
struct ApplicationConfigurationView<Content: View>: View {
    private let configuration: Result<RuntimeConfiguration, Error>
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.configuration = Result {
            try RuntimeConfiguration.fromBundleInfo(Bundle.main.infoDictionary ?? [:])
        }
    }

    var body: some View {
        switch configuration {
        case .success(let configuration):
            VStack(spacing: 0) {
                content()
                Text("\(configuration.environment.rawValue.capitalized) · Build \(configuration.diagnostics.buildIdentity) · Contract \(configuration.diagnostics.contractVersion)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("runtimeDiagnostics")
            }
        case .failure(let error):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                Text("App configuration unavailable")
                    .font(.title2)
                    .accessibilityIdentifier("configurationFailure")
                Text(message(for: error))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("configurationFailureDetails")
            }
            .padding()
        }
    }

    private func message(for error: Error) -> String {
        if let error = error as? RuntimeConfigurationError {
            switch error {
            case .missingEndpoint:
                return "This build requires a service endpoint. Install a correctly configured build. Local drafts have not been opened."
            case .invalidEndpoint, .previewEndpointForbidden:
                return "The service endpoint is invalid for this build. Install a correctly configured build. Local drafts have not been opened."
            default: break
            }
        }
        // Never display rejected Info.plist values, endpoint text or raw errors.
        return "The build environment or version settings are invalid. Install a correctly configured build. Local drafts have not been opened."
    }
}
