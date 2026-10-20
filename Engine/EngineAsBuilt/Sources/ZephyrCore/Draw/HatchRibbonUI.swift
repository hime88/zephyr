import Foundation
import ImGui

// MARK: - HatchRibbonUI
//
// Shared floating card for hatch creation and post-selection editing.

@MainActor
public struct HatchRibbonUI {

    /// Settings bundle passed between the ribbon and its owner.
    public struct Settings: Equatable {
        public var fillType: Int32 = 1       // 0=Pattern, 1=Solid, 2=Gradient
        public var patternName: String = "ANSI31"
        public var gradientName: String = "LINEAR"
        public var scale: Float = 1.0
        public var angle: Float = 0.0
        public var primaryColor: ColorRGBA? = nil
        public var backgroundColor: ColorRGBA? = nil
        public var secondaryColor: ColorRGBA? = nil
        public var selectionMode: Int32 = 0  // 0=PickPoints, 1=SelectBoundary
        public var islandStyle: Int32 = 0    // 0=Normal, 1=Outer, 2=Ignore
        public var showModeSection: Bool = true  // hidden during edit mode
        public var applyClicked: Bool = false
        public var closeRequested: Bool = false
        public var associative: Bool = true

        public init(fillType: Int32, patternName: String, gradientName: String = "LINEAR", scale: Float, angle: Float,
                    primaryColor: ColorRGBA?, backgroundColor: ColorRGBA?,
                    secondaryColor: ColorRGBA?, selectionMode: Int32, islandStyle: Int32 = 0, showModeSection: Bool,
                    applyClicked: Bool = false, closeRequested: Bool = false, associative: Bool = true) {
            self.fillType = fillType
            self.patternName = patternName
            self.gradientName = gradientName
            self.scale = scale
            self.angle = angle
            self.primaryColor = primaryColor
            self.backgroundColor = backgroundColor
            self.secondaryColor = secondaryColor
            self.selectionMode = selectionMode
            self.islandStyle = islandStyle
            self.showModeSection = showModeSection
            self.applyClicked = applyClicked
            self.closeRequested = closeRequested
            self.associative = associative
        }
    }

    public static var activeColorPopup: Int = 0  // 0=none, 1=primary, 2=background, 3=secondary
    public static var lastUsedBackgroundColor: ColorRGBA = ColorRGBA(r: 200, g: 200, b: 200, a: 255)
    private static var patternSearchText = ""

    // MARK: - Public render entry point

