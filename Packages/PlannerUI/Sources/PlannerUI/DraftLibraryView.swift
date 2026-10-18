import SwiftUI
import PlannerData

public struct DraftLibraryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: DraftLibraryModel
    @SceneStorage("localDraftSelection") private var restoredID = ""
    @State private var pendingDelete: DraftRecord?
    @State private var confirmDiscard = false
    public init(store: DraftStore) { _model = StateObject(wrappedValue: DraftLibraryModel(store: store)) }
    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Local drafts only. Compatibility is unknown. Pricing is unknown. No evaluation or service connection is available.")
                        .accessibilityIdentifier("evidenceNotice")
                }
                if let notice = model.notice { Text(notice).foregroundStyle(.red).accessibilityIdentifier("operationNotice") }
                if model.unreadableCount > 0 {
                    Text("\(model.unreadableCount) unreadable drafts were preserved in storage. They have not been deleted.")
                        .accessibilityIdentifier("corruptionNotice")
                }
                Section("Drafts") {
                    if model.pageOffset > 0 {
                        Button("Previous drafts") { Task { await model.changePage(forward: false) } }
                    }
                    if model.hasNextPage {
                        Button("More drafts") { Task { await model.changePage(forward: true) } }
                    }
                    if model.records.isEmpty { Text("No local drafts yet") }
                    ForEach(model.records, id: \.id) { record in
                        Button { Task { await model.open(record) } } label: {
                            VStack(alignment: .leading) {
                                Text(record.title.isEmpty ? "Untitled draft" : record.title)
                                Text("Local revision \(record.revision)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("draft-\(record.id)")
                        .contextMenu {
                            Button("Duplicate") { Task { await model.duplicate(record) } }
                            Button("Delete", role: .destructive) { pendingDelete = record }
                        }
                    }
                }
            }
            .navigationTitle("Your drafts")
            .toolbar {
                Button("New draft", systemImage: "plus") { Task { await model.create() } }
                    .accessibilityIdentifier("newDraft")
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
            }
            .disabled(model.busy)
            .confirmationDialog("Delete this local draft and all its revisions?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("Delete draft", role: .destructive) {
                    if let record = pendingDelete { Task { await model.delete(record) } }
                    pendingDelete = nil
                }
            }
            .sheet(isPresented: Binding(get: { model.selected != nil }, set: { if !$0 { model.close(); restoredID = "" } })) { editor }
            .task {
                await model.refresh()
                if let id = UUID(uuidString: restoredID) { await model.open(id: id) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { Task { await model.save() } }
            }
            .onChange(of: model.selected?.id) { _, id in restoredID = id?.uuidString ?? "" }
        }
    }
    private var editor: some View {
        NavigationStack {
            Form {
                Section("Draft name") {
                    TextField("Draft name", text: $model.title).accessibilityIdentifier("draftTitle")
                }
                Section("Planning notes") {
                    TextEditor(text: $model.notes).frame(minHeight: 160)
                        .accessibilityLabel("Planning notes").accessibilityIdentifier("draftNotes")
                }
                Section {
                    Text(model.dirty ? "Unsaved changes" : model.status).accessibilityIdentifier("saveStatus")
                    Text("Compatibility: unknown. Pricing: unknown. Saving notes does not create a validated build.")
                    if let notice = model.notice { Text(notice).foregroundStyle(.red) }
                }
            }
            .disabled(model.busy)
            .navigationTitle("Edit local draft")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if model.dirty { confirmDiscard = true } else { model.close(); restoredID = "" }
                    }.disabled(model.busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await model.save() } }
                        .disabled(!model.dirty || model.busy).accessibilityIdentifier("saveDraft")
                }
            }
            .interactiveDismissDisabled(model.dirty || model.busy)
            .confirmationDialog("Discard unsaved changes?", isPresented: $confirmDiscard) {
                Button("Discard changes", role: .destructive) { model.close(); restoredID = "" }
            }
        }
    }
}
