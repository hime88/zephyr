import Foundation
import CSDL3
import SwiftSDL

@MainActor
public final class StyleCommand: FeatureCommand {
    private weak var processor: CADCommandProcessor?

    public init() {}

    public var isSnappingEnabled: Bool { false }

    public func start(engine: PhrostEngine, processor: CADCommandProcessor) {
        self.processor = processor
        engine.ui.styleManagerActive = true
        processor.commandPrompt = "Manage text styles."
    }

    public func cancel(engine: PhrostEngine, processor: CADCommandProcessor) {
        engine.ui.styleManagerActive = false
        self.processor = nil
    }

    public func handleMouseClick(
        worldX: Double,
        worldY: Double,
        engine: PhrostEngine,
        processor: CADCommandProcessor
    ) -> CommandResult {
        .handled
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
        if scancode == SDL_SCANCODE_ESCAPE {
            engine.ui.styleManagerActive = false
            return .finished
        }
        return .handled
    }

    public func renderOverlay(cam: CameraTransform, engine: PhrostEngine) {}

    public func renderImGui(engine: PhrostEngine) {
        guard !engine.ui.styleManagerActive, let processor else { return }
        processor.finishFeatureCommand(engine: engine)
        self.processor = nil
    }
}
