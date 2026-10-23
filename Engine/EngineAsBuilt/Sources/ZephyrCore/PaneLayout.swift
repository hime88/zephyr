import Foundation

// =========================================================================
// MARK: - Pane Tree
// =========================================================================

/// Split direction. `.sideBySide` matches AutoCAD `VPORTS 2 Vertical` (a
/// vertical divider, panes left/right); `.stacked` matches `2 Horizontal`.
public enum PaneSplitAxis {
    case sideBySide
    case stacked
}

/// Arrow direction for keyboard divider nudges.
public enum PaneNudgeDirection {
    case left, right, up, down
}

/// Float rectangle in window points.
public struct PaneRect {
    public var x: Float
    public var y: Float
    public var w: Float
    public var h: Float

    public init(x: Float, y: Float, w: Float, h: Float) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public var minX: Float { x }
    public var minY: Float { y }
    public var maxX: Float { x + w }
    public var maxY: Float { y + h }

    public func contains(x px: Float, y py: Float) -> Bool {
        px >= minX && px < maxX && py >= minY && py < maxY
    }
}

/// One node of the main window's pane tree. Leaves show tabs (`tabID` nil
/// renders an empty pane); splits divide their rect between two children.
public indirect enum PaneNode {
    case leaf(id: UUID, tabID: UUID?)
    case split(id: UUID, axis: PaneSplitAxis, ratio: Float, first: PaneNode, second: PaneNode)

    public var id: UUID {
        switch self {
        case .leaf(let id, _): return id
        case .split(let id, _, _, _, _): return id
        }
    }
}

// =========================================================================
// MARK: - PaneLayout
// =========================================================================

/// The main window's split-pane arrangement: a binary tree plus focus state.
/// Pure value type (no engine references) so geometry and structure stay
/// unit-testable. Tab-assignment policy lives on the engine.
public struct PaneLayout {
    /// Visible gap between sibling panes in points. Leaves are inset by half
    /// of it on each side of a cut, so pane boundaries are always visible.
    public static let gutterWidth: Float = 6
    /// Hit width of dividers in points: the gutter plus a little slop on
    /// each side so the strip is easy to grab.
    public static let dividerHitWidth: Float = 10
    /// Minimum pane width/height in points.
    public static let minPaneSize: Float = 80
    /// Default step for keyboard divider nudges (fraction of the split).
    public static let nudgeStep: Float = 0.05

    public var root: PaneNode
    public var focusedLeafID: UUID
    /// Last multi-pane arrangement, for TOGGLE / VPMAX restore.
    public var savedTree: (root: PaneNode, focusedLeafID: UUID)? = nil

    public init() {
        let id = UUID()
        self.root = .leaf(id: id, tabID: nil)
        self.focusedLeafID = id
    }

    /// True while the canvas is divided (a single leaf uses the legacy path).
    public var isSplit: Bool {
        if case .split = root { return true }
        return false
    }

    /// Tab shown in the focused pane (nil when empty or focus is stale).
    public var focusedTabID: UUID? {
        guard case .leaf(_, let tabID) = findLeaf(id: focusedLeafID) else { return nil }
        return tabID
    }

    // MARK: Queries

    public func findLeaf(id: UUID) -> PaneNode? {
        findLeaf(id: id, in: root)
    }

    private func findLeaf(id: UUID, in node: PaneNode) -> PaneNode? {
        switch node {
        case .leaf(let leafID, _):
            return leafID == id ? node : nil
        case .split(_, _, _, let first, let second):
            return findLeaf(id: id, in: first) ?? findLeaf(id: id, in: second)
        }
    }

    /// First leaf (in-order) showing a tab, or nil when not visible.
    public func findLeaf(showing tabID: UUID) -> PaneNode? {
        findLeaf(showing: tabID, in: root)
    }

    private func findLeaf(showing tabID: UUID, in node: PaneNode) -> PaneNode? {
        switch node {
        case .leaf(_, let shown):
            return shown == tabID ? node : nil
        case .split(_, _, _, let first, let second):
            return findLeaf(showing: tabID, in: first) ?? findLeaf(showing: tabID, in: second)
        }
    }

    /// First leaf in in-order traversal (never nil).
    public func firstLeaf() -> PaneNode {
        var node = root
        while case .split(_, _, _, let first, _) = node {
            node = first
        }
        return node
    }

