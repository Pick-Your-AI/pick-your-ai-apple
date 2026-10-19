import Foundation
import XCTest
@testable import PlannerTransfer

private struct PlacementMutation: Decodable {
    let path: [String]
    let operation: String
    let json: String?
}

private struct PlacementVector: Decodable {
    let name: String
    let fixture: String
    let mutations: [PlacementMutation]
    let canonicalValid: Bool
    let clientValid: Bool
    let disposition: String
    let decision: String
    let reason: String
    let expectedError: String?
}

final class PlacementRelationshipTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func parsed(_ data: Data) throws -> JSONValue {
        var parser = try JSONParser(data)
        return try parser.parse()
    }

    private func encoded(_ value: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func vectors() throws -> [PlacementVector] {
        try JSONDecoder().decode([PlacementVector].self, from: fixture("placement-conformance"))
    }

    private func source(_ name: String) throws -> JSONValue {
        if name == "build" { return try parsed(fixture("build")) }
        let catalog = try parsed(fixture("catalog"))
        return try XCTUnwrap(catalog.object?["items"]?.array?.first { $0.object?["kind"] == .string(name) })
    }

    // Apply the shared compact mutation to exact JSONValue decimals, never NSNumber/Double.
    private func mutate(_ value: JSONValue, path: ArraySlice<String>, replacement: JSONValue?, remove: Bool) throws -> JSONValue {
        guard let key = path.first else { throw TransferError.malformed }
        if var object = value.object {
            if path.count == 1 {
                if remove { _ = try XCTUnwrap(object.removeValue(forKey: key)) }
                else { object[key] = try XCTUnwrap(replacement) }
            } else {
                object[key] = try mutate(XCTUnwrap(object[key]), path: path.dropFirst(), replacement: replacement, remove: remove)
            }
            return .object(object)
        }
        var array = try XCTUnwrap(value.array)
        let index = try XCTUnwrap(Int(key))
        guard array.indices.contains(index) else { throw TransferError.malformed }
        if path.count == 1 {
            if remove { array.remove(at: index) }
            else { array[index] = try XCTUnwrap(replacement) }
        } else {
            array[index] = try mutate(array[index], path: path.dropFirst(), replacement: replacement, remove: remove)
        }
        return .array(array)
    }

    private func payload(_ vector: PlacementVector) throws -> JSONValue {
        var value = try source(vector.fixture)
        for change in vector.mutations {
            guard ["set", "remove"].contains(change.operation) else { throw TransferError.malformed }
            let replacement = try change.json.map { try parsed(Data($0.utf8)) }
            value = try mutate(value, path: change.path[...], replacement: replacement, remove: change.operation == "remove")
        }
        return value
    }

    private func vector(_ name: String) throws -> PlacementVector {
        try XCTUnwrap(vectors().first { $0.name == name })
    }

    private func snapshot(_ name: String) throws -> BuildSnapshot {
        try BuildTransfer.snapshot(fromDraftJSON: encoded(payload(vector(name))))
    }

    private func catalogItem(_ name: String) throws -> CatalogItem {
        try CatalogItem.decode(encoded(payload(vector(name))))
    }

    private func selection(_ snapshot: BuildSnapshot, id: String) throws -> [String: JSONValue] {
        try XCTUnwrap(snapshot.value.object?["selections"]?.array?.first { $0.object?["id"] == .string(id) }?.object)
    }

    private func decodedValue(_ fixture: String, data: Data) throws -> JSONValue {
        if fixture == "build" { return try BuildTransfer.snapshot(fromDraftJSON: data).value }
        return try CatalogItem.decode(data).value
    }

    func testSharedPlacementVectorsPreserveTransportAndRejectUnsupportedFields() throws {
        let cases = try vectors()
        XCTAssertEqual(cases.count, 98)
        XCTAssertEqual(Set(cases.map(\.name)).count, cases.count)
        XCTAssertEqual(Set(cases.map(\.disposition)), ["preserved", "unresolved", "unsupported-field", "invalid-contract"])
        for vector in cases {
            XCTAssertEqual(vector.canonicalValid, vector.clientValid, vector.name)
            XCTAssertFalse(vector.reason.isEmpty, vector.name)
            if vector.disposition == "unresolved" || vector.disposition == "unsupported-field" {
                XCTAssertNotEqual(vector.decision, "none", vector.name)
            }
            let value = try payload(vector)
            let data = try encoded(value)
            if vector.clientValid {
                XCTAssertNil(vector.expectedError, vector.name)
                if vector.fixture == "build" {
                    let decoded = try BuildTransfer.snapshot(fromDraftJSON: data)
                    XCTAssertEqual(decoded.value, value, vector.name)
                    XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: decoded.encoded()), decoded, vector.name)
                } else {
                    let decoded = try CatalogItem.decode(data)
                    XCTAssertEqual(decoded.value, value, vector.name)
                    XCTAssertEqual(decoded.kind.rawValue, vector.fixture, vector.name)
                    XCTAssertEqual(try CatalogItem.decode(decoded.encoded()), decoded, vector.name)
                }
            } else {
                let expected: TransferError
                switch vector.expectedError {
                case "schemaViolation": expected = .schemaViolation
                case "unsupportedVersion": expected = .unsupportedVersion
                default: XCTFail("Missing exact rejection expectation: \(vector.name)"); continue
                }
                XCTAssertThrowsError(try decodedValue(vector.fixture, data: data), vector.name) {
                    XCTAssertEqual($0 as? TransferError, expected, vector.name)
                }
            }
        }
    }

    func testMixedAccessPathsRolesAndDirectedLinksAreNotCollapsed() throws {
        let original = try snapshot("canonical-relationships")
        let mixed = try snapshot("mixed-api-and-weight-selections")
        let local = try selection(mixed, id: "sel_model")
        let remote = try selection(mixed, id: "sel_remote_model")
        XCTAssertEqual(local["role"], .string("generation_local"))
        XCTAssertEqual(remote["role"], .string("generation_api"))
        XCTAssertEqual(local["settings"]?.object?["serving_mode"], .string("weights"))
        XCTAssertEqual(remote["settings"]?.object?["serving_mode"], .string("api"))
        XCTAssertNil(local["deployment"])
        XCTAssertNil(remote["deployment"])
        XCTAssertEqual(mixed.locks, original.locks)
        XCTAssertEqual(mixed.value.object?["selections"]?.array?.count, 30)
        let links = try XCTUnwrap(mixed.value.object?["links"]?.array)
        XCTAssertEqual(Array(links.dropLast()), original.value.object?["links"]?.array)
        XCTAssertEqual(links.last?.object?["from_selection_id"], .string("sel_remote_model"))
        XCTAssertEqual(links.last?.object?["to_selection_id"], .string("sel_model_provider"))
        XCTAssertEqual(links.last?.object?["required"], .bool(false))
        XCTAssertNil(links.first?.object?["required"])
        let reversed = try snapshot("link-direction-reversed").value.object?["links"]?.array?.first?.object
        XCTAssertEqual(reversed?["from_selection_id"], .string("sel_model_provider"))
        XCTAssertEqual(reversed?["to_selection_id"], .string("sel_model"))
        let disabled = try selection(snapshot("roles-remain-distinct"), id: "sel_model")
        XCTAssertEqual(disabled["enabled"], .bool(false))
        XCTAssertEqual(disabled["role"], .string("generation-local"))
        XCTAssertEqual(try catalogItem("catalog-mode-hybrid").spec["mode"], .string("hybrid"))
    }

    func testMemoryFactsCountsAndContextQuantitiesRemainSeparateAndAbsent() throws {
        let device = try catalogItem("catalog-per-device-vram")
        let host = try catalogItem("catalog-host-memory-and-count")
        XCTAssertEqual(device.spec["vram_gb"], .number(24))
        XCTAssertEqual(device.spec["interconnect"], .string("nvlink"))
        XCTAssertEqual(host.spec["ram_gb"], .number(128))
        XCTAssertEqual(host.spec["accelerator_count"], .number(4))
        XCTAssertNil(device.spec["pooled_vram_gb"])
        XCTAssertNil(device.spec["unified_memory_gb"])
        XCTAssertNil(host.spec["allocatable_ram_gb"])
        let counts = try snapshot("device-and-parallel-counts-remain-distinct")
        let accelerator = try selection(counts, id: "sel_accelerator")["settings"]?.object
        XCTAssertEqual(accelerator?["device_count"], .number(4))
        XCTAssertEqual(accelerator?["tensor_parallel_groups"], .number(2))
        XCTAssertEqual(try selection(counts, id: "sel_inference_engine")["settings"]?.object?["tensor_parallel_size"], .number(3))
        XCTAssertEqual(try selection(counts, id: "sel_compute_profile")["settings"]?.object?["instances"], .number(2))
        let missing = try catalogItem("catalog-absent-compute_profile")
        XCTAssertNil(missing.spec["accelerator_ref"])
        XCTAssertNil(missing.spec["accelerator_count"])
        XCTAssertNil(try catalogItem("catalog-absent-inference_engine").spec["supports_multi_gpu"])
        XCTAssertNil(try catalogItem("catalog-absent-model").spec["min_weights_vram_gb"])
        XCTAssertNil(try catalogItem("catalog-absent-context_policy").spec["max_allowed_tokens"])
        let context = try snapshot("context-quantities-remain-distinct")
        let settings = try selection(context, id: "sel_context_policy")["settings"]?.object
        XCTAssertEqual(settings?["requested_context_tokens"], .number(4096))
        XCTAssertEqual(settings?["reserved_output_tokens"], .number(512))
        XCTAssertEqual(try selection(context, id: "sel_model")["settings"]?.object?["max_output_tokens"], .number(256))
        XCTAssertEqual(context.value.object?["objectives"]?.object?["avg_input_tokens"], .number(700))
        XCTAssertEqual(context.value.object?["objectives"]?.object?["avg_output_tokens"], .number(400))
        XCTAssertNil(settings?["combined_context_tokens"])
        XCTAssertNil(settings?["context_semantics"])
        XCTAssertNil(settings?["provider_override"])
    }

    func testRejectedPlacementAndVersionInputsPreserveThePriorSnapshotAndRecovery() throws {
        let originalData = try fixture("build")
        let original = try BuildTransfer.snapshot(fromDraftJSON: originalData)
        let originalOutput = try original.encoded()
        for name in ["unsupported-build-memory-pools", "unsupported-selection-deployment", "unsupported-context-shared-total", "unsupported-version-build-1.0.1"] {
            let input = try encoded(payload(vector(name)))
            let savedInput = input
            XCTAssertThrowsError(try BuildTransfer.snapshot(fromDraftJSON: input)) {
                XCTAssertNotNil($0 as? TransferError)
                XCTAssertFalse(String(describing: $0).contains("pool.fixture"))
                XCTAssertFalse(String(describing: $0).contains("runtime_operator"))
            }
            XCTAssertEqual(input, savedInput, name)
            XCTAssertEqual(try original.encoded(), originalOutput, name)
            XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: originalData), original, name)
        }
        let text = try XCTUnwrap(String(data: originalOutput, encoding: .utf8))
        for key in ["role", #"r\u006fle"#] {
            let duplicate = text.replacingOccurrences(of: "\"role\":", with: "\"\(key)\":\"other\",\"role\":")
            XCTAssertNotEqual(duplicate, text)
            XCTAssertThrowsError(try BuildTransfer.snapshot(fromDraftJSON: Data(duplicate.utf8))) {
                XCTAssertEqual($0 as? TransferError, .duplicateKey)
            }
            XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: originalData), original)
        }
    }
}
