import SwiftUI
import UniformTypeIdentifiers
import PlannerData

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
