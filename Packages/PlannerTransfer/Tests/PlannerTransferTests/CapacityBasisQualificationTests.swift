import Foundation
import XCTest
@testable import PlannerTransfer

final class CapacityBasisQualificationTests: XCTestCase {
    private func context() throws -> CapacityTestContext {
        let draft = try CapacityTestDraft()
        try draft.serving()
        return try draft.freeze()
    }

    private func basis(_ context: CapacityTestContext, bytes: Data? = nil,
                       inputs: [CapacityInput]? = nil, operation: String? = nil,
                       catalog: String? = "catalog") throws -> CapacityBasis {
        try CapacityBasis(originalBuildBytes: bytes ?? context.basis.originalBuildBytes,
            operation: operation ?? context.basis.operation, normalizationPolicy: "normalization",
            sourcePolicy: "source-policy", inputs: inputs ?? context.inputs, catalogInputName: catalog)
    }

    func testSyntheticFixtureRoundTripPreservesExactDecimalBooleanAndNullKinds() throws {
        let original = Data(#"{"array":[true,false,1,0,0.4,0.85,1.23456789012345,null,"1"],"text":"cafe\u0301"}"#.utf8)
        var before = try JSONParser(original)
        let expected = try before.parse()
        let encoded = try CapacityFixtureJSON.encode(CapacityFixtureJSON.decode(original))
        var after = try JSONParser(encoded)
        XCTAssertEqual(try after.parse(), expected)
        let object = try XCTUnwrap(CapacityFixtureJSON.decode(encoded) as? [String: Any])
        let array = try XCTUnwrap(object["array"] as? [Any])
        XCTAssertTrue(type(of: array[0]) == Bool.self)
        XCTAssertTrue(type(of: array[2]) == Decimal.self)
        XCTAssertTrue(array[7] is NSNull)
        let lossyValues: [Any] = [Double(0.4), Float(0.4), NSNumber(value: 1)]
        for lossy in lossyValues {
            XCTAssertThrowsError(try CapacityFixtureJSON.encode(["value": lossy])) {
                XCTAssertTrue($0 is CapacityFixtureJSON.Failure)
            }
        }
    }

    func testSyntheticModelFixturePreservesDecimalAdmissionAndStrictDriftRejection() throws {
        let draft = try CapacityTestDraft()
        try draft.serving()
        let exactBytes = try CapacityFixtureJSON.encode(draft.build)
        let admitted = try BuildTransfer.snapshot(fromDraftJSON: exactBytes)
        let selected = try XCTUnwrap(admitted.value.object?["selections"]?.array)
        let model = try XCTUnwrap(selected.first { $0.object?["kind"] == .string("model") })
        XCTAssertEqual(model.object?["settings"]?.object?["temperature"], .number(Decimal(string: "0.4")!))
        let context = try draft.freeze()
        XCTAssertEqual(context.basis.originalBuildBytes, exactBytes)

        // This diagnostic records the old writer on the actual platform. It is not
        // an expectation that every Foundation implementation emits the same spelling.
        let legacyObject = try JSONSerialization.jsonObject(with: exactBytes)
        let legacyBytes = try JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys])
        do {
            _ = try BuildTransfer.snapshot(fromDraftJSON: legacyBytes)
            print("SYNTHETIC capacity legacy fixture admission: accepted")
        } catch let error as TransferError {
            print("SYNTHETIC capacity legacy fixture admission: \(error)")
        }

        let text = try XCTUnwrap(String(data: exactBytes, encoding: .utf8))
        let malformed = text.replacingOccurrences(of: #""temperature":0.4"#,
                                                  with: #""temperature":0.40000000000000002"#)
        XCTAssertNotEqual(malformed, text)
        let bytes = Data(malformed.utf8)
        XCTAssertThrowsError(try BuildTransfer.snapshot(fromDraftJSON: bytes)) {
            XCTAssertEqual($0 as? TransferError, .unsupportedNumber)
        }
        XCTAssertThrowsError(try basis(context, bytes: bytes)) {
            XCTAssertEqual($0 as? CapacityError, .invalidFrozenBuild)
        }
        XCTAssertEqual(try draft.freeze().basis.sha256, context.basis.sha256)
    }

