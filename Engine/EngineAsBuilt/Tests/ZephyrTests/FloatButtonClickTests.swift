import XCTest
import CSDL3
import ImGui
@testable import ZephyrCore

/// Regression test for dead float-window buttons: with ONE ImGui context
/// serving alternating per-OS-window frames, `NewFrame`'s
/// `WasActive = Active` rollover leaves every window's widgets one frame
/// too stale to hover, so buttons never fire. The engine therefore gives
/// each OS window its own context (shared font atlas) and activates it
/// before replay/framing. This test drives the real enqueue/replay
/// classes through that exact scheme and clicks a Dock-style button.
@MainActor
final class FloatButtonClickTests: XCTestCase {

    func testDockButtonClickWithPerWindowContextsUnderAlternation() {
        // Main context owns the atlas; aux shares it, as in the engine.
        let mainCtx = ImGuiCreateContext(nil)!
        let mainIO = ImGuiGetIO()!
        mainIO.pointee.ConfigFlags |= Int32(ImGuiConfigFlags_DockingEnable.rawValue)
        mainIO.pointee.IniFilename = nil
        _ = ImFontAtlas_AddFontDefault(mainIO.pointee.Fonts, nil)
        igImFontAtlasBuildMain(mainIO.pointee.Fonts)
        mainIO.pointee.DeltaTime = 1.0 / 60.0

        let auxCtx = ImGuiCreateContext(mainIO.pointee.Fonts)!
        igSetCurrentContext(auxCtx) // CreateContext restores the previous context
        let auxIO = ImGuiGetIO()!
        auxIO.pointee.ConfigFlags |= Int32(ImGuiConfigFlags_DockingEnable.rawValue)
        auxIO.pointee.IniFilename = nil
        auxIO.pointee.DeltaTime = 1.0 / 60.0
        igSetCurrentContext(mainCtx)
        defer {
            ImGuiDestroyContext(auxCtx)
            ImGuiDestroyContext(mainCtx)
        }

        let manager = EngineWindowManager()
        let main = manager.register(handle: OpaquePointer(bitPattern: 0x100)!, id: 2, isMain: true)
        let aux = manager.register(handle: OpaquePointer(bitPattern: 0x200)!, id: 3, isMain: false)
        main.imguiContext = mainCtx; main.imguiIO = mainIO
        aux.imguiContext = auxCtx; aux.imguiIO = auxIO
        aux.isFocused = true
        let ui = EngineUIManager()

        var clicked = false

        func activate(_ w: EngineManagedWindow) {
            igSetCurrentContext(w.imguiContext)
        }

        func mainFrame() {
            activate(main)
            mainIO.pointee.DisplaySize = ImVec2(x: 1920, y: 1080)
            ui.replayQueuedInput(for: main, appFocused: manager.focusedWindow != nil)
            ImGuiNewFrame()
            ImGuiRender()
            main.wantCaptureMouse = mainIO.pointee.WantCaptureMouse
        }

        func auxFrame() {
            activate(aux)
            auxIO.pointee.DisplaySize = ImVec2(x: 1280, y: 800)
            ui.replayQueuedInput(for: aux, appFocused: manager.focusedWindow != nil)
            ImGuiNewFrame()
            ImGuiSetNextWindowPos(ImVec2(x: 0, y: 0), Int32(ImGuiCond_Always.rawValue), ImVec2(x: 0, y: 0))
            ImGuiSetNextWindowSize(ImVec2(x: 1280, y: 30), Int32(ImGuiCond_Always.rawValue))
            var open = true
            let flags = Int32(
                ImGuiWindowFlags_NoTitleBar.rawValue | ImGuiWindowFlags_NoCollapse.rawValue
                    | ImGuiWindowFlags_NoResize.rawValue | ImGuiWindowFlags_NoMove.rawValue
                    | ImGuiWindowFlags_NoSavedSettings.rawValue)
            if igBegin("##FloatDockBar", &open, flags) {
                ImGuiSetCursorPos(ImVec2(x: 1200, y: 4))
                if ImGuiButton("Dock", ImVec2(x: 60, y: 22)) {
                    clicked = true
                }
            }
            igEnd()
            ImGuiRender()
            aux.wantCaptureMouse = auxIO.pointee.WantCaptureMouse
        }

        // Strict alternation, exactly like the engine's render loop.
        func loop() { mainFrame(); auxFrame() }

        func auxEvent(type: SDL_EventType, button: UInt8 = 1, x: Float, y: Float) {
            var e = SDL_Event()
            e.type = UInt32(type.rawValue)
            switch type {
            case SDL_EVENT_MOUSE_MOTION:
                e.motion.windowID = 3; e.motion.x = x; e.motion.y = y
            default:
                e.button.windowID = 3; e.button.button = button; e.button.x = x; e.button.y = y
            }
            _ = ui.enqueueImGuiInput(event: &e, for: aux)
        }

        auxEvent(type: SDL_EVENT_MOUSE_MOTION, x: 1230, y: 15)
        loop(); loop()
        XCTAssertTrue(aux.wantCaptureMouse, "dock bar should capture while hovered")

        auxEvent(type: SDL_EVENT_MOUSE_BUTTON_DOWN, x: 1230, y: 15)
        loop(); loop()
        XCTAssertFalse(clicked, "button fired on press instead of release")

        auxEvent(type: SDL_EVENT_MOUSE_BUTTON_UP, x: 1230, y: 15)
        loop(); loop()
        XCTAssertTrue(clicked, "Dock button never fired across alternating per-window-context frames")
    }
}
