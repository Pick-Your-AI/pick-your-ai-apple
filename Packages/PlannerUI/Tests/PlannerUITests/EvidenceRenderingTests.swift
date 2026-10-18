import Foundation
import PlannerCore
import SwiftUI
import XCTest
@testable import PlannerUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Read the actual native accessibility descendants of hosted SwiftUI views.
/// Expected text is never injected into a test accessibility label or fake tree.
@MainActor
final class EvidenceRenderingTests: XCTestCase {
    private struct VectorBundle: Decodable {
        let lock: [String: String]
        let schema: String
        let cases: [Vector]
    }
    private struct Vector: Decodable {
        let id: String
        let valid: Bool
        let payloadJSON: String
        let outcome: String?
        let severity: String?
        let visibleText: [String]
    }

    private func vectors() throws -> [Vector] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "evidence-vectors", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "evidence-vectors", withExtension: "json"))
        let bundle = try JSONDecoder().decode(VectorBundle.self, from: Data(contentsOf: url))
        XCTAssertEqual(bundle.lock["contract_version"], "1.0.0")
        XCTAssertEqual(bundle.schema, "evaluation-report.schema.json")
        XCTAssertEqual(bundle.cases.count, 37)
        XCTAssertEqual(Set(bundle.cases.map(\.id)).count, bundle.cases.count)
        return bundle.cases
    }

    func testSharedEvidenceVectorsRenderReportedOutcomesSeverityAndEveryPresenceState() async throws {
        let accepted = try vectors().filter(\.valid)
        XCTAssertEqual(accepted.count, 28)
        for vector in accepted {
            let report = try EvaluationReport.decode(Data(vector.payloadJSON.utf8))
            guard let finding = report.findings.first else {
                XCTAssertEqual(vector.id, "evidence/no-findings")
                try await assertRendered(EvaluationReportView(report: report), contains: vector.visibleText, context: vector.id)
                continue
            }
            let expected = vector.visibleText + ["Reported rule outcome: \(try XCTUnwrap(vector.outcome))",
                                                "Severity: \(try XCTUnwrap(vector.severity))"]
            let text = try await assertRendered(EvaluationFindingView(finding: finding), contains: expected, context: vector.id)
            for other in ["pass", "fail", "unknown", "skipped"] where other != vector.outcome {
                XCTAssertFalse(text.contains("Reported rule outcome: \(other)"), vector.id)
            }
            for other in ["error", "warning", "info"] where other != vector.severity {
                XCTAssertFalse(text.contains("Severity: \(other)"), vector.id)
            }
        }
    }

    func testReportedPassAndReadyRemainSeparateFromMissingEvidenceOnCompactAndWideViews() async throws {
        let vector = try XCTUnwrap(try vectors().first { $0.id == "evidence/reported-pass-without-support" })
        let report = try EvaluationReport.decode(Data(vector.payloadJSON.utf8))
        let expected = vector.visibleText + ["Reported compatibility: valid", "Reported readiness: ready",
            "Missing or unknown observations do not establish compatibility.",
            "Build: \(report.buildID), revision \(report.buildRevision)",
            "Catalog snapshot: \(report.catalogSnapshotID)"]
        let widths: [CGFloat] = [375, 820]
        for width in widths {
            try await assertRendered(EvaluationReportView(report: report).environment(\.dynamicTypeSize, .accessibility3),
                                     contains: expected, context: "reported pass at \(width)", width: width)
        }
    }

    func testClaimGradesRequireTheirExistingInspectionAndIndependentSupportInputs() async throws {
        let identity = try RetainedEvidenceIdentity(componentID: "synthetic.component", componentVersion: "1.0.0", catalogSnapshotID: "snapshot.retained")
        let inspection = try SourceInspectionReceipt(sourceReference: "synthetic:claim", inspectionReference: "synthetic:read", retrievalMethod: "synthetic fixture")
        let support = try AcceptedIndependentSupport(evidenceReference: "synthetic:independent", acceptanceReference: "synthetic:acceptance")
        let examples: [(OriginalVerificationStatus, ClaimSourceAvailability, AcceptedIndependentSupport?, String)] = [
            (.verified, .notInspected, nil, "Unverified"),
            (.verified, .notInspected, support, "Unverified"),
            (.verified, .inspected(inspection), nil, "Source checked"),
            (.unverified, .inspected(inspection), support, "Independently verified"),
            (.userSupplied, .notInspected, nil, "User supplied"),
            (.estimated, .notInspected, nil, "Estimated"),
            (.verified, .unavailable, support, "Unavailable"),
        ]
        for (status, source, independent, grade) in examples {
            let presentation = EvidencePresentation(identity: identity, originalVerificationStatus: status, source: source,
                                                    independentSupport: independent, freshness: .versionPinned)
            let text = try await assertRendered(ClaimEvidenceView(presentation: presentation), contains: [
                "Evidence quality: \(grade)", "Original recorded status: \(status.rawValue)",
                "Component: synthetic.component", "Version: 1.0.0", "Retained snapshot: snapshot.retained",
                "Facts remain pinned to this version."], context: grade)
            if grade != "Independently verified" {
                XCTAssertFalse(text.contains("Evidence quality: Independently verified"), grade)
            }
            if source == .notInspected { XCTAssertTrue(text.contains("Source claim has not been inspected."), grade) }
            if source == .unavailable { XCTAssertTrue(text.contains("Source claim is unavailable."), grade) }
        }
    }

    func testCorrectionAndFreshnessNoticesPreserveRetainedIdentityAndRequireARecheck() async throws {
        let identity = try RetainedEvidenceIdentity(componentID: "synthetic.component", componentVersion: "1.0.0", catalogSnapshotID: "snapshot.retained")
        let inspection = try SourceInspectionReceipt(sourceReference: "synthetic:claim", inspectionReference: "synthetic:read", retrievalMethod: "synthetic fixture")
        let support = try AcceptedIndependentSupport(evidenceReference: "synthetic:independent", acceptanceReference: "synthetic:acceptance")
        let base = EvidencePresentation(identity: identity, originalVerificationStatus: .verified, source: .inspected(inspection),
                                        independentSupport: support, freshness: .currentState(captureDate: try EvidenceCaptureDate("2024-01-02")))
        let common = ["Version: 1.0.0", "Retained snapshot: snapshot.retained", "Current-state facts as of 2024-01-02"]
        try await assertRendered(ClaimEvidenceView(presentation: base.receiving(.newerReleaseAvailable)), contains: common + [
            "A newer version is available. The retained selection has not changed."], context: "newer release")
        try await assertRendered(ClaimEvidenceView(presentation: base.receiving(.newerSnapshotAvailable)), contains: common + [
            "A newer snapshot is available. Review the evidence for this selection."], context: "newer snapshot")
        let corrected = base.receiving(.correction(identity)).receiving(.newerReleaseAvailable)
        let text = try await assertRendered(ClaimEvidenceView(presentation: corrected), contains: common + [
            "Evidence quality: Unverified", "Original recorded status: verified", "Selected evidence changed. A recheck is required."], context: "correction")
        XCTAssertFalse(text.contains("Evidence quality: Independently verified"))
    }

    @discardableResult
    private func assertRendered<V: View>(_ view: V, contains expected: [String], context: String,
                                         width: CGFloat = 375, file: StaticString = #filePath, line: UInt = #line) async throws -> String {
        let content = view.frame(maxWidth: .infinity, alignment: .leading).padding()
        #if canImport(AppKit)
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 4096),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil); window.close() }
        let root: NSObject = hosting
        #elseif canImport(UIKit)
        let hosting = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 4096))
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        let root: NSObject = hosting.view
        #endif
        var text = ""
        for _ in 0..<30 {
            #if canImport(AppKit)
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            #elseif canImport(UIKit)
            hosting.view.layoutIfNeeded()
            #endif
            text = try nativeText(root).joined(separator: "\n")
            if !text.isEmpty && expected.allSatisfy({ text.contains($0) }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(text.isEmpty, "No actual native accessibility text was rendered: \(context)", file: file, line: line)
        for value in expected {
            XCTAssertTrue(text.contains(value), "\(context): missing \(value); actual native text: \(text)", file: file, line: line)
        }
        return text
    }

    private func nativeText(_ root: NSObject) throws -> [String] {
        var pending: [NSObject] = [root]
        var visited = Set<ObjectIdentifier>()
        var text: [String] = []
        while let object = pending.popLast() {
            guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
            guard visited.count <= 10_000 else { throw RenderingError.unboundedAccessibilityTree }
            #if canImport(AppKit)
            if let accessible = object as? any NSAccessibilityProtocol {
                for value in [accessible.accessibilityLabel(), accessible.accessibilityTitle(), accessible.accessibilityValue() as? String].compactMap({ $0 }) {
                    text.append(value)
                }
                pending += (accessible.accessibilityChildren() ?? []).compactMap { $0 as? NSObject }
            }
            if let view = object as? NSView { pending += view.subviews }
            #elseif canImport(UIKit)
            if let label = object.accessibilityLabel { text.append(label) }
            if let value = object.accessibilityValue { text.append(value) }
            pending += (object.accessibilityElements ?? []).compactMap { $0 as? NSObject }
            let count = object.accessibilityElementCount()
            if count != NSNotFound {
                guard (0...10_000).contains(count) else { throw RenderingError.unboundedAccessibilityTree }
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject { pending.append(child) }
                }
            }
            if let view = object as? UIView { pending += view.subviews }
            #endif
        }
        return text
    }

    private enum RenderingError: Error { case unboundedAccessibilityTree }
}
