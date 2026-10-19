import SwiftUI

enum DraftEditorField: Hashable { case title, notes, planning(PlanningInputField) }

/// Standard form controls retain raw input and state in the existing draft model.
struct PlanningInputsSection: View {
    @ObservedObject var model: DraftLibraryModel
    let draftID: UUID
    let sessionID: UUID
    let focus: FocusState<DraftEditorField?>.Binding
    @State private var choices: [PlanningCatalogChoice] = []
    @State private var loading = true
    @State private var failed = false
    @State private var loadID = UUID()

    var body: some View {
        Section("Workload and deployment") {
            Text("Demo catalog choices are fictional. Leave either choice unanswered if it does not describe your plan.")
            ForEach(PlanningCatalogKind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind.title).font(.headline)
                    if let reference = model.planningInputs.reference(for: kind) {
                        Text(CatalogDetailText.literal(reference.name).text)
                        Text("\(CatalogDetailText.literal(reference.itemID).text) · \(CatalogDetailText.literal(reference.itemVersion).text)").font(.caption)
                        if let choice = choices.first(where: { $0.reference == reference }) {
                            Text("Catalog declaration: \(choice.declaration)").font(.caption)
                        } else {
                            Text("This saved reference is not available in the current demo catalog. It has been preserved.")
                                .font(.caption)
                        }
                        Text("Compatibility has not been evaluated.").font(.caption)
                    } else {
                        Text("Unanswered. \(kind.title) filters cannot be applied.")
                    }
                    Menu("Choose \(kind.title.lowercased())") {
                        Button("Leave unanswered") {
                            model.setPlanningReference(nil, kind: kind, draftID: draftID, sessionID: sessionID)
                        }
                        ForEach(choices.filter { $0.reference.kind == kind }, id: \.reference.itemID) { choice in
                            Button("\(choice.reference.name) — \(choice.declaration)") {
                                model.setPlanningReference(choice.reference, kind: kind, draftID: draftID, sessionID: sessionID)
                            }
                        }
                    }
                    .accessibilityIdentifier("planningChoice-\(kind.rawValue)")
                }
                .accessibilityElement(children: .contain)
            }
            if loading { ProgressView("Loading demo choices…") }
            if failed {
                Text("Demo choices could not be loaded. Your saved input is preserved.")
                Button("Retry demo choices") { loadID = UUID() }
            }
        }
        .disabled(!model.canEdit)
        .task(id: loadID) {
            loading = true; failed = false
            do {
                let loaded = try await BundledCatalogPreviewSource().planningInputChoices()
                guard !Task.isCancelled else { return }
                choices = loaded; loading = false
            } catch {
                guard !Task.isCancelled else { return }
                loading = false; failed = true
            }
        }

        Section("Usage and constraints") {
            ForEach(PlanningInputField.allCases, id: \.self) { field in
                VStack(alignment: .leading, spacing: 8) {
                    Text(field.title).font(.headline)
                    TextField("Unanswered", text: Binding(
                        get: { model.planningInputs[field] },
                        set: { model.setPlanningInput(field, raw: $0, draftID: draftID, sessionID: sessionID) }
                    ))
                    .accessibilityLabel(field.title)
                    .accessibilityIdentifier("planningInput-\(field.rawValue)")
                    .focused(focus, equals: .planning(field))
                    Text(message(for: field)).font(.caption)
                        .accessibilityIdentifier("planningInputState-\(field.rawValue)")
                }
                .accessibilityElement(children: .contain)
            }
            Text("These inputs stay in this local draft. They do not create a validated build, a compatibility result, or a price estimate.")
        }
        .disabled(!model.canEdit)
    }

    private func message(for field: PlanningInputField) -> String {
        switch field.state(of: model.planningInputs[field]) {
        case .unanswered: field.unansweredMessage
        case .invalid(let message): "Invalid input. " + message
        case .supplied:
            field == .monthlyBudgetAmount && PlanningInputField.currency.state(of: model.planningInputs[.currency]) != .supplied
                ? "Amount entered. A valid currency code is still needed to interpret this budget."
                : "Input recorded. Compatibility, availability and prices remain unknown."
        }
    }
}
