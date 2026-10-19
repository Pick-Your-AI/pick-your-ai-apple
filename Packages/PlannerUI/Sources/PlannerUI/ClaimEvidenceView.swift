import Foundation
import PlannerCore
import SwiftUI

/// Presents the existing, separately qualified claim-evidence projection.
/// Report outcomes never create or replace source inspection/support receipts.
public struct ClaimEvidenceView: View {
    @Environment(\.locale) private var locale
    private let presentation: EvidencePresentation

    public init(presentation: EvidencePresentation) { self.presentation = presentation }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "\(copy("Evidence quality:")) \(copy(grade))").font(.headline)
            field("Original recorded status:", value: presentation.originalVerificationStatus.rawValue)
            field("Component:", value: presentation.identity.componentID)
            field("Version:", value: presentation.identity.componentVersion)
            field("Retained snapshot:", value: presentation.identity.catalogSnapshotID)
            switch presentation.source {
            case .notInspected: Text(verbatim: copy("Source claim has not been inspected."))
            case .unavailable: Text(verbatim: copy("Source claim is unavailable."))
            case .inspected(let receipt):
                field("Inspected source:", value: receipt.sourceReference)
                field("Inspection receipt:", value: receipt.inspectionReference)
                field("Retrieval method:", value: receipt.retrievalMethod)
            }
            if let support = presentation.independentSupport {
                field("Independent support receipt:", value: support.evidenceReference)
                field("Receiving acceptance:", value: support.acceptanceReference)
            }
            switch presentation.freshness {
            case .versionPinned: Text(verbatim: copy("Facts remain pinned to this version."))
            case .currentState(let date):
                let dateDisplay = date.presentation(locale: locale)
                if let localized = dateDisplay.localizedDate {
                    field("Capture date (Gregorian):", value: localized)
                        .accessibilityIdentifier("claim-capture-date")
                }
                field("Current-state facts as of", value: date.rawValue)
            }
            switch presentation.reviewRequirement {
            case .none: EmptyView()
            case .newerVersionNotice: Text(verbatim: copy("A newer version is available. The retained selection has not changed."))
            case .reviewSelectedEvidence: Text(verbatim: copy("A newer snapshot is available. Review the evidence for this selection."))
            case .recheckRequired: Text(verbatim: copy("Selected evidence changed. A recheck is required."))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("claim-evidence")
    }

    // A value's punctuation must not take its visual direction from an RTL
    // label. FSI/PDI isolate this presentation run without forcing Latin
    // direction onto values whose own first strong character is Arabic.
    // Accessibility receives the same real label/value without layout controls;
    // neither the retained value nor its logical text acquires those controls.
    private func field(_ key: String, value: String) -> some View {
        let label = copy(key)
        return Text(verbatim: "\(label) \u{2068}\(value)\u{2069}")
            .accessibilityLabel(Text(verbatim: "\(label) \(value)"))
    }

    // Only closed explanatory copy enters the localization table. Selecting the
    // resource from this view's current locale also supports a locale change on
    // an existing card; no process-global language or cached copy is mutated.
    // Other languages use English. The original values never become keys,
    // format strings or Markdown, including values that resemble a copy key.
    private func copy(_ key: String) -> String {
        let requested = locale.language.languageCode?.identifier ?? "en"
        let language = requested == "de" || requested == "ar" ? requested : "en"
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "ClaimEvidence")
    }

    private var grade: String {
        switch presentation.displayGrade {
        case .independentlyVerified: "Independently verified"
        case .sourceChecked: "Source checked"
        case .userSupplied: "User supplied"
        case .estimated: "Estimated"
        case .unverified: "Unverified"
        case .unavailable: "Unavailable"
        }
    }
}
