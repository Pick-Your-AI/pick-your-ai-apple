import Foundation
import XCTest
@testable import PlannerUI

final class CatalogSourceLinkPolicyTests: XCTestCase {
    private func candidate(_ raw: String, policy: CatalogSourceLinkPolicy) -> CatalogSourceLink? {
        guard case .candidate(let link) = policy.inspect(raw) else { return nil }
        return link
    }

    func testApprovedHTTPSDestinationsPreserveTheCompleteURLAndHost() throws {
        let policy = try CatalogSourceLinkPolicy(allowedHosts: ["DOCS.EXAMPLE.COM"])
        for raw in [
            "https://docs.example.com",
            "https://docs.example.com/",
            "https://docs.example.com:443/specs?amount=0&flag=false#conditions",
            "HTTPS://DOCS.EXAMPLE.COM:443/a%20b?units=%C2%B5#method"
        ] {
            let link = try XCTUnwrap(candidate(raw, policy: policy))
            XCTAssertEqual(link.url.absoluteString, raw)
            XCTAssertEqual(link.host.lowercased(), "docs.example.com")
        }
        XCTAssertEqual(CatalogSourceLinkPolicy.denyAll.inspect("https://docs.example.com/spec"),
                       .rejected(.disallowedAuthority))
    }

    func testUnreviewedAndConfusableAuthoritiesCannotBecomeCandidates() throws {
        let policy = try CatalogSourceLinkPolicy(allowedHosts: ["docs.example.com"])
        for raw in [
            "https://example.com/spec", "https://sub.docs.example.com/spec",
            "https://docs.example.com.evil.invalid/spec", "https://evil.invalid/docs.example.com",
            "https://user@docs.example.com/spec", "https://user:password@docs.example.com/spec",
            "https://docs.example.com@evil.invalid/spec", "https://docs.example.com./spec",
            "https://docs.example.com:80/spec", "https://docs.example.com:0443/spec",
            "https://docs.example.com:443:443/spec", "https://docs.example.com:/spec",
            "https://127.0.0.1/spec", "https://[::1]/spec", "https://localhost/spec",
            "https://docs.example.com%40evil.invalid/spec", "https://%64ocs.example.com/spec",
            "https://docs.exаmple.com/spec", "https://docs.example.com\\@evil.invalid/spec"
        ] {
            XCTAssertNil(candidate(raw, policy: policy), "A different or ambiguous authority must be rejected")
        }
    }

    func testMalformedAndNonHTTPSInputCannotBeRepairedIntoNavigation() throws {
        let policy = try CatalogSourceLinkPolicy(allowedHosts: ["docs.example.com"])
        for raw in [
            "", "//docs.example.com/spec", "/spec", "http://docs.example.com/spec",
            "javascript:alert(1)", "file:///spec", "data:text/plain,fixture",
            "https:docs.example.com/spec", "https:///docs.example.com/spec",
            " https://docs.example.com/spec", "https://docs.example.com/a b",
            "https://docs.example.com/\n", "https://docs.example.com/\r\n",
            "https://docs.example.com/\u{0}", "https://docs.example.com/\u{202e}spec",
            "https://docs.example.com/µ", "https://docs.example.com/%",
            "https://docs.example.com/%2", "https://docs.example.com/%GG"
        ] {
            XCTAssertNil(candidate(raw, policy: policy), "Raw malformed input must not be automatically repaired")
        }
        let raw = "https://docs.example.com/a%20b?next=https%3A%2F%2Fevil.invalid#method"
        let link = try XCTUnwrap(candidate(raw, policy: policy))
        XCTAssertEqual(link.url.absoluteString, raw)
        XCTAssertEqual(link.host, "docs.example.com")
        // A path/query remains recorded data. This candidate does not inspect
        // remote content, follow redirects or guarantee the eventual host.
    }

    func testTheURLByteLimitIsExactAndCannotBeConfiguredAbove4096() throws {
        let prefix = "https://docs.example.com/"
        let raw = prefix + String(repeating: "x", count: 4_096 - prefix.utf8.count)
        let policy = try CatalogSourceLinkPolicy(allowedHosts: ["docs.example.com"])
        XCTAssertEqual(try XCTUnwrap(candidate(raw, policy: policy)).url.absoluteString, raw)
        XCTAssertEqual(policy.inspect(raw + "x"), .rejected(.tooLong))
        XCTAssertEqual(policy.inspect(String(repeating: "🧪", count: 1_025)), .rejected(.tooLong))
        let short = try CatalogSourceLinkPolicy(allowedHosts: ["docs.example.com"],
                                               maximumBytes: prefix.utf8.count)
        XCTAssertNotNil(candidate(prefix, policy: short))
        XCTAssertEqual(short.inspect(prefix + "x"), .rejected(.tooLong))
        for invalid in [-1, 0, 4_097, Int.max] {
            XCTAssertThrowsError(try CatalogSourceLinkPolicy(allowedHosts: [], maximumBytes: invalid))
        }
    }

    func testConfigurationRequiresExplicitBoundedASCIIDNSNames() throws {
        for host in [
            "", "*.example.com", ".example.com", "docs..example.com", "docs.example.com.",
            "https://docs.example.com", "docs.example.com:443", "docs.example.com/path",
            "-docs.example.com", "docs-.example.com", "do_cs.example.com", "döcs.example.com",
            "docs.example.com\n", "localhost", "127.0.0.1", "[::1]", "example.123",
            String(repeating: "a", count: 64) + ".example.com"
        ] {
            XCTAssertThrowsError(try CatalogSourceLinkPolicy(allowedHosts: [host]))
        }
        let longest = [63, 63, 63, 61].map { String(repeating: "a", count: $0) }.joined(separator: ".")
        XCTAssertEqual(longest.utf8.count, 253)
        XCTAssertNoThrow(try CatalogSourceLinkPolicy(allowedHosts: [longest]))
        XCTAssertThrowsError(try CatalogSourceLinkPolicy(allowedHosts: [longest + "a"]))
        XCTAssertNoThrow(try CatalogSourceLinkPolicy(allowedHosts: []))
    }

    func testDiagnosticDescriptionsRedactSourceAddressesAndOpeningIDs() throws {
        let raw = "https://docs.example.com/spec?private=REDACTED-SPECIMEN"
        let policy = try CatalogSourceLinkPolicy(allowedHosts: ["docs.example.com"])
        let decision = policy.inspect(raw)
        let link = try XCTUnwrap(candidate(raw, policy: policy))
        let id = UUID()
        let state = CatalogSourceReviewState.confirmation(link)
        let review = CatalogSourceReview(id: id, sourceIndex: 0, state: state)
        let opening = CatalogSourceOpening(id: id, url: link.url)
        let descriptions = [
            String(describing: link), String(reflecting: link),
            String(describing: decision), String(reflecting: decision),
            String(describing: state), String(reflecting: state),
            String(describing: review), String(reflecting: review),
            String(describing: opening), String(reflecting: opening)
        ]
        for text in descriptions {
            XCTAssertFalse(text.contains("docs.example.com"))
            XCTAssertFalse(text.contains("REDACTED-SPECIMEN"))
            XCTAssertFalse(text.contains(id.uuidString))
        }
    }
}
