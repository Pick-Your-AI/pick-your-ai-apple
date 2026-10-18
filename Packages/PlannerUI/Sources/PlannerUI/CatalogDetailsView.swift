import SwiftUI
import PlannerTransfer

/// A stacked, read-only consumer of the exact selected fixture item. Provenance
/// URLs use verbatim Text. A separate explicit review revalidates the same
/// destination before a one-use system handoff; the preview approves no hosts.
struct CatalogPreviewDetails: View {
    @StateObject private var model: CatalogDetailsModel
    @StateObject private var versions: CatalogRecordedVersionsModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private let inspectVersion: @MainActor (CatalogBrowserRow) -> Bool

    init(row: CatalogBrowserRow, source: any CatalogDetailSource,
         inspectVersion: @escaping @MainActor (CatalogBrowserRow) -> Bool) {
        _model = StateObject(wrappedValue: CatalogDetailsModel(row: row, source: source))
        _versions = StateObject(wrappedValue: CatalogRecordedVersionsModel(row: row, source: source))
        self.inspectVersion = inspectVersion
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Fictional sample component").font(.headline)
                    Text("Use this catalog to explore component types. Build selection is not available in this preview.")
                    if model.isLoading {
                        ProgressView("Loading this exact component…").accessibilityIdentifier("catalogDetailLoading")
                    }
                    if model.unavailable {
                        Text("Details for this exact version and catalog could not be loaded. Your selected identity and browsing filters are preserved.")
                            .accessibilityIdentifier("catalogDetailUnavailable")
                        Button("Retry details") { model.retry() }.accessibilityIdentifier("catalogDetailRetry")
                    }
                    if let result = model.result {
                        Text("Specifications: \(result.details.specifications.count) · Source records: \(result.details.provenance.count)")
                            .font(.footnote).accessibilityIdentifier("catalogDetailReady")
                    }
                }
                Section("Component") {
                    LabeledContent("Name") { literal(model.row.item.title) }
                    LabeledContent("Kind", value: CatalogBrowserView.kindTitle(model.row.item.kind))
                    LabeledContent("Version") { literal(model.row.item.version) }
                    LabeledContent("Identifier") { literal(model.row.item.id) }
                }
                if model.result != nil { recordedVersions }
                Section("Assessment") {
                    LabeledContent("Compatibility", value: "Unknown")
                    LabeledContent("Price estimate", value: "Unknown")
                }
                Section("Pinned sample source") {
                    LabeledContent("Catalog") { literal(model.row.snapshot.id) }
                    LabeledContent("Revision", value: String(model.row.snapshot.revision))
                    LabeledContent("Captured") { literal(model.row.snapshot.capturedAt) }
                    if let result = model.result {
                        VStack(alignment: .leading) {
                            Text("Snapshot SHA-256").font(.headline)
                            literal(result.sha256, identifier: "catalogDetailHash").font(.caption)
                        }
                    }
                }
                if let result = model.result {
                    recordedDetails(result.details)
                }
            }
            .accessibilityIdentifier("catalogDetailsForm")
            .navigationTitle("Component details")
            .toolbar { Button("Done") { retire(); dismiss() } }
            .task { model.loadIfNeeded() }
            .onChange(of: model.result) { _, result in
                if let result { versions.loadIfNeeded(details: result) }
            }
            .onDisappear { retire() }
        }
    }

    private var recordedVersions: some View {
        Section("Recorded versions") {
            Text("These entries share this exact identifier and kind in the pinned catalog. Other product variants, the latest version and availability have not been established.")
            if versions.isLoading {
                ProgressView("Checking recorded versions…")
                    .accessibilityIdentifier("catalogVersionsLoading")
            }
            if versions.unavailable {
                Text("Other recorded versions could not be checked or opened. This component and your browsing filters are preserved. You can close and reopen details.")
                    .accessibilityIdentifier("catalogVersionsUnavailable")
                if versions.canRetry {
                    Button("Retry recorded versions") { versions.retry() }
                        .accessibilityIdentifier("catalogVersionsRetry")
                }
            }
            if let result = versions.result {
                Text("Recorded versions in this catalog: \(result.rows.count)")
                    .accessibilityIdentifier("catalogVersionCount")
                if versions.otherVersions.isEmpty {
                    Text("No other version of this identifier and kind is recorded in this catalog.")
                        .accessibilityIdentifier("catalogVersionsNoOthers")
                } else {
                    Text("Ordered by recorded version text. Inspecting another version does not select or replace a build component.")
                    ForEach(versions.otherVersions) { row in
                        Button {
                            guard let target = versions.selection(for: row) else { return }
                            if inspectVersion(target) { retire() }
                            else { versions.rejectSelection() }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Inspect recorded version")
                                literal(row.item.version)
                                literal(row.item.title)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("catalogRecordedVersion-\(row.item.version)")
                    }
                }
            }
        }
    }

    private func retire() { model.close(); versions.close() }

    @ViewBuilder
    private func recordedDetails(_ details: CatalogItemDetails) -> some View {
        Section("Version and conditions") {
            LabeledContent("Recorded status") { literal(details.item.status) }
            LabeledContent("Billing class") { literal(details.item.billingClass) }
            LabeledContent("Record updated") { literal(details.updatedAt) }
            Text("Billing class and provider references do not establish an applicable price or serving offering. Currency, region, meter and effective period remain unknown until a qualified rate is available.")
            if let description = details.descriptionText {
                if description.isEmpty { Text("Empty description recorded") }
                else { literal(description) }
            } else { Text("Description not recorded") }
        }
        Section("Recorded specifications") {
            Text("Values retain their recorded units and conditions. Missing fields are not zero or evidence of support.")
            ForEach(details.specifications, id: \.name) { field in
                fieldRow(field, prefix: "catalogDetailSpec")
            }
        }
        Section("License declarations") {
            Text("These declarations have not been checked for your intended use. Missing permissions remain unknown.")
            ForEach(details.license, id: \.name) { field in
                fieldRow(field, prefix: "catalogDetailLicense")
            }
        }
        Section("Provenance and evidence gaps") {
            Text("The source records have not been inspected in this preview. Declared verification status does not establish a checked or independently verified claim. Dates and conflicting notes are retained without a freshness verdict.")
                .accessibilityIdentifier("catalogDetailEvidenceGap")
            let visibleCount = min(model.provenanceLimit, details.provenance.count)
            Text("Showing \(visibleCount) of \(details.provenance.count) source records")
                .accessibilityIdentifier("catalogDetailSourceCount")
            ForEach(0..<visibleCount, id: \.self) { index in
                provenanceRow(details.provenance[index], index: index)
            }
            if visibleCount < details.provenance.count {
                Button("Show more source records") { model.loadMoreSources() }
                    .accessibilityIdentifier("catalogDetailMoreSources")
            }
        }
    }

    private func fieldRow(_ field: CatalogDetailField, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: field.name).font(.headline).accessibilityAddTraits(.isHeader)
            Text(verbatim: field.type.rawValue).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: CatalogDetailText.state(field.state))
                .accessibilityIdentifier(prefix + "State-" + field.name)
            if let value = field.value {
                rendered(CatalogDetailText.value(value), identifier: prefix + "Value-" + field.name)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func provenanceRow(_ source: CatalogDetailProvenance, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source record \(index + 1)").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Declared verification status")
            literal(source.originalVerificationStatus, identifier: "catalogDetailSourceStatus-\(index)")
            Text("Recorded check date")
            literal(source.checkedAt, identifier: "catalogDetailSourceDate-\(index)")
            if let uri = source.sourceURI {
                Text("Source URL (text)")
                literal(uri, identifier: "catalogDetailSourceURI-\(index)")
                Text("Source hosts require separate review before navigation.").font(.footnote)
            } else {
                Text("Source URL not recorded").accessibilityIdentifier("catalogDetailSourceMissing-\(index)")
            }
            if let notes = source.notes {
                if notes.isEmpty { Text("Empty source notes recorded") }
                else { literal(notes, identifier: "catalogDetailSourceNotes-\(index)") }
            } else { Text("Source notes not recorded") }
            Button("Review source link") { model.inspectSource(at: index) }
                .accessibilityIdentifier("catalogSourceReview-\(index)")
            if let review = model.sourceReview, review.sourceIndex == index {
                sourceReview(review)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sourceReview(_ review: CatalogSourceReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source link review").font(.headline).accessibilityAddTraits(.isHeader)
            switch review.state {
            case .missing:
                Text("This source record has no URL. No external navigation is available.")
                    .accessibilityIdentifier("catalogSourceReviewMissing")
            case .rejected:
                Text("This address cannot be opened under the current source-link policy. Only explicitly reviewed HTTPS hosts are eligible; this fictional preview has no approved source hosts.")
                    .accessibilityIdentifier("catalogSourceReviewRejected")
            case .confirmation(let link):
                Text("Review the exact destination before leaving this preview.")
                Text(verbatim: link.host).font(.headline).textSelection(.enabled)
                // Policy input is bounded to 4,096 bytes in the app. Unlike the
                // ordinary field preview, a confirmation shows the complete URL.
                Text(verbatim: link.url.absoluteString).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).accessibilityIdentifier("catalogSourceDestination")
                Text("The system may use your browser or an associated app. The destination may redirect. Opening a link does not verify its content or grant source-use rights.")
                Button("Open source") {
                    guard let opening = model.sourceToOpen(reviewID: review.id) else { return }
                    let receiver = model
                    openURL(opening.url) { accepted in
                        Task { @MainActor [weak receiver] in
                            receiver?.completeSourceOpen(reviewID: opening.id, accepted: accepted)
                        }
                    }
                }.accessibilityIdentifier("catalogSourceConfirm")
            case .opening:
                ProgressView("Requesting system handoff…")
            case .unavailable:
                Text("The system could not open this source. Your component and browsing state are preserved.")
                    .accessibilityIdentifier("catalogSourceUnavailable")
                Button("Review again") { model.inspectSource(at: review.sourceIndex) }
                    .accessibilityIdentifier("catalogSourceRetry")
            case .handedOff:
                Text("The system accepted the request. Loading or inspecting the source content has not been verified.")
                    .accessibilityIdentifier("catalogSourceHandedOff")
            }
            Button(review.state.isConfirmation ? "Cancel source opening" : "Close source review") {
                model.closeSourceReview(id: review.id)
            }.accessibilityIdentifier("catalogSourceClose")
        }
        .padding(.vertical, 8)
    }

    private func literal(_ value: String, identifier: String? = nil) -> some View {
        rendered(CatalogDetailText.literal(value), identifier: identifier)
    }

    private func rendered(_ value: CatalogDetailLiteral, identifier: String? = nil) -> some View {
        VStack(alignment: .leading) {
            if let identifier {
                Text(verbatim: value.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .accessibilityIdentifier(identifier)
            } else {
                Text(verbatim: value.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if value.truncated {
                Text("Value shortened for display. The source record is retained.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private extension CatalogSourceReviewState {
    var isConfirmation: Bool {
        if case .confirmation = self { return true }
        return false
    }
}