    public static func render(_ settings: inout Settings, engine: PhrostEngine) {
        let fontSize = ImGuiGetFontSize()
        let uiScale = max(0.75, engine.effectiveUiScale)
        let pad: Float = 16.0 * uiScale
        let itemGap: Float = 4.0 * uiScale
        let controlH = max(ImGuiGetFrameHeight(), 30.0 * uiScale)

        let topChromeH: Float = {
            #if os(macOS)
            return 36.0 * uiScale
            #else
            return 50.0 * uiScale
            #endif
        }()
        
        let io = ImGuiGetIO()!.pointee
        let availableW = max(180.0, io.DisplaySize.x - 32.0 * uiScale)
        let preferredW = max(fontSize * 24.0, 400.0 * uiScale)
        let windowW = min(preferredW, availableW)
        let windowY = topChromeH + 24.0 * uiScale
        let windowX = max(8.0 * uiScale, io.DisplaySize.x - windowW - 24.0 * uiScale)
        let maxWindowH = max(220.0 * uiScale, io.DisplaySize.y - windowY - 16.0 * uiScale)

        ImGuiSetNextWindowPos(
            ImVec2(x: windowX, y: windowY),
            Int32(ImGuiCond_Appearing.rawValue),
            ImVec2(x: 0, y: 0))
        ImGuiSetNextWindowSizeConstraints(
            ImVec2(x: windowW, y: 0),
            ImVec2(x: windowW, y: maxWindowH),
            { _ in },
            nil)

        let theme = engine.ui.theme
        let isDark = engine.ui.isDarkTheme

        ImGuiPushStyleVar(Int32(ImGuiStyleVar_WindowRounding.rawValue), 12.0 * uiScale)
        ImGuiPushStyleVar(Int32(ImGuiStyleVar_WindowBorderSize.rawValue), 1.0)
        ImGuiPushStyleVar(Int32(ImGuiStyleVar_WindowPadding.rawValue), ImVec2(x: pad, y: pad))
        ImGuiPushStyleVar(Int32(ImGuiStyleVar_FrameRounding.rawValue), 6.0 * uiScale)
        ImGuiPushStyleVar(Int32(ImGuiStyleVar_FramePadding.rawValue), ImVec2(x: 8.0 * uiScale, y: 4.0 * uiScale))

        let frameBg = isDark
            ? ImVec4(x: 0.14, y: 0.25, z: 0.38, w: 0.70)
            : ImVec4(x: 0.88, y: 0.92, z: 0.96, w: 0.80)
        let frameHover = isDark
            ? theme.hoverBg
            : ImVec4(x: 0.80, y: 0.87, z: 0.93, w: 0.90)
        let btnBg = isDark
            ? ImVec4(x: 0.12, y: 0.22, z: 0.32, w: 0.85)
            : ImVec4(x: 0.88, y: 0.92, z: 0.96, w: 1.0)
        let btnHover = isDark
            ? theme.hoverBg
            : ImVec4(x: 0.80, y: 0.87, z: 0.93, w: 1.0)

        ImGuiPushStyleColor(Int32(ImGuiCol_WindowBg.rawValue), theme.panelBg)
        ImGuiPushStyleColor(Int32(ImGuiCol_Border.rawValue), theme.border)
        ImGuiPushStyleColor(Int32(ImGuiCol_FrameBg.rawValue), frameBg)
        ImGuiPushStyleColor(Int32(ImGuiCol_FrameBgHovered.rawValue), frameHover)
        ImGuiPushStyleColor(Int32(ImGuiCol_FrameBgActive.rawValue), theme.activeBg)
        ImGuiPushStyleColor(Int32(ImGuiCol_Button.rawValue), btnBg)
        ImGuiPushStyleColor(Int32(ImGuiCol_ButtonHovered.rawValue), btnHover)
        ImGuiPushStyleColor(Int32(ImGuiCol_ButtonActive.rawValue), theme.activeBg)
        ImGuiPushStyleColor(Int32(ImGuiCol_SliderGrab.rawValue), theme.brandGold)
        ImGuiPushStyleColor(Int32(ImGuiCol_SliderGrabActive.rawValue), theme.brandGoldActive)
        ImGuiPushStyleColor(Int32(ImGuiCol_CheckMark.rawValue), theme.brandGold)
        ImGuiPushStyleColor(Int32(ImGuiCol_Text.rawValue), theme.textPrimary)
        ImGuiPushStyleColor(Int32(ImGuiCol_TextDisabled.rawValue), theme.textDim)

        let flags = Int32(ImGuiWindowFlags_NoTitleBar.rawValue
                        | ImGuiWindowFlags_NoSavedSettings.rawValue
                        | ImGuiWindowFlags_NoCollapse.rawValue
                        | ImGuiWindowFlags_AlwaysAutoResize.rawValue)

        guard igBegin("##HatchCard", nil, flags) else {
            ImGuiEnd()
            ImGuiPopStyleVar(5)
            ImGuiPopStyleColor(13)
            return
        }

        defer {
            ImGuiEnd()
            ImGuiPopStyleVar(5)
            ImGuiPopStyleColor(13)
        }

        let dl = igGetWindowDrawList()
        let contentW = ImGuiGetContentRegionAvail().x

        // --- Custom Header ---
        igBeginGroup()
        if let bold = engine.ui.boldFont ?? engine.ui.commandTitleFont { ImGuiPushFont(bold, 0.0) }
        ImGuiPushStyleColor(Int32(ImGuiCol_Text.rawValue), theme.brandGold)
        ImGuiTextV("Hatch")
        ImGuiPopStyleColor(1)
        if engine.ui.boldFont != nil || engine.ui.commandTitleFont != nil { ImGuiPopFont() }
        
        if !settings.showModeSection {
            ImGuiSameLine(0, 8.0 * uiScale)
            ImGuiPushStyleColor(Int32(ImGuiCol_Text.rawValue), theme.textDim)
            ImGuiTextV("[ 1 SELECTED ]")
            ImGuiPopStyleColor(1)
        }

        // Close button '✕' on right
        ImGuiSameLine(0, 0)
        let closeX = pad + contentW - controlH
        if ImGuiGetCursorPosX() < closeX {
            ImGuiSetCursorPosX(closeX)
        }
        ImGuiPushStyleColor(Int32(ImGuiCol_Button.rawValue), ImVec4(x: 0, y: 0, z: 0, w: 0))
        ImGuiPushStyleColor(Int32(ImGuiCol_ButtonHovered.rawValue), theme.dangerBg)
        ImGuiPushStyleColor(Int32(ImGuiCol_ButtonActive.rawValue), theme.dangerBg)
        ImGuiPushStyleColor(Int32(ImGuiCol_Text.rawValue), theme.textDim)
        if igButton("✕##HatchClose", ImVec2(x: controlH, y: controlH)) {
            settings.closeRequested = true
        }
        ImGuiPopStyleColor(4)
        igEndGroup()
        
        ImGuiDummy(ImVec2(x: 0, y: 8.0 * uiScale))

        // --- Fill Type Segments ---
        let fillTypeTabs = [
            (label: "Pattern", value: 0),
            (label: "Gradient", value: 2),
            (label: "Solid", value: 1),
            (label: "User", value: 3)
        ]
        
        let segW = max(48.0 * uiScale, (contentW - itemGap * 3.0) / 4.0)
        for (idx, tab) in fillTypeTabs.enumerated() {
            if idx > 0 { ImGuiSameLine(0, itemGap) }
            let isSelected = settings.fillType == Int32(tab.value)
            if renderSegmentButton(
                label: tab.label,
                isSelected: isSelected,
                size: ImVec2(x: segW, y: controlH),
                engine: engine) {
                settings.fillType = Int32(tab.value)
            }
        }
        
        ImGuiDummy(ImVec2(x: 0, y: 12.0 * uiScale))

        // --- Preview Area ---
        let previewH: Float = 84.0 * uiScale
        let pScreenPos = igGetCursorScreenPos()
        let pMin = ImVec2(x: pScreenPos.x, y: pScreenPos.y)
        let pMax = ImVec2(x: pMin.x + contentW, y: pMin.y + previewH)
        


        
        if settings.fillType == 2 {
            let c1 = settings.primaryColor ?? ColorRGBA(r: 255, g: 255, b: 255, a: 255)
            let c1U32 = makeCol32(c1.r, c1.g, c1.b, c1.a)
            let c2 = settings.secondaryColor ?? ColorRGBA(
                r: UInt8(min(255, Int(c1.r) + 60)),
                g: UInt8(min(255, Int(c1.g) + 60)),
                b: UInt8(min(255, Int(c1.b) + 60)),
                a: c1.a)
            let c2U32 = makeCol32(c2.r, c2.g, c2.b, c2.a)
            ImDrawListAddRectFilledMultiColor(dl, pMin, pMax, c1U32, c2U32, c2U32, c1U32)
        } else {
            let previewBgU32: UInt32 = {
                if settings.fillType == 0, let bg = settings.backgroundColor {
                    return makeCol32(bg.r, bg.g, bg.b, bg.a)
                }
                return makeCol32(24, 26, 32, 255)
            }()
            ImDrawListAddRectFilled(dl, pMin, pMax, previewBgU32, 8.0 * uiScale, 0)

            let fgU32: UInt32 = {
                if let c = settings.primaryColor {
                    return makeCol32(c.r, c.g, c.b, c.a)
                }
                if let bg = settings.backgroundColor {
                    let lum = 0.299 * Double(bg.r) + 0.587 * Double(bg.g) + 0.114 * Double(bg.b)
                    return lum > 140 ? makeCol32(20, 20, 20, 255) : makeCol32(240, 240, 240, 255)
                }
                return makeCol32(220, 220, 220, 255)
            }()
            
            if settings.fillType == 0 {
                renderPatternPreview(
                    patternKey: settings.patternName,
                    angleRadians: Double(settings.angle),
                    pMin: pMin,
                    pMax: pMax,
                    color: fgU32,
                    uiScale: uiScale,
                    drawList: dl)
            } else if settings.fillType == 1 {
                let solidU32 = settings.primaryColor != nil ? fgU32 : makeCol32(220, 220, 220, 255)
                ImDrawListAddRectFilled(dl, pMin, pMax, solidU32, 8.0 * uiScale, 0)
            }
        }
        ImDrawListAddRect(dl, pMin, pMax, igGetColorU32_Vec4(theme.border), 8.0 * uiScale, 1.0 * uiScale, 0)
        
        // Pattern / Gradient Name Badge in bottom left
        let badgeText = settings.fillType == 0
            ? DXFHatchGenerator.patternDisplayName(for: settings.patternName)
            : (settings.fillType == 2 ? settings.gradientName.capitalized : "Solid")
        let badgeSize = igCalcTextSize(badgeText, nil, false, -1.0)
        let badgeMin = ImVec2(x: pMin.x + 8.0 * uiScale, y: pMax.y - badgeSize.y - 12.0 * uiScale)
        let badgeMax = ImVec2(x: badgeMin.x + badgeSize.x + 12.0 * uiScale, y: badgeMin.y + badgeSize.y + 8.0 * uiScale)
        ImDrawListAddRectFilled(dl, badgeMin, badgeMax, makeCol32(40, 40, 40, 200), 4.0 * uiScale, 0)
        
        ImGuiDummy(ImVec2(x: contentW, y: previewH))
        
        let oldPos = igGetCursorScreenPos()
        ImGuiSetCursorScreenPos(ImVec2(x: badgeMin.x + 6.0 * uiScale, y: badgeMin.y + 4.0 * uiScale))
        ImGuiPushStyleColor(Int32(ImGuiCol_Text.rawValue), makeCol32(240, 240, 240, 255))
        ImGuiTextV(badgeText)
        ImGuiPopStyleColor(1)
        ImGuiSetCursorScreenPos(oldPos)
        
        ImGuiDummy(ImVec2(x: 0, y: 12.0 * uiScale))

        if settings.fillType == 0 {
            renderPatternBrowser(
                settings: &settings,
                contentWidth: contentW,
                controlHeight: controlH,
                uiScale: uiScale,
                engine: engine)
            ImGuiDummy(ImVec2(x: 0, y: 12.0 * uiScale))
        }

        // Colors
        if settings.fillType == 0 || settings.fillType == 1 {
            ImGuiTextV(settings.fillType == 0 ? "Pattern color" : "Color")
            renderColorPresetRow(id: 1, currentColor: &settings.primaryColor, engine: engine)
            
            if settings.fillType == 0 {
                ImGuiDummy(ImVec2(x: 0, y: 8.0 * uiScale))
                var hasBg = settings.backgroundColor != nil
                if igCheckbox("Background color", &hasBg) {
                    if hasBg {
                        settings.backgroundColor = lastUsedBackgroundColor
                    } else {
                        if let current = settings.backgroundColor {
                            lastUsedBackgroundColor = current
                        }
                        settings.backgroundColor = nil
                    }
                }
                if hasBg {
                    ImGuiDummy(ImVec2(x: 0, y: 4.0 * uiScale))
                    renderColorPresetRow(id: 2, currentColor: &settings.backgroundColor, engine: engine)
                    if let current = settings.backgroundColor {
                        lastUsedBackgroundColor = current
                    }
                }
            }
        } else if settings.fillType == 2 {
            ImGuiDummy(ImVec2(x: 0, y: 8.0 * uiScale))
            ImGuiTextV("Type")
            let gradients = ["LINEAR", "CYLINDER", "INVCYLINDER", "SPHERICAL", "HEMISPHERICAL", "CURVED", "INVCURVED", "INVSPHERICAL", "INVHEMISPHERICAL"]
            if let currentIdx = gradients.firstIndex(of: settings.gradientName.uppercased()) {
                var idx = Int32(currentIdx)
                ImGuiPushItemWidth(-1)
                // Use a C array of C strings for Combo
                let cStrings = gradients.map { z_strdup($0) }
                var cPointers: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) }
                if igCombo_Str_arr("##GradientCombo", &idx, &cPointers, Int32(gradients.count), -1) {
                    settings.gradientName = gradients[Int(idx)]
                }
                ImGuiPopItemWidth()
                for cStr in cStrings { free(cStr) }
            } else {
                var idx: Int32 = 0
                ImGuiPushItemWidth(-1)
                let cStrings = gradients.map { z_strdup($0) }
                var cPointers: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) }
                if igCombo_Str_arr("##GradientCombo", &idx, &cPointers, Int32(gradients.count), -1) {
                    settings.gradientName = gradients[Int(idx)]
                }
                ImGuiPopItemWidth()
                for cStr in cStrings { free(cStr) }
            }

            ImGuiDummy(ImVec2(x: 0, y: 12.0 * uiScale))
            ImGuiTextV("Start color")
            renderColorPresetRow(id: 1, currentColor: &settings.primaryColor, engine: engine)
            ImGuiDummy(ImVec2(x: 0, y: 8.0 * uiScale))
            ImGuiTextV("Stop color")
            renderColorPresetRow(id: 3, currentColor: &settings.secondaryColor, engine: engine)
        }
        
        ImGuiDummy(ImVec2(x: 0, y: 12.0 * uiScale))
        
        // Sliders
        ImGuiTextV("Angle")
        ImGuiPushItemWidth(-1)
        ImGuiSliderAngle("##HatchAngle", &settings.angle, -180, 180, "%.0f", ImGuiSliderFlags(0))
        ImGuiPopItemWidth()
        
        if settings.fillType == 0 {
            ImGuiDummy(ImVec2(x: 0, y: 8.0 * uiScale))
            ImGuiTextV("Scale")
            ImGuiPushItemWidth(-1)
            ImGuiInputFloat("##HatchScale", &settings.scale, 0.1, 1.0, "%.2f", 0)
            ImGuiPopItemWidth()
        }
        
        ImGuiDummy(ImVec2(x: 0, y: 12.0 * uiScale))
        
        // Associative Toggle
        // Swift ImGui checkbox uses inout Bool, let's use a var
        var assoc = settings.associative
        if igCheckbox("Associative boundary", &assoc) {
            settings.associative = assoc
        }

        // Island Detection Style (Normal / Outer / Ignore)
        ImGuiDummy(ImVec2(x: 0, y: 10.0 * uiScale))
        ImGuiTextV("Island detection")
        let islandTabs = [
            (label: "Normal", value: 0, tooltip: "Normal: Hatches inward from outer boundary, alternating islands"),
            (label: "Outer", value: 1, tooltip: "Outer: Hatches from outer boundary to first island only"),
            (label: "Ignore", value: 2, tooltip: "Ignore: Hatches through all internal islands")
        ]
        let islandSegW = max(48.0 * uiScale, (contentW - itemGap * 2.0) / 3.0)
        for (idx, tab) in islandTabs.enumerated() {
            if idx > 0 { ImGuiSameLine(0, itemGap) }
            let isSelected = settings.islandStyle == Int32(tab.value)
            if renderSegmentButton(
                label: tab.label + "##IslandStyle",
                isSelected: isSelected,
                size: ImVec2(x: islandSegW, y: controlH),
                engine: engine,
                tooltip: tab.tooltip) {
                settings.islandStyle = Int32(tab.value)
            }
        }
        
        // Creation Actions
        if settings.showModeSection {
            ImGuiDummy(ImVec2(x: 0, y: 16.0 * uiScale))
            
            // Pick / Boundary segmented
            let selW = max(80.0 * uiScale, (contentW - itemGap) / 2.0)
            if renderSegmentButton(
                label: "+ Pick Points",
                isSelected: settings.selectionMode == 0,
                size: ImVec2(x: selW, y: controlH),
                engine: engine) {
                settings.selectionMode = 0
            }
            ImGuiSameLine(0, itemGap)
            if renderSegmentButton(
                label: "* Boundary",
                isSelected: settings.selectionMode == 1,
                size: ImVec2(x: selW, y: controlH),
                engine: engine) {
                settings.selectionMode = 1
            }
            
            ImGuiDummy(ImVec2(x: 0, y: 12.0 * uiScale))
            
            // Apply hatch button
            let gold = engine.ui.theme.brandGold
            let goldHover = engine.ui.theme.brandGoldHover
            let goldActive = engine.ui.theme.brandGoldActive
            let darkText = engine.ui.theme.rowHoverText

            ImGuiPushStyleColor(Int32(ImGuiCol_Button.rawValue), gold)
            ImGuiPushStyleColor(Int32(ImGuiCol_ButtonHovered.rawValue), goldHover)
            ImGuiPushStyleColor(Int32(ImGuiCol_ButtonActive.rawValue), goldActive)
            ImGuiPushStyleColor(Int32(ImGuiCol_Text.rawValue), darkText)
            
            if igButton("Apply hatch", ImVec2(x: ImGuiGetContentRegionAvail().x, y: max(controlH, 40.0 * uiScale))) {
                settings.applyClicked = true
            }
            ImGuiPopStyleColor(4)
        }
    }


    private static func renderPatternBrowser(
        settings: inout Settings,
        contentWidth: Float,
        controlHeight: Float,
        uiScale: Float,
        engine: PhrostEngine
    ) {
        HatchPatternLibrary.ensureLoaded()

        var searchBuffer = [CChar](repeating: 0, count: 192)
        let bytes = patternSearchText.utf8CString
        let copyCount = min(bytes.count, searchBuffer.count - 1)
        if copyCount > 0 {
            searchBuffer.withUnsafeMutableBufferPointer { target in
                _ = target.initialize(from: bytes.prefix(copyCount))
            }
        }

        ImGuiPushItemWidth(-1)
        if igInputTextWithHint(
            "##HatchPatternSearch",
            "Search hatch patterns...",
            &searchBuffer,
            searchBuffer.count,
            0,
            nil,
            nil) {
            patternSearchText = searchBuffer.withUnsafeBufferPointer {
                String(cString: $0.baseAddress!)
            }
        }
        ImGuiPopItemWidth()

        ImGuiDummy(ImVec2(x: 0, y: 6.0 * uiScale))
        let matches = HatchPatternLibrary.search(patternSearchText)
        let fileCount = HatchPatternLibrary.loadedFiles.count
        ImGuiTextV("\(matches.count) patterns from \(fileCount) PAT file\(fileCount == 1 ? "" : "s")")

        let reloadLabel = "Reload##HatchPatterns"
        let reloadWidth = ImGuiCalcTextSize("Reload", nil, false, -1).x + 20.0 * uiScale
        ImGuiSameLine(max(0, contentWidth - reloadWidth), 0)
        if igButton(reloadLabel, ImVec2(x: reloadWidth, y: controlHeight)) {
            HatchPatternLibrary.reload()
        }

        ImGuiDummy(ImVec2(x: 0, y: 6.0 * uiScale))
        let listHeight = min(150.0 * uiScale, max(96.0 * uiScale, ImGuiGetTextLineHeightWithSpacing() * 5.0))
        let childBg = engine.ui.isDarkTheme
            ? ImVec4(x: 0.06, y: 0.14, z: 0.22, w: 0.50)
            : ImVec4(x: 1.0, y: 1.0, z: 1.0, w: 0.60)
        ImGuiPushStyleColor(Int32(ImGuiCol_ChildBg.rawValue), childBg)
        if igBeginChild_Str(
            "##HatchPatternResults",
            ImVec2(x: contentWidth, y: listHeight),
            1,
            Int32(ImGuiWindowFlags_AlwaysVerticalScrollbar.rawValue)) {
            if matches.isEmpty {
                ImGuiTextV("No matching hatch patterns")
            } else {
                for entry in matches {
                    let selected = settings.patternName.caseInsensitiveCompare(entry.key) == .orderedSame
                    let label = "\(entry.name)  [\(entry.sourceName)]##\(entry.key)"
                    if ImGuiSelectable(
                        label,
                        selected,
                        Int32(ImGuiSelectableFlags_None.rawValue),
                        ImVec2(x: 0, y: controlHeight)) {
                        settings.fillType = 0
                        settings.patternName = entry.key
                    }
                    if ImGuiIsItemHovered(0) {
                        ImGuiBeginTooltip()
                        ImGuiTextV(entry.name)
                        if !entry.description.isEmpty { ImGuiTextWrappedV(entry.description) }
                        ImGuiTextV("Source: \(entry.sourceName).pat")
                        ImGuiTextV("Definition lines: \(entry.definition.lines.count)")
                        ImGuiEndTooltip()
                    }
                }
            }
        }
        igEndChild()
        ImGuiPopStyleColor(1)
    }

    private static func renderPatternPreview(
        patternKey: String,
        angleRadians: Double,
        pMin: ImVec2,
        pMax: ImVec2,
        color: UInt32,
        uiScale: Float,
        drawList: UnsafeMutablePointer<ImDrawList>?
    ) {
        let inset = 5.0 * uiScale
        let width = max(1.0, Double(pMax.x - pMin.x - inset * 2.0))
        let height = max(1.0, Double(pMax.y - pMin.y - inset * 2.0))
        let polygon = [
            Vector3(x: 0, y: 0, z: 0),
            Vector3(x: width, y: 0, z: 0),
            Vector3(x: width, y: height, z: 0),
            Vector3(x: 0, y: height, z: 0)
        ]
        let previewScale = DXFHatchGenerator.previewScale(
            for: patternKey,
            targetSpacing: Double(10.0 * uiScale))
        let primitives = DXFHatchGenerator.generatePatternHatch(
            polygon: polygon,
            patternName: patternKey,
            scale: previewScale,
            angleDegrees: angleRadians * 180.0 / .pi,
            minimumSpacing: Double(2.0 * uiScale))

        for primitive in primitives.prefix(2048) {
            switch primitive {
            case .line(let start, let end, _):
                ImDrawListAddLine(
                    drawList,
                    ImVec2(x: pMin.x + inset + Float(start.x), y: pMin.y + inset + Float(start.y)),
                    ImVec2(x: pMin.x + inset + Float(end.x), y: pMin.y + inset + Float(end.y)),
                    color,
                    max(1.0, uiScale))
            case .point(let position, _):
                ImDrawListAddCircleFilled(
                    drawList,
                    ImVec2(x: pMin.x + inset + Float(position.x), y: pMin.y + inset + Float(position.y)),
                    max(1.0, 1.5 * uiScale),
                    color,
                    8)
            default:
                break
            }
        }
    }

    private static func renderColorPresetRow(id: Int, currentColor: inout ColorRGBA?, engine: PhrostEngine) {
        let presetColors: [ColorRGBA] = [
            ColorRGBA(r: 255, g: 90,  b: 90),
            ColorRGBA(r: 250, g: 180, b: 40),
            ColorRGBA(r: 80,  g: 220, b: 120),
            ColorRGBA(r: 40,  g: 220, b: 240),
            ColorRGBA(r: 60,  g: 140, b: 255),
            ColorRGBA(r: 160, g: 90,  b: 220),
            ColorRGBA(r: 250, g: 250, b: 250),
            ColorRGBA(r: 140, g: 150, b: 160)
        ]
        
        let uiScale = max(0.75, engine.effectiveUiScale)
        let spacing: Float = 4.0 * uiScale
        let buttonCount: Float = 9.0
        let available = ImGuiGetContentRegionAvail().x
        let buttonW = min(24.0 * uiScale, max(14.0 * uiScale, (available - spacing * (buttonCount - 1.0)) / buttonCount))
        let size = ImVec2(x: buttonW, y: max(ImGuiGetFrameHeight(), 24.0 * uiScale))
        for (i, col) in presetColors.enumerated() {
            if i > 0 { ImGuiSameLine(0, spacing) }
            
            let colU32 = makeCol32(col.r, col.g, col.b, 255)
            ImGuiPushStyleColor(Int32(ImGuiCol_Button.rawValue), colU32)
            ImGuiPushStyleColor(Int32(ImGuiCol_ButtonHovered.rawValue), colU32)
            ImGuiPushStyleColor(Int32(ImGuiCol_ButtonActive.rawValue), colU32)
            
            if igButton("##c\(id)_\(i)", size) {
                currentColor = col
            }
            
            ImGuiPopStyleColor(3)
            
            // Highlight if selected
            if currentColor == col {
                let rMin = igGetItemRectMin()
                let rMax = igGetItemRectMax()
                let highlightCol = engine.ui.isDarkTheme
                    ? makeCol32(255, 255, 255, 255)
                    : igGetColorU32_Vec4(engine.ui.theme.brandGold)
                ImDrawListAddRect(igGetWindowDrawList(), rMin, rMax, highlightCol, 4.0 * uiScale, 2.0 * uiScale, 0)
            } else {
                let rMin = igGetItemRectMin()
                let rMax = igGetItemRectMax()
                ImDrawListAddRect(igGetWindowDrawList(), rMin, rMax, makeCol32(0, 0, 0, 50), 4.0 * uiScale, 1.0 * uiScale, 0)
            }
        }
        
        // Custom + button
        ImGuiSameLine(0, spacing)
        if igButton("+##custom_\(id)", size) {
            activeColorPopup = id
            igOpenPopup_Str("##ColorPopup", 0)
        }
        
        if activeColorPopup == id && igBeginPopup("##ColorPopup", 0) {
            var col: [Float] = [0.5, 0.5, 0.5, 1.0]
            if let c = currentColor {
                col = [Float(c.r) / 255.0, Float(c.g) / 255.0, Float(c.b) / 255.0, Float(c.a) / 255.0]
            }
            if igColorEdit4("##CustomColor", &col, 0) {
                currentColor = ColorRGBA(
                    r: UInt8(Swift.max(0, Swift.min(255, col[0] * 255))),
                    g: UInt8(Swift.max(0, Swift.min(255, col[1] * 255))),
                    b: UInt8(Swift.max(0, Swift.min(255, col[2] * 255))),
                    a: UInt8(Swift.max(0, Swift.min(255, col[3] * 255))))
            }
            igEndPopup()
        }
    }

    private static func renderSegmentButton(
        label: String,
        isSelected: Bool,
        size: ImVec2,
        engine: PhrostEngine,
        tooltip: String? = nil
    ) -> Bool {
        let theme = engine.ui.theme
        let isDark = engine.ui.isDarkTheme

        let gold = theme.brandGold
        let goldHover = theme.brandGoldHover
        let goldActive = theme.brandGoldActive
        let darkText = theme.rowHoverText

        if isSelected {
            ImGuiPushStyleColor(Int32(ImGuiCol_Button.rawValue), gold)
            ImGuiPushStyleColor(Int32(ImGuiCol_ButtonHovered.rawValue), goldHover)
            ImGuiPushStyleColor(Int32(ImGuiCol_ButtonActive.rawValue), goldActive)
            ImGuiPushStyleColor(Int32(ImGuiCol_Text.rawValue), darkText)
        } else {
            if isDark {
                ImGuiPushStyleColor(Int32(ImGuiCol_Button.rawValue), makeCol32(24, 46, 66, 220))
                ImGuiPushStyleColor(Int32(ImGuiCol_ButtonHovered.rawValue), makeCol32(40, 72, 100, 255))
                ImGuiPushStyleColor(Int32(ImGuiCol_ButtonActive.rawValue), makeCol32(30, 58, 82, 255))
                ImGuiPushStyleColor(Int32(ImGuiCol_Text.rawValue), theme.textDim)
            } else {
                ImGuiPushStyleColor(Int32(ImGuiCol_Button.rawValue), ImVec4(x: 0.88, y: 0.92, z: 0.96, w: 1.0))
                ImGuiPushStyleColor(Int32(ImGuiCol_ButtonHovered.rawValue), ImVec4(x: 0.80, y: 0.87, z: 0.93, w: 1.0))
                ImGuiPushStyleColor(Int32(ImGuiCol_ButtonActive.rawValue), theme.activeBg)
                ImGuiPushStyleColor(Int32(ImGuiCol_Text.rawValue), theme.textPrimary)
            }
        }

        let clicked = igButton(label, size)
        ImGuiPopStyleColor(4)

        if isSelected {
            let rMin = igGetItemRectMin()
            let rMax = igGetItemRectMax()
            let dl = igGetWindowDrawList()
            let borderCol = isDark ? makeCol32(255, 255, 255, 180) : makeCol32(200, 140, 0, 255)
            ImDrawListAddRect(dl, rMin, rMax, borderCol, 4.0 * max(0.75, engine.effectiveUiScale), 1.0, 0)
        }

        if let tooltip, ImGuiIsItemHovered(0) {
            ImGuiBeginTooltip()
            ImGuiTextV(tooltip)
            ImGuiEndTooltip()
        }

        return clicked
    }
}