    func testWholeOriginalBytesInvalidateEvidenceEvenWhenBuildIDAndRevisionMatch() throws {
        let original = try context()
        let answer = try original.answer("/deployment/sel_model/operator", .runtimeOperator)
        let domain = try CapacityDomain.component("sel_model")
        try original.qualify(answer, .runtimeOperator, domain)
        let qualified = try original.qualifications()
        XCTAssertNotNil(try qualified.use(basis: original.basis, answer: answer, fact: .runtimeOperator, domain: domain))
        var changed = original.basis.originalBuildBytes
        changed.append(10)
        let next = try basis(original, bytes: changed)
        XCTAssertEqual(next.buildID, original.basis.buildID)
        XCTAssertEqual(next.buildRevision, original.basis.buildRevision)
        XCTAssertNotEqual(next.sha256, original.basis.sha256)
        XCTAssertNil(try qualified.use(basis: next, answer: answer, fact: .runtimeOperator, domain: domain))
        XCTAssertNotNil(try qualified.use(basis: original.basis, answer: answer, fact: .runtimeOperator, domain: domain))
    }

    func testEveryNamedInputAndSelectedOperationParticipatesInTheOriginalBasis() throws {
        let original = try context()
        for index in original.inputs.indices {
            var inputs = original.inputs
            let old = inputs[index]
            var bytes = old.originalBytes; bytes.append(32)
            inputs[index] = try CapacityInput(name: old.name, kind: old.kind, originalBytes: bytes)
            let changed = try basis(original, inputs: inputs)
            XCTAssertNotEqual(changed.sha256, original.basis.sha256, old.name)
            XCTAssertEqual(changed.buildID, original.basis.buildID)
        }
        XCTAssertNotEqual(try basis(original, operation: "training").sha256, original.basis.sha256)
        XCTAssertNotEqual(try basis(original, catalog: nil).sha256, original.basis.sha256)
    }

    func testInputOrderDoesNotAlterIdentityButExactUTF8NamesStayDistinct() throws {
        let original = try context()
        XCTAssertEqual(try basis(original, inputs: Array(original.inputs.reversed())).sha256, original.basis.sha256)
        let first = try CapacityInput(name: "caf\u{00e9}", kind: .hardware, originalBytes: Data("first".utf8))
        let second = try CapacityInput(name: "cafe\u{0301}", kind: .hardware, originalBytes: Data("second".utf8))
        let exact = try basis(original, inputs: original.inputs + [first, second])
        XCTAssertEqual(exact.input(named: "caf\u{00e9}")?.originalBytes, Data("first".utf8))
        XCTAssertEqual(exact.input(named: "cafe\u{0301}")?.originalBytes, Data("second".utf8))
        XCTAssertEqual(exact.inputNames.filter { Data($0.utf8) == Data("caf\u{00e9}".utf8)
            || Data($0.utf8) == Data("cafe\u{0301}".utf8) }.count, 2)
        XCTAssertThrowsError(try basis(original, inputs: original.inputs + [first, first])) {
            XCTAssertEqual($0 as? CapacityError, .duplicateIdentity)
        }
    }

    func testDeclaredInputHashesAreCheckedEvenForAnUnusedOriginal() throws {
        let original = try context()
        XCTAssertThrowsError(try CapacityInput(name: "unused", kind: .hardware,
            originalBytes: Data("actual".utf8), declaredSHA256: String(repeating: "0", count: 64))) {
                XCTAssertEqual($0 as? CapacityError, .declaredBytesMismatch)
        }
        var bytes = Data("explicit retained original".utf8)
        let input = try CapacityInput(name: "unused", kind: .hardware, originalBytes: bytes)
        bytes.removeAll()
        let extended = try basis(original, inputs: original.inputs + [input])
        XCTAssertEqual(extended.input(named: "unused")?.originalBytes, Data("explicit retained original".utf8))
        XCTAssertNotEqual(extended.sha256, original.basis.sha256)
    }

