import Foundation

// =========================================================================
// MARK: - PaneViewStore
//
// Remembers one view per split pane (keyed by leaf ID): which tab and
// which of that tab's drawing views (Model, paper layouts, ...) the pane
// shows, plus the camera for it. The tab tag keeps rebinding honest: a pane
// rebound to another tab falls back to that tab's own `cameraState` and
// active view instead of replaying a stale view.
//
// Policy (enforced by the engine, which owns the live camera):
// - Entries are written only for panes that are (or are becoming)
//   non-focused. The focused pane's view IS the live camera, synced with
//   the tab's active drawing view so editing lands in the right document.
// - Entries are read when a pane gains focus (consumed via `take`) or when
//   a non-focused pane renders (dual view / different tab).
// - A tag mismatch means "no remembered view" — the caller falls back to
//   the tab's active drawing view and its `cameraState`.
// =========================================================================

/// One remembered pane view: tab, drawing-view index, and camera.
public struct PaneViewEntry: Sendable {
    public var tabID: UUID?
    public var viewIndex: Int
    public var state: CameraState

    public init(tabID: UUID?, viewIndex: Int, state: CameraState) {
        self.tabID = tabID
        self.viewIndex = viewIndex
        self.state = state
    }
}

public struct PaneViewStore: Sendable {
    private var entries: [UUID: PaneViewEntry] = [:]

    public init() {}

    /// Remember `state` as `leafID`'s view of `tabID` drawing view
    /// `viewIndex`, replacing any entry.
    public mutating func save(leafID: UUID, tabID: UUID?, viewIndex: Int, state: CameraState) {
        entries[leafID] = PaneViewEntry(tabID: tabID, viewIndex: viewIndex, state: state)
    }

    /// `leafID`'s remembered entry, or nil when none exists or the tag no
    /// longer matches the tab the pane shows.
    public func entry(leafID: UUID, tabID: UUID?) -> PaneViewEntry? {
        guard let entry = entries[leafID], entry.tabID == tabID else { return nil }
        return entry
    }

    /// Consume `leafID`'s remembered entry (focus gain). Only matching tags
    /// are removed and returned; mismatches are left untouched.
    @discardableResult
    public mutating func take(leafID: UUID, tabID: UUID?) -> PaneViewEntry? {
        guard let entry = entries[leafID], entry.tabID == tabID else { return nil }
        entries.removeValue(forKey: leafID)
        return entry
    }

    /// Drop `leafID`'s entry (pane destroyed).
    public mutating func remove(leafID: UUID) {
        entries.removeValue(forKey: leafID)
    }

    /// Number of entries (stale tags included).
    public var count: Int { entries.count }
}
