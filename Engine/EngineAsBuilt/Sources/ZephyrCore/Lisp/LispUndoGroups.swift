import Foundation

// =========================================================================
// MARK: - Undo Groups (AutoCAD UNDO Begin/End parity)
// =========================================================================
//
// AutoLISP scripts — and interactive users — can bracket a sequence of
// commands between UNDO Begin and UNDO End so the whole sequence undoes as
// one step. `UndoManager` only knows single snapshot pushes, so this
// extension adds the group stack:
//
// * `beginUndoGroup()` / `endUndoGroup()` nest; pushes made while a group
//   is open coalesce into a single stack entry (the pre-group state).
// * `markUndo()` / `backToUndoMark(_:currentSnapshot:)` implement the
//   UNDO Mark / UNDO Back options.
// * `discardOpenUndoGroups()` drops uncommitted group state when a script
//   aborts mid-group (*error* unwind).
//
// A group that is still open at end of script is auto-closed with a
// warning by the Lisp driver (AutoCAD behavior for this case is
// undocumented; auto-close preserves the coalescing the script asked for).
extension UndoManager {

    // MARK: - Group state

    /// Number of currently open UNDO groups (Begin without matching End).
    public var undoGroupDepth: Int { undoLock.withLock { _undoGroupDepth } }

    /// UNDOCTL bit 0: 1 while a group is open, 0 otherwise.
    /// (Higher AutoCAD UNDOCTL bits describe XREF/zoom state Zephyr has no
    /// equivalent for and always read 0.)
    public var undoControlFlags: Int { undoLock.withLock { _undoGroupDepth > 0 ? 1 : 0 } }

    /// Open an UNDO group. Groups nest; only the outermost End commits.
    public func beginUndoGroup() {
        undoLock.withLock { _undoGroupDepth += 1 }
    }

    /// Close the most recently opened UNDO group.
    ///
    /// When the outermost group closes, the pre-group state captured by the
    /// first push inside the group is committed as a single undo entry and
    /// all intermediate pushes are discarded. A group with no pushes
    /// commits nothing.
    ///
    /// - Returns: `true` if a group was closed, `false` for an unmatched
    ///   End (AutoCAD prints "No group to end" and continues).
    @discardableResult
    public func endUndoGroup() -> Bool {
        undoLock.withLock {
            guard _undoGroupDepth > 0 else { return false }
            _undoGroupDepth -= 1
            if _undoGroupDepth == 0, let first = _pendingGroupSnapshot {
                _pendingGroupSnapshot = nil
                pushUndo(first)
            }
            return true
        }
    }

    /// Route a snapshot push through the group machinery.
    ///
    /// Outside a group this is exactly `pushUndo`. Inside a group only the
    /// first pre-state is retained; later pushes are dropped because the
    /// coalesced entry restores the pre-group state directly.
    public func pushUndoGrouped(_ snapshot: CADDocumentSnapshot) {
        undoLock.withLock {
            if _undoGroupDepth > 0 {
                if _pendingGroupSnapshot == nil {
                    _pendingGroupSnapshot = snapshot
                }
            } else {
                pushUndo(snapshot)
            }
        }
    }

    /// Abandon all open groups and their uncommitted state.
    ///
    /// Used on abnormal script termination (*error* unwind, Esc cancel):
    /// the pre-group pre-state is dropped so a half-run script cannot leave
    /// a dangling group behind. Committed stack entries are untouched.
    public func discardOpenUndoGroups() {
        undoLock.withLock {
            _undoGroupDepth = 0
            _pendingGroupSnapshot = nil
        }
    }

    // MARK: - Mark / Back

    /// Record the current undo position for a later `backToUndoMark`.
    ///
    /// The mark counts an uncommitted open group as one entry, matching
    /// what `undoDepth` will read once the group closes.
    public func markUndo() -> Int {
        undoLock.withLock {
            undoDepth + (_pendingGroupSnapshot == nil ? 0 : 1)
        }
    }

    /// Undo back to a position previously recorded with `markUndo`.
    ///
    /// Open groups are auto-closed first (their pending entry commits),
    /// then entries are popped onto the redo stack until the marked depth
    /// is reached. Redo order after a Back re-applies commands oldest-first,
    /// matching AutoCAD.
    ///
    /// - Returns: The snapshot to restore (the state at the mark), or `nil`
    ///   if `mark` is out of range (negative, or beyond current depth).
    public func backToUndoMark(_ mark: Int, currentSnapshot: CADDocumentSnapshot) -> CADDocumentSnapshot? {
        undoLock.withLock {
            // Commit any open group first so the mark arithmetic is exact.
            while _undoGroupDepth > 0 { endUndoGroup() }
            guard mark >= 0, mark <= undoStackCountForLisp else { return nil }
            var current = currentSnapshot
            var restored: CADDocumentSnapshot? = currentSnapshot
            while undoStackCountForLisp > mark {
                guard let previous = popUndo(currentSnapshot: current) else { return nil }
                current = previous
                restored = previous
            }
            return restored
        }
    }
}

// MARK: - Private helpers

extension UndoManager {
    fileprivate var undoStackCountForLisp: Int { undoDepth }
}
