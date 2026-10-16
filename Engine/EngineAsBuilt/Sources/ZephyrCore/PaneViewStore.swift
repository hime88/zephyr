import Foundation

// =========================================================================
// MARK: - PaneViewStore
//
// Remembers one camera view per split pane (keyed by leaf ID), tagged with
// the tab the pane showed when the view was saved. The tag keeps rebinding
// honest: a pane rebound to another tab falls back to that tab's own
// `cameraState` instead of replaying a stale view.
//
// Policy (enforced by the engine, which owns the live camera):
// - Entries are written only for panes that are (or are becoming)
//   non-focused. The focused pane's view IS the live camera.
// - Entries are read when a pane gains focus (consumed via `take`) or when
//   a non-focused pane showing the active tab renders (dual view).
// - A tag mismatch means "no remembered view" — the caller falls back to
//   the tab's `cameraState` (inactive tab) or keeps the live camera.
// =========================================================================

/// One remembered pane view: the tab it belongs to plus the camera.
public struct PaneViewEntry: Sendable {
    public var tabID: UUID?
    public var state: CameraState

    public init(tabID: UUID?, state: CameraState) {
        self.tabID = tabID
        self.state = state
    }
}

public struct PaneViewStore: Sendable {
    private var entries: [UUID: PaneViewEntry] = [:]

    public init() {}

    /// Remember `state` as `leafID`'s view of `tabID`, replacing any entry.
    public mutating func save(leafID: UUID, tabID: UUID?, state: CameraState) {
        entries[leafID] = PaneViewEntry(tabID: tabID, state: state)
    }

    /// `leafID`'s remembered view, or nil when none exists or the tag no
    /// longer matches the tab the pane shows.
    public func view(leafID: UUID, tabID: UUID?) -> CameraState? {
        guard let entry = entries[leafID], entry.tabID == tabID else { return nil }
        return entry.state
    }

    /// Consume `leafID`'s remembered view (focus gain). Only matching tags
    /// are removed and returned; mismatches are left untouched.
    @discardableResult
    public mutating func take(leafID: UUID, tabID: UUID?) -> CameraState? {
        guard let entry = entries[leafID], entry.tabID == tabID else { return nil }
        entries.removeValue(forKey: leafID)
        return entry.state
    }

    /// Drop `leafID`'s entry (pane destroyed).
    public mutating func remove(leafID: UUID) {
        entries.removeValue(forKey: leafID)
    }

    /// Number of entries (stale tags included).
    public var count: Int { entries.count }
}
