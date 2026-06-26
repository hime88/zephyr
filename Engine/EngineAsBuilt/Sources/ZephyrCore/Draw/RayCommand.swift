import Foundation
import CSDL3
import ImGui
import SwiftSDL

// =========================================================================
// MARK: - RayCommand
// =========================================================================

/// Interactive ray: start point then direction.
/// After placing the start point, click to set direction or type an angle
/// and press Enter to create a ray at that exact angle.
@MainActor
public final class RayCommand: FeatureCommand {

    private enum State {
        case waitingForStart
        case waitingForDirection(startX: Double, startY: Double)
    }

    private var state: State = .waitingForStart
    private var currentMouseWorldX: Double = 0
    private var currentMouseWorldY: Double = 0
    private var input = DynamicNumericInput()

    public init() {}

    public func start(engine: PhrostEngine, processor: CADCommandProcessor) {
        state = .waitingForStart
        input.reset()
        input.tabCycle = [.angle]
        processor.commandPrompt = "Specify start point or enter angle (Esc to cancel)."
    }

    public func cancel(engine: PhrostEngine, processor: CADCommandProcessor) {
        state = .waitingForStart
        input.reset()
    }

    public func handleMouseClick(
        worldX: Double, worldY: Double,
        engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult {
        switch state {
        case .waitingForStart:
            state = .waitingForDirection(startX: worldX, startY: worldY)
            input.reset()
            processor.commandPrompt = "Specify direction point or type angle + Enter (Esc to cancel)."
            return .continue

        case .waitingForDirection(let startX, let startY):
            let dx = worldX - startX
            let dy = worldY - startY
            return commitRay(startX: startX, startY: startY, dx: dx, dy: dy,
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
        case .commitValue:
            return .handled  // value not used for ray
        case .commitAngle(let angleDeg):
            guard case .waitingForDirection(let sx, let sy) = state else {
                processor.commandPrompt = "Click a start point first."
                return .handled
            }
            let rad = angleDeg * .pi / 180.0
            return commitRay(startX: sx, startY: sy,
                             dx: cos(rad), dy: sin(rad),
                             engine: engine, processor: processor)
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
        case .commitValue: return .handled
        case .commitAngle(let angleDeg):
            guard case .waitingForDirection(let sx, let sy) = state else {
                processor.commandPrompt = "Click a start point first."
                return .handled
            }
            let rad = angleDeg * .pi / 180.0
            return commitRay(startX: sx, startY: sy,
                             dx: cos(rad), dy: sin(rad),
                             engine: engine, processor: processor)
        case .cancel: return .finished
        }
    }

    private func commitRay(startX: Double, startY: Double,
                           dx: Double, dy: Double,
                           engine: PhrostEngine, processor: CADCommandProcessor) -> CommandResult {
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 1e-9 else {
            processor.commandPrompt = "Direction too short. Try again."
            return .continue
        }
        let direction = Vector3(x: dx, y: dy, z: 0)
        let start = Vector3(x: startX, y: startY, z: 0)
        let prim: CADPrimitive = .ray(start: start, direction: direction)
        let entity = CADEntity(
            layerID: engine.document.activeLayerID ?? UUID(),
            localGeometry: [prim])
        engine.document.addEntity(entity)
        engine.tabManager.markActiveDirty()
        let angleDeg = atan2(dy, dx) * 180.0 / .pi
        processor.commandPrompt = "Ray created at \(String(format: "%.1f", angleDeg))°."
        return .finished
    }

    // MARK: - Overlay

    public func renderOverlay(cam: CameraTransform, engine: PhrostEngine) {
        guard case .waitingForDirection(let startX, let startY) = state else { return }

        let drawList = igGetForegroundDrawList_ViewportPtr(nil)
        let col = makeCol32(0, 255, 128, 200)

        let dx = currentMouseWorldX - startX
        let dy = currentMouseWorldY - startY
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 1e-9 else { return }
        let unitX = dx / dist
        let unitY = dy / dist

        let farDist = 25000.0
        let farX = startX + unitX * farDist
        let farY = startY + unitY * farDist

        let p1 = EngineCameraManager.worldToScreen(worldX: startX, worldY: startY, cam: cam)
        let p2 = EngineCameraManager.worldToScreen(worldX: farX, worldY: farY, cam: cam)
        ImDrawListAddLine(drawList, ImVec2(x: p1.x, y: p1.y), ImVec2(x: p2.x, y: p2.y), col, 1.5)

        // Arrowhead
        let mp = EngineCameraManager.worldToScreen(worldX: currentMouseWorldX, worldY: currentMouseWorldY, cam: cam)
        let arrowSize: Float = 8.0
        let perpX = -Float(unitY) * arrowSize * 0.5
        let perpY = Float(unitX) * arrowSize * 0.5
        ImDrawListAddLine(drawList,
                          ImVec2(x: mp.x - Float(unitX) * arrowSize + perpX,
                                 y: mp.y - Float(unitY) * arrowSize + perpY),
                          ImVec2(x: mp.x, y: mp.y), col, 2.0)
        ImDrawListAddLine(drawList,
                          ImVec2(x: mp.x - Float(unitX) * arrowSize - perpX,
                                 y: mp.y - Float(unitY) * arrowSize - perpY),
                          ImVec2(x: mp.x, y: mp.y), col, 2.0)

        // Angle label
        let angleDeg = atan2(dy, dx) * 180.0 / .pi
        let midX = (startX + currentMouseWorldX) / 2
        let midY = (startY + currentMouseWorldY) / 2
        let midScreen = EngineCameraManager.worldToScreen(worldX: midX, worldY: midY, cam: cam)
        let label = String(format: "<%.1f°", angleDeg)
        ImDrawListAddText(drawList, ImVec2(x: midScreen.x, y: midScreen.y),
                          makeCol32(255, 255, 255, 200), label, nil)

        input.renderOverlay(cam: cam, worldX: currentMouseWorldX, worldY: currentMouseWorldY)
    }
}
