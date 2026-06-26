import Foundation
import CSDL3
import ImGui
import SwiftSDL

// =========================================================================
// MARK: - CircleCommand
// =========================================================================

/// Interactive circle drawing: center point then radius.
/// After placing the center, type a radius and press Enter to create
/// a circle at that exact radius.
@MainActor
public final class CircleCommand: FeatureCommand {

    private enum State {
        case waitingForCenter
        case waitingForRadius(centerX: Double, centerY: Double)
    }

    private var state: State = .waitingForCenter
    private var currentMouseWorldX: Double = 0
    private var currentMouseWorldY: Double = 0
    private var input = DynamicNumericInput()

    public init() {}

    public func start(engine: PhrostEngine, processor: CADCommandProcessor) {
        state = .waitingForCenter
        input.reset()
        input.tabCycle = [.distance]      // "distance" means radius here
        processor.commandPrompt = "Specify center point or enter radius (Esc to cancel)."
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
            state = .waitingForRadius(centerX: worldX, centerY: worldY)
            input.reset()
            processor.commandPrompt = "Specify radius or type value + Enter (Esc to cancel)."
            return .continue

        case .waitingForRadius(let cx, let cy):
            let center = Vector3(x: cx, y: cy, z: 0)
            let radius = sqrt((worldX - cx) * (worldX - cx) + (worldY - cy) * (worldY - cy))
            guard radius > 1e-9 else {
                processor.commandPrompt = "Radius too small. Try again."
                return .continue
            }
            return commitCircle(center: center, radius: radius, engine: engine, processor: processor)
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
        case .commitValue(let radius):
            guard case .waitingForRadius(let cx, let cy) = state else {
                processor.commandPrompt = "Click a center point first."
                return .handled
            }
            return commitCircle(center: Vector3(x: cx, y: cy, z: 0), radius: radius,
                                engine: engine, processor: processor)
        case .commitAngle:
            return .handled  // angle not used for circle
        case .cancel:
            return .finished
        }

        // Legacy keys
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
        case .commitValue(let radius):
            guard case .waitingForRadius(let cx, let cy) = state else {
                processor.commandPrompt = "Click a center point first."
                return .handled
            }
            return commitCircle(center: Vector3(x: cx, y: cy, z: 0), radius: radius,
                                engine: engine, processor: processor)
        case .commitAngle: return .handled
        case .cancel:     return .finished
        }
    }

    private func commitCircle(center: Vector3, radius: Double,
                               engine: PhrostEngine, processor: CADCommandProcessor) -> CommandResult {
        guard radius > 1e-9 else {
            processor.commandPrompt = "Radius must be positive."
            return .handled
        }
        let prim: CADPrimitive = .circle(center: center, radius: radius)
        let entity = CADEntity(
            layerID: engine.document.activeLayerID ?? UUID(),
            localGeometry: [prim])
        engine.document.addEntity(entity)
        engine.tabManager.markActiveDirty()
        processor.commandPrompt = "Circle created (r=\(String(format: "%.2f", radius)))."
        return .finished
    }

    // MARK: - Overlay

    public func renderOverlay(cam: CameraTransform, engine: PhrostEngine) {
        guard case .waitingForRadius(let cx, let cy) = state else { return }

        let drawList = igGetForegroundDrawList_ViewportPtr(nil)
        let col = makeCol32(0, 255, 128, 200)
        let radius = sqrt(
            (currentMouseWorldX - cx) * (currentMouseWorldX - cx)
                + (currentMouseWorldY - cy) * (currentMouseWorldY - cy))

        if radius > 1e-6 {
            let segments = 64
            var pts: [ImVec2] = []
            for i in 0...segments {
                let angle = Double(i) * 2.0 * .pi / Double(segments)
                let wx = cx + cos(angle) * radius
                let wy = cy + sin(angle) * radius
                let sp = EngineCameraManager.worldToScreen(worldX: wx, worldY: wy, cam: cam)
                pts.append(ImVec2(x: sp.x, y: sp.y))
            }
            pts.withUnsafeBufferPointer { buf in
                ImDrawListAddPolyline(drawList, buf.baseAddress, Int32(pts.count), col, 1.5, ImDrawFlags(0))
            }
        }

        // Crosshair at center
        let cp = EngineCameraManager.worldToScreen(worldX: cx, worldY: cy, cam: cam)
        let crossCol = makeCol32(255, 255, 255, 150)
        ImDrawListAddLine(drawList, ImVec2(x: cp.x - 6, y: cp.y), ImVec2(x: cp.x + 6, y: cp.y), crossCol, 1.0)
        ImDrawListAddLine(drawList, ImVec2(x: cp.x, y: cp.y - 6), ImVec2(x: cp.x, y: cp.y + 6), crossCol, 1.0)

        // Line from center to cursor
        let mp = EngineCameraManager.worldToScreen(worldX: currentMouseWorldX, worldY: currentMouseWorldY, cam: cam)
        ImDrawListAddLine(drawList, ImVec2(x: cp.x, y: cp.y), ImVec2(x: mp.x, y: mp.y),
                          makeCol32(0, 255, 128, 100), 1.0)

        // Show radius label
        let midX = (cx + currentMouseWorldX) / 2
        let midY = (cy + currentMouseWorldY) / 2
        let midScreen = EngineCameraManager.worldToScreen(worldX: midX, worldY: midY, cam: cam)
        let label = String(format: "R %.2f", radius)
        ImDrawListAddText(drawList, ImVec2(x: midScreen.x, y: midScreen.y),
                          makeCol32(255, 255, 255, 200), label, nil)

        // Dynamic input pill
        input.renderOverlay(cam: cam, worldX: currentMouseWorldX, worldY: currentMouseWorldY)
    }
}
