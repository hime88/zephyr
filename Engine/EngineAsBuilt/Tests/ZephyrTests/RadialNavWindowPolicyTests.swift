import XCTest
import Foundation
@testable import ZephyrCore

@MainActor
final class RadialNavWindowPolicyTests: XCTestCase {

    private func makeManager() -> (EngineWindowManager, EngineManagedWindow, EngineManagedWindow) {
        let manager = EngineWindowManager()
        let main = manager.register(
            handle: OpaquePointer(bitPattern: 0x100)!,
            id: 1, isMain: true)
        let aux = manager.register(
            handle: OpaquePointer(bitPattern: 0x200)!,
            id: 2, isMain: false)
        return (manager, main, aux)
    }

    func testMainFrameTargetsMainWindow() {
        let (manager, main, aux) = makeManager()
        aux.isFocused = true

        let target = RadialNavWindowPolicy.targetWindow(
            frameRole: .mainWindow,
            windowManager: manager,
            floatWindowIDs: [:])

        XCTAssertTrue(target === main)
    }

    func testFloatFrameTargetsHostedAuxWindowNotMainWindow() {
        let (manager, main, aux) = makeManager()
        let tabID = UUID()
        aux.hostedTabID = tabID

        let target = RadialNavWindowPolicy.targetWindow(
            frameRole: .floatWindow(hostedTabID: tabID),
            windowManager: manager,
            floatWindowIDs: [tabID: aux.id])

        XCTAssertTrue(target === aux)
        XCTAssertFalse(target === main)
    }

    func testFloatFrameFallsBackToAuxHostingTabWhenIDMapMissing() {
        let (manager, _, aux) = makeManager()
        let tabID = UUID()
        aux.hostedTabID = tabID

        let target = RadialNavWindowPolicy.targetWindow(
            frameRole: .floatWindow(hostedTabID: tabID),
            windowManager: manager,
            floatWindowIDs: [:])

        XCTAssertTrue(target === aux)
    }

    func testFloatFrameWithoutHostedTabUsesFocusedAuxBeforeMain() {
        let (manager, _, aux) = makeManager()
        aux.isFocused = true

        let target = RadialNavWindowPolicy.targetWindow(
            frameRole: .floatWindow(hostedTabID: nil),
            windowManager: manager,
            floatWindowIDs: [:])

        XCTAssertTrue(target === aux)
    }
}
