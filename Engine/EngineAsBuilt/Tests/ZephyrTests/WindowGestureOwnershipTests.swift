import XCTest
import Foundation
import SwiftSDL
@testable import ZephyrCore

@MainActor
final class WindowGestureOwnershipTests: XCTestCase {

    func testRectSelectionContinuesOnlyInWindowWhereItStarted() {
        let interaction = EngineInteractionManager()
        let tabID = UUID()

        interaction.beginWindowGesture(windowID: 1, tabID: tabID)
        interaction.rectSelectActive = true

        XCTAssertTrue(interaction.shouldContinueWindowGesture(in: 1))
        XCTAssertFalse(interaction.shouldContinueWindowGesture(in: 2))
    }

    func testFirstGestureOwnerIsNotOverwrittenByAnotherWindow() {
        let interaction = EngineInteractionManager()

        interaction.beginWindowGesture(windowID: 1, tabID: UUID())
        interaction.dragActive = true
        interaction.beginWindowGesture(windowID: 2, tabID: UUID())

        XCTAssertEqual(interaction.gestureWindowID, SDL_WindowID(1))
        XCTAssertFalse(interaction.shouldContinueWindowGesture(in: 2))
    }

    func testIdleClaimMayBeReplacedByNextRealDown() {
        let interaction = EngineInteractionManager()
        let secondTabID = UUID()

        // A plain click claims ownership before any drag threshold is
        // crossed; if its mouse-up is missed, the next window's real
        // down must still be able to claim its own gesture.
        interaction.beginWindowGesture(windowID: 1, tabID: UUID())
        interaction.beginWindowGesture(windowID: 2, tabID: secondTabID)

        XCTAssertEqual(interaction.gestureWindowID, SDL_WindowID(2))
        XCTAssertEqual(interaction.gestureTabID, secondTabID)
    }

    func testCancelRectSelectClearsPreviewAndIdleOwner() {
        let interaction = EngineInteractionManager()
        interaction.beginWindowGesture(windowID: 1, tabID: UUID())
        interaction.rectSelectActive = true
        interaction.rectSelectPreviewHandles = [UUID()]

        interaction.cancelRectSelect()

        XCTAssertFalse(interaction.rectSelectActive)
        XCTAssertTrue(interaction.rectSelectPreviewHandles.isEmpty)
        XCTAssertNil(interaction.gestureWindowID)
        XCTAssertNil(interaction.gestureTabID)
    }

    func testOwnerSurvivesUntilGestureBecomesIdle() {
        let interaction = EngineInteractionManager()
        let tabID = UUID()
        interaction.beginWindowGesture(windowID: 2, tabID: tabID)
        interaction.rectSelectActive = true

        interaction.clearWindowGestureIfIdle()
        XCTAssertEqual(interaction.gestureWindowID, SDL_WindowID(2))
        XCTAssertEqual(interaction.gestureTabID, tabID)

        interaction.rectSelectActive = false
        interaction.clearWindowGestureIfIdle()
        XCTAssertNil(interaction.gestureWindowID)
        XCTAssertNil(interaction.gestureTabID)
    }
}