    /// All leaves in in-order traversal.
    public func leaves() -> [PaneNode] {
        var out: [PaneNode] = []
        collectLeaves(root, into: &out)
        return out
    }

    private func collectLeaves(_ node: PaneNode, into out: inout [PaneNode]) {
        switch node {
        case .leaf:
            out.append(node)
        case .split(_, _, _, let first, let second):
            collectLeaves(first, into: &out)
            collectLeaves(second, into: &out)
        }
    }

    /// Screen rect of every leaf within `canvas`.
    public func leafRects(canvas: PaneRect) -> [(id: UUID, tabID: UUID?, rect: PaneRect)] {
        var out: [(id: UUID, tabID: UUID?, rect: PaneRect)] = []
        collectLeafRects(root, rect: canvas, into: &out)
        return out
    }

    private func collectLeafRects(
        _ node: PaneNode, rect: PaneRect,
        into out: inout [(id: UUID, tabID: UUID?, rect: PaneRect)]
    ) {
        switch node {
        case .leaf(let id, let tabID):
            out.append((id, tabID, rect))
        case .split(_, let axis, let ratio, let first, let second):
            let (a, b) = splitRects(rect: rect, axis: axis, ratio: ratio)
            collectLeafRects(first, rect: a, into: &out)
            collectLeafRects(second, rect: b, into: &out)
        }
    }

    /// Child rects of a split. The cut sits at `ratio` of the extent and the
    /// gutter is carved symmetrically around it.
    private func splitRects(rect: PaneRect, axis: PaneSplitAxis, ratio: Float) -> (PaneRect, PaneRect) {
        let r = max(0.01, min(0.99, ratio))
        switch axis {
        case .sideBySide:
            let cut = rect.w * r
            let half = min(Self.gutterWidth * 0.5, cut, rect.w - cut)
            return (
                PaneRect(x: rect.x, y: rect.y, w: cut - half, h: rect.h),
                PaneRect(x: rect.x + cut + half, y: rect.y, w: rect.w - cut - half, h: rect.h))
        case .stacked:
            let cut = rect.h * r
            let half = min(Self.gutterWidth * 0.5, cut, rect.h - cut)
            return (
                PaneRect(x: rect.x, y: rect.y, w: rect.w, h: cut - half),
                PaneRect(x: rect.x, y: rect.y + cut + half, w: rect.w, h: rect.h - cut - half))
        }
    }

    /// Hit rect of every divider within `canvas`: split ID, rect, axis.
    public func dividers(canvas: PaneRect) -> [(id: UUID, rect: PaneRect, axis: PaneSplitAxis)] {
        var out: [(id: UUID, rect: PaneRect, axis: PaneSplitAxis)] = []
        collectDividers(root, rect: canvas, into: &out)
        return out
    }

    private func collectDividers(
        _ node: PaneNode, rect: PaneRect,
        into out: inout [(id: UUID, rect: PaneRect, axis: PaneSplitAxis)]
    ) {
        guard case .split(let id, let axis, let ratio, let first, let second) = node else { return }
        let half = Self.dividerHitWidth * 0.5
        switch axis {
        case .sideBySide:
            let cutX = rect.x + rect.w * max(0.01, min(0.99, ratio))
            out.append((id, PaneRect(x: cutX - half, y: rect.y, w: half * 2, h: rect.h), axis))
        case .stacked:
            let cutY = rect.y + rect.h * max(0.01, min(0.99, ratio))
            out.append((id, PaneRect(x: rect.x, y: cutY - half, w: rect.w, h: half * 2), axis))
        }
        let (a, b) = splitRects(rect: rect, axis: axis, ratio: ratio)
        collectDividers(first, rect: a, into: &out)
        collectDividers(second, rect: b, into: &out)
    }

    /// Leaf containing a window point, or nil when outside the canvas or in
    /// a gutter between panes (gutters belong to the divider widgets).
    public func hitTest(point: (x: Float, y: Float), canvas: PaneRect) -> PaneNode? {
        guard canvas.contains(x: point.x, y: point.y) else { return nil }
        return hitTest(point: point, node: root, rect: canvas)
    }

