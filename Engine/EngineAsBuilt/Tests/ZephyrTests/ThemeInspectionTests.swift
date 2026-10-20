import XCTest
import ImGui
@testable import ZephyrCore

@MainActor
final class ThemeInspectionTests: XCTestCase {

    func testThemeApplicationAndContrast() {
        let ctx = ImGuiCreateContext(nil)!
        defer { ImGuiDestroyContext(ctx) }
        let ui = EngineUIManager()
        let io = ImGuiGetIO()!
        io.pointee.DisplaySize = ImVec2(x: 1920, y: 1080)
        io.pointee.DeltaTime = 1.0 / 60.0
        _ = ImFontAtlas_AddFontDefault(io.pointee.Fonts, nil)
        igImFontAtlasBuildMain(io.pointee.Fonts)

        func luminance(_ col: ImVec4) -> Double {
            return 0.2126 * Double(col.x) + 0.7152 * Double(col.y) + 0.0722 * Double(col.z)
        }
        func contrastRatio(_ c1: ImVec4, _ c2: ImVec4) -> Double {
            let l1 = luminance(c1)
            let l2 = luminance(c2)
            let top = max(l1, l2) + 0.05
            let bottom = min(l1, l2) + 0.05
            return top / bottom
        }

        // 1. Dark theme verification
        ui.isDarkTheme = true
        ui.applyTheme()
        XCTAssertTrue(ui.isDarkTheme)
        XCTAssertEqual(ui.theme.panelBg.x, AppTheme.dark.panelBg.x, accuracy: 0.001)
        XCTAssertEqual(ui.theme.panelBg.y, AppTheme.dark.panelBg.y, accuracy: 0.001)
        XCTAssertEqual(ui.theme.panelBg.z, AppTheme.dark.panelBg.z, accuracy: 0.001)

        ImGuiNewFrame()
        let darkWinBg = ImGuiGetStyleColorVec4(Int32(ImGuiCol_WindowBg.rawValue))!.pointee
        let darkText = ImGuiGetStyleColorVec4(Int32(ImGuiCol_Text.rawValue))!.pointee
        let darkSliderGrab = ImGuiGetStyleColorVec4(Int32(ImGuiCol_SliderGrab.rawValue))!.pointee
        let darkCheckMark = ImGuiGetStyleColorVec4(Int32(ImGuiCol_CheckMark.rawValue))!.pointee
        let darkFrameBg = ImGuiGetStyleColorVec4(Int32(ImGuiCol_FrameBg.rawValue))!.pointee
        let darkButton = ImGuiGetStyleColorVec4(Int32(ImGuiCol_Button.rawValue))!.pointee
        let darkTextDisabled = ImGuiGetStyleColorVec4(Int32(ImGuiCol_TextDisabled.rawValue))!.pointee

        XCTAssertEqual(darkWinBg.x, AppTheme.dark.panelBg.x, accuracy: 0.001)
        XCTAssertEqual(darkText.x, AppTheme.dark.textPrimary.x, accuracy: 0.001)
        XCTAssertEqual(darkSliderGrab.x, AppTheme.dark.brandGold.x, accuracy: 0.001)
        XCTAssertEqual(darkCheckMark.x, AppTheme.dark.brandGold.x, accuracy: 0.001)
        XCTAssertEqual(darkTextDisabled.x, AppTheme.dark.textDim.x, accuracy: 0.001)

        // Dark theme frame and button should be subtle dark values
        XCTAssertLessThan(darkFrameBg.x, 0.3)
        XCTAssertEqual(darkButton.x, AppTheme.dark.border.x, accuracy: 0.001)

        ImGuiRender()

        // 2. Light theme verification via property didSet
        ui.isDarkTheme = false
        XCTAssertFalse(ui.isDarkTheme)
        XCTAssertEqual(ui.theme.panelBg.x, AppTheme.light.panelBg.x, accuracy: 0.001)
        XCTAssertEqual(ui.theme.panelBg.y, AppTheme.light.panelBg.y, accuracy: 0.001)
        XCTAssertEqual(ui.theme.panelBg.z, AppTheme.light.panelBg.z, accuracy: 0.001)

        ImGuiNewFrame()
        let lightWinBg = ImGuiGetStyleColorVec4(Int32(ImGuiCol_WindowBg.rawValue))!.pointee
        let lightText = ImGuiGetStyleColorVec4(Int32(ImGuiCol_Text.rawValue))!.pointee
        let lightSliderGrab = ImGuiGetStyleColorVec4(Int32(ImGuiCol_SliderGrab.rawValue))!.pointee
        let lightCheckMark = ImGuiGetStyleColorVec4(Int32(ImGuiCol_CheckMark.rawValue))!.pointee
        let lightFrameBg = ImGuiGetStyleColorVec4(Int32(ImGuiCol_FrameBg.rawValue))!.pointee
        let lightButton = ImGuiGetStyleColorVec4(Int32(ImGuiCol_Button.rawValue))!.pointee
        let lightTextDisabled = ImGuiGetStyleColorVec4(Int32(ImGuiCol_TextDisabled.rawValue))!.pointee

        // Light panel background should be pale/white (~0.97), text should be dark navy (~0.086)
        XCTAssertGreaterThan(lightWinBg.x, 0.9)
        XCTAssertGreaterThan(lightWinBg.y, 0.9)
        XCTAssertGreaterThan(lightWinBg.z, 0.9)

        XCTAssertLessThan(lightText.x, 0.2)
        XCTAssertLessThan(lightText.y, 0.3)
        XCTAssertLessThan(lightText.z, 0.4)

        // Light frame and button should be soft pale tones (not dark or hardcoded dark navy)
        XCTAssertGreaterThan(lightFrameBg.x, 0.8)
        XCTAssertGreaterThan(lightButton.x, 0.8)

        XCTAssertEqual(lightSliderGrab.x, AppTheme.light.brandGold.x, accuracy: 0.001)
        XCTAssertEqual(lightCheckMark.x, AppTheme.light.brandGold.x, accuracy: 0.001)
        XCTAssertEqual(lightTextDisabled.x, AppTheme.light.textDim.x, accuracy: 0.001)

        // 3. Contrast verification: ensure text is readable against panel and button backgrounds
        let darkTextWinContrast = contrastRatio(darkText, darkWinBg)
        let lightTextWinContrast = contrastRatio(lightText, lightWinBg)
        let lightTextBtnContrast = contrastRatio(lightText, lightButton)

        XCTAssertGreaterThan(darkTextWinContrast, 3.0, "Dark theme must provide high contrast between text and panelBg")
        XCTAssertGreaterThan(lightTextWinContrast, 3.0, "Light theme must provide high contrast between text and panelBg")
        XCTAssertGreaterThan(lightTextBtnContrast, 3.0, "Light theme must provide high contrast between text and button background")

        // 4. Verify unselected segment button contrast in light mode
        let unselectedBtnBgLight = ImVec4(x: 0.88, y: 0.92, z: 0.96, w: 1.0)
        let unselectedTextLight = AppTheme.light.textPrimary
        let segmentBtnContrast = contrastRatio(unselectedTextLight, unselectedBtnBgLight)
        XCTAssertGreaterThan(segmentBtnContrast, 4.0, "Unselected segment button in light mode must be easily legible")

        ImGuiRender()

        // 5. toggleTheme() toggles between dark and light seamlessly
        ui.toggleTheme()
        XCTAssertTrue(ui.isDarkTheme)
        ui.toggleTheme()
        XCTAssertFalse(ui.isDarkTheme)
    }
}
