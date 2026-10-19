import XCTest
@testable import ZephyrCore

@MainActor
final class StatusBarUIPolicyTests: XCTestCase {

    private func makeDocument(layerName: String, entityCount: Int, dirty: Bool = false) -> CADDocument {
        let document = CADDocument()
        let layer = Layer(name: layerName, color: .white)
        let entities = (0..<entityCount).map { _ in
            CADEntity(layerID: layer.handle, transform: .identity)
        }
        document.importLayersBlocksEntities(
            layers: [layer], blocks: [], entities: entities)
        if dirty { document.markEdited() }
        return document
    }

    private func makeTab(name: String) -> DocumentTab {
        DocumentTab(
            displayName: name,
            drawingViews: [
                DrawingView(
                    name: "Model", kind: .model,
                    document: makeDocument(layerName: "\(name)ModelLayer", entityCount: 2)),
                DrawingView(
                    name: "Layout1", kind: .sheet,
                    document: makeDocument(layerName: "\(name)LayoutLayer", entityCount: 5, dirty: true)),
            ])
    }

    func testShownInfoUsesGivenTabAndViewNotAnotherTab() {
        let mainTab = makeTab(name: "Main.dxf")
        let floatTab = makeTab(name: "Float.dxf")

        let mainInfo = StatusBarUIPolicy.shownInfo(tab: mainTab, viewIndex: 0)
        let floatInfo = StatusBarUIPolicy.shownInfo(tab: floatTab, viewIndex: 1)

        XCTAssertEqual(mainInfo.tabName, "Main.dxf")
        XCTAssertEqual(mainInfo.viewName, "Model")
        XCTAssertEqual(mainInfo.layerName, "Main.dxfModelLayer")
        XCTAssertEqual(mainInfo.entityCount, 2)

        XCTAssertEqual(floatInfo.tabName, "Float.dxf")
        XCTAssertEqual(floatInfo.viewName, "Layout1")
        XCTAssertEqual(floatInfo.layerName, "Float.dxfLayoutLayer")
        XCTAssertEqual(floatInfo.entityCount, 5)
        XCTAssertTrue(floatInfo.isDirty)
    }

    func testLeftTextIsBuiltFromShownInfo() {
        let tab = makeTab(name: "Float.dxf")
        let info = StatusBarUIPolicy.shownInfo(tab: tab, viewIndex: 1)

        XCTAssertEqual(
            StatusBarUIPolicy.leftText(info: info, trackingSuffix: ""),
            "Float.dxf *  ·  View: Layout1  ·  Layer: Float.dxfLayoutLayer  ·  Entities: 5")
    }

    func testShownInfoClampsViewIndexAndFallsBackWithoutTab() {
        let tab = makeTab(name: "Clamp.dxf")

        XCTAssertEqual(
            StatusBarUIPolicy.shownInfo(tab: tab, viewIndex: 99).viewName,
            "Layout1")
        XCTAssertEqual(
            StatusBarUIPolicy.shownInfo(tab: nil, viewIndex: 0),
            StatusBarShownInfo(
                tabName: "Untitled", isDirty: false, viewName: "Model",
                layerName: "none", entityCount: 0))
    }
}
