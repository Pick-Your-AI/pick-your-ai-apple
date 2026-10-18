import SwiftUI
import PlannerCatalog

/// A visibly synthetic read-only browsing surface. Choosing a row inspects its
/// exact pinned identity; this view receives no draft store or selection writer.
public struct CatalogBrowserView: View {
    @StateObject private var model: CatalogBrowserModel
    @State private var inspected: CatalogBrowserRow?
    @FocusState private var searchFocused: Bool
    private let detailSource: any CatalogDetailSource

    public init() {
        let source = BundledCatalogPreviewSource()
        detailSource = source
        _model = StateObject(wrappedValue: CatalogBrowserModel(
            source: source, availableKinds: BundledCatalogPreviewSource.availableKinds,
            preferences: CatalogFilterPreferences()))
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Sample data for exploring the planner. These fictional components have no current compatibility assessment or price estimate.")
                        .accessibilityIdentifier("catalogQualification")
                }
                Section("Find components") {
                    TextField("Search name, kind or identifier", text: Binding(
                        get: { model.filters.query }, set: { model.setQuery($0) }))
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                        .onSubmit { searchFocused = false }
                        .accessibilityIdentifier("catalogSearch")
                    Picker("Sort", selection: Binding(
                        get: { model.filters.sort }, set: { model.setSort($0) })) {
                        ForEach(CatalogBrowserSort.allCases, id: \.self) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("catalogSort")
                    Menu {
                        ForEach(model.visibleKinds, id: \.self) { kind in
                            Toggle(Self.kindTitle(kind), isOn: Binding(
                                get: { model.filters.kinds.contains(kind) },
                                set: { model.setKind(kind, included: $0) }))
                                .accessibilityIdentifier("catalogKind-\(kind)")
                        }
                    } label: {
                        Label(model.filters.kinds.isEmpty ? "All component kinds" : "Kinds: \(model.filters.kinds.count) selected",
                              systemImage: "line.3.horizontal.decrease")
                    }
                    // Keep the menu's own activation target. The automatic List
                    // row wrapper can expose a larger, inactive button to AX.
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("catalogKinds")
                    if !model.filters.kinds.isEmpty {
                        Text(model.filters.kinds.sorted().map(Self.kindTitle).joined(separator: ", "))
                            .font(.subheadline)
                            .accessibilityIdentifier("catalogActiveKinds")
                    }
                    Button("Clear filters") { model.clearFilters() }
                        .disabled(model.filters.isDefault)
                        .accessibilityIdentifier("catalogClearFilters")
                }
                Section {
                    if model.isLoading {
                        ProgressView(model.rows.isEmpty ? "Searching components…" : "Loading more components…")
                            .accessibilityIdentifier("catalogLoading")
                    }
                    if let notice = model.notice {
                        Text(notice.message).foregroundStyle(.red).accessibilityIdentifier("catalogNotice")
                        if model.canRetry {
                            Button(notice == .catalogChanged ? "Reload results" : "Retry") { model.retry() }
                                .accessibilityIdentifier("catalogRetry")
                        }
                    }
                    if model.snapshot != nil {
                        Text("Showing \(model.rows.count) of \(model.totalCount) results")
                            .accessibilityIdentifier("catalogResultCount")
                    }
                    if model.rows.isEmpty && !model.isLoading && model.notice == nil {
                        Text("No components match these filters.")
                            .accessibilityIdentifier("catalogEmpty")
                    }
                    ForEach(model.rows) { row in
                        Button { inspected = row } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.item.title).font(.headline)
                                Text("\(Self.kindTitle(row.item.kind)) · \(row.item.version)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("catalogItem-\(row.item.id)-\(row.item.version)")
                        .accessibilityLabel("\(row.item.title), \(Self.kindTitle(row.item.kind)), version \(row.item.version). Sample component.")
                        .accessibilityHint("Opens component details")
                    }
                    if model.canLoadMore {
                        Button("Load more components") { model.loadMore() }
                            .accessibilityIdentifier("catalogLoadMore")
                    }
                } header: { Text("Components") }
                if let snapshot = model.snapshot {
                    Section("Sample catalog version") {
                        Text("\(snapshot.id) · Revision \(snapshot.revision)")
                        Text("Fixture captured \(snapshot.capturedAt)").font(.footnote)
                        Text("Compatibility and pricing remain unknown. Browsing does not change your notes or saved builds.")
                            .font(.footnote)
                    }
                }
            }
            .accessibilityIdentifier("catalogList")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Demo catalog")
            .toolbar {
                Button("Reload", systemImage: "arrow.clockwise") { model.reload() }
                    .accessibilityIdentifier("catalogReload")
            }
            .task { model.loadIfNeeded() }
            .sheet(item: $inspected) { row in
                CatalogPreviewDetails(row: row, source: detailSource).id(CatalogDetailsIdentity(row))
            }
        }
    }

    static func kindTitle(_ kind: String) -> String {
        kind.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
