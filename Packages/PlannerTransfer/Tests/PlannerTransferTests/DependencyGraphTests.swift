import Foundation
import XCTest
@testable import PlannerTransfer

private struct DependencyGraphVector: Decodable {
    let name: String
    let path: [String]
    let operation: String
    let json: String?
    let canonicalValid: Bool
    let clientValid: Bool
}

final class DependencyGraphTests: XCTestCase {
    private func fixtureData() throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "dependency-graph", withExtension: "json")))
    }

    private func fixture() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData()) as? [String: Any])
    }

    private func encoded(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
    }

    func testCanonicalGraphPreservesEveryDirectedRelationshipAndLabel() throws {
        let graph = try DependencyGraph.decode(fixtureData())
        let source = try fixture()
        let edges = try XCTUnwrap(source["edges"] as? [[String: Any]])
        XCTAssertEqual(graph.id, source["id"] as? String)
        XCTAssertEqual(graph.revision, 1)
        XCTAssertEqual(graph.edges.count, edges.count)
        XCTAssertGreaterThan(graph.edges.count, 50)
        for (edge, original) in zip(graph.edges, edges) {
            XCTAssertEqual(edge.id, original["id"] as? String)
            XCTAssertEqual(edge.dependentKind.rawValue, original["dependent_kind"] as? String)
            XCTAssertEqual(edge.dependsOnKind.rawValue, original["depends_on_kind"] as? String)
            XCTAssertEqual(edge.relationship.rawValue, original["relationship"] as? String)
            XCTAssertEqual(edge.activation.rawValue, original["activation"] as? String)
            XCTAssertEqual(edge.rationale, original["rationale"] as? String)
        }
        var parser = try JSONParser(fixtureData())
        XCTAssertEqual(graph.value, try parser.parse())
        XCTAssertEqual(try DependencyGraph.decode(graph.encoded()), graph)
    }

    func testSharedCanonicalDependencyGraphVectors() throws {
        let resource = try XCTUnwrap(Bundle.module.url(forResource: "dependency-graph-conformance", withExtension: "json"))
        let cases = try JSONDecoder().decode([DependencyGraphVector].self, from: Data(contentsOf: resource))
        XCTAssertEqual(cases.count, 150)
        XCTAssertEqual(cases.filter { $0.canonicalValid != $0.clientValid }.count, 3)
        let source = try fixture()
        for vector in cases {
            let payload: Any
            if vector.operation == "none" { payload = source }
            else {
                let replacement = try vector.json.map {
                    try JSONSerialization.jsonObject(with: Data($0.utf8), options: [.fragmentsAllowed])
                }
                payload = try mutate(source, path: vector.path[...], replacement: replacement,
                                     remove: vector.operation == "remove")
            }
            let data = try encoded(payload)
            do {
                let graph = try DependencyGraph.decode(data)
                XCTAssertTrue(vector.clientValid, vector.name)
                var original = try JSONParser(data)
                XCTAssertEqual(graph.value, try original.parse(), vector.name)
                XCTAssertEqual(try DependencyGraph.decode(graph.encoded()), graph, vector.name)
            } catch {
                XCTAssertFalse(vector.clientValid, "\(vector.name): \(error)")
            }
        }
    }

    private func mutate(_ value: Any, path: ArraySlice<String>, replacement: Any?, remove: Bool) throws -> Any {
        guard let key = path.first else { return try XCTUnwrap(replacement) }
        if var object = value as? [String: Any] {
            if path.count == 1 {
                if remove { object.removeValue(forKey: key) }
                else { object[key] = try XCTUnwrap(replacement) }
            } else {
                object[key] = try mutate(XCTUnwrap(object[key]), path: path.dropFirst(), replacement: replacement, remove: remove)
            }
            return object
        }
        var array = try XCTUnwrap(value as? [Any])
        let index = try XCTUnwrap(Int(key))
        guard array.indices.contains(index) else { throw TransferError.malformed }
        if path.count == 1 {
            if remove { array.remove(at: index) }
            else { array[index] = try XCTUnwrap(replacement) }
        } else {
            array[index] = try mutate(array[index], path: path.dropFirst(), replacement: replacement, remove: remove)
        }
        return array
    }

    func testRepeatedIdentifiersSelfEdgesAndCyclesRemainUnmodified() throws {
        var source = try fixture()
        var edge = try XCTUnwrap((source["edges"] as? [[String: Any]])?.first)
        edge["dependent_kind"] = "model"
        edge["depends_on_kind"] = "model_provider"
        var reverse = edge
        reverse["id"] = "dep.synthetic.reverse"
        reverse["dependent_kind"] = "model_provider"
        reverse["depends_on_kind"] = "model"
        var selfEdge = edge
        selfEdge["depends_on_kind"] = "model"
        source["edges"] = [edge, reverse, edge, selfEdge]
        let graph = try DependencyGraph.decode(encoded(source))
        XCTAssertEqual(graph.edges.count, 4)
        XCTAssertEqual(graph.edges[0], graph.edges[2])
        XCTAssertEqual(graph.edges[0].dependentKind, graph.edges[1].dependsOnKind)
        XCTAssertEqual(graph.edges[0].dependsOnKind, graph.edges[1].dependentKind)
        XCTAssertEqual(graph.edges[3].dependentKind, graph.edges[3].dependsOnKind)
        XCTAssertEqual(try DependencyGraph.decode(graph.encoded()), graph)
    }

    func testDuplicateRootAndEscapedEdgeKeysAreRejected() throws {
        let source = try XCTUnwrap(String(data: encoded(fixture()), encoding: .utf8))
        let duplicateRoot = source.replacingOccurrences(of: "\"revision\":", with: "\"revision\":2,\"revision\":")
        let duplicateEdge = source.replacingOccurrences(of: "\"dependent_kind\":", with: #""dependent_\u006bind":"workload","dependent_kind":"#)
        for duplicate in [duplicateRoot, duplicateEdge] {
            XCTAssertNotEqual(duplicate, source)
            XCTAssertThrowsError(try DependencyGraph.decode(Data(duplicate.utf8))) {
                XCTAssertEqual($0 as? TransferError, .duplicateKey)
            }
        }
        XCTAssertNoThrow(try DependencyGraph.decode(Data(source.utf8)))
    }

    func testCompleteDocumentByteDepthAndNodeLimitsPrecedeSchemaValidation() throws {
        XCTAssertThrowsError(try DependencyGraph.decode(Data(repeating: 32, count: BuildTransfer.maximumBytes + 1))) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        let nested = String(repeating: "[", count: 50) + "0" + String(repeating: "]", count: 50)
        XCTAssertThrowsError(try DependencyGraph.decode(Data(nested.utf8))) {
            XCTAssertEqual($0 as? TransferError, .tooDeep)
        }
        var source = try fixture()
        let edge: [String: Any] = ["id": "dep.synthetic", "dependent_kind": "model", "depends_on_kind": "workload",
                                   "relationship": "requires", "activation": "always", "rationale": "x"]
        source["edges"] = Array(repeating: edge, count: 2_400)
        let complex = try encoded(source)
        XCTAssertLessThan(complex.count, BuildTransfer.maximumBytes)
        XCTAssertThrowsError(try DependencyGraph.decode(complex)) {
            XCTAssertEqual($0 as? TransferError, .tooComplex)
        }
    }

    func testEncodedExpansionCannotReturnBytesThatCannotBeReopened() throws {
        var source = try fixture()
        var edge = try XCTUnwrap((source["edges"] as? [[String: Any]])?.first)
        edge["rationale"] = String(repeating: "/", count: 270_000)
        source["edges"] = [edge]
        let compact = try JSONSerialization.data(withJSONObject: source, options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertLessThan(compact.count, BuildTransfer.maximumBytes)
        let graph = try DependencyGraph.decode(compact)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertGreaterThan(try encoder.encode(graph.value).count, BuildTransfer.maximumBytes)
        XCTAssertThrowsError(try graph.encoded()) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        XCTAssertEqual(try DependencyGraph.decode(compact), graph)
    }
}
