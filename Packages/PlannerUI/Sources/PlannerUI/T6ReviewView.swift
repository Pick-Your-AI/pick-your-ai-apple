import Foundation
import PlannerCore
import PlannerTransfer
import SwiftUI
import UniformTypeIdentifiers

/// Reusable destination; its parent owns the selected persisted Build and the
/// current compatibility adapter. It does not create, approve, publish or deploy.
public struct T6ReviewView: View {
    @ObservedObject private var model: T6ReviewModel
    @State private var filePicker = false
    @State private var fileSelection: T6FileSelection?

    public init(model: T6ReviewModel) { self.model = model }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("T6 review").font(.title).accessibilityAddTraits(.isHeader)
                if let build = model.build {
                    Text(verbatim: build.name).font(.headline)
                    Text(verbatim: "Build: \(build.id), revision \(json(build.value.t6Object?["revision"]))")
                        .accessibilityIdentifier("t6-build-identity")
                    Text("Reviewing retained declarations does not approve quality or deploy a Build.")
                    controls
                    compatibilitySection
                    if let notice = model.notice {
                        Text(verbatim: notice).accessibilityIdentifier("t6-notice")
                    }
                    if model.busy {
                        ProgressView("Reviewing records…").accessibilityIdentifier("t6-pending")
                    } else if let content = model.content {
                        qualitySection(content.guidance)
                        manifestSection(content)
                        DisclosureGroup("Exact version locks") { value(build.locks) }
                        DisclosureGroup("Monitoring selections") {
                            let monitoring = build.value.t6Object!["selections"]!.t6Array!.filter {
                                $0.t6Object?["kind"] == .string("monitoring_stack")
                            }
                            if monitoring.isEmpty { Text("No monitoring selection was supplied.") }
                            ForEach(monitoring.indices, id: \.self) { value(monitoring[$0]) }
                        }
                    }
                } else {
                    Text("Select a retained Build in Imported builds to review T6.")
                        .accessibilityIdentifier("t6-no-build")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle("T6 review")
        .accessibilityIdentifier("t6-review")
        .background {
            if let request = fileSelection {
                T6FileSelectionPresenter(model: model, request: request, isPresented: $filePicker)
                    .id(request.id)
            }
        }
        .onDisappear {
            model.cancel(); filePicker = false; fileSelection = nil
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Choose quality record") { chooseFile(.quality) }
                .accessibilityIdentifier("t6-import-quality")
            Button("Choose deployment declaration") { chooseFile(.manifest) }
                .accessibilityIdentifier("t6-import-manifest")
            Button("Review / Retry") { Task { await model.retry() } }
                .accessibilityIdentifier("t6-retry")
            if model.busy {
                Button("Cancel review") { model.cancel() }.accessibilityIdentifier("t6-cancel")
            }
            Button("Remove quality record") { Task { await model.removeQuality() } }
            Button("Remove deployment declaration") { Task { await model.removeManifest() } }
        }
    }

    private func chooseFile(_ kind: T6FileSelection.Kind) {
        guard let request = model.beginFileSelection(kind) else { return }
        fileSelection = request; filePicker = true
    }

    @ViewBuilder private var compatibilitySection: some View {
        Text("Compatibility").font(.title2).accessibilityAddTraits(.isHeader)
        if let report = model.compatibility {
            Text(verbatim: "Reported compatibility: \(report.result.rawValue)")
                .accessibilityIdentifier("t6-compatibility")
            DisclosureGroup("Inspect the current compatibility record") {
                EvaluationReportView(report: report)
            }
        } else {
            Text("Compatibility is unavailable for the current selection. This is not a pass.")
                .accessibilityIdentifier("t6-compatibility")
        }
    }

