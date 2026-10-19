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
            Text(verbatim: "\(copy("Original recorded status:")) \(presentation.originalVerificationStatus.rawValue)")
            Text(verbatim: "\(copy("Component:")) \(presentation.identity.componentID)")
            Text(verbatim: "\(copy("Version:")) \(presentation.identity.componentVersion)")
            Text(verbatim: "\(copy("Retained snapshot:")) \(presentation.identity.catalogSnapshotID)")
            switch presentation.source {
            case .notInspected: Text(verbatim: copy("Source claim has not been inspected."))
            case .unavailable: Text(verbatim: copy("Source claim is unavailable."))
            case .inspected(let receipt):
                Text(verbatim: "\(copy("Inspected source:")) \(receipt.sourceReference)")
                Text(verbatim: "\(copy("Inspection receipt:")) \(receipt.inspectionReference)")
                Text(verbatim: "\(copy("Retrieval method:")) \(receipt.retrievalMethod)")
            }
            if let support = presentation.independentSupport {
                Text(verbatim: "\(copy("Independent support receipt:")) \(support.evidenceReference)")
                Text(verbatim: "\(copy("Receiving acceptance:")) \(support.acceptanceReference)")
            }
            switch presentation.freshness {
            case .versionPinned: Text(verbatim: copy("Facts remain pinned to this version."))
            case .currentState(let date):
                let dateDisplay = date.presentation(locale: locale)
                if let localized = dateDisplay.localizedDate {
                    Text(verbatim: "\(copy("Capture date (Gregorian):")) \(localized)")
                        .accessibilityIdentifier("claim-capture-date")
                }
                Text(verbatim: "\(copy("Current-state facts as of")) \(date.rawValue)")
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
