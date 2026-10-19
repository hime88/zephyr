import XCTest
@testable import ZephyrCore

final class TabBarActivationPolicyTests: XCTestCase {
    func testPersistentVisibleDockedTabDoesNotActivateWhileFloatedTabIsActive() {
        XCTAssertFalse(TabBarActivationPolicy.shouldActivateTab(
            isActive: false,
            tabItemClicked: false,
            tabItemVisible: true,
            activeTabIsFloated: true
        ))
    }

    func testClickedDockedTabActivatesWhileFloatedTabIsActive() {
        XCTAssertTrue(TabBarActivationPolicy.shouldActivateTab(
            isActive: false,
            tabItemClicked: true,
            tabItemVisible: false,
            activeTabIsFloated: true
        ))
    }

    func testVisibleDockedTabStillActivatesWhenActiveTabIsDocked() {
        XCTAssertTrue(TabBarActivationPolicy.shouldActivateTab(
            isActive: false,
            tabItemClicked: false,
            tabItemVisible: true,
            activeTabIsFloated: false
        ))
    }

    func testAlreadyActiveTabNeverReactivates() {
        XCTAssertFalse(TabBarActivationPolicy.shouldActivateTab(
            isActive: true,
            tabItemClicked: true,
            tabItemVisible: true,
            activeTabIsFloated: false
        ))
        XCTAssertFalse(TabBarActivationPolicy.shouldActivateTab(
            isActive: true,
            tabItemClicked: true,
            tabItemVisible: true,
            activeTabIsFloated: true
        ))
    }
}
