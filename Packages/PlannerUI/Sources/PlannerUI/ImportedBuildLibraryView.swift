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

private struct PreparedBuildComparison {
    let result: BuildComparison
    let beforeSynthetic: Bool
    let afterSynthetic: Bool
}

public struct ImportedBuildLibraryView: View {
    @StateObject private var model: ImportedBuildLibraryModel
    @State private var importing = false
    @State private var exporting = false
    @State private var alias = ""
    @State private var reviewed = false
    @State private var comparisonBaseline: BuildSnapshot?
    @State private var baselineSynthetic = false
    @State private var comparison: PreparedBuildComparison?
    @State private var comparisonNotice: String?
    public init(store: DraftStore) { _model = StateObject(wrappedValue: ImportedBuildLibraryModel(store: store)) }
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Imported builds are read-only local forks. Schema validation does not establish source rights, ownership, compatibility, pricing, or current evidence.")
                    if let notice = model.notice { Text(notice).foregroundStyle(.red) }
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
                    if model.offset > 0 {
                        Button("Previous builds") { Task { await model.refresh(offset: model.offset - ImportedBuildLibraryModel.pageSize) } }
                    }
                    if model.hasNext {
                        Button("More builds") { Task { await model.refresh(offset: model.offset + ImportedBuildLibraryModel.pageSize) } }
                    }
                    if model.records.isEmpty { Text("No imported builds on this page") }
                    if model.unreadableCount > 0 { Text("\(model.unreadableCount) unreadable records were preserved.") }
                    ForEach(model.records, id: \.id) { record in
                        Button(record.title) { Task { await model.open(record) } }
                    }
                }
                if let snapshot = model.snapshot {
                    Section("Selected local fork") {
                        Text(snapshot.name)
                        Text(model.markedSynthetic ? "Marked synthetic fixture" : "Data qualification unknown")
                        Text("Compatibility: unknown. Pricing: unknown. Imported analysis is not current.")
                        Text(snapshot.id).font(.caption).textSelection(.enabled)
                    }
                    Section("Compare configurations") {
                        Button("Use selected build as baseline") {
                            comparisonBaseline = snapshot; baselineSynthetic = model.markedSynthetic
                            comparison = nil; comparisonNotice = nil
                        }.accessibilityIdentifier("pinComparisonBaseline")
                        if let baseline = comparisonBaseline {
                            Text("Baseline: " + baseline.name)
                            Text(baseline.id).font(.caption).textSelection(.enabled)
                            Text("Choose another imported build above, then compare. The baseline stays pinned until you replace or clear it.")
                            Button("Compare baseline with selected build") {
                                comparison = nil; comparisonNotice = nil
                                do {
                                    comparison = PreparedBuildComparison(
                                        result: try BuildComparison.compare(baseline, snapshot),
                                        beforeSynthetic: baselineSynthetic, afterSynthetic: model.markedSynthetic)
                                }
                                catch {
                                    comparisonNotice = "These builds could not be compared completely. Their identities may be ambiguous or conflicting, or the number of differences exceeds the supported limit. Both builds were preserved."
                                }
                            }.accessibilityIdentifier("compareSelectedBuilds")
                            Button("Clear comparison baseline", role: .cancel) {
                                comparisonBaseline = nil; comparison = nil; comparisonNotice = nil
                            }.accessibilityIdentifier("clearComparisonBaseline")
                        }
                        if let comparisonNotice { Text(comparisonNotice).fixedSize(horizontal: false, vertical: true) }
                        if let comparison {
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
            .disabled(model.busy)
            .navigationTitle("Imported builds")
            .task { await model.refresh() }
            .onChange(of: alias) { _, _ in reviewed = false; model.clearExport() }
            .onChange(of: model.selected?.id) { _, _ in alias = ""; reviewed = false }
            .onChange(of: model.snapshot) { _, _ in comparison = nil; comparisonNotice = nil }
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
}