    private func hitTest(point: (x: Float, y: Float), node: PaneNode, rect: PaneRect) -> PaneNode? {
        switch node {
        case .leaf:
            return node
        case .split(_, let axis, let ratio, let first, let second):
            let (a, b) = splitRects(rect: rect, axis: axis, ratio: ratio)
            if a.contains(x: point.x, y: point.y) {
                return hitTest(point: point, node: first, rect: a)
            }
            if b.contains(x: point.x, y: point.y) {
                return hitTest(point: point, node: second, rect: b)
            }
            return nil
        }
    }

    // MARK: Focus

    /// Focus a leaf (unknown IDs heal to the first leaf).
    public mutating func focus(id: UUID) {
        focusedLeafID = findLeaf(id: id) != nil ? id : firstLeaf().id
    }

    /// The tab a leaf shows (nil for empty leaves and unknown IDs).
    public func tabID(of leafID: UUID) -> UUID? {
        guard case .leaf(_, let tabID) = findLeaf(id: leafID) else { return nil }
        return tabID
    }

    // MARK: Structure

    /// Split the focused leaf (or first leaf when focus is stale). The
    /// original keeps its tab; the new pane shows `newTabID`. Focus moves
    /// to the new pane so the next tab click retargets it.
    /// - Returns: The new leaf's ID (now focused).
    @discardableResult
    public mutating func splitFocused(axis: PaneSplitAxis, newTabID: UUID?) -> UUID {
        let targetID = findLeaf(id: focusedLeafID) != nil ? focusedLeafID : firstLeaf().id
        let newLeafID = UUID()
        root = split(node: root, targetID: targetID, axis: axis, newLeafID: newLeafID, newTabID: newTabID)
        focusedLeafID = newLeafID
        return newLeafID
    }

    /// Recursively split `targetID` along `newAxis`. Existing splits keep
    /// their own axis (`nodeAxis`); the two names must stay distinct — when
    /// the binding shadowed the parameter, every split below the root
    /// inherited its parent's axis (VSPLIT then HSPLIT split side-by-side).
    private func split(
        node: PaneNode, targetID: UUID, axis newAxis: PaneSplitAxis,
        newLeafID: UUID, newTabID: UUID?
    ) -> PaneNode {
        switch node {
        case .leaf(let id, let tabID) where id == targetID:
            return .split(
                id: UUID(), axis: newAxis, ratio: 0.5,
                first: .leaf(id: id, tabID: tabID),
                second: .leaf(id: newLeafID, tabID: newTabID))
        case .split(let id, let nodeAxis, let ratio, let first, let second):
            return .split(
                id: id, axis: nodeAxis, ratio: ratio,
                first: split(node: first, targetID: targetID, axis: newAxis, newLeafID: newLeafID, newTabID: newTabID),
                second: split(node: second, targetID: targetID, axis: newAxis, newLeafID: newLeafID, newTabID: newTabID))
        case .leaf:
            return node
        }
    }

    /// Close the focused leaf, promoting its sibling (AutoCAD `JOIN`).
    /// Focus moves to the promoted subtree's first leaf.
    /// - Returns: False when there is only one pane.
    @discardableResult
    public mutating func closeFocused() -> Bool {
        guard isSplit else { return false }
        let targetID = findLeaf(id: focusedLeafID) != nil ? focusedLeafID : firstLeaf().id
        guard let (updated, promoted) = close(node: root, targetID: targetID) else { return false }
        root = updated
        focusedLeafID = firstLeafID(of: promoted)
        return true
    }

    /// Remove `targetID`, returning the replacement subtree plus the promoted
    /// sibling (for focus). Nil when the target is not below `node`.
    private func close(node: PaneNode, targetID: UUID) -> (PaneNode, PaneNode)? {
        guard case .split(let id, let axis, let ratio, let first, let second) = node else {
            return nil  // leaves are removed by their parent
        }
        if isLeaf(first, id: targetID) { return (second, second) }
        if isLeaf(second, id: targetID) { return (first, first) }
        if let (updatedFirst, promoted) = close(node: first, targetID: targetID) {
            return (.split(id: id, axis: axis, ratio: ratio, first: updatedFirst, second: second), promoted)
        }
        if let (updatedSecond, promoted) = close(node: second, targetID: targetID) {
            return (.split(id: id, axis: axis, ratio: ratio, first: first, second: updatedSecond), promoted)
        }
        return nil
    }

    private func isLeaf(_ node: PaneNode, id: UUID) -> Bool {
        if case .leaf(let leafID, _) = node, leafID == id { return true }
        return false
    }

