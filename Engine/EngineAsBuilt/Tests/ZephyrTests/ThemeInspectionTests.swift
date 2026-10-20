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

        XCTAssertEqual(darkWinBg.x, AppTheme.dark.panelBg.x, accuracy: 0.001)
        XCTAssertEqual(darkText.x, AppTheme.dark.textPrimary.x, accuracy: 0.001)
        XCTAssertEqual(darkSliderGrab.x, AppTheme.dark.brandGold.x, accuracy: 0.001)
        XCTAssertEqual(darkCheckMark.x, AppTheme.dark.brandGold.x, accuracy: 0.001)

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

        // Light panel background should be pale/white (~0.97), text should be dark navy (~0.086)
        XCTAssertGreaterThan(lightWinBg.x, 0.9)
        XCTAssertGreaterThan(lightWinBg.y, 0.9)
        XCTAssertGreaterThan(lightWinBg.z, 0.9)

        XCTAssertLessThan(lightText.x, 0.2)
        XCTAssertLessThan(lightText.y, 0.3)
        XCTAssertLessThan(lightText.z, 0.4)

        XCTAssertEqual(lightSliderGrab.x, AppTheme.light.brandGold.x, accuracy: 0.001)
        XCTAssertEqual(lightCheckMark.x, AppTheme.light.brandGold.x, accuracy: 0.001)

        // 3. Contrast verification: ensure text is readable against panel background
        func luminance(_ col: ImVec4) -> Double {
            return 0.2126 * Double(col.x) + 0.7152 * Double(col.y) + 0.0722 * Double(col.z)
        }
        let darkContrast = (luminance(darkText) + 0.05) / (luminance(darkWinBg) + 0.05)
        let lightContrast = (luminance(lightWinBg) + 0.05) / (luminance(lightText) + 0.05)

        XCTAssertGreaterThan(darkContrast, 3.0, "Dark theme must provide high contrast between text and panelBg")
        XCTAssertGreaterThan(lightContrast, 3.0, "Light theme must provide high contrast between text and panelBg")

        ImGuiRender()

        // 4. toggleTheme() toggles between dark and light seamlessly
        ui.toggleTheme()
        XCTAssertTrue(ui.isDarkTheme)
        ui.toggleTheme()
        XCTAssertFalse(ui.isDarkTheme)
    }
}
