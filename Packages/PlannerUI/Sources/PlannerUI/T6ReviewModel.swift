import Foundation
import PlannerCore
import PlannerTransfer
import SwiftUI

/// An opaque, single-use request created when the picker is presented. A saved
/// request cannot be reconstructed from a later snapshot or reused after review.
public struct T6FileSelection: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case quality, manifest }
    public let id: UUID
    fileprivate let build: BuildSnapshot
    fileprivate let kind: Kind
    fileprivate init(id: UUID, build: BuildSnapshot, kind: Kind) {
        self.id = id; self.build = build; self.kind = kind
    }
}

/// One exact disclosure preview. Only this model can create its admission token;
/// the retained private inputs are never the document supplied to Files.
public struct T6PlanExportRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let report: T6PlanReport
    fileprivate let build: BuildSnapshot
    fileprivate let content: T6ReviewContent
    fileprivate let reviewGeneration: UUID
    fileprivate init(id: UUID, report: T6PlanReport, build: BuildSnapshot,
                     content: T6ReviewContent, reviewGeneration: UUID) {
        self.id = id; self.report = report; self.build = build
        self.content = content; self.reviewGeneration = reviewGeneration
    }
}

/// Deliver only the actual terminal result of this request's system Files UI.
public enum T6PlanExportOutcome: Sendable { case saved, failed, cancelled }

/// View state for an explicitly selected retained snapshot. The receiver calls
/// select for snapshot changes, clear for record closure/deletion, and cancel
/// when the actual T6 navigation route is withdrawn, even with a Files dialog.
@MainActor
public final class T6ReviewModel: ObservableObject {
    @Published public private(set) var build: BuildSnapshot?
    @Published public private(set) var content: T6ReviewContent?
    @Published public private(set) var compatibility: EvaluationReport?
    @Published public private(set) var busy = false
    @Published public private(set) var notice: String?
    @Published public private(set) var planExport: T6PlanExportRequest?
    @Published public private(set) var exportPreparing = false
    private let preparation: T6ArtifactPreparation
    private let reportPreparation: T6PlanReportPreparation
    private var exportGeneration = UUID()
    private var exportTask: Task<Void, Never>?
    private var activeExport: T6PlanExportRequest?
    private var generation = UUID()
    private var active: Task<T6ReviewContent, Error>?
    private var inputs = T6ArtifactInputs()
    private var fileSelection: T6FileSelection?

    public convenience init(build: BuildSnapshot? = nil) {
        self.init(build: build, preparation: .live)
    }
    init(build: BuildSnapshot?, preparation: T6ArtifactPreparation,
         reportPreparation: T6PlanReportPreparation = .live) {
        self.build = build; self.preparation = preparation; self.reportPreparation = reportPreparation
    }

    /// Full snapshot equality includes exact declared locks, settings and private
    /// fields. An equal ID/revision alone cannot retain a previous result.
    public func select(_ build: BuildSnapshot?) {
        guard self.build != build else { return }
        invalidate()
        self.build = build; inputs = T6ArtifactInputs(); compatibility = nil; notice = nil
    }

    public func clear() {
        invalidate(); build = nil; inputs = T6ArtifactInputs(); compatibility = nil; notice = nil
    }

    /// The receiver must call this when the actual T6 route is withdrawn, even
    /// while its Files dialog is pending. Visibility alone is not that signal.
    public func cancel() {
        invalidate()
        notice = "Review cancelled. Retry to inspect the selected records."
    }

    /// Returns true when ordinary disappearance cancelled this review. An owned
    /// Files request remains live until its terminal callback or an explicit
    /// route/selection cancellation, including the binding-to-callback interval.
    @discardableResult
    func handleDisappearance() -> Bool {
        guard fileSelection == nil, activeExport == nil else { return false }
        cancel()
        return true
    }

    /// Consume only an already-current result from the existing analysis owner.
    /// This additional display check is not a new report-governance authority.
    @discardableResult
    public func receiveCompatibility(_ state: AnalysisState<EvaluationReport>, for capturedBuild: BuildSnapshot) -> Bool {
        guard let build, build == capturedBuild else { return false }
        compatibility = nil
        guard case .current(let request, let report) = state,
              request.identity == report.analysisIdentity,
              build.id.utf8.elementsEqual(report.buildID.utf8),
              build.value.t6Object?["revision"] == .number(Decimal(report.buildRevision)),
              let locks = build.locks.t6Object,
              locks["catalog_snapshot_id"] == .string(report.catalogSnapshotID),
              locks["ruleset_id"] == .string(report.rulesetID),
              locks["ruleset_version"] == .string(report.rulesetVersion),
              locks["dependency_graph_id"] == .string(report.dependencyGraphID),
              locks["dependency_graph_revision"] == .number(Decimal(report.dependencyGraphRevision)) else { return false }
        compatibility = report
        return true
    }

    public func review(qualityJSON: Data? = nil, manifestJSON: Data? = nil) async {
        await review(T6ArtifactInputs(quality: qualityJSON.map(T6ArtifactSource.bytes),
                                      manifest: manifestJSON.map(T6ArtifactSource.bytes)))
    }
    /// Starting another picker also retires any pending review and old picker.
    public func beginFileSelection(_ kind: T6FileSelection.Kind) -> T6FileSelection? {
        guard let selected = build else { return nil }
        invalidate(); notice = nil
        let request = T6FileSelection(id: generation, build: selected, kind: kind)
        fileSelection = request
        return request
    }

