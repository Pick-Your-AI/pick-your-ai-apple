import SwiftUI
import PlannerData

public struct DraftLibraryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: DraftLibraryModel
    @SceneStorage("localDraftSelection") private var restoredID = ""
    @State private var pendingDelete: DraftRecord?
    @State private var pendingRestore: DraftRecord?
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
                    if model.records.isEmpty { Text("No readable drafts on this page") }
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
                        .disabled(!model.canEdit)
                }
                Section("Planning notes") {
                    TextEditor(text: $model.notes).frame(minHeight: 160)
                        .accessibilityLabel("Planning notes").accessibilityIdentifier("draftNotes")
                        .disabled(!model.canEdit)
                }
                Section("Edit history") {
                    HStack {
                        Button("Undo edit", systemImage: "arrow.uturn.backward") { model.undo() }
                            .disabled(!model.canUndo).accessibilityIdentifier("undoDraftEdit")
                        Button("Redo edit", systemImage: "arrow.uturn.forward") { model.redo() }
                            .disabled(!model.canRedo).accessibilityIdentifier("redoDraftEdit")
                    }
                    .buttonStyle(.borderless)
                    Text("Changes save automatically after you pause typing. Undo and redo apply to this editing session; saved revisions remain available below.")
                }
                Section("Revision history") {
                    Button("Load saved revisions") { Task { await model.loadHistory() } }
                        .accessibilityIdentifier("loadRevisions")
                    if model.historyOffset > 0 {
                        Button("Newer revisions") { Task { await model.loadHistory(offset: model.historyOffset - DraftLibraryModel.pageSize) } }
                    }
                    if model.hasOlderRevisions {
                        Button("Older revisions") { Task { await model.loadHistory(offset: model.historyOffset + DraftLibraryModel.pageSize) } }
                    }
                    if model.unreadableRevisions > 0 {
                        Text("\(model.unreadableRevisions) unreadable revisions were preserved.")
                    }
                    ForEach(model.revisions, id: \.revision) { revision in
                        VStack(alignment: .leading) {
                            Text("Local revision \(revision.revision)")
                            Text(revision.title).font(.caption)
                                .accessibilityIdentifier("revisionTitle-\(revision.revision)")
                            if let source = revision.restoredFrom {
                                Text("Restored from local revision \(source)").font(.caption)
                            }
                            if revision.revision < (model.selected?.revision ?? 0) {
                                Button("Restore revision \(revision.revision)") { pendingRestore = revision }
                                    .disabled(model.dirty)
                            }
                        }
                    }
                    Text("Restoration creates a new local revision and keeps later saved revisions. Save or discard unsaved changes first. Historical notes are not current compatibility or pricing evidence.")
                }
                .disabled(model.busy)
                Section {
                    Text(model.dirty ? "Unsaved changes" : model.status).accessibilityIdentifier("saveStatus")
                    Text("Compatibility: unknown. Pricing: unknown. Saving notes does not create a validated build.")
                    if let notice = model.notice {
                        Text(notice).foregroundStyle(.red).accessibilityIdentifier("editorNotice")
                    }
                }
            }
            .accessibilityIdentifier("draftEditorForm")
            .navigationTitle("Edit local draft")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        model.requestClose()
                    }.disabled(model.busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await model.save() } }
                        .disabled(!model.dirty || model.busy).accessibilityIdentifier("saveDraft")
                }
            }
            .confirmationDialog("Restore this saved revision as a new local revision?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })) {
                Button("Restore revision") {
                    if let revision = pendingRestore { Task { await model.restore(revision) } }
                    pendingRestore = nil
                }
            }
            .interactiveDismissDisabled(model.dirty || model.busy)
            .confirmationDialog("Discard unsaved changes?", isPresented: Binding(
                get: { model.awaitingDiscardDecision },
                set: { if !$0 { model.cancelDiscardDecision() } }
            )) {
                Button("Discard changes", role: .destructive) { model.discardChangesAndClose(); restoredID = "" }
            }
        }
    }
}
