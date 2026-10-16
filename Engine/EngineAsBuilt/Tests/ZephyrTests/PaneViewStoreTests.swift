import XCTest
@testable import ZephyrCore

final class PaneViewStoreTests: XCTestCase {
    private func state(_ zoom: Double) -> CameraState {
        CameraState(offsetX: 1, offsetY: 2, zoom: zoom, rotation: 0)
    }

    func testSaveAndEntryRoundTrip() {
        var store = PaneViewStore()
        let leaf = UUID()
        let tab = UUID()
        XCTAssertNil(store.entry(leafID: leaf, tabID: tab))
        store.save(leafID: leaf, tabID: tab, viewIndex: 2, state: state(3))
        let entry = store.entry(leafID: leaf, tabID: tab)
        XCTAssertEqual(entry?.state.zoom, 3)
        XCTAssertEqual(entry?.viewIndex, 2)
        XCTAssertEqual(store.count, 1)
    }

    func testTagMismatchFallsBackToNil() {
        var store = PaneViewStore()
        let leaf = UUID()
        store.save(leafID: leaf, tabID: UUID(), viewIndex: 0, state: state(3))
        // Pane rebound to another tab: no remembered view for it.
        XCTAssertNil(store.entry(leafID: leaf, tabID: UUID()))
    }

    func testTakeConsumesOnlyOnTagMatch() {
        var store = PaneViewStore()
        let leaf = UUID()
        let tab = UUID()
        store.save(leafID: leaf, tabID: tab, viewIndex: 1, state: state(5))
        XCTAssertNil(store.take(leafID: leaf, tabID: UUID()))
        XCTAssertEqual(store.count, 1)  // mismatch left untouched
        let taken = store.take(leafID: leaf, tabID: tab)
        XCTAssertEqual(taken?.state.zoom, 5)
        XCTAssertEqual(taken?.viewIndex, 1)
        XCTAssertEqual(store.count, 0)
        XCTAssertNil(store.entry(leafID: leaf, tabID: tab))
    }

    func testSaveOverwrites() {
        var store = PaneViewStore()
        let leaf = UUID()
        let tab = UUID()
        store.save(leafID: leaf, tabID: tab, viewIndex: 0, state: state(1))
        store.save(leafID: leaf, tabID: tab, viewIndex: 3, state: state(2))
        let entry = store.entry(leafID: leaf, tabID: tab)
        XCTAssertEqual(entry?.state.zoom, 2)
        XCTAssertEqual(entry?.viewIndex, 3)
        XCTAssertEqual(store.count, 1)
    }

    func testRemoveDropsEntry() {
        var store = PaneViewStore()
        let leaf = UUID()
        let tab = UUID()
        store.save(leafID: leaf, tabID: tab, viewIndex: 0, state: state(1))
        store.remove(leafID: leaf)
        XCTAssertNil(store.entry(leafID: leaf, tabID: tab))
        XCTAssertEqual(store.count, 0)
    }

    func testLeavesAreIndependent() {
        var store = PaneViewStore()
        let tab = UUID()
        let a = UUID()
        let b = UUID()
        // Same tab, different drawing views and cameras per pane.
        store.save(leafID: a, tabID: tab, viewIndex: 0, state: state(1))
        store.save(leafID: b, tabID: tab, viewIndex: 2, state: state(9))
        XCTAssertEqual(store.entry(leafID: a, tabID: tab)?.viewIndex, 0)
        XCTAssertEqual(store.entry(leafID: a, tabID: tab)?.state.zoom, 1)
        XCTAssertEqual(store.entry(leafID: b, tabID: tab)?.viewIndex, 2)
        XCTAssertEqual(store.entry(leafID: b, tabID: tab)?.state.zoom, 9)
    }
}
