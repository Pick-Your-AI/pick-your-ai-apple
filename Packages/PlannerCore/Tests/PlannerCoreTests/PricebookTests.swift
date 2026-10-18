import Foundation
import XCTest
@testable import PlannerCore

final class PricebookTests: XCTestCase {
    private func fixture() throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "pricebook", withExtension: "json")))
    }
    private func object() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
    }
    private func decode(_ object: [String: Any]) throws -> Pricebook {
        try Pricebook.decode(JSONSerialization.data(withJSONObject: object))
    }
    private func withRate(_ mutation: (inout [String: Any]) -> Void) throws -> Pricebook {
        var report = try object()
        var rates = try XCTUnwrap(report["rates"] as? [[String: Any]])
        mutation(&rates[0]); report["rates"] = rates
        return try decode(report)
    }
    func testPinnedSyntheticFixturePreservesMoneyCatalogIdentityAndEvidence() throws {
        let book = try Pricebook.decode(fixture())
        XCTAssertEqual(book.schemaVersion, "1.0.0")
        XCTAssertEqual(book.id, "prices.fixture.1")
        XCTAssertEqual(book.revision, 1)
        XCTAssertEqual(book.rates.count, 2)
        XCTAssertEqual(book.rates[0].catalogItemVersion, "2026.10-demo")
        XCTAssertEqual(book.rates[0].meter, .gpuHour)
        XCTAssertEqual(book.rates[0].unitPrice.amount.rawValue, "0.80")
        XCTAssertEqual(book.rates[0].provenance.verificationStatus, .estimated)
        XCTAssertNil(book.rates[0].provenance.sourceURI)
        XCTAssertEqual(book.rates[0].priceType, .estimate)
        XCTAssertEqual(book, try Pricebook.decode(JSONEncoder().encode(book)))
    }
    func testAllRequiredFieldsRejectMissingNullAndWrongType() throws {
        for key in ["schema_version", "id", "revision", "captured_at", "rates"] {
            for replacement: Any? in [nil, NSNull(), true] {
                var book = try object(); book[key] = replacement
                XCTAssertThrowsError(try decode(book), key)
            }
        }
        for key in ["id", "catalog_item_id", "catalog_item_version", "meter", "unit_price", "valid_from", "provenance", "price_type"] {
            for replacement: Any? in [nil, NSNull(), true] {
                XCTAssertThrowsError(try withRate { $0[key] = replacement }, key)
            }
        }
        for key in ["checked_at", "verification_status"] {
            for replacement: Any? in [nil, NSNull(), true] {
                XCTAssertThrowsError(try withRate { rate in
                    var provenance = rate["provenance"] as! [String: Any]
                    provenance[key] = replacement; rate["provenance"] = provenance
                }, key)
            }
        }
    }
    func testClosedObjectsAndOptionalNullRejection() throws {
        var book = try object(); book["extra"] = 1
        XCTAssertThrowsError(try decode(book))
        XCTAssertThrowsError(try withRate { $0["extra"] = 1 })
        XCTAssertThrowsError(try withRate { $0["provenance"] = ["checked_at": "2026-01-01T00:00:00Z", "verification_status": "verified", "extra": 1] })
        XCTAssertThrowsError(try withRate { $0["unit_price"] = ["amount": "1", "currency": "USD", "extra": 1] })
        for field in ["region", "valid_until", "conditions"] {
            XCTAssertThrowsError(try withRate { $0[field] = NSNull() }, field)
        }
        for field in ["source_uri", "notes"] {
            XCTAssertThrowsError(try withRate { rate in
                var provenance = rate["provenance"] as! [String: Any]
                provenance[field] = NSNull(); rate["provenance"] = provenance
            }, field)
        }
    }
    func testVersionIdentityEnumsAndMinimums() throws {
        for (key, value) in [("schema_version", "2.0.0" as Any), ("id", "ab"), ("id", "UPPER"),
                             ("revision", 0), ("revision", -1), ("revision", 1.5), ("rates", [])] {
            var book = try object(); book[key] = value
            XCTAssertThrowsError(try decode(book), key)
        }
        for (key, value) in [("id", "a" as Any), ("catalog_item_id", "Nope"), ("catalog_item_version", ""),
                             ("meter", "egress_gb"), ("price_type", "unknown"), ("conditions", [1])] {
            XCTAssertThrowsError(try withRate { $0[key] = value }, key)
        }
        XCTAssertThrowsError(try withRate { $0["provenance"] = ["checked_at": "2026-01-01T00:00:00Z", "verification_status": "unknown"] })
        for meter in PriceMeter.allCases {
            XCTAssertEqual(try withRate { $0["meter"] = meter.rawValue }.rates[0].meter, meter)
        }
    }
    func testMoneyIsDecimalStringWithNoRoundingOrCurrencyConversion() throws {
        for amount: Any in [1.25, -1, NSNull(), "-1", "1e2", "01", "1.1234567890123"] {
            XCTAssertThrowsError(try withRate { $0["unit_price"] = ["amount": amount, "currency": "USD"] })
        }
        for currency in ["usd", "US", "USDD", "€UR"] {
            XCTAssertThrowsError(try withRate { $0["unit_price"] = ["amount": "1", "currency": currency] })
        }
        let huge = "12345678901234567890123456789012345678901234567890.123456789012"
        let book = try withRate { $0["unit_price"] = ["amount": huge, "currency": "EUR"] }
        XCTAssertEqual(book.rates[0].unitPrice.amount.rawValue, huge)
        XCTAssertEqual(try Pricebook.decode(JSONEncoder().encode(book)).rates[0].unitPrice.amount.rawValue, huge)
        XCTAssertEqual(book.rates[0].unitPrice.currency, "EUR")
    }
    func testStrictTimestampsAtEveryBoundary() throws {
        for timestamp in ["2026-02-30T00:00:00Z", "1900-02-29T00:00:00Z", "2026-01-01T24:00:00Z", "2026-01-01T00:00:00+24:00", "tomorrow"] {
            var book = try object(); book["captured_at"] = timestamp
            XCTAssertThrowsError(try decode(book))
            for field in ["valid_from", "valid_until"] {
                XCTAssertThrowsError(try withRate { $0[field] = timestamp }, field)
            }
            XCTAssertThrowsError(try withRate { $0["provenance"] = ["checked_at": timestamp, "verification_status": "verified"] })
        }
        XCTAssertEqual(try withRate { $0["valid_until"] = "2000-02-29T23:59:59.123Z" }.rates[0].validUntil, "2000-02-29T23:59:59.123Z")
        // Schema has no chronological validity constraint; no such policy is invented here.
    }
    func testOptionalProvenanceNeverPromotesTrust() throws {
        for status in ["verified", "user_supplied", "estimated", "unverified"] {
            let book = try withRate { $0["provenance"] = ["checked_at": "2026-01-01T00:00:00Z", "verification_status": status] }
            XCTAssertEqual(book.rates[0].provenance.verificationStatus.rawValue, status)
            XCTAssertNil(book.rates[0].provenance.sourceURI)
        }
        for uri in ["https://example.com/prices?x=1#rates", "urn:example:rates", "https://example.com/%20"] {
            let book = try withRate { $0["provenance"] = ["checked_at": "2026-01-01T00:00:00Z", "verification_status": "unverified", "source_uri": uri, "notes": ""] }
            XCTAssertEqual(book.rates[0].provenance.sourceURI, uri)
            XCTAssertEqual(book.rates[0].provenance.verificationStatus, .unverified)
        }
        for uri in ["", "/relative", "https://example.com/a b", "https://example.com/%GG", "https://example.com/%A", "https://example.com/%", "https://example.com/[a]"] {
            XCTAssertThrowsError(try withRate { $0["provenance"] = ["checked_at": "2026-01-01T00:00:00Z", "verification_status": "unverified", "source_uri": uri] }, uri)
        }
    }
    func testPayloadLimitAndIntegerRepresentationBound() throws {
        XCTAssertThrowsError(try Pricebook.decode(Data(repeating: 0xff, count: Pricebook.maximumPayloadBytes + 1))) { error in
            XCTAssertEqual(error as? Pricebook.BoundaryError, .payloadTooLarge)
        }
        let original = String(data: try fixture(), encoding: .utf8)!
        XCTAssertThrowsError(try Pricebook.decode(Data(original.replacingOccurrences(of: "\"revision\": 1", with: "\"revision\": 99999999999999999999999999999999").utf8)))
    }
    func testIdenticalSharedPythonSwiftVectors() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "pricebook-vectors", withExtension: "json"))
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        XCTAssertEqual(cases.count, 82)
        for vector in cases {
            let payload = try JSONSerialization.data(withJSONObject: XCTUnwrap(vector["payload"]))
            let valid = try XCTUnwrap(vector["valid"] as? Bool)
            let name = try XCTUnwrap(vector["id"] as? String)
            if valid { XCTAssertNoThrow(try Pricebook.decode(payload), name) }
            else { XCTAssertThrowsError(try Pricebook.decode(payload), name) }
        }
    }

}
