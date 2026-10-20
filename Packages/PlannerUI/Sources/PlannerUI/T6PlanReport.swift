import Foundation
import PlannerTransfer
import SwiftUI
import UniformTypeIdentifiers

public enum T6PlanReportError: Error, Equatable, Sendable {
    case unavailable, mismatchedContent, unsafeValue, oversized, notImportable
}

/// A disclosure projection for a human reader. It is neither a frozen-v1
/// manifest nor a deployment command, and never replaces the private local pair.
public struct T6PlanReport: Equatable, Sendable {
    public static let maximumBytes = 512 * 1024
    public static let defaultFilename = "proposed-deployment-plan.txt"
    public static let omissions = [
        "Build and selection names, owner references, roles, settings, objectives, policy, links, notes and extensions.",
        "Approver identities and approval dates; all report, artifact and deployment reference identities and addresses.",
        "Manifest identity and request date; quality record identity, evaluator and dataset labels, measurements and private notes.",
        "Other tier selections. Their omission from this report does not establish that they are absent from the retained Build.",
    ]
    public let bytes: Data
    public var text: String { String(decoding: bytes, as: UTF8.self) }

    public init(content: T6ReviewContent) throws {
        guard content.manifestIssue == nil, content.localArtifacts != nil,
              let manifest = content.manifest else { throw T6PlanReportError.unavailable }
        guard content.guidance.build == content.build else { throw T6PlanReportError.mismatchedContent }
        _ = try ProposedDeploymentPlan(build: content.build, manifest: manifest)
        let build = content.build
        let declaration = manifest.value.t6Object!
        var output = Data()
        func line(_ value: String = "") throws {
            try Task.checkCancellation()
            let data = Data((value + "\n").utf8)
            guard data.count <= Self.maximumBytes - output.count else { throw T6PlanReportError.oversized }
            output.append(data)
        }
        func field(_ label: String, _ value: JSONValue) throws {
            try line("\(label): \(try Self.scalar(value))")
        }
        func selection(_ row: JSONValue) throws {
            let object = row.t6Object!
            for key in ["id", "kind", "catalog_item_id", "catalog_item_version"] {
                guard let value = object[key] else { throw T6PlanReportError.unsafeValue }
                try field("  \(key)", value)
            }
            guard let enabledValue = object["enabled"], case .bool(let enabled) = enabledValue else {
                throw T6PlanReportError.unsafeValue
            }
            try line("  enabled: \(enabled ? "true" : "false")")
        }

        try line("PROPOSED DEPLOYMENT PLAN")
        try line("Human-readable planning report. Not frozen-v1 JSON and not executable.")
        try line("Saving this report does not establish approval or deployment.")
        try line("The complete original Build and manifest remain separate private local declarations.")
        try line()
        try field("Build ID", .string(build.id))
        try field("Build revision", build.value.t6Object!["revision"]!)
        try field("Declared plan status", .string(manifest.status))
        try field("Declared rollout strategy", declaration["rollout_strategy"]!)
        try line()
        try line("EXACT DECLARED LOCKS")
        let locks = build.locks.t6Object!
        let knownLocks = ["catalog_snapshot_id", "ruleset_id", "ruleset_version",
                          "dependency_graph_id", "dependency_graph_revision", "pricebook_id"]
        let keys = Set(knownLocks).union(locks.keys).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        for key in keys {
            let label = "Lock \(try Self.quoted(key))"
            if let value = locks[key] { try field(label, value) }
            else { try line("\(label): not supplied") }
        }
        try line()
        try line("BOUND DEPLOYMENT TARGET")
        let selections = build.value.t6Object!["selections"]!.t6Array!
        let target = selections.first {
            $0.t6Object?["id"] == .string(manifest.deploymentTargetSelectionID)
        }!
        try selection(target)
        try line()
        try line("MONITORING SELECTIONS (original order; settings omitted)")
        let monitoring = selections.filter { $0.t6Object?["kind"] == .string("monitoring_stack") }
        if monitoring.isEmpty { try line("No monitoring selection was supplied.") }
        for (index, row) in monitoring.enumerated() {
            try line("Monitoring row \(index + 1)")
            try selection(row)
        }
        try line()
        try line("REPORTED APPROVAL DECLARATIONS (original order; unverified)")
        for (index, row) in manifest.approvals.enumerated() {
            let approval = row.t6Object!
            try line("Approval row \(index + 1)")
            try field("  scope", approval["scope"]!)
            try field("  decision", approval["decision"]!)
        }
        try line("Approver identities and dates are withheld. No approval authority is inferred.")
        try line()
        try line("SELECTED QUALITY RECORD (reported values only)")
        switch content.guidance.record {
        case .notSupplied:
            try line("Reported quality: not supplied; quality remains unknown.")
        case .supplied(let scenario):
            let run = scenario.run
            try field("Reported quality status", .string(run.status.rawValue))
            try field("Recorded sample size", .number(run.sampleSize))
            try line("Measurement rows: \(run.measurements.count)")
            try line("Reported passed flags: \(run.measurements.filter(\.passed).count)")
            try line("Reported false flags: \(run.measurements.filter { !$0.passed }.count)")
            try line("Artifact reference count: \(run.artifacts.count); identities and addresses withheld.")
        }
        try line("No thresholds are recomputed. This summary does not assert a binding to the manifest's reference IDs.")
        try line()
        try line("REFERENCE AND ROLLBACK PRESENCE")
        for key in ["compatibility_report_id", "quality_run_id", "cost_estimate_id", "resource_estimate_id"] {
            try line("\(key): \(declaration[key] == nil ? "not supplied" : "supplied; private identity withheld")")
        }
        try line("rollback_artifact_uri: \(declaration["rollback_artifact_uri"] == nil ? "not supplied" : "supplied; private address withheld")")
        try line("Use the retained declaration for rollback requirements and private references.")
        try line("An absent rollback reference does not establish a rollback procedure; a supplied reference is not verified.")
        try line()
        try line("DISCLOSURE OMISSIONS")
        for omission in Self.omissions { try line("- \(omission)") }
        self.bytes = output
    }

