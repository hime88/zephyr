import ZephyrCore
import Foundation
import ImGui

@MainActor
struct DrawingViewTabBarUI {
    private static var lastDocumentID: UUID?
    private static var lastActiveViewIndex: Int = -1

    static func render(engine: PhrostEngine, dw: Float, dh: Float) {
        guard let tab = engine.tabManager.activeTab,
              tab.editingBlockID == nil,
              tab.drawingViews.count > 1 else { return }

        let barH = AppLayout.drawingViewTabBarHeight
        let barY = dh - AppLayout.statusBarHeight - barH
        let flags: Int32 =
            Int32(ImGuiWindowFlags_NoTitleBar.rawValue) |
            Int32(ImGuiWindowFlags_NoCollapse.rawValue) |
            Int32(ImGuiWindowFlags_NoResize.rawValue) |
            Int32(ImGuiWindowFlags_NoMove.rawValue) |
            Int32(ImGuiWindowFlags_NoSavedSettings.rawValue)

        ImGuiSetNextWindowPos(
            ImVec2(x: 0, y: barY),
            Int32(ImGuiCond_Always.rawValue),
            ImVec2(x: 0, y: 0))
        ImGuiSetNextWindowSize(
            ImVec2(x: dw, y: barH),
            Int32(ImGuiCond_Always.rawValue))

        ImGuiPushStyleVarX(Int32(ImGuiStyleVar_WindowPadding.rawValue), 8)
        ImGuiPushStyleVarY(Int32(ImGuiStyleVar_WindowPadding.rawValue), 3)
        ImGuiPushStyleVarX(Int32(ImGuiStyleVar_ItemSpacing.rawValue), 2)
        ImGuiPushStyleColor(Int32(ImGuiCol_WindowBg.rawValue), engine.ui.theme.tabBarBg)

        if lastDocumentID != tab.id {
            lastDocumentID = tab.id
            lastActiveViewIndex = -1
        }

        var opened = true
        if igBegin("##DrawingViewTabBar", &opened, flags) {
            let activeIndex = tab.activeViewIndex
            let forceSelection = activeIndex != lastActiveViewIndex
            if forceSelection {
                lastActiveViewIndex = activeIndex
            }

            let tabBarFlags = Int32(ImGuiTabBarFlags_NoTooltip.rawValue)

            if ImGuiBeginTabBar("DrawingViews", tabBarFlags) {
                for index in tab.drawingViews.indices {
                    let view = tab.drawingViews[index]
                    let isActive = index == activeIndex
                    var itemFlags: Int32 = 0
                    if isActive && forceSelection {
                        itemFlags |= Int32(ImGuiTabItemFlags_SetSelected.rawValue)
                    }

                    if isActive, let boldFont = engine.ui.boldFont {
                        ImGuiPushFont(boldFont, ImGuiGetFontSize())
                    }

                    let visible = ImGuiBeginTabItem(
                        "\(view.name)###DrawingView_\(tab.id.uuidString)_\(index)",
                        nil,
                        itemFlags)

                    if isActive, engine.ui.boldFont != nil {
                        ImGuiPopFont()
                    }

                    if visible {
                        if !isActive {
                            let incomingCamera = view.cameraState
                            let needsInitialFit =
                                abs(incomingCamera.offsetX) < 1e-12 &&
                                abs(incomingCamera.offsetY) < 1e-12 &&
                                abs(incomingCamera.zoom - 1.0) < 1e-12 &&
                                abs(incomingCamera.rotation) < 1e-12

                            if engine.tabManager.switchToView(at: index) {
                                lastActiveViewIndex = index
                                if needsInitialFit {
                                    engine.zoomExtents()
                                }
                            }
                        }

                        if index == engine.tabManager.activeTab?.activeViewIndex {
                            let min = ImGuiGetItemRectMin()
                            let max = ImGuiGetItemRectMax()
                            ImDrawListAddRectFilled(
                                igGetWindowDrawList(),
                                ImVec2(x: min.x, y: max.y - 3),
                                ImVec2(x: max.x, y: max.y),
                                igGetColorU32_Vec4(engine.ui.theme.brandGold),
                                0,
                                0)
                        }

                        ImGuiEndTabItem()
                    }
                }
                ImGuiEndTabBar()
            }
        }
        igEnd()

        ImGuiPopStyleColor(1)
        ImGuiPopStyleVar(3)
    }
}
