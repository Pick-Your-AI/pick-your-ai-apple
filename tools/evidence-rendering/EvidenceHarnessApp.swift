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
                            .transformEnvironment(\.locale) { value in
                                if let environment = scenarios[index].presentationEnvironment { value = environment.locale }
                            }
                            .transformEnvironment(\.calendar) { value in
                                if let environment = scenarios[index].presentationEnvironment { value = environment.calendar }
                            }
                            .transformEnvironment(\.timeZone) { value in
                                if let environment = scenarios[index].presentationEnvironment { value = environment.timeZone }
                            }
                            .transformEnvironment(\.layoutDirection) { value in
                                if let environment = scenarios[index].presentationEnvironment { value = environment.layoutDirection }
                            }
                            .transformEnvironment(\.dynamicTypeSize) { value in
                                if scenarios[index].useLargeClaimText { value = .accessibility3 }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("evidence-harness-content")
                case .analysis(let report, let mode):
                    AnalysisScenarioView(report: report, mode: mode)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("evidence-harness-content")
                }
            }
            .id(scenarios[index].renderIdentity)
        }
    }
}

private struct Scenario {
    enum Content {
        case report(EvaluationReport, width: CGFloat?, largeText: Bool)
        case claim(EvidencePresentation)
        case analysis(EvaluationReport, mode: String)
    }
    let id: String
    let content: Content
    let presentationEnvironment: PresentationEnvironment?
    let renderIdentity: String
    let useLargeClaimText: Bool

    struct PresentationEnvironment {
        let locale: Locale
        let calendar: Calendar
        let timeZone: TimeZone
        let layoutDirection: LayoutDirection
    }

