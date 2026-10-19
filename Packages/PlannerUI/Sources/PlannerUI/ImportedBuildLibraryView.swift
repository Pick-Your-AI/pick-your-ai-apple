import SwiftUI
import UniformTypeIdentifiers
import PlannerData
import PlannerTransfer

private struct ExportBuildDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

public struct ImportedBuildLibraryView: View {
    @StateObject private var model: ImportedBuildLibraryModel
    @State private var importing = false
    @State private var exporting = false
    @State private var alias = ""
    @State private var reviewed = false
    @State private var pendingRename: DraftRecord?
    @State private var renaming = false
    @State private var localLabel = ""
    @State private var pendingDelete: DraftRecord?
    @State private var deleting = false
    #if DEBUG
    private var syntheticT6Fixture: T6SyntheticJourney?
    public init(store: DraftStore, syntheticT6Scenario: String) {
        _model = StateObject(wrappedValue: ImportedBuildLibraryModel(store: store))
        syntheticT6Fixture = T6SyntheticJourney(rawValue: syntheticT6Scenario)
    }
    #endif
    public init(store: DraftStore) { _model = StateObject(wrappedValue: ImportedBuildLibraryModel(store: store)) }
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Imported builds are read-only local forks. Schema validation does not establish source rights, ownership, compatibility, pricing, or current evidence.")
                    if let notice = model.notice { Text(notice).foregroundStyle(.red) }
                    if let notice = model.libraryNotice { Text(notice).foregroundStyle(.red) }
                }
                if let preview = model.preview {
                    Section("Review import") {
                        Text(preview.snapshot.name)
                        Text(preview.usesSyntheticData == true ? "Marked synthetic fixture" : "Data qualification unknown")
                        Text("Import creates a new local ID and owner reference. It does not update the source or contact a service. Pinned catalog/rule references are retained, but their availability and qualification are unverified.")
                        Button("Create new local fork") { Task { await model.confirmImport() } }
                            .accessibilityIdentifier("confirmBuildImport")
                        Button("Cancel import", role: .cancel) { model.cancelPreview() }
                    }
                }
                Section("Imported builds") {
                    Button("Choose JSON file") { importing = true }
                        .accessibilityIdentifier("chooseBuildImport")
                    Button("Refresh builds") { Task { await model.refresh(offset: model.offset) } }
                        .accessibilityIdentifier("refreshImportedBuilds")
                    if model.offset > 0 {
                        Button("Previous builds") { Task { await model.refresh(offset: model.offset - ImportedBuildLibraryModel.pageSize) } }
                    }
                    if model.hasNext {
                        Button("More builds") { Task { await model.refresh(offset: model.offset + ImportedBuildLibraryModel.pageSize) } }
                    }
                    if model.records.isEmpty { Text("No readable imported builds on this page") }
                    if model.unreadableCount > 0 { Text("\(model.unreadableCount) unreadable records were preserved.") }
                    ForEach(model.records, id: \.id) { record in
                        Button { Task { await model.open(record) } } label: {
                            VStack(alignment: .leading) {
                                Text(record.title)
                                Text("Local revision \(record.revision)").font(.caption)
                                Text("Evidence: not revalidated").font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("importedBuild.\(record.id.uuidString)")
                            .accessibilityLabel(Text(verbatim: record.title))
                            .accessibilityValue(Text("Local revision \(record.revision). Evidence: not revalidated."))
                    }
                }
                if let snapshot = model.snapshot {
                    Section("Selected local fork") {
                        if let record = model.selected {
                            Text("Local label: " + record.title)
                            Text("Local revision \(record.revision)")
                            Button("Rename local label") { localLabel = record.title; pendingRename = record; renaming = true }
                                .accessibilityIdentifier("renameImportedBuild")
                            Button("Duplicate as new local fork") { Task { await model.duplicate(record) } }
                                .accessibilityIdentifier("duplicateImportedBuild")
                            Button("Delete local entry", role: .destructive) { pendingDelete = record; deleting = true }
                                .accessibilityIdentifier("deleteImportedBuild")
                        }
                        Text("Pinned snapshot: " + snapshot.name)
                        Text("Pinned snapshot revision: " + revisionText(snapshot))
                        Text(model.markedSynthetic ? "Marked synthetic fixture" : "Data qualification unknown")
                        Text("Compatibility: unknown. Imported analysis is not current.")
                        Text(snapshot.id).font(.caption).textSelection(.enabled)
                        NavigationLink("T6 review") {
                            T6ReviewView(model: model.t6Review)
                        }.accessibilityIdentifier("openT6Review")
                    }
                    Section("Cost coverage") {
                        switch ImportedBuildCostContext(snapshot: snapshot) {
                        case .available(let input):
                            // No qualified cost producer is connected to this local library.
                            CostCoverageView(summary: nil, currentBuildID: input.buildID,
                                currentBuildRevision: input.buildRevision, monthlyBudget: input.monthlyBudget,
                                isSynthetic: model.markedSynthetic)
                        case .unavailable(let reason):
                            Text("Cost estimate unavailable")
                                .accessibilityIdentifier("costCoverage.contextUnavailable")
                            Text(verbatim: reason.explanation)
                        }
                    }
                    Section("Compare configurations") {
                        Button("Use selected build as baseline") {
                            model.pinComparisonBaseline()
                        }.accessibilityIdentifier("pinComparisonBaseline")
                        if let baseline = model.comparisonBaseline {
                            Text("Baseline: " + baseline.name)
                            Text(baseline.id).font(.caption).textSelection(.enabled)
                            Text("Choose another imported build above, then compare. The baseline stays pinned until you replace or clear it, or delete its local entry.")
                            Button("Compare baseline with selected build") {
                                model.prepareComparison()
                            }.disabled(model.comparing).accessibilityIdentifier("compareSelectedBuilds")
                            Button("Clear comparison baseline", role: .cancel) {
                                model.clearComparisonBaseline()
                            }.accessibilityIdentifier("clearComparisonBaseline")
                        }
                        if model.comparing {
                            ProgressView("Preparing comparison…")
                            Button("Cancel comparison", role: .cancel) { model.cancelComparison() }
                                .accessibilityIdentifier("cancelBuildComparison")
                        }
                        if let comparisonNotice = model.comparisonNotice { Text(comparisonNotice).fixedSize(horizontal: false, vertical: true) }
                        if let comparison = model.comparison {
                            NavigationLink("View configuration differences (\(comparison.result.differences.count))") {
                                BuildComparisonView(comparison: comparison.result, beforeSynthetic: comparison.beforeSynthetic,
                                                    afterSynthetic: comparison.afterSynthetic)
                            }.accessibilityIdentifier("viewBuildComparison")
                        }
                    }
                    Section("Prepare export") {
                        TextField("Public owner alias", text: $alias)
                            .accessibilityIdentifier("publicExportAlias")
                        Text("Use an alias you intend to disclose. Private owner references, notes, and extensions are removed. Names and allowed settings remain visible and may contain sensitive free text.")
                        Button("Preview projected JSON") { reviewed = false; model.prepareExport(publicAlias: alias) }
                        if let data = model.exportData {
                            ScrollView {
                                Text(String(decoding: data, as: UTF8.self)).font(.caption.monospaced()).textSelection(.enabled)
                            }.frame(maxHeight: 240).accessibilityLabel("Projected export JSON")
                            Toggle("I reviewed the visible text and public alias for disclosure", isOn: $reviewed)
                            Button("Save reviewed JSON file") { exporting = true }
                                .disabled(!reviewed).accessibilityIdentifier("exportReviewedBuild")
                        }
                    }
                }
            }
            .accessibilityIdentifier("importedBuildsForm")
            .disabled(model.busy)
            .navigationTitle("Imported builds")
            .task {
                #if DEBUG
                if let fixture = syntheticT6Fixture { await model.installSyntheticT6Journey(fixture) }
                #endif
                await model.refresh()
            }
            .onDisappear { model.cancelComparison() }
            .onChange(of: alias) { _, _ in reviewed = false; model.clearExport() }
            .onChange(of: model.selected?.id) { _, _ in alias = ""; reviewed = false }
            .alert("Rename local label", isPresented: $renaming, presenting: pendingRename) { record in
                TextField("Local label", text: $localLabel)
                Button("Save label") {
                    let title = localLabel
                    Task { await model.rename(record, to: title) }
                }.disabled(localLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The label organizes this library entry separately from its pinned snapshot.")
            }
            .confirmationDialog("Delete this local entry and its revision history?", isPresented: $deleting, presenting: pendingDelete) { record in
                Button("Delete local entry", role: .destructive) {
                    Task { await model.delete(record) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { record in
                Text("Delete “" + record.title + "” at local revision \(record.revision)?")
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { Task { await model.previewFile(url) } }
                case .failure: model.reportFileFailure()
                }
            }
            .fileExporter(isPresented: $exporting, document: model.exportData.map { ExportBuildDocument(data: $0) }, contentType: .json, defaultFilename: "build.json") { result in
                if case .failure = result { model.reportFileFailure() }
                reviewed = false; model.clearExport()
            }
        }
    }
    private func revisionText(_ snapshot: BuildSnapshot) -> String {
        guard case .object(let fields) = snapshot.value, case .number(let revision)? = fields["revision"] else {
            return "Unavailable"
        }
        return NSDecimalNumber(decimal: revision).stringValue
    }
}
