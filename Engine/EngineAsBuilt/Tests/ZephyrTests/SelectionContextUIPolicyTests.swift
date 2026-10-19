import XCTest
@testable import ZephyrCore

final class SelectionContextUIPolicyTests: XCTestCase {
    func testSelectionContextUIRendersOnlyInWindowShowingActiveTab() {
        XCTAssertFalse(SelectionContextUIPolicy.shouldRender(showsActiveTab: false))
        XCTAssertTrue(SelectionContextUIPolicy.shouldRender(showsActiveTab: true))
    }

    func testHatchEditorDoesNotRenderInWindowNotShowingActiveTab() {
        XCTAssertFalse(SelectionContextUIPolicy.shouldRenderHatchEditor(
            showsActiveTab: false,
            hasActiveFeatureCommand: false,
            selectedCount: 1,
            hasLastSelectedHandle: true
        ))
    }

    func testHatchEditorRequiresSingleSelectionAndNoActiveFeatureCommand() {
        XCTAssertTrue(SelectionContextUIPolicy.shouldRenderHatchEditor(
            showsActiveTab: true,
            hasActiveFeatureCommand: false,
            selectedCount: 1,
            hasLastSelectedHandle: true
        ))
        XCTAssertFalse(SelectionContextUIPolicy.shouldRenderHatchEditor(
            showsActiveTab: true,
            hasActiveFeatureCommand: true,
            selectedCount: 1,
            hasLastSelectedHandle: true
        ))
        XCTAssertFalse(SelectionContextUIPolicy.shouldRenderHatchEditor(
            showsActiveTab: true,
            hasActiveFeatureCommand: false,
            selectedCount: 2,
            hasLastSelectedHandle: true
        ))
        XCTAssertFalse(SelectionContextUIPolicy.shouldRenderHatchEditor(
            showsActiveTab: true,
            hasActiveFeatureCommand: false,
            selectedCount: 1,
            hasLastSelectedHandle: false
        ))
    }
}
