import Foundation
import PlannerCore
import PlannerUI
import SwiftUI

// A separate, test-only application. It never opens the editor or a DraftStore.
// Launch inputs select synthetic scenarios; expected text is not read or rendered.
@main
struct EvidenceHarnessApp: App {
    private let scenarios: Result<[Scenario], Error>

    init() {
        scenarios = Result { try Scenario.load(arguments: ProcessInfo.processInfo.arguments) }
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup { root }.defaultSize(width: 1000, height: 900)
        #else
        WindowGroup { root }
        #endif
    }

    @ViewBuilder private var root: some View {
        switch scenarios {
        case .success(let values): ScenarioHost(scenarios: values)
        case .failure:
            Text("Evidence harness could not load its synthetic scenario.")
                .accessibilityIdentifier("evidence-harness-error")
        }
    }
}

private struct ScenarioHost: View {
    let scenarios: [Scenario]
    @State private var index = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(verbatim: scenarios[index].id).accessibilityIdentifier("evidence-harness-case")
                    Text("Case \(index + 1) of \(scenarios.count)").accessibilityIdentifier("evidence-harness-position")
                }
                Spacer()
                Button("Next fixture") { index += 1 }
                    .disabled(index + 1 == scenarios.count)
                    .accessibilityIdentifier("evidence-harness-next")
            }
            .padding()
            Divider()
            GeometryReader { geometry in
                switch scenarios[index].content {
                case .report(let report, let width, let largeText):
                    // The report owns its vertical scrolling. A horizontal
                    // viewport also exposes the requested wide layout on a
                    // compact device without changing the production view.
                    ScrollView(.horizontal) {
                        EvaluationReportView(report: report)
                            .frame(width: width ?? geometry.size.width, height: geometry.size.height)
                            .environment(\.dynamicTypeSize, largeText ? .accessibility3 : .large)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("evidence-harness-content")
                case .claim(let presentation):
                    ScrollView {
                        ClaimEvidenceView(presentation: presentation)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("evidence-harness-content")
                }
            }
            .id(scenarios[index].id)
        }
    }
}

private struct Scenario {
    enum Content {
        case report(EvaluationReport, width: CGFloat?, largeText: Bool)
        case claim(EvidencePresentation)
    }
    let id: String
    let content: Content

    private struct VectorBundle: Decodable {
        let lock: [String: String]
        let cases: [Vector]
    }
    private struct Vector: Decodable {
        let id: String
        let valid: Bool
        let payloadJSON: String
    }
    private enum InputError: Error { case unsupportedScenario, invalidFixture }

    static func load(arguments: [String]) throws -> [Scenario] {
        guard let offset = arguments.firstIndex(of: "--evidence-group"), offset + 1 < arguments.count else {
            throw InputError.unsupportedScenario
        }
        let group = arguments[offset + 1]
        switch group {
        case "shared", "report-size":
            guard let url = Bundle.main.url(forResource: "evidence-vectors", withExtension: "json") else {
                throw InputError.invalidFixture
            }
            let bundle = try JSONDecoder().decode(VectorBundle.self, from: Data(contentsOf: url))
            guard bundle.lock["contract_version"] == "1.0.0", bundle.cases.count == 37,
                  Set(bundle.cases.map(\.id)).count == 37 else { throw InputError.invalidFixture }
            if group == "shared" {
                let accepted = bundle.cases.filter(\.valid)
                guard accepted.count == 28 else { throw InputError.invalidFixture }
                return try accepted.map {
                    Scenario(id: $0.id, content: .report(try EvaluationReport.decode(Data($0.payloadJSON.utf8)),
                                                        width: nil, largeText: false))
                }
            }
            guard let vector = bundle.cases.first(where: { $0.id == "evidence/reported-pass-without-support" && $0.valid }) else {
                throw InputError.invalidFixture
            }
            let report = try EvaluationReport.decode(Data(vector.payloadJSON.utf8))
            return [375, 820].map { width in
                Scenario(id: "reported-pass-width-\(width)", content: .report(report, width: CGFloat(width), largeText: true))
            }
        case "claims":
            let retainedIdentity = try identity()
            let inspected = try inspection()
            let independent = try support()
            let inputs: [(String, OriginalVerificationStatus, ClaimSourceAvailability, AcceptedIndependentSupport?)] = [
                ("not-inspected", .verified, .notInspected, nil),
                ("support-without-inspection", .verified, .notInspected, independent),
                ("inspected", .verified, .inspected(inspected), nil),
                ("independent", .unverified, .inspected(inspected), independent),
                ("user-supplied", .userSupplied, .notInspected, nil),
                ("estimated", .estimated, .notInspected, nil),
                ("unavailable", .verified, .unavailable, independent),
            ]
            return inputs.map { id, original, source, accepted in
                Scenario(id: id, content: .claim(EvidencePresentation(identity: retainedIdentity,
                    originalVerificationStatus: original, source: source,
                    independentSupport: accepted, freshness: .versionPinned)))
            }
        case "notices":
            let retainedIdentity = try identity()
            let base = EvidencePresentation(identity: retainedIdentity, originalVerificationStatus: .verified,
                source: .inspected(try inspection()), independentSupport: try support(),
                freshness: .currentState(captureDate: try EvidenceCaptureDate("2024-01-02")))
            return [
                Scenario(id: "newer-release", content: .claim(base.receiving(.newerReleaseAvailable))),
                Scenario(id: "newer-snapshot", content: .claim(base.receiving(.newerSnapshotAvailable))),
                Scenario(id: "correction", content: .claim(base.receiving(.correction(retainedIdentity)).receiving(.newerReleaseAvailable))),
            ]
        default: throw InputError.unsupportedScenario
        }
    }

    private static func identity() throws -> RetainedEvidenceIdentity {
        try RetainedEvidenceIdentity(componentID: "synthetic.component", componentVersion: "1.0.0",
                                     catalogSnapshotID: "snapshot.retained")
    }
    private static func inspection() throws -> SourceInspectionReceipt {
        try SourceInspectionReceipt(sourceReference: "synthetic:claim", inspectionReference: "synthetic:read",
                                    retrievalMethod: "synthetic fixture")
    }
    private static func support() throws -> AcceptedIndependentSupport {
        try AcceptedIndependentSupport(evidenceReference: "synthetic:independent", acceptanceReference: "synthetic:acceptance")
    }
}
