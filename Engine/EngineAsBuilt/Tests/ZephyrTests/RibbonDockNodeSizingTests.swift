import XCTest
import ImGui

/// Pins the two ImGui mechanisms the ribbon relies on and that are easy to
/// get subtly wrong:
///
/// 1. A **docked** window's height is owned by its dock node, so changing the
///    ribbon presentation (menu / labels / icons) has to resize that node at
///    runtime — and the new size must survive the following frames.
/// 2. A popup opened with `OpenPopup` only draws in frames where
///    `BeginPopup` is called for its id, so the flyout code must evaluate
///    `BeginPopup` every frame instead of only on the click frame. That bug
///    (flyouts opening into nothing) is what motivated this test.
///
/// Runs headless: a bare ImGui context, no window, same recipe as
/// `SequentialFrameCaptureTests`.
final class RibbonDockNodeSizingTests: XCTestCase {

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

    private let hostFlags: Int32 =
        Int32(ImGuiWindowFlags_NoTitleBar.rawValue)
        | Int32(ImGuiWindowFlags_NoCollapse.rawValue)
        | Int32(ImGuiWindowFlags_NoResize.rawValue)
        | Int32(ImGuiWindowFlags_NoMove.rawValue)
        | Int32(ImGuiWindowFlags_NoBringToFrontOnFocus.rawValue)
        | Int32(ImGuiWindowFlags_NoNavFocus.rawValue)
        | Int32(ImGuiWindowFlags_NoBackground.rawValue)

    // MARK: - Dock node sizing

    func testDockedWindowNodeCanBeResizedAtRuntime() {
        let io = makeContext()
        defer { ImGuiDestroyContext(nil) }

        var dockID: ImGuiID = 0
        var ribbonNode: ImGuiID = 0
        var measuredWidth: Float = 0
        var measuredHeight: Float = 0
        var windowDockID: ImGuiID = 0

        func frame(_ body: () -> Void) {
            io.pointee.DisplaySize = ImVec2(x: 1280, y: 800)
            ImGuiNewFrame()
            body()
            ImGuiRender()
        }

        // The dockspace host the ribbon lives in (mirrors AppUI).
        func host() {
            ImGuiSetNextWindowPos(
                ImVec2(x: 0, y: 0), Int32(ImGuiCond_Always.rawValue),
                ImVec2(x: 0, y: 0))
            ImGuiSetNextWindowSize(
                ImVec2(x: 1280, y: 800), Int32(ImGuiCond_Always.rawValue))
            var open = true
            if igBegin("MainWorkspace", &open, hostFlags) {
                // No PassthruCentralNode: ImGui refuses to *split* a
                // passthru central node from the builder API (user dragging
                // still works). The sizing semantics under test are the same.
                dockID = igDockSpace(
                    igGetID_Str("MainDockSpace"), ImVec2(x: 0, y: 0), 0, nil)
            }
            igEnd()
        }

        // Submits the ribbon window and records the node rect it lives in.
        func ribbonWindow() {
            var open = true
            if igBegin(
                "Ribbon", &open,
                Int32(ImGuiWindowFlags_NoTitleBar.rawValue)) {
                windowDockID = ImGuiGetWindowDockID()
                if let node = ImGuiDockBuilderGetNode(windowDockID) {
                    let rect = ImGuiDockNodeRect(node)
                    measuredWidth = rect.Max.x - rect.Min.x
                    measuredHeight = rect.Max.y - rect.Min.y

                }
            }
            igEnd()
        }

        // Frame 1: dockspace plus a top split reserved for the ribbon, using
        // the documented builder idiom (the root must be sized first, and the
        // returned id is the node at the split direction).
        frame {
            host()
            if dockID != 0 {
                ImGuiDockBuilderRemoveNode(dockID)
                // The rebuilt node must be flagged as a dockspace, otherwise
                // DockSpace() resets it and the split is discarded.
                // ImGuiDockNodeFlags_DockSpace (1 << 10) is a private flag
                // with no Swift binding; the raw bit is what the builder
                // needs to keep treating this node as a dockspace.
                ImGuiDockBuilderAddNode(dockID, 1 << 10)
                ImGuiDockBuilderSetNodeSize(
                    dockID, ImVec2(x: 1280, y: 800))
                var main: ImGuiID = dockID
                ribbonNode = ImGuiDockBuilderSplitNode(
                    main, ImGuiDir_Up, 0.25, nil, &main)
                ImGuiDockBuilderDockWindow("Ribbon", ribbonNode)
                ImGuiDockBuilderFinish(dockID)
            }
        }
        XCTAssertNotEqual(ribbonNode, 0, "the builder must hand back a node")
        XCTAssertNotEqual(ribbonNode, dockID,
                          "the ribbon node must be the top split, not the root")

        // Frames 2-3: the window docks in the reserved node.
        frame {
            host()
            ribbonWindow()
        }
        frame {
            host()
            ribbonWindow()
        }
        XCTAssertEqual(windowDockID, ribbonNode,
                       "the ribbon must be docked in the reserved node")
        XCTAssertGreaterThan(measuredWidth, 100)
        XCTAssertGreaterThan(measuredHeight, 100,
                             "a 25% top split of 800 should be tall")
        XCTAssertLessThan(measuredHeight, 400,
                          "the top split must not fill the whole dockspace")

        // Collapse: resize the node to a labels-bar height, like the ribbon
        // does when cycling to a shorter presentation.
        let target: Float = 58
        ImGuiDockBuilderSetNodeSize(
            ribbonNode, ImVec2(x: measuredWidth, y: target))

        frame {
            host()
            ribbonWindow()
        }
        XCTAssertEqual(measuredHeight, target, accuracy: 2,
                       "the node must adopt the requested height")

        // ...and the new size must stick instead of snapping back.
        frame {
            host()
            ribbonWindow()
        }
        frame {
            host()
            ribbonWindow()
        }
        XCTAssertEqual(measuredHeight, target, accuracy: 2,
                       "the collapsed height must survive later frames")

        // Expanding again follows the same path.
        let expanded: Float = 140
        ImGuiDockBuilderSetNodeSize(
            ribbonNode, ImVec2(x: measuredWidth, y: expanded))
        frame {
            host()
            ribbonWindow()
        }
        XCTAssertEqual(measuredHeight, expanded, accuracy: 2)
    }

