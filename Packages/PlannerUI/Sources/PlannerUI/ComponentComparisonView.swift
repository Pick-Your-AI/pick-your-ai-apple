import SwiftUI

/// Field-first stacking on narrow windows and at accessibility text sizes keeps
/// each component label with its value. Wide layouts align the same rows in a
/// grid. Both layouts retain the same selection order, values and visible state.
public struct ComponentComparisonView: View {
    @ObservedObject private var model: ComponentComparisonModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(model: ComponentComparisonModel) { self.model = model }

    // A sheet may retain its binding while dismissal completes. Capture the
    // presentation identity now so that an older binding cannot expose or
    // dismiss a replacement inspection, including a newly reopened record.
    var inspectionBinding: Binding<ComponentComparisonInspection?> {
        let inspectionID = model.inspection?.id
        return Binding(get: {
            guard let inspectionID, let current = model.inspection,
                  current.id == inspectionID else { return nil }
            return current
        }, set: { value in
            guard value == nil, let inspectionID else { return }
            model.closeInspection(inspectionID)
        })
    }

    public var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        qualification
                        selections
                        if let notice = model.notice {
                            Text(notice.message).accessibilityIdentifier("componentComparisonNotice")
                            Button("Dismiss comparison message") { model.dismissNotice() }.frame(minHeight: 44)
                        }
                        if model.isReady {
                            fieldNavigation
                            if model.visibleRows.isEmpty {
                                Text("No different declarations in this section. Unknowns still remain unknown; no comparison or eligibility verdict has been made.")
                                    .accessibilityIdentifier("componentComparisonNoDifferences")
                            } else if geometry.size.width >= 900 && !dynamicTypeSize.isAccessibilitySize {
                                wideMatrix
                            } else {
                                narrowMatrix
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("componentComparisonScroll")
            }
            .navigationTitle("Compare components")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("componentComparisonDone")
                }
            }
            .sheet(item: inspectionBinding) { inspection in
                completeRecord(inspection)
            }
        }
    }

    private var qualification: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Read-only sample comparison").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Compare two to four explicitly selected records. Their order follows your choices; no variant family, preferred version or ranking is inferred.")
            Text("Recorded fields keep their types, units and conditions. Different units, contexts, currencies or provider offerings are not converted or treated as equivalent. Compatibility, current prices and evidence eligibility remain unknown.")
                .accessibilityIdentifier("componentComparisonQualification")
            Text("\(model.selections.count) of 4 components selected")
                .accessibilityIdentifier("componentComparisonCount")
            if !model.isReady {
                Text(model.selections.isEmpty
                     ? "Inspect a catalog component and choose Add to comparison. No components have been selected."
                     : "Add one more component to show aligned fields. Your first selection is retained.")
                    .accessibilityIdentifier("componentComparisonEmpty")
            }
        }
    }

    private var selections: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(model.selections.enumerated()), id: \.element.id) { index, candidate in
                VStack(alignment: .leading, spacing: 6) {
                    heading("Component \(index + 1)")
                    literal(candidate.details.item.name)
                    literal(candidate.details.item.id)
                    Text("Kind: \(candidate.details.item.kind.rawValue)")
                    Text("Version")
                    literal(candidate.details.item.version)
                    Text("Catalog pin")
                    literal(candidate.catalog.identity.id)
                    Text("Revision \(candidate.catalog.identity.revision); schema \(candidate.catalog.identity.schemaVersion)")
                    literal(candidate.catalog.identity.capturedAt)
                    literal(candidate.catalog.sha256)
                        .accessibilityIdentifier("componentComparisonPin-\(index)")
                    Button("Inspect complete record for component \(index + 1)") { model.inspect(candidate.id) }
                        .frame(minHeight: 44).accessibilityIdentifier("componentComparisonInspect-\(index)")
                    Button("Remove component \(index + 1) from comparison") { model.remove(candidate.id) }
                        .frame(minHeight: 44).accessibilityIdentifier("componentComparisonRemove-\(index)")
                }
                .accessibilityElement(children: .contain)
                .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            if !model.selections.isEmpty {
                Button("Clear comparison") { model.clear() }
                    .frame(minHeight: 44).accessibilityIdentifier("componentComparisonClear")
            }
        }
    }

    private var fieldNavigation: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Compare recorded fields")
            ForEach(ComponentComparisonSection.allCases) { section in
                Button { model.section = section } label: {
                    Label(section.rawValue, systemImage: model.section == section ? "checkmark.circle.fill" : "circle")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.section == section ? .isSelected : [])
                .accessibilityValue(model.section == section ? "Selected section" : "Not selected")
                .accessibilityIdentifier("componentComparisonSection-\(section.rawValue)")
            }
            Button {
                model.differencesOnly.toggle()
            } label: {
                Label(model.differencesOnly ? "Showing differences only" : "Showing all fields",
                      systemImage: model.differencesOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
            }
            .accessibilityValue(model.differencesOnly ? "Differences only" : "All fields")
            .accessibilityIdentifier("componentComparisonDifferences")
            Text("Difference markers describe recorded declarations, including unknown and not-applicable states. They do not mean better, worse, compatible or zero.")
                .font(.footnote)
        }
    }

    private var narrowMatrix: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(model.visibleRows) { row in
                VStack(alignment: .leading, spacing: 12) {
                    rowHeading(row)
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { index, cell in
                        VStack(alignment: .leading, spacing: 6) {
                            heading("Component \(index + 1)")
                            literal(model.selections[index].details.item.name)
                            literal(model.selections[index].details.item.version)
                            cellContents(cell)
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
                .padding().overlay(RoundedRectangle(cornerRadius: 8).stroke(row.differs ? Color.accentColor : Color.clear))
                .accessibilityIdentifier("componentComparisonField-\(row.id)")
            }
        }
        .accessibilityIdentifier("componentComparisonStackedFields")
    }

    private var wideMatrix: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 20) {
            GridRow {
                heading("Field and conditions")
                ForEach(Array(model.selections.enumerated()), id: \.element.id) { index, candidate in
                    VStack(alignment: .leading, spacing: 4) {
                        heading("Component \(index + 1)")
                        literal(candidate.details.item.name)
                        literal(candidate.details.item.version)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(model.visibleRows) { row in
                GridRow {
                    rowHeading(row).frame(maxWidth: 180, alignment: .leading)
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { index, cell in
                        cellContents(cell).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Component \(index + 1), \(row.field)")
                            .accessibilityElement(children: .contain)
                    }
                }
                .accessibilityIdentifier("componentComparisonField-\(row.id)")
            }
        }
        .accessibilityIdentifier("componentComparisonAlignedFields")
    }

    private func rowHeading(_ row: ComponentComparisonRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            heading(row.field)
            Text(row.differs ? "Recorded declarations differ" : "Same recorded declaration")
            if row.hasUnknown { Text("Contains unknown information").font(.footnote) }
        }
    }

    private func cellContents(_ cell: ComponentComparisonCell) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let type = cell.type { Text(verbatim: "Type: " + type).font(.caption) }
            Text(verbatim: cell.availability.label)
            if !cell.isComparable {
                Text(verbatim: "Comparison unavailable: this value could not be encoded for comparison")
            }
            if let value = cell.value { completeText(ComponentComparisonText.value(value)) }
        }
    }

    private func completeRecord(_ inspection: ComponentComparisonInspection) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    heading("Complete selected record")
                    literal(inspection.candidate.details.item.id)
                    literal(inspection.candidate.details.item.version)
                    Text("Normalized JSON for this immutable selection. Its original catalog pin is retained in the comparison. Source declarations are not independently verified; URLs remain text and do not open here.")
                    completeText(ComponentComparisonText.record(inspection.candidate))
                        .font(.caption).accessibilityIdentifier("componentComparisonCompleteRecord")
                }.padding()
            }
            .navigationTitle("Recorded evidence")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { model.closeInspection(inspection.id) }
                        .accessibilityIdentifier("componentComparisonInspectionDone")
                }
            }
        }
    }

    private func heading(_ value: String) -> some View {
        Text(verbatim: value).font(.headline).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
    }
    private func literal(_ value: String) -> some View { completeText(ComponentComparisonText.literal(value)) }
    private func completeText(_ value: String) -> some View {
        Text(verbatim: value).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }
}
