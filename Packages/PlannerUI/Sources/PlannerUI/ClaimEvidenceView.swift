import PlannerCore
import SwiftUI

/// Presents the existing, separately qualified claim-evidence projection.
/// Report outcomes never create or replace source inspection/support receipts.
public struct ClaimEvidenceView: View {
    private let presentation: EvidencePresentation

    public init(presentation: EvidencePresentation) { self.presentation = presentation }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Evidence quality: \(grade)").font(.headline)
            Text(verbatim: "Original recorded status: \(presentation.originalVerificationStatus.rawValue)")
            Text(verbatim: "Component: \(presentation.identity.componentID)")
            Text(verbatim: "Version: \(presentation.identity.componentVersion)")
            Text(verbatim: "Retained snapshot: \(presentation.identity.catalogSnapshotID)")
            switch presentation.source {
            case .notInspected: Text("Source claim has not been inspected.")
            case .unavailable: Text("Source claim is unavailable.")
            case .inspected(let receipt):
                Text(verbatim: "Inspected source: \(receipt.sourceReference)")
                Text(verbatim: "Inspection receipt: \(receipt.inspectionReference)")
                Text(verbatim: "Retrieval method: \(receipt.retrievalMethod)")
            }
            if let support = presentation.independentSupport {
                Text(verbatim: "Independent support receipt: \(support.evidenceReference)")
                Text(verbatim: "Receiving acceptance: \(support.acceptanceReference)")
            }
            switch presentation.freshness {
            case .versionPinned: Text("Facts remain pinned to this version.")
            case .currentState(let date): Text(verbatim: "Current-state facts as of \(date.rawValue)")
            }
            switch presentation.reviewRequirement {
            case .none: EmptyView()
            case .newerVersionNotice: Text("A newer version is available. The retained selection has not changed.")
            case .reviewSelectedEvidence: Text("A newer snapshot is available. Review the evidence for this selection.")
            case .recheckRequired: Text("Selected evidence changed. A recheck is required.")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("claim-evidence")
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
