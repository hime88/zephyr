import XCTest
@testable import ZephyrCore

final class PropertiesPanelUIPolicyTests: XCTestCase {
    func testHiddenWhenPanelToggledOff() {
        XCTAssertEqual(
            PropertiesPanelUIPolicy.content(isVisible: false, hasSelectedEntity: false),
            .hidden)
        XCTAssertEqual(
            PropertiesPanelUIPolicy.content(isVisible: false, hasSelectedEntity: true),
            .hidden)
    }

    /// Regression: the panel used to auto-close as soon as the selection
    /// emptied, forcing the user to reopen it for every inspection. An
    /// open panel with no selection must stay open on an empty state.
    func testOpenPanelWithNoSelectionShowsEmptyStateNotHidden() {
        XCTAssertEqual(
            PropertiesPanelUIPolicy.content(isVisible: true, hasSelectedEntity: false),
            .empty)
    }

    func testOpenPanelWithSelectionShowsEntity() {
        XCTAssertEqual(
            PropertiesPanelUIPolicy.content(isVisible: true, hasSelectedEntity: true),
            .entity)
    }
}