    private func firstLeafID(of node: PaneNode) -> UUID {
        var current = node
        while case .split(_, _, _, let first, _) = current {
            current = first
        }
        return current.id
    }

    /// Collapse to the focused pane's tab, saving the tree for TOGGLE/VPMIN.
    /// - Returns: False when already single.
    @discardableResult
    public mutating func collapseToFocused() -> Bool {
        guard isSplit else { return false }
        savedTree = (root, focusedLeafID)
        let tabID = focusedTabID
        let id = UUID()
        root = .leaf(id: id, tabID: tabID)
        focusedLeafID = id
        return true
    }

    /// Toggle between single and the last multi-pane arrangement.
    /// - Returns: False when single with nothing saved.
    @discardableResult
    public mutating func toggle() -> Bool {
        if isSplit {
            return collapseToFocused()
        }
        guard let saved = savedTree else { return false }
        root = saved.root
        focusedLeafID = findLeaf(id: saved.focusedLeafID) != nil ? saved.focusedLeafID : firstLeaf().id
        return true
    }

    /// Move a divider so its cut passes through `point`, clamped to the
    /// minimum pane size. Canvas is the FULL canvas (ratios are relative to
    /// each split's own rect, resolved by walking the tree).
    public mutating func setRatioFromPoint(splitID: UUID, point: (x: Float, y: Float), canvas: PaneRect) {
        root = updateRatio(node: root, splitID: splitID, rect: canvas) { axis, rect, _ in
            switch axis {
            case .sideBySide: return (point.x - rect.x) / rect.w
            case .stacked: return (point.y - rect.y) / rect.h
            }
        }
    }

    /// Set a split's ratio directly (e.g. double-click reset to 0.5),
    /// clamped to the minimum pane size within `canvas`.
    public mutating func setRatio(splitID: UUID, ratio: Float, canvas: PaneRect) {
        root = updateRatio(node: root, splitID: splitID, rect: canvas) { _, _, _ in ratio }
    }

    /// Current ratio of a split (nil for unknown IDs).
    public func ratio(of splitID: UUID) -> Float? {
        ratio(of: splitID, in: root)
    }

    private func ratio(of splitID: UUID, in node: PaneNode) -> Float? {
        guard case .split(let id, _, let ratio, let first, let second) = node else { return nil }
        if id == splitID { return ratio }
        return self.ratio(of: splitID, in: first) ?? self.ratio(of: splitID, in: second)
    }

    /// Walk to `splitID` tracking its rect, then replace its ratio with
    /// `compute(axis, rect, currentRatio)` clamped so both sides keep at
    /// least `minPaneSize` (plus their half of the gutter).
    private func updateRatio(
        node: PaneNode, splitID: UUID, rect: PaneRect,
        _ compute: (PaneSplitAxis, PaneRect, Float) -> Float
    ) -> PaneNode {
        guard case .split(let id, let axis, let ratio, let first, let second) = node else {
            return node
        }
        if id == splitID {
            let total: Float = axis == .sideBySide ? rect.w : rect.h
            let minSide = Self.minPaneSize + Self.gutterWidth * 0.5
            guard total > minSide * 2 else { return node }
            let lo = minSide / total
            let clamped = max(lo, min(1 - lo, compute(axis, rect, ratio)))
            return .split(id: id, axis: axis, ratio: clamped, first: first, second: second)
        }
        let (a, b) = splitRects(rect: rect, axis: axis, ratio: ratio)
        return .split(
            id: id, axis: axis, ratio: ratio,
            first: updateRatio(node: first, splitID: splitID, rect: a, compute),
            second: updateRatio(node: second, splitID: splitID, rect: b, compute))
    }

    // MARK: Equalize / nudge

    /// Give every pane an equal share along each run of same-axis splits
    /// (`A | B | C` → thirds; `A | (B / C)` → halves both ways).
    public mutating func equalizeAll() {
        root = equalize(root)
    }

    private func equalize(_ node: PaneNode) -> PaneNode {
        guard case .split(let id, let axis, _, let first, let second) = node else { return node }
        let a = Float(span(first, along: axis))
        let b = Float(span(second, along: axis))
        return .split(
            id: id, axis: axis, ratio: a / (a + b),
            first: equalize(first), second: equalize(second))
    }

