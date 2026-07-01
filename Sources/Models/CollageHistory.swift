import SwiftUI
import Observation

/// A snapshot-based undo/redo stack for the working collage. Simpler and more
/// robust than command objects given how many places mutate a placed element
/// directly (gestures, the inspector, the background picker): callers just take
/// a `checkpoint()` immediately before any committed change.
@Observable
@MainActor
final class CollageHistory {
    private var undoStack: [CollageSnapshot] = []
    private var redoStack: [CollageSnapshot] = []
    /// Cap the depth so a long editing session doesn't grow without bound.
    private let limit = 80

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Record the state as it is *before* an edit is applied. Clears the redo
    /// branch, matching standard editor semantics.
    func record(_ snapshot: CollageSnapshot) {
        undoStack.append(snapshot)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    /// Pop the most recent pre-edit snapshot to restore, banking `current` for a
    /// possible redo. Returns nil when there is nothing to undo.
    func undo(current: CollageSnapshot) -> CollageSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// Inverse of `undo`.
    func redo(current: CollageSnapshot) -> CollageSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    /// Drop the most recent recorded checkpoint without applying anything — used
    /// when a just-started edit (e.g. adding a blank text label) is cancelled.
    func discardLast() {
        _ = undoStack.popLast()
    }

    /// Clear all history (e.g. after opening a saved collage).
    func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