    func testMalformedFrozenBuildAndUnusedCatalogItemRejectBeforeQualification() throws {
        let original = try context()
        var build = try XCTUnwrap(JSONSerialization.jsonObject(with: original.basis.originalBuildBytes) as? [String: Any])
        build["unsupported"] = true
        XCTAssertThrowsError(try basis(original, bytes: JSONSerialization.data(withJSONObject: build))) {
            XCTAssertEqual($0 as? CapacityError, .invalidFrozenBuild)
        }
        let draft = try CapacityTestDraft(); try draft.serving()
        var items = try XCTUnwrap(draft.catalog["items"] as? [[String: Any]])
        let index = try XCTUnwrap(items.firstIndex { ($0["kind"] as? String) == "monitoring_stack" })
        items[index]["tier"] = "T9"; draft.catalog["items"] = items
        XCTAssertThrowsError(try draft.freeze()) { XCTAssertEqual($0 as? CapacityError, .invalidFrozenCatalog) }
    }

    func testMissingCatalogScopeNeverFallsBackToAnItemWithTheSameID() throws {
        let draft = try CapacityTestDraft(); try draft.serving()
        draft.catalog["id"] = "cat.snapshot.different"
        let different = try draft.freeze()
        XCTAssertFalse(different.basis.catalogMatchesBuild)
        XCTAssertNil(different.basis.catalogItem(forSelectionID: "sel_model"))
        let absent = try basis(different, catalog: nil)
        XCTAssertFalse(absent.catalogMatchesBuild)
        XCTAssertNil(absent.catalogItem(forSelectionID: "sel_model"))
    }

    func testDuplicateCatalogPairsAndDanglingBuildLinksReject() throws {
        let duplicate = try CapacityTestDraft(); try duplicate.serving()
        var items = try XCTUnwrap(duplicate.catalog["items"] as? [[String: Any]])
        items.append(try XCTUnwrap(items.first)); duplicate.catalog["items"] = items
        XCTAssertThrowsError(try duplicate.freeze())
        let dangling = try CapacityTestDraft(); try dangling.serving()
        var links = try XCTUnwrap(dangling.build["links"] as? [[String: Any]])
        links[0]["to_selection_id"] = "missing_selection"; dangling.build["links"] = links
        XCTAssertThrowsError(try dangling.freeze()) { XCTAssertEqual($0 as? CapacityError, .danglingReference) }
    }

    func testQualificationRequiresTheExactAnswerFactDomainAndActualEvidenceInput() throws {
        let original = try context()
        let answer = try original.answer("/deployment/sel_model/operator", .runtimeOperator)
        let domain = try CapacityDomain.component("sel_model")
        try original.qualify(answer, .runtimeOperator, domain)
        let values = try original.qualifications()
        XCTAssertNotNil(try values.use(basis: original.basis, answer: answer, fact: .runtimeOperator, domain: domain))
        XCTAssertNil(try values.use(basis: original.basis, answer: answer, fact: .capacityMode, domain: domain))
        XCTAssertNil(try values.use(basis: original.basis, answer: answer, fact: .runtimeOperator,
                                   domain: .component("other_component")))
        let key = try answer.qualificationKey(fact: .runtimeOperator, domain: domain)
        XCTAssertThrowsError(try CapacityQualification(key: key, eligibility: .qualified, evidenceInputName: "hardware",
            evidenceSHA256: XCTUnwrap(original.basis.input(named: "hardware")).sha256,
            conflictRankResolved: true, checkedOnly: false)) { XCTAssertEqual($0 as? CapacityError, .invalidDomain) }
        XCTAssertThrowsError(try CapacityQualification(key: key, eligibility: .qualified, evidenceInputName: "qualification",
            evidenceSHA256: String(repeating: "0", count: 64), conflictRankResolved: true, checkedOnly: false)) {
                XCTAssertEqual($0 as? CapacityError, .declaredBytesMismatch)
        }
    }

