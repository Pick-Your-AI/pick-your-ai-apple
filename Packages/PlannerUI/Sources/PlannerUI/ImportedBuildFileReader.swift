import Darwin
import Foundation
import PlannerTransfer

/// Apple Files intake uses one opened regular object for admission and reading.
/// PlannerUI supports iOS and macOS; this follows the existing Darwin descriptor
/// boundary in PlannerCatalog without changing the frozen transfer validator.
enum ImportedBuildFileReader {
    /// The internal opener permits deterministic path-replacement regressions.
    /// Production always uses the default Darwin open with these exact flags.
    static func read(
        _ url: URL,
        openFile: (UnsafePointer<CChar>, Int32) -> Int32 = { Darwin.open($0, $1) }
    ) throws -> Data {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        guard url.isFileURL else { throw TransferError.malformed }
        // Retain the existing URL admission, including its link/type semantics.
        // This preflight is not authority for the object subsequently opened.
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw TransferError.malformed
        }

        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return openFile(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        }
        guard descriptor >= 0 else { throw TransferError.malformed }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        // A file provider may replace the path after an earlier metadata query.
        // Nonblocking open avoids waiting for a FIFO writer; fstat qualifies the
        // actual descriptor, and no second path lookup/reopen precedes reading.
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw TransferError.malformed
        }
        var bytes = Data()
        while bytes.count <= BuildTransfer.maximumBytes {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: min(65_536, BuildTransfer.maximumBytes + 1 - bytes.count)) ?? Data()
            if chunk.isEmpty { break }
            bytes.append(chunk)
        }
        guard bytes.count <= BuildTransfer.maximumBytes else { throw TransferError.oversized }
        return bytes
    }
}
