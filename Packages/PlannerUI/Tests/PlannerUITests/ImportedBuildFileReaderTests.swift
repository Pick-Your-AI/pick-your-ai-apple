import Darwin
import Foundation
import XCTest
import PlannerTransfer
@testable import PlannerUI

@MainActor
final class ImportedBuildFileReaderTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func assertClosed(_ descriptor: Int32, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(descriptor, 0, file: file, line: line)
        errno = 0
        let result = fcntl(descriptor, F_GETFD)
        let failure = errno
        XCTAssertEqual(result, -1, file: file, line: line)
        XCTAssertEqual(failure, EBADF, file: file, line: line)
    }

    func testRegularReadPreservesBytesAndClosesDescriptor() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("selected.json")
        let original = Data([0, 255, 10, 123, 125])
        try original.write(to: url)
        var descriptor: Int32 = -1
        let bytes = try ImportedBuildFileReader.read(url) { path, flags in
            XCTAssertEqual(flags & O_ACCMODE, O_RDONLY)
            XCTAssertNotEqual(flags & O_NONBLOCK, 0)
            XCTAssertNotEqual(flags & O_CLOEXEC, 0)
            descriptor = Darwin.open(path, flags)
            return descriptor
        }
        XCTAssertEqual(bytes, original)
        XCTAssertEqual(try Data(contentsOf: url), original)
        assertClosed(descriptor)
    }

    func testExactByteLimitAcceptedAndOverflowRejected() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("selected.json")
        let exact = Data(repeating: 32, count: BuildTransfer.maximumBytes)
        try exact.write(to: url)
        XCTAssertEqual(try ImportedBuildFileReader.read(url), exact)
        let oversized = exact + Data([32])
        try oversized.write(to: url)
        var descriptor: Int32 = -1
        XCTAssertThrowsError(try ImportedBuildFileReader.read(url) { path, flags in
            descriptor = Darwin.open(path, flags)
            return descriptor
        }) { XCTAssertEqual($0 as? TransferError, .oversized) }
        XCTAssertEqual(try Data(contentsOf: url), oversized)
        assertClosed(descriptor)
    }

    func testDescriptorTypeRejectsFIFOAfterPathReturnsToRegularFile() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("selected.json")
        let original = Data("original regular file".utf8)
        let replacement = Data("replacement regular file".utf8)
        try original.write(to: url)
        var descriptor: Int32 = -1
        XCTAssertThrowsError(try ImportedBuildFileReader.read(url) { path, flags in
            // Deterministically replace the initially regular path at open time.
            guard unlink(path) == 0, mkfifo(path, mode_t(0o600)) == 0 else {
                XCTFail("Could not prepare the owned FIFO replacement")
                return -1
            }
            XCTAssertNotEqual(flags & O_NONBLOCK, 0)
            // Keep this regression bounded even if the required flag is removed.
            // The assertion above still fails for that mutation.
            descriptor = Darwin.open(path, flags | O_NONBLOCK)
            guard descriptor >= 0, unlink(path) == 0 else {
                XCTFail("Could not open or retire the owned FIFO path")
                return descriptor
            }
            do { try replacement.write(to: url) }
            catch { XCTFail("Could not restore the owned regular-file path") }
            return descriptor
        }) { XCTAssertEqual($0 as? TransferError, .malformed) }
        // Path metadata is regular again; only the open descriptor exposes FIFO.
        XCTAssertTrue(try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true)
        XCTAssertEqual(try Data(contentsOf: url), replacement)
        assertClosed(descriptor)
        XCTAssertEqual(try ImportedBuildFileReader.read(url), replacement)
    }

    func testPathReplacementAfterOpenKeepsOriginalDescriptor() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("selected.json")
        let original = Data("opened original".utf8)
        let replacement = Data("new pathname target".utf8)
        try original.write(to: url)
        var descriptor: Int32 = -1
        let bytes = try ImportedBuildFileReader.read(url) { path, flags in
            descriptor = Darwin.open(path, flags)
            guard descriptor >= 0, unlink(path) == 0 else {
                XCTFail("Could not replace the owned regular-file path")
                return descriptor
            }
            do { try replacement.write(to: url) }
            catch { XCTFail("Could not create the owned replacement") }
            return descriptor
        }
        XCTAssertEqual(bytes, original)
        XCTAssertEqual(try Data(contentsOf: url), replacement)
        assertClosed(descriptor)
    }

    func testMissingAndNonFileURLsFailBeforeReading() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try ImportedBuildFileReader.read(root.appendingPathComponent("missing.json")))
        let external = try XCTUnwrap(URL(string: "https://example.invalid/selected.json"))
        XCTAssertThrowsError(try ImportedBuildFileReader.read(external) { _, _ in
            XCTFail("A non-file URL must not reach the descriptor opener")
            return -1
        }) { XCTAssertEqual($0 as? TransferError, .malformed) }
        XCTAssertThrowsError(try ImportedBuildFileReader.read(root)) {
            XCTAssertEqual($0 as? TransferError, .malformed)
        }
    }

    func testCancellationBeforeOpenDoesNotAcquireDescriptor() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("selected.json")
        try Data("owned input".utf8).write(to: url)
        await Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try ImportedBuildFileReader.read(url) { _, _ in
                    XCTFail("Cancelled intake must not acquire a descriptor")
                    return -1
                }
                XCTFail("Cancelled intake must throw")
            } catch { XCTAssertTrue(error is CancellationError) }
        }.value
    }

    func testCancellationAfterOpenClosesDescriptor() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("selected.json")
        let original = Data("owned input".utf8)
        try original.write(to: url)
        let descriptor = await Task { @MainActor in
            var descriptor: Int32 = -1
            do {
                _ = try ImportedBuildFileReader.read(url) { path, flags in
                    descriptor = Darwin.open(path, flags)
                    withUnsafeCurrentTask { $0?.cancel() }
                    return descriptor
                }
                XCTFail("Cancelled intake must throw before reading")
            } catch { XCTAssertTrue(error is CancellationError) }
            return descriptor
        }.value
        assertClosed(descriptor)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
