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
        XCTAssertEqual(rects[0].rect.w, 500, accuracy: 0.01)
        XCTAssertEqual(rects[1].rect.x, 500, accuracy: 0.01)
        XCTAssertEqual(rects[1].rect.w, 500, accuracy: 0.01)
        XCTAssertEqual(rects[0].rect.h, 800, accuracy: 0.01)
    }

    func testSplitGeometryStacked() {
        var layout = PaneLayout()
        layout.splitFocused(axis: .stacked, newTabID: UUID())

        let rects = layout.leafRects(canvas: canvas)
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].rect.h, 400, accuracy: 0.01)
        XCTAssertEqual(rects[1].rect.y, 400, accuracy: 0.01)
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

        // Drag near the left edge: clamped so the left pane keeps 80pt.
        layout.setRatioFromPoint(splitID: splitID, point: (x: 5, y: 400), canvas: canvas)
        guard case .split(_, _, let ratio, _, _) = layout.root else {
            return XCTFail("expected split root")
        }
        XCTAssertEqual(ratio, 80.0 / 1000.0, accuracy: 0.001)

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
