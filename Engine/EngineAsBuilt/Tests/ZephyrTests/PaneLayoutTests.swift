import XCTest
@testable import ZephyrCore

@MainActor
final class PaneLayoutTests: XCTestCase {

    private let canvas = PaneRect(x: 0, y: 0, w: 1000, h: 800)

    private func tabIDs(_ layout: PaneLayout) -> [UUID?] {
        layout.leaves().map {
            if case .leaf(_, let tabID) = $0 { return tabID }
            return nil
        }
    }

    // MARK: - Split

    func testSplitFocusedMovesFocusToNewPane() {
        var layout = PaneLayout()
        let tabA = UUID()
        let tabB = UUID()
        layout.rebindLeaf(layout.focusedLeafID, to: tabA)

        layout.splitFocused(axis: .sideBySide, newTabID: tabB)

        XCTAssertTrue(layout.isSplit)
        XCTAssertEqual(layout.leaves().count, 2)
        XCTAssertEqual(tabIDs(layout), [tabA, tabB])
        XCTAssertEqual(layout.focusedTabID, tabB)
    }

    func testSplitGeometrySideBySide() {
        var layout = PaneLayout()
        layout.splitFocused(axis: .sideBySide, newTabID: UUID())

        let rects = layout.leafRects(canvas: canvas)
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].rect.w, 497, accuracy: 0.01)
        XCTAssertEqual(rects[1].rect.x, 503, accuracy: 0.01)
        XCTAssertEqual(rects[1].rect.w, 497, accuracy: 0.01)
        XCTAssertEqual(rects[0].rect.h, 800, accuracy: 0.01)
    }

    func testSplitGeometryStacked() {
        var layout = PaneLayout()
        layout.splitFocused(axis: .stacked, newTabID: UUID())

        let rects = layout.leafRects(canvas: canvas)
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].rect.h, 397, accuracy: 0.01)
        XCTAssertEqual(rects[1].rect.y, 403, accuracy: 0.01)
    }

    func testVSplitThenHSplitNestsStackedInsideSideBySide() {
        var layout = PaneLayout()
        let tabA = UUID()
        let tabB = UUID()
        let tabC = UUID()
        layout.rebindLeaf(layout.focusedLeafID, to: tabA)
        layout.splitFocused(axis: .sideBySide, newTabID: tabB)
        // Now focused is tabB (the right pane). Split it stacked (HSPLIT).
        layout.splitFocused(axis: .stacked, newTabID: tabC)

        // Root must still be sideBySide, second child must be stacked!
        guard case .split(_, let rootAxis, _, let first, let second) = layout.root else {
            return XCTFail("expected split root")
        }
        XCTAssertEqual(rootAxis, .sideBySide)
        guard case .leaf(_, let leftTab) = first else {
            return XCTFail("expected left leaf")
        }
        XCTAssertEqual(leftTab, tabA)
        guard case .split(_, let childAxis, _, let topChild, let bottomChild) = second else {
            return XCTFail("expected right child to be split")
        }
        XCTAssertEqual(childAxis, .stacked)
        guard case .leaf(_, let topTab) = topChild, case .leaf(_, let bottomTab) = bottomChild else {
            return XCTFail("expected nested leaves")
        }
        XCTAssertEqual(topTab, tabB)
        XCTAssertEqual(bottomTab, tabC)
        XCTAssertEqual(layout.focusedTabID, tabC)
    }

    func testHSplitThenVSplit() {
        var layout = PaneLayout()
        let tabA = UUID()
        let tabB = UUID()
        let tabC = UUID()
        layout.rebindLeaf(layout.focusedLeafID, to: tabA)
        layout.splitFocused(axis: .stacked, newTabID: tabB)
        layout.splitFocused(axis: .sideBySide, newTabID: tabC)

        guard case .split(_, let rootAxis, _, _, let second) = layout.root else {
            return XCTFail("expected split root")
        }
        XCTAssertEqual(rootAxis, .stacked)
        guard case .split(_, let childAxis, _, _, _) = second else {
            return XCTFail("expected bottom child to be split")
        }
        XCTAssertEqual(childAxis, .sideBySide)
        XCTAssertEqual(layout.focusedTabID, tabC)
    }

    func testThreeWayMixedLeafRects() {
        var layout = PaneLayout()
        layout.splitFocused(axis: .sideBySide, newTabID: UUID())
        layout.splitFocused(axis: .stacked, newTabID: UUID())

        let rects = layout.leafRects(canvas: canvas)
        XCTAssertEqual(rects.count, 3)
        // Left pane: (x: 0, y: 0, w: 497, h: 800)
        XCTAssertEqual(rects[0].rect.x, 0, accuracy: 0.01)
        XCTAssertEqual(rects[0].rect.w, 497, accuracy: 0.01)
        XCTAssertEqual(rects[0].rect.h, 800, accuracy: 0.01)
        // Top-right pane: (x: 503, y: 0, w: 497, h: 397)
        XCTAssertEqual(rects[1].rect.x, 503, accuracy: 0.01)
        XCTAssertEqual(rects[1].rect.y, 0, accuracy: 0.01)
        XCTAssertEqual(rects[1].rect.w, 497, accuracy: 0.01)
        XCTAssertEqual(rects[1].rect.h, 397, accuracy: 0.01)
        // Bottom-right pane: (x: 503, y: 403, w: 497, h: 397)
        XCTAssertEqual(rects[2].rect.x, 503, accuracy: 0.01)
        XCTAssertEqual(rects[2].rect.y, 403, accuracy: 0.01)
        XCTAssertEqual(rects[2].rect.w, 497, accuracy: 0.01)
        XCTAssertEqual(rects[2].rect.h, 397, accuracy: 0.01)
    }

    // MARK: - Hit test / focus

    func testHitTestFindsLeaves() {
        var layout = PaneLayout()
        layout.splitFocused(axis: .sideBySide, newTabID: UUID())
        let leaves = layout.leaves()

        let left = layout.hitTest(point: (x: 100, y: 100), canvas: canvas)
        let right = layout.hitTest(point: (x: 900, y: 100), canvas: canvas)
        XCTAssertEqual(left?.id, leaves[0].id)
        XCTAssertEqual(right?.id, leaves[1].id)
        XCTAssertNil(layout.hitTest(point: (x: 2000, y: 100), canvas: canvas))
        // Cut at 500: gutter is x in [497, 503]. Points in the gutter hit neither leaf.
        XCTAssertNil(layout.hitTest(point: (x: 500, y: 100), canvas: canvas))
    }

    func testFocusHealsUnknownID() {
        var layout = PaneLayout()
        layout.focus(id: UUID())
        XCTAssertEqual(layout.focusedLeafID, layout.firstLeaf().id)
    }

    // MARK: - Close / collapse / toggle

    func testCloseFocusedPromotesSibling() {
        var layout = PaneLayout()
        let tabA = UUID()
        let tabB = UUID()
        layout.rebindLeaf(layout.focusedLeafID, to: tabA)
        layout.splitFocused(axis: .sideBySide, newTabID: tabB)
        XCTAssertEqual(layout.focusedTabID, tabB)

        XCTAssertTrue(layout.closeFocused())

        XCTAssertFalse(layout.isSplit)
        XCTAssertEqual(tabIDs(layout), [tabA])
        XCTAssertEqual(layout.focusedTabID, tabA)
    }

    func testCloseLastPaneFails() {
        var layout = PaneLayout()
        XCTAssertFalse(layout.closeFocused())
    }

    func testCollapseAndToggleRoundTrip() {
        var layout = PaneLayout()
        let tabA = UUID()
        let tabB = UUID()
        layout.rebindLeaf(layout.focusedLeafID, to: tabA)
        layout.splitFocused(axis: .stacked, newTabID: tabB)

        XCTAssertTrue(layout.collapseToFocused())
        XCTAssertFalse(layout.isSplit)
        XCTAssertEqual(layout.focusedTabID, tabB)

        XCTAssertTrue(layout.toggle())
        XCTAssertTrue(layout.isSplit)
        XCTAssertEqual(tabIDs(layout), [tabA, tabB])
        XCTAssertEqual(layout.focusedTabID, tabB)
    }

    func testToggleSingleWithoutSavedFails() {
        var layout = PaneLayout()
        XCTAssertFalse(layout.toggle())
    }

    // MARK: - Divider ratios

    func testSetRatioFromPointClampsToMinPane() {
        var layout = PaneLayout()
        layout.splitFocused(axis: .sideBySide, newTabID: UUID())
        guard case .split(let splitID, _, _, _, _) = layout.root else {
            return XCTFail("expected split root")
        }

        // Drag near the left edge: clamped so the left pane keeps minPaneSize (80pt).
        // (minSide = 80 + 3 = 83; 83 / 1000 = 0.083; leaves cut at 83, left pane w = 80).
        layout.setRatioFromPoint(splitID: splitID, point: (x: 5, y: 400), canvas: canvas)
        guard case .split(_, _, let ratio, _, _) = layout.root else {
            return XCTFail("expected split root")
        }
        XCTAssertEqual(ratio, 83.0 / 1000.0, accuracy: 0.001)

        // Drag to 3/4 across.
        layout.setRatioFromPoint(splitID: splitID, point: (x: 750, y: 400), canvas: canvas)
        guard case .split(_, _, let ratio2, _, _) = layout.root else {
            return XCTFail("expected split root")
        }
        XCTAssertEqual(ratio2, 0.75, accuracy: 0.001)
    }

    func testDividersReportHitRects() {
        var layout = PaneLayout()
        layout.splitFocused(axis: .sideBySide, newTabID: UUID())

        let dividers = layout.dividers(canvas: canvas)
        XCTAssertEqual(dividers.count, 1)
        XCTAssertEqual(dividers[0].rect.w, PaneLayout.dividerHitWidth, accuracy: 0.01)
        XCTAssertEqual(dividers[0].rect.h, 800, accuracy: 0.01)
    }

    // MARK: - Equalize & Nudge

    func testEqualizeAllBalancesNestedSplits() {
        var layout = PaneLayout()
        _ = layout.splitFocused(axis: .sideBySide, newTabID: UUID())
        _ = layout.splitFocused(axis: .sideBySide, newTabID: UUID())
        // Currently A is 0.5, and the right side is split 0.5/0.5 of 0.5 -> 0.25 each.
        // Equalize should make root ratio 1/3 (0.333...) so all three columns have equal span.
        layout.equalizeAll()
        guard case .split(_, _, let rootRatio, _, let second) = layout.root else {
            return XCTFail("expected split root")
        }
        XCTAssertEqual(rootRatio, 1.0 / 3.0, accuracy: 0.001)
        guard case .split(_, _, let childRatio, _, _) = second else {
            return XCTFail("expected child split")
        }
        XCTAssertEqual(childRatio, 0.5, accuracy: 0.001)
    }

    func testNudgeFocusedMovesDivider() {
        var layout = PaneLayout()
        layout.splitFocused(axis: .sideBySide, newTabID: UUID())
        let beforeRatio = layout.ratio(of: layout.ancestorSplits(of: layout.focusedLeafID)[0].id)!
        XCTAssertEqual(beforeRatio, 0.5, accuracy: 0.001)

        XCTAssertTrue(layout.nudgeFocused(.right, step: 0.1, canvas: canvas))
        let afterRatio = layout.ratio(of: layout.ancestorSplits(of: layout.focusedLeafID)[0].id)!
        XCTAssertEqual(afterRatio, 0.6, accuracy: 0.001)

        XCTAssertTrue(layout.nudgeFocused(.left, step: 0.1, canvas: canvas))
        let backRatio = layout.ratio(of: layout.ancestorSplits(of: layout.focusedLeafID)[0].id)!
        XCTAssertEqual(backRatio, 0.5, accuracy: 0.001)
    }

    func testResizeFocusedGrowsAndShrinks() {
        var layout = PaneLayout()
        layout.splitFocused(axis: .sideBySide, newTabID: UUID())
        // focused is right pane (leafInFirst: false).
        // Growing by +0.1 should shrink the first pane (ratio decreases from 0.5 to 0.4).
        XCTAssertTrue(layout.resizeFocused(by: 0.1, canvas: canvas))
        let ratio = layout.ratio(of: layout.ancestorSplits(of: layout.focusedLeafID)[0].id)!
        XCTAssertEqual(ratio, 0.4, accuracy: 0.001)
    }

    // MARK: - Rebind

    func testRebindAllRetargetsMatchingLeaves() {
        var layout = PaneLayout()
        let tabA = UUID()
        let tabB = UUID()
        let tabC = UUID()
        layout.rebindLeaf(layout.focusedLeafID, to: tabA)
        layout.splitFocused(axis: .sideBySide, newTabID: tabB)
        // Show tabA in both panes, then float it away.
        layout.rebindAll(from: tabB, to: tabA)
        layout.rebindAll(from: tabA, to: tabC)

        XCTAssertEqual(tabIDs(layout), [tabC, tabC])
    }
}