    /// Quoted values retain scalar spelling, including distinct UTF-8 Unicode
    /// spellings. Control/format scalars cannot create lines or hide headings.
    private static func quoted(_ value: String) throws -> String {
        guard value.range(of: "secret://", options: .caseInsensitive) == nil else {
            throw T6PlanReportError.unsafeValue
        }
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: result += "\\\""
            case 0x5c: result += "\\\\"
            case 0x08: result += "\\b"
            case 0x09: result += "\\t"
            case 0x0a: result += "\\n"
            case 0x0c: result += "\\f"
            case 0x0d: result += "\\r"
            default:
                switch scalar.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator:
                    for unit in String(scalar).utf16 {
                        let hex = String(unit, radix: 16)
                        result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                    }
                default: result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }

    private static func scalar(_ value: JSONValue) throws -> String {
        switch value {
        case .string(let string): return try quoted(string)
        case .number:
            let data = try JSONEncoder().encode(value)
            return "number \(try quoted(String(decoding: data, as: UTF8.self)))"
        default: throw T6PlanReportError.unsafeValue
        }
    }
}

struct T6PlanReportPreparation: Sendable {
    let prepare: @Sendable (T6ReviewContent) async throws -> T6PlanReport
    static let live = Self { content in
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let report = try T6PlanReport(content: content)
            try Task.checkCancellation()
            return report
        }
        return try await withTaskCancellationHandler(operation: {
            let result = await worker.result
            try Task.checkCancellation()
            return try result.get()
        }, onCancel: { worker.cancel() })
    }
}

/// Export-only in-memory document. SwiftUI owns the selected destination; this
/// type creates no temporary file and cannot import either private JSON artifact.
struct T6PlanReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [] }
    static var writableContentTypes: [UTType] { [.utf8PlainText] }
    let bytes: Data
    init(report: T6PlanReport) { bytes = report.bytes }
    init(configuration: ReadConfiguration) throws { throw T6PlanReportError.notImportable }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: bytes)
    }
}
