import Foundation
import XCTest
import PlannerCore
import PlannerData
import PlannerTransfer
@testable import PlannerUI

@MainActor
final class ImportedBuildCostContextTests: XCTestCase {
    private func value(id: JSONValue? = .string("build.cost.context"), revision: JSONValue? = .number(7),
                       budget: JSONValue? = .string("100.00"), currency: JSONValue? = .string("USD")) -> JSONValue {
        var fields: [String: JSONValue] = [:]
        if let id { fields["id"] = id }
        if let revision { fields["revision"] = revision }
        var objectives: [String: JSONValue] = [:]
        if let budget { objectives["monthly_budget_amount"] = budget }
        if let currency { objectives["currency"] = currency }
        fields["objectives"] = .object(objectives)
        return .object(fields)
    }

    private func available(_ context: ImportedBuildCostContext,
                           file: StaticString = #filePath, line: UInt = #line) throws -> ImportedBuildCostContext.Selection {
        guard case .available(let selection) = context else {
            XCTFail("Expected a readable selected cost context", file: file, line: line)
            throw TransferError.malformed
        }
        return selection
    }

    private func snapshot(id: String = "build.cost.context", revision: Decimal = 7,
                          amount: String? = "100.00", currency: String = "USD") throws -> BuildSnapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "build", withExtension: "json"))
        let original = try BuildTransfer.snapshot(fromDraftJSON: Data(contentsOf: url))
        guard case .object(var fields) = original.value,
              case .object(var objectives)? = fields["objectives"] else { throw TransferError.malformed }
        fields["id"] = .string(id)
        fields["revision"] = .number(revision)
        objectives["currency"] = .string(currency)
        if let amount { objectives["monthly_budget_amount"] = .string(amount) }
        else { objectives.removeValue(forKey: "monthly_budget_amount") }
        fields["objectives"] = .object(objectives)
        return try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(fields)))
    }

    private func makeStore() throws -> (DraftStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (try DraftStore(url: folder.appendingPathComponent("cost-context.sqlite")), folder)
    }

    private func save(_ snapshot: BuildSnapshot, in store: DraftStore, title: String) async throws -> DraftRecord {
        let wrapper = try ImportedBuildRecord(snapshot: snapshot, markedSynthetic: true,
                                              sourceRevision: String(repeating: "e", count: 40))
        return try await store.save(id: UUID(), expectedRevision: nil, title: title,
                                    payload: JSONEncoder().encode(wrapper))
    }

    func testExactBudgetDigitsCurrencyAndSnapshotBytesArePreserved() throws {
        let amount = "123456789012345678901234567890.123456789012"
        for currency in ["USD", "EUR", "JPY"] {
            let selected = try snapshot(amount: amount, currency: currency)
            let originalBytes = try selected.encoded()
            let context = try available(ImportedBuildCostContext(snapshot: selected))
            XCTAssertEqual(context.buildID, selected.id)
            XCTAssertEqual(context.buildRevision, 7)
            XCTAssertEqual(context.monthlyBudget?.amount.rawValue, amount)
            XCTAssertEqual(context.monthlyBudget?.currency, currency)
            XCTAssertEqual(try selected.encoded(), originalBytes)
        }
    }

    func testAbsentBudgetIsDistinctFromAnExactZeroBudget() throws {
        let absent = try available(ImportedBuildCostContext(snapshotValue: value(budget: nil)))
        XCTAssertNil(absent.monthlyBudget)
        let zero = try available(ImportedBuildCostContext(snapshotValue: value(budget: .string("0.000000000000"))))
        XCTAssertEqual(zero.monthlyBudget?.amount.rawValue, "0.000000000000")
        XCTAssertEqual(zero.monthlyBudget?.currency, "USD")
    }

    func testMissingAndInvalidRevisionDoNotReceiveADefaultOrTruncatedIdentity() {
        let invalid: [JSONValue?] = [nil, .null, .bool(true), .string("7"), .number(0), .number(-1),
                                    .number(Decimal(15) / 10), .array([])]
        for revision in invalid {
            XCTAssertEqual(ImportedBuildCostContext(snapshotValue: value(revision: revision)), .unavailable(.revision))
        }
    }

    func testLargestRepresentableRevisionIsExactAndOverflowIsUnavailable() throws {
        let maximum = try available(ImportedBuildCostContext(snapshotValue: value(revision: .number(Decimal(Int.max)))))
        XCTAssertEqual(maximum.buildRevision, Int.max)
        let overflow = Decimal(Int.max) + 1
        XCTAssertEqual(ImportedBuildCostContext(snapshotValue: value(revision: .number(overflow))), .unavailable(.revision))
    }

    func testValidFrozenSnapshotWithWideRevisionRemainsReadableButHasNoCostContext() throws {
        let wide = try XCTUnwrap(Decimal(string: "1000000000000000000000000000000"))
        let selected = try snapshot(revision: wide)
        let originalBytes = try selected.encoded()
        XCTAssertEqual(ImportedBuildCostContext(snapshot: selected), .unavailable(.revision))
        XCTAssertEqual(try selected.encoded(), originalBytes)
    }

    func testIntegralDecimalRevisionAliasesKeepTheirMathematicalIdentity() throws {
        for spelling in ["7", "7.0", "7.000000", "7e0"] {
            let revision = try XCTUnwrap(Decimal(string: spelling))
            let context = try available(ImportedBuildCostContext(snapshotValue: value(revision: .number(revision))))
            XCTAssertEqual(context.buildRevision, 7)
        }
    }

    func testMalformedPresentBudgetIsUnavailableInsteadOfMissingOrZero() {
        let invalid: [JSONValue] = [.null, .number(100), .bool(false), .array([]), .object([:]),
            .string(""), .string("-1"), .string("01.00"), .string("1e2"), .string("NaN"),
            .string("1,000"), .string("1.1234567890123")]
        for budget in invalid {
            XCTAssertEqual(ImportedBuildCostContext(snapshotValue: value(budget: budget)), .unavailable(.budget))
        }
    }

    func testMissingOrInvalidCurrencyCannotBeInferredEvenWithoutABudget() {
        let invalid: [JSONValue?] = [nil, .null, .number(1), .string(""), .string("usd"),
                                    .string("US"), .string("USDX"), .string("€UR")]
        for currency in invalid {
            XCTAssertEqual(ImportedBuildCostContext(snapshotValue: value(currency: currency)), .unavailable(.budget))
            XCTAssertEqual(ImportedBuildCostContext(snapshotValue: value(budget: nil, currency: currency)), .unavailable(.budget))
        }
    }

    func testMissingObjectivesAndUnreadableIdentityHaveExplicitUnavailableContexts() {
        XCTAssertEqual(ImportedBuildCostContext(snapshotValue: .object(["id": .string("build.cost.context"),
            "revision": .number(7)])), .unavailable(.budget))
        let invalidIDs: [JSONValue?] = [nil, .null, .string(""), .number(1)]
        for id in invalidIDs {
            XCTAssertEqual(ImportedBuildCostContext(snapshotValue: value(id: id)), .unavailable(.identity))
        }
        XCTAssertEqual(ImportedBuildCostContext(snapshotValue: .array([])), .unavailable(.identity))
    }

    func testLocalLabelRevisionDoesNotReplacePinnedWireRevisionOrBudget() async throws {
        let (store, folder) = try makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let selected = try snapshot(revision: 7, amount: "123.4500", currency: "EUR")
        let originalBytes = try selected.encoded()
        let row = try await save(selected, in: store, title: "Original local label")
        let model = ImportedBuildLibraryModel(store: store)
        await model.open(row)
        let before = try available(ImportedBuildCostContext(snapshot: XCTUnwrap(model.snapshot)))
        XCTAssertEqual(before.buildRevision, 7)
        XCTAssertNotEqual(row.revision, before.buildRevision)

        await model.rename(row, to: "Renamed local label")

        let renamed = try XCTUnwrap(model.selected)
        XCTAssertEqual(renamed.revision, row.revision + 1)
        XCTAssertEqual(renamed.title, "Renamed local label")
        let reopened = try XCTUnwrap(model.snapshot)
        XCTAssertEqual(try available(ImportedBuildCostContext(snapshot: reopened)), before)
        XCTAssertEqual(try reopened.encoded(), originalBytes)
        XCTAssertTrue(model.markedSynthetic)
    }

    func testChangedSelectionUsesOnlyItsOwnWireIdentityBudgetAndCurrency() async throws {
        let (store, folder) = try makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try snapshot(id: "build.cost.context.first", revision: 3, amount: "90.000", currency: "USD")
        let second = try snapshot(id: "build.cost.context.second", revision: 9, amount: "120.50", currency: "EUR")
        let firstRow = try await save(first, in: store, title: "First local entry")
        let secondRow = try await save(second, in: store, title: "Second local entry")
        let model = ImportedBuildLibraryModel(store: store)
        await model.open(firstRow)
        let firstContext = try available(ImportedBuildCostContext(snapshot: XCTUnwrap(model.snapshot)))

        await model.open(secondRow)

        let secondContext = try available(ImportedBuildCostContext(snapshot: XCTUnwrap(model.snapshot)))
        XCTAssertEqual(secondContext.buildID, second.id)
        XCTAssertEqual(secondContext.buildRevision, 9)
        XCTAssertEqual(secondContext.monthlyBudget?.amount.rawValue, "120.50")
        XCTAssertEqual(secondContext.monthlyBudget?.currency, "EUR")
        XCTAssertNotEqual(secondContext, firstContext)
        await model.open(firstRow)
        XCTAssertEqual(try available(ImportedBuildCostContext(snapshot: XCTUnwrap(model.snapshot))), firstContext)
    }

    func testReimportAndDuplicateUseFreshForkIdentityAndKeepCostUnavailable() async throws {
        let (store, folder) = try makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = try snapshot(revision: 17, amount: "75.0000", currency: "EUR")
        guard case .object(var fields) = original.value,
              case .array(let selections)? = fields["selections"] else { throw TransferError.malformed }
        // Match the existing import fixture's public projection before testing
        // the production preview, confirmation, and duplicate paths.
        fields["selections"] = .array(selections.map { value in
            guard case .object(var selection) = value,
                  case .object(var settings)? = selection["settings"] else { return value }
            settings.removeValue(forKey: "index_name")
            selection["settings"] = .object(settings)
            return .object(selection)
        })
        let clean = try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(fields)))
        let data = try ImportedBuildPreparation.live.export(.init(snapshot: clean, publicAlias: "fixture.public",
            markedSynthetic: true, sourceRevision: String(repeating: "e", count: 40)))
        let model = ImportedBuildLibraryModel(store: store)
        var forkIDs: Set<String> = []
        for _ in 0..<2 {
            try await model.preparePreview(data)
            await model.confirmImport()
            let context = try available(ImportedBuildCostContext(snapshot: XCTUnwrap(model.snapshot)))
            XCTAssertNotEqual(context.buildID, original.id)
            XCTAssertTrue(forkIDs.insert(context.buildID).inserted)
            XCTAssertEqual(context.buildRevision, 1)
            XCTAssertEqual(context.monthlyBudget?.amount.rawValue, "75.0000")
            XCTAssertEqual(context.monthlyBudget?.currency, "EUR")
            XCTAssertTrue(model.markedSynthetic)
        }

        let secondFork = try XCTUnwrap(model.selected)
        await model.duplicate(secondFork)

        let duplicated = try available(ImportedBuildCostContext(snapshot: XCTUnwrap(model.snapshot)))
        XCTAssertNotEqual(duplicated.buildID, original.id)
        XCTAssertTrue(forkIDs.insert(duplicated.buildID).inserted)
        XCTAssertEqual(duplicated.buildRevision, 1)
        XCTAssertEqual(duplicated.monthlyBudget?.amount.rawValue, "75.0000")
        XCTAssertEqual(duplicated.monthlyBudget?.currency, "EUR")
        XCTAssertTrue(model.markedSynthetic)
        let display = CostCoveragePresentation(summary: nil, currentBuildID: duplicated.buildID,
            currentBuildRevision: duplicated.buildRevision, monthlyBudget: duplicated.monthlyBudget)
        XCTAssertEqual(display.state, .unavailable)
        XCTAssertNil(display.amount)
        XCTAssertNil(display.budgetAssessment)
        XCTAssertEqual(display.budgetHeading(hasBudget: true), "Budget status unknown")
    }
}
