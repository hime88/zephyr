import XCTest
import ImGui

/// Reproduces the one-ImGui-context / sequential-per-OS-window frame scheme:
/// a "main" frame builds the AppUI dock host (full-canvas passthru dockspace),
/// then a "float" frame builds only a small top bar. If main-frame windows
/// still capture the mouse during float frames, `io.WantCaptureMouse` will be
/// true over the float's canvas — which the engine stores as the float
/// window's capture flag, classifying every subsequent CAD click/wheel/drag
/// as ImGui-handled.
final class SequentialFrameCaptureTests: XCTestCase {

    private func makeContext() -> UnsafeMutablePointer<ImGuiIO> {
        _ = ImGuiCreateContext(nil)
        let io = ImGuiGetIO()!
        io.pointee.ConfigFlags |= Int32(ImGuiConfigFlags_DockingEnable.rawValue)
        io.pointee.IniFilename = nil
        _ = ImFontAtlas_AddFontDefault(io.pointee.Fonts, nil)
        igImFontAtlasBuildMain(io.pointee.Fonts)
        io.pointee.DeltaTime = 1.0 / 60.0
        return io
    }

    private func mainFrame(io: UnsafeMutablePointer<ImGuiIO>, mouse: ImVec2) {
        io.pointee.DisplaySize = ImVec2(x: 1920, y: 1080)
        ImGuiIO_AddMousePosEvent(io, mouse.x, mouse.y)
        ImGuiNewFrame()

        // Mirror AppUI's MainWorkspace host.
        ImGuiSetNextWindowPos(ImVec2(x: 0, y: 80), Int32(ImGuiCond_Always.rawValue), ImVec2(x: 0, y: 0))
        ImGuiSetNextWindowSize(ImVec2(x: 1920, y: 960), Int32(ImGuiCond_Always.rawValue))
        let hostFlags: Int32 =
            Int32(ImGuiWindowFlags_NoTitleBar.rawValue)
            | Int32(ImGuiWindowFlags_NoCollapse.rawValue)
            | Int32(ImGuiWindowFlags_NoResize.rawValue)
            | Int32(ImGuiWindowFlags_NoMove.rawValue)
            | Int32(ImGuiWindowFlags_NoBringToFrontOnFocus.rawValue)
            | Int32(ImGuiWindowFlags_NoNavFocus.rawValue)
            | Int32(ImGuiWindowFlags_NoBackground.rawValue)
        var open = true
        if igBegin("MainWorkspace", &open, hostFlags) {
            igDockSpace(igGetID_Str("MainDockSpace"), ImVec2(x: 0, y: 0),
                        Int32(ImGuiDockNodeFlags_PassthruCentralNode.rawValue), nil)
        }
        igEnd()
        ImGuiRender()
    }

    private func floatFrame(io: UnsafeMutablePointer<ImGuiIO>, mouse: ImVec2) {
        io.pointee.DisplaySize = ImVec2(x: 1280, y: 800)
        ImGuiIO_AddMousePosEvent(io, mouse.x, mouse.y)
        ImGuiNewFrame()

        // Mirror renderFloatWindowUI's top bar only.
        ImGuiSetNextWindowPos(ImVec2(x: 0, y: 0), Int32(ImGuiCond_Always.rawValue), ImVec2(x: 0, y: 0))
        ImGuiSetNextWindowSize(ImVec2(x: 1280, y: 30), Int32(ImGuiCond_Always.rawValue))
        var open = true
        let flags = Int32(
            ImGuiWindowFlags_NoTitleBar.rawValue | ImGuiWindowFlags_NoCollapse.rawValue
                | ImGuiWindowFlags_NoResize.rawValue | ImGuiWindowFlags_NoMove.rawValue
                | ImGuiWindowFlags_NoSavedSettings.rawValue)
        if igBegin("##FloatDockBar", &open, flags) {
            ImGuiTextV("tab")
        }
        igEnd()
        ImGuiRender()
    }

    func testMainFrameCanvasDoesNotCapture() {
        let io = makeContext()
        defer { ImGuiDestroyContext(nil) }
        mainFrame(io: io, mouse: ImVec2(x: 960, y: 500))
        mainFrame(io: io, mouse: ImVec2(x: 960, y: 500))
        XCTAssertFalse(io.pointee.WantCaptureMouse,
                       "precondition: main-frame canvas must not capture")
    }

    // Hover is computed in NewFrame from the previous frame's window set,
    // so every probe runs its frame twice and reads the second result.
    private func floatCaptureAfterTwoFrames(
        io: UnsafeMutablePointer<ImGuiIO>, mouse: ImVec2
    ) -> Bool {
        floatFrame(io: io, mouse: mouse)
        floatFrame(io: io, mouse: mouse)
        return io.pointee.WantCaptureMouse
    }

    func testFloatFrameCanvasCenterDoesNotCapture() {
        let io = makeContext()
        defer { ImGuiDestroyContext(nil) }
        mainFrame(io: io, mouse: ImVec2(x: 960, y: 500))
        mainFrame(io: io, mouse: ImVec2(x: 960, y: 500))
        XCTAssertFalse(floatCaptureAfterTwoFrames(io: io, mouse: ImVec2(x: 640, y: 400)),
                       "float-frame canvas center must not capture (else CAD input dies)")
    }

    func testFloatFrameCanvasLeftDoesNotCapture() {
        let io = makeContext()
        defer { ImGuiDestroyContext(nil) }
        mainFrame(io: io, mouse: ImVec2(x: 960, y: 500))
        mainFrame(io: io, mouse: ImVec2(x: 960, y: 500))
        XCTAssertFalse(floatCaptureAfterTwoFrames(io: io, mouse: ImVec2(x: 100, y: 400)),
                       "float-frame canvas left area must not capture")
    }

    func testFloatFrameTopBarCaptures() {
        let io = makeContext()
        defer { ImGuiDestroyContext(nil) }
        mainFrame(io: io, mouse: ImVec2(x: 960, y: 500))
        mainFrame(io: io, mouse: ImVec2(x: 960, y: 500))
        XCTAssertTrue(floatCaptureAfterTwoFrames(io: io, mouse: ImVec2(x: 640, y: 15)),
                      "float dock bar should capture (control)")
    }
}
