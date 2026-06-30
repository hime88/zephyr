import Foundation
import CSDL3
import ImGui
import SwiftSDL

// =========================================================================
// MARK: - EllipseCommand
// =========================================================================

/// Interactive ellipse: center, major axis endpoint, minor axis point.
/// After placing the center, type a major axis length + Enter. After the major
/// axis is placed, type a minor axis length + Enter to create the ellipse.
@MainActor
public final class EllipseCommand: FeatureCommand {

    private enum State {
        case waitingForCenter
        case waitingForMajorAxis(centerX: Double, centerY: Double)
        case waitingForMinorAxis(centerX: Double, centerY: Double, majorX: Double, majorY: Double)
    }

    private var state: State = .waitingForCenter
    private var currentMouseWorldX: Double = 0
    private var currentMouseWorldY: Double = 0
    private var input = DynamicNumericInput()

    public init() {}

    public func start(engine: PhrostEngine, processor: CADCommandProcessor) {
        state = .waitingForCenter
        input.reset()
        input.tabCycle = [.distance]      // "distance" = axis length at each step
        processor.commandPrompt = "Specify center point (Esc to cancel)."
    }

    public func cancel(engine: PhrostEngine, processor: CADCommandProcessor) {
        state = .waitingForCenter
        input.reset()
    }

