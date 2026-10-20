import XCTest
import CSDL3
import ImGui
@testable import ZephyrCore

@MainActor
final class WindowInputRoutingTests: XCTestCase {

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

    // MARK: - Registry

    func testRegisterLookupAndMainFirst() {
        let (manager, main, aux) = makeManager()

        XCTAssertTrue(manager.window(for: 1) === main)
        XCTAssertTrue(manager.window(for: 2) === aux)
        XCTAssertNil(manager.window(for: 99))
        XCTAssertTrue(manager.mainWindow === main)
        XCTAssertEqual(manager.auxWindows.count, 1)
        XCTAssertTrue(manager.auxWindows.first === aux)
    }

    func testUnregisterRemovesAuxButNeverMain() {
        let (manager, main, _) = makeManager()

        manager.unregister(id: 2)
        XCTAssertNil(manager.window(for: 2))
        XCTAssertTrue(manager.auxWindows.isEmpty)

        manager.unregister(id: 1)
        XCTAssertTrue(manager.window(for: 1) === main)
    }

    // MARK: - Enqueue routing

    func testMouseMotionRoutesToTargetWindow() {
        let (_, main, aux) = makeManager()
        let ui = EngineUIManager()
        aux.wantCaptureMouse = true

        var e = SDL_Event()
        e.type = UInt32(SDL_EVENT_MOUSE_MOTION.rawValue)
        e.motion.windowID = 2
        e.motion.x = 120
        e.motion.y = 80

        let handled = ui.enqueueImGuiInput(event: &e, for: aux)

        XCTAssertTrue(handled)
        XCTAssertEqual(aux.inputQueue.count, 1)
        XCTAssertTrue(main.inputQueue.isEmpty)
        XCTAssertEqual(aux.mouseX, 120)
        XCTAssertEqual(aux.mouseY, 80)
        XCTAssertTrue(aux.hasMousePos)
        if case .mousePos(let x, let y) = aux.inputQueue.first {
            XCTAssertEqual(x, 120)
            XCTAssertEqual(y, 80)
        } else {
            XCTFail("Expected .mousePos, got \(String(describing: aux.inputQueue.first))")
        }
    }

    func testCaptureFlagsComeFromTargetWindow() {
        let (_, main, aux) = makeManager()
        let ui = EngineUIManager()
        main.wantCaptureMouse = false
        aux.wantCaptureMouse = true

        var forMain = SDL_Event()
        forMain.type = UInt32(SDL_EVENT_MOUSE_BUTTON_DOWN.rawValue)
        forMain.button.windowID = 1
        forMain.button.button = 1
        XCTAssertFalse(ui.enqueueImGuiInput(event: &forMain, for: main))

        var forAux = SDL_Event()
        forAux.type = UInt32(SDL_EVENT_MOUSE_BUTTON_DOWN.rawValue)
        forAux.button.windowID = 2
        forAux.button.button = 1
        XCTAssertTrue(ui.enqueueImGuiInput(event: &forAux, for: aux))
    }

    func testKeyEventQueuesKeyAndModifiers() {
        let (_, main, _) = makeManager()
        let ui = EngineUIManager()
        main.wantCaptureKeyboard = true

        var e = SDL_Event()
        e.type = UInt32(SDL_EVENT_KEY_DOWN.rawValue)
        e.key.windowID = 1
        e.key.key = SDLK_A
        e.key.scancode = SDL_SCANCODE_A

        XCTAssertTrue(ui.enqueueImGuiInput(event: &e, for: main))
        XCTAssertEqual(main.inputQueue.count, 1)
        if case .key(let key, let down) = main.inputQueue.first {
            XCTAssertEqual(key.rawValue, ImGuiKey_A.rawValue)
            XCTAssertTrue(down)
        } else {
            XCTFail("Expected .key, got \(String(describing: main.inputQueue.first))")
        }
    }

    func testTextInputCopiesString() {
        let (_, _, aux) = makeManager()
        let ui = EngineUIManager()

        var e = SDL_Event()
        e.type = UInt32(SDL_EVENT_TEXT_INPUT.rawValue)
        e.text.windowID = 2
        "hi".withCString { ptr in
            e.text.text = ptr
            _ = ui.enqueueImGuiInput(event: &e, for: aux)
        }

        XCTAssertEqual(aux.inputQueue.count, 1)
        if case .text(let string) = aux.inputQueue.first {
            XCTAssertEqual(string, "hi")
        } else {
            XCTFail("Expected .text, got \(String(describing: aux.inputQueue.first))")
        }
    }

    func testFocusLostReleasesButtons() {
        let (_, main, _) = makeManager()
        let ui = EngineUIManager()

        var e = SDL_Event()
        e.type = UInt32(SDL_EVENT_WINDOW_FOCUS_LOST.rawValue)
        e.window.windowID = 1

        XCTAssertFalse(ui.enqueueImGuiInput(event: &e, for: main))
        // focus(false) plus five button releases.
        XCTAssertEqual(main.inputQueue.count, 6)
        if case .focus(let gained) = main.inputQueue.first {
            XCTAssertFalse(gained)
        } else {
            XCTFail("Expected .focus first, got \(String(describing: main.inputQueue.first))")
        }
    }

    func testMouseLeaveClearsTrackedPosition() {
        let (_, _, aux) = makeManager()
        let ui = EngineUIManager()
        aux.hasMousePos = true

        var e = SDL_Event()
        e.type = UInt32(SDL_EVENT_WINDOW_MOUSE_LEAVE.rawValue)
        e.window.windowID = 2

        _ = ui.enqueueImGuiInput(event: &e, for: aux)
        XCTAssertFalse(aux.hasMousePos)
    }
}