    /// Number of panes laid out side by side along `axis` within `node`.
    private func span(_ node: PaneNode, along axis: PaneSplitAxis) -> Int {
        if case .split(_, let nodeAxis, _, let first, let second) = node, nodeAxis == axis {
            return span(first, along: axis) + span(second, along: axis)
        }
        return 1
    }

    /// Splits from the root down to `leafID`, each with the side the leaf is
    /// on. Empty when the leaf is the root or unknown.
    public func ancestorSplits(of leafID: UUID)
        -> [(id: UUID, axis: PaneSplitAxis, ratio: Float, leafInFirst: Bool)]
    {
        var path: [(id: UUID, axis: PaneSplitAxis, ratio: Float, leafInFirst: Bool)] = []
        _ = collectAncestors(root, leafID: leafID, into: &path)
        return path
    }

    private func collectAncestors(
        _ node: PaneNode, leafID: UUID,
        into path: inout [(id: UUID, axis: PaneSplitAxis, ratio: Float, leafInFirst: Bool)]
    ) -> Bool {
        switch node {
        case .leaf(let id, _):
            return id == leafID
        case .split(let id, let axis, let ratio, let first, let second):
            path.append((id, axis, ratio, true))
            if collectAncestors(first, leafID: leafID, into: &path) { return true }
            path[path.count - 1].leafInFirst = false
            if collectAncestors(second, leafID: leafID, into: &path) { return true }
            path.removeLast()
            return false
        }
    }

    /// Move the divider nearest the focused pane on the arrow's axis by
    /// `step` (fraction of that split) in the arrow's direction.
    /// - Returns: False when no ancestor split runs along that axis.
    @discardableResult
    public mutating func nudgeFocused(
        _ direction: PaneNudgeDirection, step: Float = PaneLayout.nudgeStep, canvas: PaneRect
    ) -> Bool {
        let axis: PaneSplitAxis = (direction == .left || direction == .right) ? .sideBySide : .stacked
        guard let split = ancestorSplits(of: focusedLeafID).last(where: { $0.axis == axis }) else {
            return false
        }
        let sign: Float = (direction == .right || direction == .down) ? 1 : -1
        setRatio(splitID: split.id, ratio: split.ratio + sign * step, canvas: canvas)
        return true
    }

    /// Grow (positive) or shrink (negative) the focused pane along its
    /// immediate parent split by `delta` (fraction of that split).
    /// - Returns: False when the layout is not split.
    @discardableResult
    public mutating func resizeFocused(by delta: Float, canvas: PaneRect) -> Bool {
        guard let split = ancestorSplits(of: focusedLeafID).last else { return false }
        let ratio = split.leafInFirst ? split.ratio + delta : split.ratio - delta
        setRatio(splitID: split.id, ratio: ratio, canvas: canvas)
        return true
    }

    // MARK: Tab assignment

    /// Show `tabID` in one leaf (unknown IDs ignored).
    public mutating func rebindLeaf(_ leafID: UUID, to tabID: UUID?) {
        root = rebind(node: root, leafID: leafID, tabID: tabID)
    }

    private func rebind(node: PaneNode, leafID: UUID, tabID: UUID?) -> PaneNode {
        switch node {
        case .leaf(let id, _) where id == leafID:
            return .leaf(id: id, tabID: tabID)
        case .split(let id, let axis, let ratio, let first, let second):
            return .split(
                id: id, axis: axis, ratio: ratio,
                first: rebind(node: first, leafID: leafID, tabID: tabID),
                second: rebind(node: second, leafID: leafID, tabID: tabID))
        case .leaf:
            return node
        }
    }

    /// Retarget every leaf showing `old` (used when a tab floats or closes).
    public mutating func rebindAll(from old: UUID, to new: UUID?) {
        root = rebindAll(node: root, from: old, to: new)
    }

    private func rebindAll(node: PaneNode, from old: UUID, to new: UUID?) -> PaneNode {
        switch node {
        case .leaf(let id, let tabID) where tabID == old:
            return .leaf(id: id, tabID: new)
        case .split(let id, let axis, let ratio, let first, let second):
            return .split(
                id: id, axis: axis, ratio: ratio,
                first: rebindAll(node: first, from: old, to: new),
                second: rebindAll(node: second, from: old, to: new))
        case .leaf:
            return node
        }
    }
}