    @ViewBuilder private func qualitySection(_ guidance: T6QualityGuidance) -> some View {
        Text("Quality and controls").font(.title2).accessibilityAddTraits(.isHeader)
        Text("Approval is not established.").accessibilityIdentifier("t6-approval-unknown")
        ForEach(guidance.selections.indices, id: \.self) { index in
            let selection = guidance.selections[index]
            DisclosureGroup("\(selection.kind.rawValue): \(selection.id) (\(selection.enabled ? "enabled" : "disabled"))") {
                value(selection.value)
            }
        }
        switch guidance.record {
        case .notSupplied:
            Text("Quality record not supplied. Quality remains unknown.")
                .accessibilityIdentifier("t6-quality-status")
        case .supplied(let scenario):
            Text(verbatim: "Reported quality: \(scenario.run.status.rawValue)")
                .accessibilityIdentifier("t6-quality-status")
            Text(verbatim: "Quality record: \(scenario.run.id)")
            Text(verbatim: "Evaluator: \(scenario.run.evaluatorVersion); dataset: \(scenario.run.datasetRevision)")
            Text(verbatim: "Recorded sample size: \(scenario.run.sampleSize)")
            ForEach(scenario.run.measurements.indices, id: \.self) { index in
                let row = scenario.run.measurements[index]
                VStack(alignment: .leading) {
                    Text(verbatim: row.metric).font(.headline)
                    Text(verbatim: "Observed \(row.observed); threshold \(row.comparator.rawValue) \(row.threshold)")
                    Text(verbatim: "Unit: \(json(row.value.t6Object?["unit"])); reported passed: \(row.passed)")
                }.accessibilityIdentifier("t6-measurement-\(index)")
            }
            if scenario.run.artifacts.isEmpty { Text("No artifact references were supplied.") }
            ForEach(scenario.run.artifacts.indices, id: \.self) { index in
                Text(verbatim: "Unverified reference: \(scenario.run.artifacts[index])")
            }
            Text("References are displayed as text and are not opened or authenticated.")
        }
        ForEach(guidance.nextSteps.indices, id: \.self) { index in
            Text(verbatim: guidance.nextSteps[index].message)
        }
    }

    @ViewBuilder private func manifestSection(_ content: T6ReviewContent) -> some View {
        Text("Deployment declaration").font(.title2).accessibilityAddTraits(.isHeader)
        Text(verbatim: manifestMessage(content.manifestIssue))
            .accessibilityIdentifier("t6-plan-status")
        if let manifest = content.manifest {
            Text(verbatim: "Declared status: \(manifest.status)")
            Text(verbatim: "Declared Build: \(manifest.buildID), revision \(manifest.buildRevision)")
            Text(verbatim: "Declared target: \(manifest.deploymentTargetSelectionID)")
            ForEach(["compatibility_report_id", "quality_run_id", "cost_estimate_id", "resource_estimate_id", "rollback_artifact_uri"], id: \.self) { key in
                Text(verbatim: "\(key): \(json(manifest.value.t6Object?[key]))")
            }
            DisclosureGroup("Reported approvals (unverified)") {
                ForEach(manifest.approvals.indices, id: \.self) { index in value(manifest.approvals[index]) }
            }
            DisclosureGroup("Complete original declaration, including private fields") { value(manifest.value) }
        }
        if content.localArtifacts != nil {
            Text("A private local Build and proposed manifest are prepared separately. Nothing has been saved, shared or deployed.")
                .accessibilityIdentifier("t6-local-pair")
        }
    }

    private func manifestMessage(_ issue: T6ManifestIssue?) -> String {
        switch issue {
        case nil: return "Proposed local plan; approvals and references remain unverified."
        case .notSupplied: return "No deployment declaration supplied. A proposed plan is not available."
        case .unreadableOrIncomplete: return "The declaration is incomplete, unsupported or unreadable. All four report IDs and at least one approval declaration are required; no replacement values were inserted."
        case .notProposed: return "The original status is retained. Only a proposed declaration can prepare a local plan."
        case .buildMismatch: return "This declaration belongs to another Build or revision. It was not attached to the selected Build."
        case .targetBinding: return "The declaration does not identify exactly one enabled deployment target in this Build."
        }
    }

    private func value(_ value: JSONValue) -> some View {
        Text(verbatim: json(value)).font(.system(.body, design: .monospaced))
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
    private func json(_ value: JSONValue?) -> String {
        guard let value else { return "not supplied" }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(value), let text = String(data: bytes, encoding: .utf8) else {
            return "value cannot be displayed"
        }
        return text
    }
}

/// One presenter identity owns one immutable request. A late completion never
/// reads the parent view's mutable state to borrow a newer picker's token.
@MainActor
private struct T6FileSelectionPresenter: View {
    let model: T6ReviewModel
    let request: T6FileSelection
    @Binding var isPresented: Bool

    var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.json],
                          allowsMultipleSelection: false, onCompletion: { result in
                switch result {
                case .success(let urls):
                    guard urls.count == 1, let url = urls.first else {
                        model.fileSelectionFailed(for: request); return
                    }
                    Task { await model.importFile(url, for: request) }
                case .failure:
                    model.fileSelectionFailed(for: request)
                }
            }, onCancellation: {
                model.fileSelectionCancelled(for: request)
            })
    }
}