    public func importFile(_ url: URL, for request: T6FileSelection) async {
        let selectedInputs: T6ArtifactInputs
        switch request.kind {
        case .quality: selectedInputs = T6ArtifactInputs(quality: .file(url), manifest: inputs.manifest)
        case .manifest: selectedInputs = T6ArtifactInputs(quality: inputs.quality, manifest: .file(url))
        }
        // Admission is repeated inside review before its first state change.
        // An actor suspension before entry cannot revive a cancelled request.
        await review(selectedInputs, accepting: request)
    }
    public func removeQuality() async {
        await review(T6ArtifactInputs(manifest: inputs.manifest))
    }
    public func removeManifest() async {
        await review(T6ArtifactInputs(quality: inputs.quality))
    }
    public func retry() async { await review(inputs) }

    public func fileSelectionFailed(for request: T6FileSelection) {
        guard consume(request) else { return }
        notice = "The file selection did not complete. Existing records were not changed."
    }

    public func fileSelectionCancelled(for request: T6FileSelection) {
        guard consume(request) else { return }
        cancel()
    }

    /// Capture the exact visible content synchronously, before scheduling work.
    /// The returned task is useful to an owning lifecycle/test; callers may ignore it.
    @discardableResult
    public func preparePlanExport() -> Task<Void, Never>? {
        invalidatePlanExport()
        guard let selected = build, let captured = content, captured.build == selected, !busy else {
            notice = "Review a proposed local plan before preparing its disclosure report."
            return nil
        }
        let token = exportGeneration
        let reviewToken = generation
        let preparation = reportPreparation
        exportPreparing = true; notice = nil
        let task = Task {
            defer {
                if exportGeneration == token { exportPreparing = false; exportTask = nil }
            }
            do {
                let report = try await preparation.prepare(captured)
                try Task.checkCancellation()
                guard exportGeneration == token, generation == reviewToken,
                      build == selected, content == captured else { return }
                planExport = T6PlanExportRequest(id: token, report: report, build: selected,
                                                content: captured, reviewGeneration: reviewToken)
            } catch is CancellationError {
                guard exportGeneration == token else { return }
                notice = "Report preparation was cancelled. The retained declarations were not changed."
            } catch {
                guard exportGeneration == token, generation == reviewToken,
                      build == selected, content == captured, !Task.isCancelled else { return }
                notice = "The proposed-plan report could not be prepared safely. Check the declaration and selected identifiers, then retry."
            }
        }
        exportTask = task
        return task
    }

    /// Save is admitted only for the exact preview whose omissions were reviewed.
    @discardableResult
    public func beginPlanExport(_ request: T6PlanExportRequest, disclosureReviewed: Bool) -> Bool {
        guard disclosureReviewed, currentPlanExport(request), activeExport == nil else { return false }
        activeExport = request
        return true
    }

    public func finishPlanExport(_ outcome: T6PlanExportOutcome, for request: T6PlanExportRequest) {
        guard activeExport == request, currentPlanExport(request) else { return }
        invalidatePlanExport()
        switch outcome {
        case .saved:
            notice = "Files reported that the proposed-plan report was saved. No approval or deployment was performed."
        case .failed:
            notice = "Files did not confirm a saved report. The retained declarations were not changed; prepare a fresh preview to retry."
        case .cancelled:
            notice = "Plan report export was cancelled. No save was confirmed; the retained declarations were not changed."
        }
    }

    public func cancelPlanExportPreparation() {
        guard exportPreparing else { return }
        invalidatePlanExport()
        notice = "Report preparation was cancelled. The retained declarations were not changed."
    }

    public func dismissPlanExport(_ request: T6PlanExportRequest) {
        guard currentPlanExport(request) else { return }
        invalidatePlanExport()
        notice = "The disclosure preview was closed. No save was confirmed."
    }

    private func currentPlanExport(_ request: T6PlanExportRequest) -> Bool {
        planExport == request && exportGeneration == request.id &&
        generation == request.reviewGeneration && build == request.build && content == request.content
    }

    private func invalidatePlanExport() {
        exportGeneration = UUID(); exportTask?.cancel(); exportTask = nil
        exportPreparing = false; activeExport = nil; planExport = nil
    }

    private func consume(_ request: T6FileSelection) -> Bool {
        guard fileSelection == request, generation == request.id, build == request.build else { return false }
        fileSelection = nil
        return true
    }

    private func invalidate() {
        invalidatePlanExport()
        generation = UUID(); fileSelection = nil; active?.cancel(); active = nil
        busy = false; content = nil
    }

    private func review(_ inputs: T6ArtifactInputs, accepting request: T6FileSelection? = nil) async {
        if let request, !consume(request) { return }
        invalidate()
        guard let selected = build else {
            notice = "Select a retained Build before reviewing T6."; return
        }
        self.inputs = inputs; notice = nil; busy = true
        let token = generation
        let preparation = preparation
        let worker = Task { try await preparation.prepare(selected, inputs) }
        active = worker
        defer { if generation == token { busy = false; active = nil } }
        do {
            let result = try await withTaskCancellationHandler(operation: {
                let result = await worker.result
                try Task.checkCancellation()
                return try result.get()
            }, onCancel: { worker.cancel() })
            guard generation == token, build == selected else { return }
            guard result.build == selected else { throw TransferError.malformed }
            content = result
        } catch is CancellationError {
            guard generation == token else { return }
            notice = "Review cancelled. Retry to inspect the selected records."
        } catch {
            guard generation == token, build == selected, !Task.isCancelled else { return }
            notice = "The records could not be reviewed for this exact Build. Check their format, size, revision and evaluation selection, then retry."
        }
    }
}