    // MARK: - Popup submission

    /// `BeginPopup` must run every frame: the popup body only executes in
    /// frames where it is submitted, even while ImGui keeps the popup open.
    func testPopupBodyOnlyRunsWhenBeginPopupIsCalled() {
        let io = makeContext()
        defer { ImGuiDestroyContext(nil) }

        var openPopupThisFrame = false
        var submitPopup = true
        var bodyRuns = 0
        var openReported = false

        func frame() {
            io.pointee.DisplaySize = ImVec2(x: 1280, y: 800)
            ImGuiNewFrame()
            var open = true
            if igBegin(
                "Ribbon", &open,
                Int32(ImGuiWindowFlags_NoTitleBar.rawValue)) {
                if openPopupThisFrame {
                    ImGuiOpenPopup("##flyout", 0)
                }
                openReported = ImGuiIsPopupOpen("##flyout", 0)
                if submitPopup, ImGuiBeginPopup("##flyout", 0) {
                    bodyRuns += 1
                    igMenuItem_Bool("Ellipse", nil, false, true)
                    ImGuiEndPopup()
                }
            }
            igEnd()
            ImGuiRender()
        }

        // Frame 0: nothing open.
        frame()
        XCTAssertFalse(openReported)
        XCTAssertEqual(bodyRuns, 0)

        // Frame 1: the click opens the popup and it draws in the same frame.
        openPopupThisFrame = true
        frame()
        XCTAssertTrue(openReported, "OpenPopup must register the popup")
        XCTAssertEqual(bodyRuns, 1, "the body must draw in the opening frame")

        // Frame 2: no further click, but BeginPopup still runs -> body draws
        // again and the popup stays on screen.
        openPopupThisFrame = false
        frame()
        XCTAssertEqual(bodyRuns, 2)
        XCTAssertTrue(openReported)

        // Frame 3: skipping BeginPopup is exactly the reported bug — the
        // popup is still "open" but nothing renders.
        submitPopup = false
        frame()
        XCTAssertEqual(bodyRuns, 2,
                       "without BeginPopup the body must not run")
        XCTAssertTrue(
            openReported,
            "ImGui still considers it open, which is why it looked like "
                + "nothing happened")
    }
}
