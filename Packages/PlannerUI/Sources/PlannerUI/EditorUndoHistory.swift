import Foundation

/// Transient editor text only. Durable revision history remains owned by DraftStore.
struct EditorContents: Equatable, Sendable {
    let title: String
    let notes: String
    var byteCount: Int { title.utf8.count + notes.utf8.count }
}

/// Keep a bounded session history, including redo, without retaining analysis or IDs.
/// Oversized text stays in the editor; undo must not discard text it cannot retain for redo.
struct EditorUndoHistory {
    static let maximumEntries = 100
    static let maximumBytes = 4 * 1_048_576
    private(set) var past: [EditorContents] = []
    private(set) var future: [EditorContents] = []
    var byteCount: Int { (past + future).reduce(0) { $0 + $1.byteCount } }

    func canUndo(_ current: EditorContents) -> Bool {
        !past.isEmpty && current.byteCount <= Self.maximumBytes
    }
    func canRedo(_ current: EditorContents) -> Bool {
        !future.isEmpty && current.byteCount <= Self.maximumBytes
    }
    mutating func record(_ current: EditorContents) {
        future = []
        guard current.byteCount <= Self.maximumBytes else { past = []; return }
        past.append(current)
        trim()
    }
    mutating func undo(_ current: EditorContents) -> EditorContents? {
        guard canUndo(current), let previous = past.popLast() else { return nil }
        future.append(current)
        trim()
        return previous
    }
    mutating func redo(_ current: EditorContents) -> EditorContents? {
        guard canRedo(current), let next = future.popLast() else { return nil }
        past.append(current)
        trim(preservePast: true)
        return next
    }
    private mutating func trim(preservePast: Bool = false) {
        while past.count + future.count > Self.maximumEntries || byteCount > Self.maximumBytes {
            if preservePast && !future.isEmpty { future.removeFirst() }
            else if !past.isEmpty { past.removeFirst() }
            else { future.removeFirst() }
        }
    }
}
