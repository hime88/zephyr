import XCTest
@testable import ZephyrCore

final class PaneViewStoreTests: XCTestCase {
    private func state(_ zoom: Double) -> CameraState {
        CameraState(offsetX: 1, offsetY: 2, zoom: zoom, rotation: 0)
    }

    func testSaveAndViewRoundTrip() {
        var store = PaneViewStore()
        let leaf = UUID()
        let tab = UUID()
        XCTAssertNil(store.view(leafID: leaf, tabID: tab))
        store.save(leafID: leaf, tabID: tab, state: state(3))
        XCTAssertEqual(store.view(leafID: leaf, tabID: tab)?.zoom, 3)
        XCTAssertEqual(store.count, 1)
    }

    func testTagMismatchFallsBackToNil() {
        var store = PaneViewStore()
        let leaf = UUID()
        store.save(leafID: leaf, tabID: UUID(), state: state(3))
        // Pane rebound to another tab: no remembered view for it.
        XCTAssertNil(store.view(leafID: leaf, tabID: UUID()))
    }

    func testTakeConsumesOnlyOnTagMatch() {
        var store = PaneViewStore()
        let leaf = UUID()
        let tab = UUID()
        store.save(leafID: leaf, tabID: tab, state: state(5))
        XCTAssertNil(store.take(leafID: leaf, tabID: UUID()))
        XCTAssertEqual(store.count, 1)  // mismatch left untouched
        XCTAssertEqual(store.take(leafID: leaf, tabID: tab)?.zoom, 5)
        XCTAssertEqual(store.count, 0)
        XCTAssertNil(store.view(leafID: leaf, tabID: tab))
    }

    func testSaveOverwrites() {
        var store = PaneViewStore()
        let leaf = UUID()
        let tab = UUID()
        store.save(leafID: leaf, tabID: tab, state: state(1))
        store.save(leafID: leaf, tabID: tab, state: state(2))
        XCTAssertEqual(store.view(leafID: leaf, tabID: tab)?.zoom, 2)
        XCTAssertEqual(store.count, 1)
    }

    func testRemoveDropsEntry() {
        var store = PaneViewStore()
        let leaf = UUID()
        let tab = UUID()
        store.save(leafID: leaf, tabID: tab, state: state(1))
        store.remove(leafID: leaf)
        XCTAssertNil(store.view(leafID: leaf, tabID: tab))
        XCTAssertEqual(store.count, 0)
    }

    func testLeavesAreIndependent() {
        var store = PaneViewStore()
        let tab = UUID()
        let a = UUID()
        let b = UUID()
        store.save(leafID: a, tabID: tab, state: state(1))
        store.save(leafID: b, tabID: tab, state: state(9))
        XCTAssertEqual(store.view(leafID: a, tabID: tab)?.zoom, 1)
        XCTAssertEqual(store.view(leafID: b, tabID: tab)?.zoom, 9)
    }
}
