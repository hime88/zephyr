import XCTest
@testable import ZephyrCore

final class DrawingViewTabBarPolicyTests: XCTestCase {
    func testRendersOnlyForShownTabWithMultipleViewsOutsideBlockEditor() {
        XCTAssertFalse(DrawingViewTabBarPolicy.shouldRender(
            shownTabViewCount: 1,
            isEditingBlock: false
        ))
        XCTAssertFalse(DrawingViewTabBarPolicy.shouldRender(
            shownTabViewCount: 3,
            isEditingBlock: true
        ))
        XCTAssertTrue(DrawingViewTabBarPolicy.shouldRender(
            shownTabViewCount: 3,
            isEditingBlock: false
        ))
    }

    func testSelectedViewIndexIsClampedToShownTabViews() {
        XCTAssertEqual(DrawingViewTabBarPolicy.clampedViewIndex(-2, viewCount: 3), 0)
        XCTAssertEqual(DrawingViewTabBarPolicy.clampedViewIndex(1, viewCount: 3), 1)
        XCTAssertEqual(DrawingViewTabBarPolicy.clampedViewIndex(9, viewCount: 3), 2)
        XCTAssertEqual(DrawingViewTabBarPolicy.clampedViewIndex(9, viewCount: 0), 0)
    }

    @MainActor
    func testModelAndLayoutSelectionIsIndependentPerDocumentTab() throws {
        func makeDocument(layerName: String) -> CADDocument {
            let document = CADDocument()
            document.importLayersBlocksEntities(
                layers: [Layer(name: layerName, color: .white)],
                blocks: [],
                entities: [])
            return document
        }
        func writeTwoViewEAB(prefix: String) throws -> URL {
            let snapshots = [
                makeDocument(layerName: "\(prefix)Model").buildSaveSnapshot(
                    viewName: "Model", viewKind: .model, cameraState: .default),
                makeDocument(layerName: "\(prefix)Layout").buildSaveSnapshot(
                    viewName: "Layout1", viewKind: .sheet, cameraState: .default),
            ]
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(prefix)_\(UUID().uuidString).eab")
            try EABWriter.write(snapshots: snapshots, to: url)
            return url
        }

        let urlA = try writeTwoViewEAB(prefix: "A")
        let urlB = try writeTwoViewEAB(prefix: "B")
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }

        let manager = TabManager()
        let indexA = try manager.openEAB(url: urlA)
        XCTAssertTrue(manager.switchToView(at: 1))
        XCTAssertEqual(manager.activeTab?.activeViewIndex, 1)
        XCTAssertTrue(manager.activeDocument.allLayers.contains { $0.name == "ALayout" })

        let indexB = try manager.openEAB(url: urlB)
        XCTAssertEqual(manager.activeTab?.activeViewIndex, 0)
        XCTAssertTrue(manager.activeDocument.allLayers.contains { $0.name == "BModel" })
        XCTAssertTrue(manager.switchToView(at: 1))

        manager.switchToTab(at: indexA)
        XCTAssertEqual(manager.activeTab?.activeViewIndex, 1)
        XCTAssertTrue(manager.activeDocument.allLayers.contains { $0.name == "ALayout" })
        XCTAssertTrue(manager.switchToView(at: 0))
        XCTAssertTrue(manager.activeDocument.allLayers.contains { $0.name == "AModel" })

        manager.switchToTab(at: indexB)
        XCTAssertEqual(manager.activeTab?.activeViewIndex, 1)
        XCTAssertTrue(manager.activeDocument.allLayers.contains { $0.name == "BLayout" })
    }

    func testSwitchRequiresWindowShowingActiveTabAndDifferentView() {
        XCTAssertFalse(DrawingViewTabBarPolicy.shouldSwitch(
            showsActiveTab: false,
            selectedViewIndex: 0,
            clickedViewIndex: 1
        ))
        XCTAssertFalse(DrawingViewTabBarPolicy.shouldSwitch(
            showsActiveTab: true,
            selectedViewIndex: 1,
            clickedViewIndex: 1
        ))
        XCTAssertTrue(DrawingViewTabBarPolicy.shouldSwitch(
            showsActiveTab: true,
            selectedViewIndex: 0,
            clickedViewIndex: 1
        ))
    }
}
