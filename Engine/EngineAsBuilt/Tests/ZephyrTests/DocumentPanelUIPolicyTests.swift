import XCTest
@testable import ZephyrCore

final class DocumentPanelUIPolicyTests: XCTestCase {
    func testLayersRenderOnlyWhenVisibleAndWindowShowsATab() {
        XCTAssertFalse(DocumentPanelUIPolicy.shouldRenderLayers(
            isVisible: false,
            hasShownTab: true
        ))
        XCTAssertFalse(DocumentPanelUIPolicy.shouldRenderLayers(
            isVisible: true,
            hasShownTab: false
        ))
        XCTAssertTrue(DocumentPanelUIPolicy.shouldRenderLayers(
            isVisible: true,
            hasShownTab: true
        ))
    }

    func testActiveDocumentPanelsRenderOnlyInWindowShowingActiveTab() {
        XCTAssertFalse(DocumentPanelUIPolicy.shouldRenderActiveDocumentPanel(
            isVisible: true,
            showsActiveTab: false
        ))
        XCTAssertFalse(DocumentPanelUIPolicy.shouldRenderActiveDocumentPanel(
            isVisible: false,
            showsActiveTab: true
        ))
        XCTAssertTrue(DocumentPanelUIPolicy.shouldRenderActiveDocumentPanel(
            isVisible: true,
            showsActiveTab: true
        ))
    }
}