    public func handleMouseClick(
        worldX: Double, worldY: Double,
        engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult {
        switch state {
        case .waitingForCenter:
            state = .waitingForMajorAxis(centerX: worldX, centerY: worldY)
            input.reset()
            processor.commandPrompt = "Specify end of major axis or type length + Enter (Esc to cancel)."
            return .continue

        case .waitingForMajorAxis(let cx, let cy):
            let dx = worldX - cx
            let dy = worldY - cy
            let dist = sqrt(dx * dx + dy * dy)
            guard dist > 1e-9 else {
                processor.commandPrompt = "Major axis too short. Try again."
                return .continue
            }
            state = .waitingForMinorAxis(centerX: cx, centerY: cy,
                                         majorX: worldX, majorY: worldY)
            input.reset()
            processor.commandPrompt = "Specify end of minor axis or type length + Enter (Esc to cancel)."
            return .continue

        case .waitingForMinorAxis(let cx, let cy, let mx, let my):
            return commitEllipse(cx: cx, cy: cy, mx: mx, my: my,
                                 worldX: worldX, worldY: worldY,
                                 engine: engine, processor: processor)
        }
    }

    public func handleMouseMotion(
        worldX: Double, worldY: Double,
        engine: PhrostEngine, processor: CADCommandProcessor
    ) {
        currentMouseWorldX = worldX
        currentMouseWorldY = worldY
    }

    public func handleKeyDown(
        scancode: SDL_Scancode, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult {
        let dynResult = input.handleKey(scancode)
        switch dynResult {
        case .ignored:
            break
        case .consumed:
            return .handled
        case .commitValue(let axisLength):
            return handleAxisLength(axisLength, engine: engine, processor: processor)
        case .commitAngle:
            return .handled
        case .cancel:
            return .finished
        }

        switch scancode {
        case SDL_SCANCODE_ESCAPE:
            return .finished
        default:
            return .continue
        }
    }

    public func handleCommandText(
        _ text: String, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult {
        let dynResult = input.handleText(text)
        switch dynResult {
        case .ignored:  return .continue
        case .consumed: return .handled
        case .commitValue(let len): return handleAxisLength(len, engine: engine, processor: processor)
        case .commitAngle: return .handled
        case .cancel: return .finished
        }
    }

    /// Handle a typed axis length depending on the current state.
    private func handleAxisLength(_ length: Double,
                                   engine: PhrostEngine,
                                   processor: CADCommandProcessor) -> CommandResult {
        guard length > 1e-9 else {
            processor.commandPrompt = "Length must be positive."
            return .handled
        }
        switch state {
        case .waitingForMajorAxis(let cx, let cy):
            // Place major axis endpoint at this length in the mouse direction
            let dx = currentMouseWorldX - cx
            let dy = currentMouseWorldY - cy
            let dist = hypot(dx, dy)
            let unitX: Double, unitY: Double
            if dist > 1e-9 {
                unitX = dx / dist
                unitY = dy / dist
            } else {
                unitX = 1; unitY = 0
            }
            let mx = cx + unitX * length
            let my = cy + unitY * length
            state = .waitingForMinorAxis(centerX: cx, centerY: cy, majorX: mx, majorY: my)
            input.reset()
            processor.commandPrompt = "Major axis: \(String(format: "%.2f", length)). Specify minor axis or type length + Enter."
            return .handled

        case .waitingForMinorAxis(let cx, let cy, let mx, let my):
            // Place minor axis at the given length perpendicular to the major axis
            let majorDx = mx - cx
            let majorDy = my - cy
            let angle = atan2(majorDy, majorDx)
            let perpX = -sin(angle)
            let perpY = cos(angle)
            // Determine which side of the major axis the cursor is on
            let cursorDx = currentMouseWorldX - cx
            let cursorDy = currentMouseWorldY - cy
            let dot = cursorDx * perpX + cursorDy * perpY
            let sign = dot >= 0 ? 1.0 : -1.0
            let minorLen = length
            let worldX = cx + perpX * minorLen * sign
            let worldY = cy + perpY * minorLen * sign
            return commitEllipse(cx: cx, cy: cy, mx: mx, my: my,
                                 worldX: worldX, worldY: worldY,
                                 engine: engine, processor: processor)

        default:
            return .handled
        }
    }

    private func commitEllipse(cx: Double, cy: Double,
                               mx: Double, my: Double,
                               worldX: Double, worldY: Double,
                               engine: PhrostEngine, processor: CADCommandProcessor) -> CommandResult {
        let center = Vector3(x: cx, y: cy, z: 0)
        let majorAxis = Vector3(x: mx - cx, y: my - cy, z: 0)
        let majorLen = majorAxis.magnitude
        let angle = atan2(majorAxis.y, majorAxis.x)

        let dx = worldX - cx
        let dy = worldY - cy
        let perp = Vector3(x: -sin(angle), y: cos(angle), z: 0)
        let minorDist = abs(dx * perp.x + dy * perp.y)
        let minorRatio = majorLen > 1e-9 ? minorDist / majorLen : 0.5

        guard minorRatio > 1e-9 else {
            processor.commandPrompt = "Minor axis too short. Try again."
            return .continue
        }

        let prim: CADPrimitive = .ellipse(center: center, majorAxis: majorAxis,
                                           minorRatio: minorRatio)
        let entity = CADEntity(
            layerID: engine.document.activeLayerID ?? UUID(),
            localGeometry: [prim])
        engine.document.addEntity(entity)
        engine.tabManager.markActiveDirty()
        processor.commandPrompt = "Ellipse created (major=\(String(format: "%.2f", majorLen)), ratio=\(String(format: "%.3f", minorRatio)))."
        return .finished
    }

    // MARK: - Overlay

    public func renderOverlay(cam: CameraTransform, engine: PhrostEngine) {
        let drawList = igGetForegroundDrawList_ViewportPtr(nil)
        let col = makeCol32(0, 255, 128, 200)

        switch state {
        case .waitingForCenter:
            break

        case .waitingForMajorAxis(let cx, let cy):
            let cp = EngineCameraManager.worldToScreen(worldX: cx, worldY: cy, cam: cam)
            let mp = EngineCameraManager.worldToScreen(worldX: currentMouseWorldX, worldY: currentMouseWorldY, cam: cam)
            ImDrawListAddLine(drawList, ImVec2(x: cp.x, y: cp.y), ImVec2(x: mp.x, y: mp.y), col, 1.5)
            let dist = hypot(currentMouseWorldX - cx, currentMouseWorldY - cy)
            let midX = (cx + currentMouseWorldX) / 2
            let midY = (cy + currentMouseWorldY) / 2
            let midScreen = EngineCameraManager.worldToScreen(worldX: midX, worldY: midY, cam: cam)
            let label = String(format: "%.2f", dist)
            ImDrawListAddText(drawList, ImVec2(x: midScreen.x, y: midScreen.y),
                              makeCol32(255, 255, 255, 200), label, nil)

        case .waitingForMinorAxis(let cx, let cy, let mx, let my):
            let majorAxis = Vector3(x: mx - cx, y: my - cy, z: 0)
            let majorLen = majorAxis.magnitude
            let angle = atan2(majorAxis.y, majorAxis.x)

            let dx = currentMouseWorldX - cx
            let dy = currentMouseWorldY - cy
            let perpX = -sin(angle)
            let perpY = cos(angle)
            let minorDist = abs(dx * perpX + dy * perpY)
            let minorRatio = majorLen > 1e-9 ? minorDist / majorLen : 0.5
            let minorLen = majorLen * minorRatio

            let segments = 64
            let cosRot = cos(angle)
            let sinRot = sin(angle)
            var pts: [ImVec2] = []
            for i in 0...segments {
                let t = Double(i) * 2.0 * .pi / Double(segments)
                let px = majorLen * cos(t)
                let py = minorLen * sin(t)
                let rx = px * cosRot - py * sinRot + cx
                let ry = px * sinRot + py * cosRot + cy
                let sp = EngineCameraManager.worldToScreen(worldX: rx, worldY: ry, cam: cam)
                pts.append(ImVec2(x: sp.x, y: sp.y))
            }
            pts.withUnsafeBufferPointer { buf in
                ImDrawListAddPolyline(drawList, buf.baseAddress, Int32(pts.count), col, 1.5, ImDrawFlags(0))
            }

            let cp = EngineCameraManager.worldToScreen(worldX: cx, worldY: cy, cam: cam)
            let mp = EngineCameraManager.worldToScreen(worldX: mx, worldY: my, cam: cam)
            let ep1 = EngineCameraManager.worldToScreen(worldX: cx + perpX * minorLen,
                                                        worldY: cy + perpY * minorLen, cam: cam)
            let ep2 = EngineCameraManager.worldToScreen(worldX: cx - perpX * minorLen,
                                                        worldY: cy - perpY * minorLen, cam: cam)
            let axisCol = makeCol32(255, 255, 100, 100)
            ImDrawListAddLine(drawList, ImVec2(x: cp.x, y: cp.y), ImVec2(x: mp.x, y: mp.y), axisCol, 1.0)
            ImDrawListAddLine(drawList, ImVec2(x: ep1.x, y: ep1.y), ImVec2(x: ep2.x, y: ep2.y), axisCol, 1.0)
        }

        // Dynamic input pill
        if case .waitingForCenter = state {} else {
            input.renderOverlay(cam: cam, worldX: currentMouseWorldX, worldY: currentMouseWorldY)
        }
    }
}
