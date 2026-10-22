import Foundation
import SwiftSDL

// =========================================================================
// MARK: - ExplodeCommand
// =========================================================================

/// EXPLODE (`X`) — Breaks compound objects into their component elements.
///
/// Supports exploding:
///   - Rectangles (`.rect`, `.fillRect`) → four independent line entities
///   - Polylines and Polygons (`.polyline`, `.polygon`, etc.) → line/arc segments
///   - Associative Arrays (`CADArrayData`) → independent block references
///   - Block References (`INSERT`) → independent loose entities for each component
///   - Dimensions and Leaders → loose geometry (lines, text, arrows)
///   - Data Tables (`.table`) → lines and text entities
///   - Multi-primitive entities → individual entities per primitive
///
/// Workflow (AutoCAD convention):
///   - If entities are pre-selected when EXPLODE is called, explodes them immediately.
///   - If nothing is selected, prompts the user to select objects, then press Enter.
@MainActor
public final class ExplodeCommand: FeatureCommand {

    private enum Step {
        case selectObjects
        case done
    }

    private var step: Step = .selectObjects

    public init() {}

    public func start(engine: PhrostEngine, processor: CADCommandProcessor) {
        if engine.cadSelection.hasSelection {
            executeExplode(engine: engine, processor: processor)
        } else {
            step = .selectObjects
            processor.commandPrompt = "Select objects to explode, then press Enter"
        }
    }

    public func cancel(engine: PhrostEngine, processor: CADCommandProcessor) {
        step = .done
        processor.commandPrompt = nil
    }

    public func handleMouseClick(
        worldX: Double,
        worldY: Double,
        engine: PhrostEngine,
        processor: CADCommandProcessor
    ) -> CommandResult {
        guard step == .selectObjects else { return .finished }
        let threshold = 8.0 / max(engine.camera.zoom, 0.001)
        guard let handle = engine.cadSelection.hitTest(
            worldX: worldX,
            worldY: worldY,
            document: engine.document,
            threshold: threshold,
            simplifyComplexBlocks: engine.simplifyComplexBlocks
        ) else {
            return .handled
        }

        let shiftHeld = engine.io?.pointee.KeyShift ?? false
        if shiftHeld {
            engine.cadSelection.removeFromSelection(handle)
        } else {
            engine.cadSelection.addToSelection(handle)
        }
        processor.commandPrompt = "Select objects to explode, then press Enter (\(engine.cadSelection.selectedCount) selected)"
        return .handled
    }

    public func handleMouseMotion(
        worldX: Double,
        worldY: Double,
        engine: PhrostEngine,
        processor: CADCommandProcessor
    ) {}

    public func handleKeyDown(
        scancode: SDL_Scancode,
        engine: PhrostEngine,
        processor: CADCommandProcessor
    ) -> CommandResult {
        switch scancode {
        case SDL_SCANCODE_RETURN, SDL_SCANCODE_KP_ENTER, SDL_SCANCODE_SPACE:
            if step == .selectObjects {
                executeExplode(engine: engine, processor: processor)
                return .finished
            }
            return .finished
        case SDL_SCANCODE_ESCAPE:
            return .finished
        default:
            return .continue
        }
    }

    public func handleCommandText(
        _ text: String,
        engine: PhrostEngine,
        processor: CADCommandProcessor
    ) -> CommandResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && step == .selectObjects {
            executeExplode(engine: engine, processor: processor)
            return .finished
        }
        return .continue
    }

    public func renderOverlay(cam: CameraTransform, engine: PhrostEngine) {}
    public var isSnappingEnabled: Bool { false }

    private func executeExplode(engine: PhrostEngine, processor: CADCommandProcessor) {
        let selectedHandles = engine.cadSelection.selectedHandles
        guard !selectedHandles.isEmpty else {
            processor.commandPrompt = "No objects selected."
            processor.finishFeatureCommand(engine: engine)
            return
        }

        let exploded = engine.document.explodeEntities(handles: selectedHandles)
        if !exploded.isEmpty {
            engine.cadSelection.clearSelection()
            for handle in exploded {
                engine.cadSelection.addToSelection(handle)
            }
            engine.tabManager.markActiveDirty()
            processor.commandPrompt = "\(exploded.count) object(s) created from explosion."
        } else {
            processor.commandPrompt = "Selected object(s) could not be exploded."
        }
        processor.finishFeatureCommand(engine: engine)
    }
}
