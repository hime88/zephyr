import ZephyrCore
import Foundation
import ImGui

@MainActor
struct StyleManagerUI {
    private static var documentID: ObjectIdentifier?
    private static var selectedName = "Standard"
    private static var originalName = "Standard"
    private static var draft = CADTextStyle.standard
    private static var message = ""
    private static var fonts: [CADFontManager.AvailableFont] = []

    static func render(engine: PhrostEngine, dw: Float, dh: Float) {
        let document = engine.document
        let currentID = ObjectIdentifier(document)
        if documentID != currentID {
            documentID = currentID
            fonts = CADFontManager.availableFonts()
            select(document.resolvedTextStyleName("Standard"), document: document)
        }

        if document.textStyle(named: selectedName) == nil {
            select(document.resolvedTextStyleName("Standard"), document: document)
        }

        let width: Float = 760
        let height: Float = 470
        ImGuiSetNextWindowPos(
            ImVec2(x: (dw - width) * 0.5, y: (dh - height) * 0.5),
            Int32(ImGuiCond_Always.rawValue),
            ImVec2(x: 0, y: 0))
        ImGuiSetNextWindowSize(ImVec2(x: width, y: height), Int32(ImGuiCond_Always.rawValue))

        var opened = true
        let flags = Int32(ImGuiWindowFlags_NoSavedSettings.rawValue)
            | Int32(ImGuiWindowFlags_NoResize.rawValue)
            | Int32(ImGuiWindowFlags_NoCollapse.rawValue)
        guard igBegin("Text Style Manager##StyleManager", &opened, flags) else {
            ImGuiEnd()
            return
        }
        defer { ImGuiEnd() }

        if !opened {
            engine.ui.styleManagerActive = false
            return
        }

        let styles = document.textStyles.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        if igBeginChild_Str("##StyleList", ImVec2(x: 220, y: -52), 1, 0) {
            ImGuiTextV("Styles")
            igSeparator()
            for style in styles {
                let selected = style.name.caseInsensitiveCompare(selectedName) == .orderedSame
                if ImGuiSelectable(style.name, selected, 0, ImVec2(x: 0, y: 0)) {
                    select(style.name, document: document)
                }
            }
        }
        igEndChild()

        ImGuiSameLine(0, 14)
        if igBeginChild_Str("##StyleProperties", ImVec2(x: 0, y: -52), 0, 0) {
            ImGuiTextV("Properties")
            igSeparator()

            inputText("Name", value: &draft.name)

            ImGuiSetNextItemWidth(-1)
            if ImGuiBeginCombo("Font", draft.fontFile, 0) {
                for font in fonts {
                    let selected = font.name.caseInsensitiveCompare(draft.fontFile) == .orderedSame
                    if ImGuiSelectable("\(font.name) [\(font.type.rawValue)]", selected, 0, ImVec2(x: 0, y: 0)) {
                        draft.fontFile = font.name
                    }
                    if selected { ImGuiSetItemDefaultFocus() }
                }
                ImGuiEndCombo()
            }

            var fixedHeight = Float(draft.fixedHeight)
            ImGuiSetNextItemWidth(180)
            if ImGuiDragFloat("Fixed height", &fixedHeight, 0.1, 0, 100000, "%.3f", ImGuiSliderFlags(0)) {
                draft.fixedHeight = Double(fixedHeight)
            }

            var widthFactor = Float(draft.widthFactor)
            ImGuiSetNextItemWidth(180)
            if ImGuiDragFloat("Width factor", &widthFactor, 0.01, 0.01, 100, "%.3f", ImGuiSliderFlags(0)) {
                draft.widthFactor = Double(widthFactor)
            }

            var oblique = Float(draft.obliqueAngle)
            ImGuiSetNextItemWidth(180)
            if ImGuiDragFloat("Oblique angle", &oblique, 0.5, -85, 85, "%.1f°", ImGuiSliderFlags(0)) {
                draft.obliqueAngle = Double(oblique)
            }

            _ = ImGuiCheckbox("Annotative", &draft.isAnnotative)
            ImGuiTextWrappedV("A fixed height of 0 uses each text entity's local height.")

            if !message.isEmpty {
                igSpacing()
                ImGuiTextWrappedV(message)
            }
        }
        igEndChild()

        if igButton("New", ImVec2(x: 90, y: 0)) {
            let name = uniqueName(document: document)
            let style = CADTextStyle(name: name)
            if document.applyTextStyle(style) {
                select(name, document: document)
                message = "Created \(name)."
            }
        }

        ImGuiSameLine(0, 8)
        let isStandard = selectedName.caseInsensitiveCompare("Standard") == .orderedSame
        if isStandard { ImGuiBeginDisabled(true) }
        if igButton("Delete", ImVec2(x: 90, y: 0)) {
            if document.deleteTextStyle(named: selectedName) {
                select(document.resolvedTextStyleName("Standard"), document: document)
                message = "Style deleted. Referencing text now uses Standard."
            }
        }
        if isStandard { ImGuiEndDisabled() }

        ImGuiSameLine(0, 8)
        if igButton("Apply", ImVec2(x: 100, y: 0)) {
            let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                message = "Style name cannot be empty."
            } else if originalName.caseInsensitiveCompare("Standard") == .orderedSame
                        && trimmed.caseInsensitiveCompare("Standard") != .orderedSame {
                message = "Standard cannot be renamed."
            } else {
                draft.name = trimmed
                if document.applyTextStyle(draft, replacing: originalName) {
                    select(trimmed, document: document)
                    message = "Style applied."
                } else {
                    message = "A style with that name already exists."
                }
            }
        }

        ImGuiSameLine(0, 8)
        if igButton("Reset", ImVec2(x: 90, y: 0)) {
            select(selectedName, document: document)
            message = ""
        }

        ImGuiSameLine(width - 112, 0)
        if igButton("Close", ImVec2(x: 90, y: 0)) {
            engine.ui.styleManagerActive = false
        }

        if ImGuiIsKeyPressed(ImGuiKey_Escape, false) {
            engine.ui.styleManagerActive = false
        }
    }

    private static func select(_ name: String, document: CADDocument) {
        let style = document.textStyle(named: name) ?? .standard
        selectedName = style.name
        originalName = style.name
        draft = style
        message = ""
    }

    private static func uniqueName(document: CADDocument) -> String {
        var index = 1
        while document.textStyle(named: "Style\(index)") != nil { index += 1 }
        return "Style\(index)"
    }

    private static func inputText(_ label: String, value: inout String) {
        let capacity = 256
        var buffer = [CChar](repeating: 0, count: capacity)
        let bytes = value.utf8CString
        for index in 0..<min(bytes.count, capacity - 1) { buffer[index] = bytes[index] }
        ImGuiSetNextItemWidth(-1)
        let changed = buffer.withUnsafeMutableBufferPointer { pointer -> Bool in
            guard let base = pointer.baseAddress else { return false }
            return igInputText(label, base, capacity, 0, { _ in 0 }, nil)
        }
        if changed {
            value = buffer.withUnsafeBufferPointer { pointer in
                String(cString: pointer.baseAddress!)
            }
        }
    }
}