    init(id: String, content: Content, presentationEnvironment: PresentationEnvironment? = nil,
         renderIdentity: String? = nil, useLargeClaimText: Bool = false) {
        self.id = id
        self.content = content
        self.presentationEnvironment = presentationEnvironment
        self.renderIdentity = renderIdentity ?? id
        self.useLargeClaimText = useLargeClaimText
    }

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
        case "shared", "report-size", "analysis-state":
            guard let url = Bundle.main.url(forResource: "evidence-vectors", withExtension: "json") else {
                throw InputError.invalidFixture
            }
            let bundle = try JSONDecoder().decode(VectorBundle.self, from: Data(contentsOf: url))
            guard bundle.lock["contract_version"] == "1.0.0", bundle.cases.count == 41,
                  Set(bundle.cases.map(\.id)).count == 41 else { throw InputError.invalidFixture }
            if group == "shared" {
                let accepted = bundle.cases.filter(\.valid)
                guard accepted.count == 32 else { throw InputError.invalidFixture }
                return try accepted.map {
                    Scenario(id: $0.id, content: .report(try EvaluationReport.decode(Data($0.payloadJSON.utf8)),
                                                        width: nil, largeText: false))
                }
            }
            guard let vector = bundle.cases.first(where: { $0.id == "evidence/reported-pass-without-support" && $0.valid }) else {
                throw InputError.invalidFixture
            }
            let report = try EvaluationReport.decode(Data(vector.payloadJSON.utf8))
            if group == "analysis-state" {
                return ["current", "foreign-visible", "pending-retry", "cancelled", "failed", "disconnected", "cleared"].map {
                    Scenario(id: "analysis-\($0)", content: .analysis(report, mode: $0))
                }
            }
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
        case "dates":
            let retainedIdentity = try identity()
            let source = try inspection()
            let inputs: [(String, String, String, Calendar.Identifier, String, Bool, Bool)] = [
                ("date-us-honolulu", "2024-01-02", "en_US", .gregorian, "Pacific/Honolulu", false, false),
                ("date-gb-kiritimati", "2024-01-02", "en_GB", .buddhist, "Pacific/Kiritimati", false, false),
                ("date-de-berlin", "2024-01-02", "de_DE", .gregorian, "Europe/Berlin", false, false),
                ("date-ar-calendar", "2024-01-02", "ar_EG@numbers=arab;calendar=islamic-civil", .islamicCivil, "Africa/Cairo", true, false),
                ("date-th-calendar", "2024-01-02", "th_TH@calendar=buddhist", .buddhist, "Asia/Bangkok", false, false),
                ("date-gregorian-switch", "1582-10-10", "en_US", .gregorian, "UTC", false, false),
                ("date-first-year", "0001-01-01", "en_US", .japanese, "Asia/Tokyo", false, false),
                ("date-leap-day", "2000-02-29", "en_GB", .gregorian, "Pacific/Honolulu", false, false),
                ("date-last-year", "9999-12-31", "en_US", .gregorian, "Pacific/Kiritimati", false, false),
                ("date-locale-recovery", "2024-01-02", "en_US", .gregorian, "UTC", false, true),
            ]
            return try inputs.map { id, raw, locale, calendar, zone, rtl, correction in
                guard let timeZone = TimeZone(identifier: zone) else { throw InputError.invalidFixture }
                let base = EvidencePresentation(identity: retainedIdentity, originalVerificationStatus: .verified,
                    source: .inspected(source), freshness: .currentState(captureDate: try EvidenceCaptureDate(raw)))
                let presentation = correction ? base.receiving(.correction(retainedIdentity)) : base
                return Scenario(id: id, content: .claim(presentation),
                    presentationEnvironment: PresentationEnvironment(locale: Locale(identifier: locale),
                        calendar: Calendar(identifier: calendar), timeZone: timeZone,
                        layoutDirection: rtl ? .rightToLeft : .leftToRight),
                    renderIdentity: "retained-date-view")
            }
        case "copy":
            // Values deliberately resemble localization keys, Markdown and
            // format placeholders. They remain typed evidence, never copy keys.
            let retainedIdentity = try RetainedEvidenceIdentity(componentID: "synthetic.*component*",
                componentVersion: "1.0.0", catalogSnapshotID: "snapshot.[retained](literal)")
            let inspected = try SourceInspectionReceipt(sourceReference: "Source checked",
                inspectionReference: "receipt:**literal**", retrievalMethod: "method:%@")
            let accepted = try AcceptedIndependentSupport(evidenceReference: "support:[literal]",
                acceptanceReference: "acceptance:*literal*")
            guard let timeZone = TimeZone(secondsFromGMT: 0) else { throw InputError.invalidFixture }
            let inputs: [(String, String, Bool, OriginalVerificationStatus, ClaimSourceAvailability, Bool, EvidenceChangeEvent?)] = [
                ("copy-en", "en_US", false, .verified, .inspected(inspected), true, nil),
                ("copy-de", "de_DE", false, .verified, .inspected(inspected), true, nil),
                ("copy-ar", "ar_EG", true, .verified, .inspected(inspected), true, nil),
                ("copy-de-missing", "de_DE", false, .verified, .notInspected, false, nil),
                ("copy-ar-unavailable", "ar_EG", true, .verified, .unavailable, false, nil),
                ("copy-de-user", "de_DE", false, .userSupplied, .notInspected, false, nil),
                ("copy-ar-estimated", "ar_EG", true, .estimated, .notInspected, false, nil),
                ("copy-de-checked", "de_DE", false, .verified, .inspected(inspected), false, nil),
                ("copy-de-release", "de_DE", false, .verified, .inspected(inspected), true, .newerReleaseAvailable),
                ("copy-ar-snapshot", "ar_EG", true, .verified, .inspected(inspected), true, .newerSnapshotAvailable),
                ("copy-de-correction", "de_DE", false, .verified, .inspected(inspected), true, .correction(retainedIdentity)),
                ("copy-ar-correction", "ar_EG", true, .verified, .inspected(inspected), true, .correction(retainedIdentity)),
                ("copy-fr-fallback", "fr_FR", false, .verified, .inspected(inspected), true, .correction(retainedIdentity)),
                ("copy-en-recovery", "en_US", false, .verified, .inspected(inspected), true, .correction(retainedIdentity)),
            ]
            return try inputs.map { id, locale, rtl, original, source, independent, event in
                let base = EvidencePresentation(identity: retainedIdentity, originalVerificationStatus: original,
                    source: source, independentSupport: independent ? accepted : nil,
                    freshness: .currentState(captureDate: try EvidenceCaptureDate("2024-01-02")))
                let presentation = event.map { base.receiving($0) } ?? base
                return Scenario(id: id, content: .claim(presentation),
                    presentationEnvironment: PresentationEnvironment(locale: Locale(identifier: locale),
                        calendar: Calendar(identifier: .gregorian), timeZone: timeZone,
                        layoutDirection: rtl ? .rightToLeft : .leftToRight),
                    renderIdentity: "retained-copy-view", useLargeClaimText: true)
            }
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

/// Test-only event source driving the actual production model and view. It uses
/// the frozen synthetic tuple independently of the supplied report's identity.
@MainActor
private struct AnalysisScenarioView: View {
    let report: EvaluationReport
    let mode: String
    @State private var model = EvaluationAnalysisModel()
    @State private var prepared = false

    private func identity(revision: Int = 1) -> AnalysisIdentity {
        .frozenV1Evaluation(buildID: "build.fixture.1", buildRevision: revision,
            catalogSnapshotID: "catalog.fixture.1", rulesetID: "rules.fixture.1", rulesetVersion: "1.0.0",
            dependencyGraphID: "dependencies.core.1", dependencyGraphRevision: 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if prepared {
                Text("Synthetic analysis scenario ready: \(mode)").accessibilityIdentifier("analysis-scenario-ready")
                EvaluationAnalysisView(model: model,
                    visibleIdentity: mode == "cleared" ? nil : identity(revision: mode == "foreign-visible" ? 2 : 1))
            } else {
                ProgressView("Preparing synthetic analysis scenario")
            }
        }
        .task {
            model.select(identity())
            guard let request = await model.begin() else { return }
            switch mode {
            case "cancelled": guard await model.cancel(request) else { return }
            case "failed": guard await model.fail(request) else { return }
            default:
                guard await model.receive(report, for: request) else { return }
                switch mode {
                case "pending-retry": guard await model.begin() != nil else { return }
                case "disconnected": model.disconnect()
                case "cleared": model.clear()
                default: break
                }
            }
            prepared = true
        }
    }
}