    func testUnknownIneligibleAndUnresolvedConflictRemainDistinctFromQualifiedUse() throws {
        let original = try context()
        let answer = try original.answer("/deployment/sel_model/operator", .runtimeOperator)
        let domain = try CapacityDomain.component("sel_model")
        for eligibility in [CapacityEligibility.unknown, .ineligible] {
            try original.qualify(answer, .runtimeOperator, domain, eligibility: eligibility)
            let result = try original.qualifications()
            XCTAssertEqual(try result.eligibility(basis: original.basis, answer: answer,
                                                 fact: .runtimeOperator, domain: domain), eligibility)
            XCTAssertNil(try result.use(basis: original.basis, answer: answer, fact: .runtimeOperator, domain: domain))
        }
        let unresolved: [Bool?] = [nil, false]
        for resolved in unresolved {
            try original.qualify(answer, .runtimeOperator, domain, resolved: resolved)
            let result = try original.qualifications()
            XCTAssertEqual(try result.eligibility(basis: original.basis, answer: answer,
                                                 fact: .runtimeOperator, domain: domain), .unknown)
        }
    }

    func testQualificationChangesHaveTheirOwnIdentityAndCheckedOnlyFlag() throws {
        let original = try context()
        let answer = try original.answer("/deployment/sel_model/operator", .runtimeOperator)
        let domain = try CapacityDomain.component("sel_model")
        try original.qualify(answer, .runtimeOperator, domain, checked: false)
        let first = try original.qualifications()
        try original.qualify(answer, .runtimeOperator, domain, checked: true)
        let checked = try original.qualifications()
        XCTAssertNotEqual(first.sha256, checked.sha256)
        let use = try XCTUnwrap(checked.use(basis: original.basis, answer: answer, fact: .runtimeOperator, domain: domain))
        XCTAssertTrue(use.checkedOnly)
        XCTAssertEqual(use.answer.observation.assumption, true)
        XCTAssertEqual(use.answer.observation.presetSource, "preset:apple-capacity-test")
        XCTAssertThrowsError(try CapacityQualifications([use.qualification, use.qualification])) {
            XCTAssertEqual($0 as? CapacityError, .duplicateIdentity)
        }
    }

    func testIncompletePhysicalIdentityCannotBeQualifiedByAHashAlone() throws {
        let original = try context()
        let answer = try original.answer("/deployment/sel_model/operator", .runtimeOperator)
        let partial = try CapacityDomain.physical(pool: "pool", addressSpace: nil, partition: "whole", tenancy: "tenant")
        try original.qualify(answer, .physicalIdentity, partial)
        let values = try original.qualifications()
        XCTAssertNil(try values.use(basis: original.basis, answer: answer, fact: .physicalIdentity, domain: partial))
        XCTAssertNotEqual(try CapacityDomain.physical(pool: "pool", addressSpace: "address", partition: "whole",
                                                     tenancy: "tenant"), partial)
        XCTAssertNotEqual(try capacityKey([Data("ab".utf8), Data("c".utf8)]),
                          try capacityKey([Data("a".utf8), Data("bc".utf8)]))
    }

    func testDocumentAndAggregateNativeLimitsRejectBeforeParsingAndPermitRecovery() throws {
        XCTAssertThrowsError(try CapacityInput(name: "too-large", kind: .hardware,
            originalBytes: Data(repeating: 32, count: CapacityInput.maximumBytes + 1))) {
                XCTAssertEqual($0 as? CapacityError, .unsupportedNativeLimit)
        }
        XCTAssertThrowsError(try CapacityInput(name: String(repeating: "x", count: 4097),
            kind: .hardware, originalBytes: Data())) { XCTAssertEqual($0 as? CapacityError, .unsupportedNativeLimit) }
        let original = try context()
        let additional = try (0..<32).map {
            try CapacityInput(name: "extra-\($0)", kind: .hardware, originalBytes: Data())
        }
        XCTAssertThrowsError(try basis(original, inputs: original.inputs + additional)) {
            XCTAssertEqual($0 as? CapacityError, .unsupportedNativeLimit)
        }
        let large = try (0..<9).map {
            try CapacityInput(name: "large-\($0)", kind: .hardware,
                              originalBytes: Data(repeating: 32, count: CapacityInput.maximumBytes))
        }
        XCTAssertThrowsError(try basis(original, inputs: original.inputs + large)) {
            XCTAssertEqual($0 as? CapacityError, .unsupportedNativeLimit)
        }
        XCTAssertEqual(try basis(original).sha256, original.basis.sha256)
    }
}
