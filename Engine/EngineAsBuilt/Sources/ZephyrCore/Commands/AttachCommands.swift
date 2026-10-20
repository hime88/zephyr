import Foundation
import CSDL3
import ImGui

// =========================================================================
// ATTACH — umbrella reference attach (drawings → XATTACH flow,
// raster images → IMAGEATTACH, PDFs → PDFATTACH).
// IMAGEATTACH / PDFATTACH — referenced (live-linked) media placement.
// -ATTACH — command-line variant with per-type prompts.
// Embedded flows stay separate: IMAGE and PDFIMPORT.
// =========================================================================

@MainActor
enum MediaCommandSupport {
    static func tabContext(engine: PhrostEngine) -> (
        store: MediaReferenceStore, documents: [CADDocument],
        active: CADDocument, hostFolder: String?
    )? {
        guard let tab = engine.tabManager.activeTab else { return nil }
        return (
            tab.mediaStore,
            tab.drawingViews.map(\.document),
            engine.document,
            tab.fileURL?.deletingLastPathComponent().path)
    }

    /// Hand control to a follow-up feature command.
    static func handOff(
        to command: FeatureCommand, processor: CADCommandProcessor,
        start: (PhrostEngine, CADCommandProcessor) -> Void,
        engine: PhrostEngine
    ) -> CommandResult {
        processor.activeFeatureCommand = command
        start(engine, processor)
        return .continue
    }
}

/// Shared placement flow for IMAGEATTACH / PDFATTACH / -ATTACH media:
/// point → scale → rotation, then insert the instance.
@MainActor
final class MediaPlacementFlow {
    enum Stage { case awaitingPoint, awaitingScale, awaitingRotation, done }

    private(set) var stage: Stage = .done
    private var definitionName = ""
    private var kind: MediaReferenceKind = .image
    private var naturalWidth: Double = 0
    private var naturalHeight: Double = 0
    private var center: Vector3 = .zero
    private var scale: Double = 1
    var mouseWorldX: Double = 0
    var mouseWorldY: Double = 0

    func begin(
        name: String, kind: MediaReferenceKind,
        naturalWidth: Double, naturalHeight: Double,
        processor: CADCommandProcessor
    ) {
        definitionName = name
        self.kind = kind
        self.naturalWidth = naturalWidth
        self.naturalHeight = naturalHeight
        stage = .awaitingPoint
        XrefCommandSupport.showCanvasPrompt(
            "Specify insertion point for \"\(name)\":", processor: processor)
    }

    func handleClick(worldX: Double, worldY: Double, processor: CADCommandProcessor) -> CommandResult? {
        guard stage == .awaitingPoint else { return nil }
        center = Vector3(x: worldX, y: worldY, z: 0)
        stage = .awaitingScale
        XrefCommandSupport.openTextPrompt("Specify scale factor <1>:", processor: processor)
        return .continue
    }

    func handleText(_ text: String, engine: PhrostEngine, processor: CADCommandProcessor) -> CommandResult? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch stage {
        case .awaitingScale:
            scale = Double(input) ?? 1
            if scale <= 0 { scale = 1 }
            stage = .awaitingRotation
            XrefCommandSupport.openTextPrompt("Specify rotation angle <0>:", processor: processor)
            return .continue
        case .awaitingRotation:
            let rotation = Double(input) ?? 0
            let layerID = engine.document.activeLayerID
                ?? engine.document.allLayers.first?.handle ?? UUID()
            let entity = MediaManager.makeInstance(
                name: definitionName, kind: kind,
                naturalWidth: naturalWidth, naturalHeight: naturalHeight,
                center: center, scale: scale, rotationDegrees: rotation,
                layerID: layerID)
            engine.document.addEntity(entity)
            engine.tabManager.markActiveDirty()
            print("[Attach] Placed '\(definitionName)' at (\(center.x), \(center.y))")
            stage = .done
            return .finished
        default:
            return nil
        }
    }

    func renderPreview(cam: CameraTransform) {
        guard stage == .awaitingPoint, naturalWidth > 0, naturalHeight > 0 else { return }
        let drawList = igGetForegroundDrawList_ViewportPtr(nil)
        let color = makeCol32(255, 217, 51, 230)
        let hw = naturalWidth / 2, hh = naturalHeight / 2
        let corners = [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]
        let screen = corners.map { c in
            EngineCameraManager.worldToScreen(
                worldX: mouseWorldX + c.0, worldY: mouseWorldY + c.1, cam: cam)
        }
        for i in screen.indices {
            let a = screen[i]
            let b = screen[(i + 1) % screen.count]
            ImDrawListAddLine(
                drawList, ImVec2(x: a.x, y: a.y), ImVec2(x: b.x, y: b.y), color, 1.5)
        }
    }
}

// MARK: - IMAGEATTACH

public final class ImageAttachCommand: FeatureCommand {
    public var name: String { "IMAGEATTACH" }
    public var isSnappingEnabled: Bool { true }
    public func getDrawingSnapPoints() -> [Vector3] { [] }
    public func renderImGui(engine: PhrostEngine) {}

    private let placement = MediaPlacementFlow()
    private var finished = false

    public init() {}

    public func start(engine: PhrostEngine, processor: CADCommandProcessor) {
        processor.commandPrompt = "Select image file to attach (Esc to cancel)…"
        processor.commandLineActive = false
        NativeFileDialog.showOpenDialog(
            window: engine.dialogParentWindow,
            filters: [NativeFileDialog.Filter(
                label: "Images",
                extensions: Array(CADImageAsset.supportedExtensions).sorted())]
        ) { [weak self, weak processor] urls in
            guard let self, let processor else { return }
            MainActor.assumeIsolated {
                guard let url = urls.first else {
                    self.finished = true
                    processor.activeFeatureCommand = nil
                    return
                }
                self.attachPicked(url, engine: engine, processor: processor)
            }
        }
    }

    /// Entry for ATTACH/-ATTACH routing: file already chosen.
    public func startWithPickedFile(
        _ url: URL, engine: PhrostEngine, processor: CADCommandProcessor
    ) {
        attachPicked(url, engine: engine, processor: processor)
    }

    private func attachPicked(_ url: URL, engine: PhrostEngine, processor: CADCommandProcessor) {
        guard let ctx = MediaCommandSupport.tabContext(engine: engine) else {
            finished = true
            return
        }
        do {
            let def = try MediaManager.attachImage(
                store: ctx.store, documents: ctx.documents, activeDocument: ctx.active,
                fileURL: url, pathType: XrefSysvars.refPathType, hostFolder: ctx.hostFolder)
            placement.begin(
                name: def.name, kind: .image,
                naturalWidth: Double(def.pixelWidth), naturalHeight: Double(def.pixelHeight),
                processor: processor)
        } catch {
            print("[Attach] Image attach failed: \(error)")
            finished = true
        }
    }

    public func cancel(engine: PhrostEngine, processor: CADCommandProcessor) { finished = true }

    public func handleKeyDown(
        scancode: SDL_Scancode, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult { .continue }

    public func handleCommandText(
        _ text: String, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult {
        placement.handleText(text, engine: engine, processor: processor)
            ?? (finished ? .finished : .continue)
    }

    public func handleMouseClick(
        worldX: Double, worldY: Double, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult {
        placement.handleClick(worldX: worldX, worldY: worldY, processor: processor)
            ?? (finished ? .finished : .continue)
    }

    public func handleMouseMotion(
        worldX: Double, worldY: Double, engine: PhrostEngine, processor: CADCommandProcessor
    ) {
        placement.mouseWorldX = worldX
        placement.mouseWorldY = worldY
    }

    public func renderOverlay(cam: CameraTransform, engine: PhrostEngine) {
        placement.renderPreview(cam: cam)
    }
}

// MARK: - PDFATTACH

public final class PdfAttachCommand: FeatureCommand {
    public var name: String { "PDFATTACH" }
    public var isSnappingEnabled: Bool { true }
    public func getDrawingSnapPoints() -> [Vector3] { [] }
    public func renderImGui(engine: PhrostEngine) {}

    private enum Stage { case awaitingFile, awaitingPage, placing, done }
    private var stage: Stage = .awaitingFile
    private var pickedURL: URL?
    private var pageCount: Int = 1
    private let placement = MediaPlacementFlow()

    public init() {}

    public func start(engine: PhrostEngine, processor: CADCommandProcessor) {
        processor.commandPrompt = "Select PDF file to attach (Esc to cancel)…"
        processor.commandLineActive = false
        NativeFileDialog.showOpenDialog(
            window: engine.dialogParentWindow,
            filters: [NativeFileDialog.Filter(label: "PDF", extensions: ["pdf"])]
        ) { [weak self, weak processor] urls in
            guard let self, let processor else { return }
            MainActor.assumeIsolated {
                guard let url = urls.first else {
                    self.stage = .done
                    processor.activeFeatureCommand = nil
                    return
                }
                self.beginWithFile(url, engine: engine, processor: processor)
            }
        }
    }

    /// Entry for ATTACH routing: file already chosen.
    public func startWithPickedFile(
        _ url: URL, engine: PhrostEngine, processor: CADCommandProcessor
    ) {
        beginWithFile(url, engine: engine, processor: processor)
    }

    /// Entry for -ATTACH: file and page already chosen.
    public func startWithPickedFile(
        _ url: URL, page: Int, engine: PhrostEngine, processor: CADCommandProcessor
    ) {
        pickedURL = url
        attach(page: page, engine: engine, processor: processor)
    }

    private func beginWithFile(
        _ url: URL, engine: PhrostEngine, processor: CADCommandProcessor
    ) {
        pickedURL = url
        pageCount = PDFPageRenderer.openPDF(at: url)?.pageCount ?? 1
        if pageCount <= 1 {
            attach(page: 1, engine: engine, processor: processor)
        } else {
            stage = .awaitingPage
            XrefCommandSupport.openTextPrompt(
                "Enter page number (1...\(pageCount)) <1>:", processor: processor)
        }
    }

    private func attach(page: Int, engine: PhrostEngine, processor: CADCommandProcessor) {
        guard let url = pickedURL,
              let ctx = MediaCommandSupport.tabContext(engine: engine) else {
            stage = .done
            return
        }
        do {
            let def = try MediaManager.attachPDF(
                store: ctx.store, documents: ctx.documents, activeDocument: ctx.active,
                fileURL: url, pageNumber: page,
                pathType: XrefSysvars.refPathType, hostFolder: ctx.hostFolder)
            stage = .placing
            // Placeholder page size; the loader resyncs to the true
            // page size when rendering completes.
            placement.begin(
                name: def.name, kind: .pdf,
                naturalWidth: CADPdfUnderlayParams.placeholderPageWidth,
                naturalHeight: CADPdfUnderlayParams.placeholderPageHeight,
                processor: processor)
        } catch {
            print("[Attach] PDF attach failed: \(error)")
            stage = .done
        }
    }

    public func cancel(engine: PhrostEngine, processor: CADCommandProcessor) { stage = .done }

    public func handleKeyDown(
        scancode: SDL_Scancode, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult { .continue }

    public func handleCommandText(
        _ text: String, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult {
        if stage == .awaitingPage {
            let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            attach(page: Int(input) ?? 1, engine: engine, processor: processor)
            return stage == .done ? .finished : .continue
        }
        return placement.handleText(text, engine: engine, processor: processor)
            ?? (stage == .done ? .finished : .continue)
    }

    public func handleMouseClick(
        worldX: Double, worldY: Double, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult {
        placement.handleClick(worldX: worldX, worldY: worldY, processor: processor)
            ?? (stage == .done ? .finished : .continue)
    }

    public func handleMouseMotion(
        worldX: Double, worldY: Double, engine: PhrostEngine, processor: CADCommandProcessor
    ) {
        placement.mouseWorldX = worldX
        placement.mouseWorldY = worldY
    }

    public func renderOverlay(cam: CameraTransform, engine: PhrostEngine) {
        placement.renderPreview(cam: cam)
    }
}

// MARK: - ATTACH (router)

public final class AttachCommand: FeatureCommand {
    public var name: String { "ATTACH" }
    public var isSnappingEnabled: Bool { true }
    public func getDrawingSnapPoints() -> [Vector3] { [] }
    public func renderImGui(engine: PhrostEngine) {}
    public func cancel(engine: PhrostEngine, processor: CADCommandProcessor) {}
    public func handleKeyDown(
        scancode: SDL_Scancode, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult { .continue }
    public func handleCommandText(
        _ text: String, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult { .continue }
    public func handleMouseClick(
        worldX: Double, worldY: Double, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult { .continue }
    public func handleMouseMotion(
        worldX: Double, worldY: Double, engine: PhrostEngine, processor: CADCommandProcessor
    ) {}
    public func renderOverlay(cam: CameraTransform, engine: PhrostEngine) {}

    public init() {}

    public func start(engine: PhrostEngine, processor: CADCommandProcessor) {
        processor.commandPrompt = "Select reference file to attach (Esc to cancel)…"
        processor.commandLineActive = false
        NativeFileDialog.showOpenDialog(
            window: engine.dialogParentWindow,
            filters: [
                NativeFileDialog.Filter(label: "Drawings", extensions: ["dxf", "dwg"]),
                NativeFileDialog.Filter(
                    label: "Images",
                    extensions: Array(CADImageAsset.supportedExtensions).sorted()),
                NativeFileDialog.Filter(label: "PDF", extensions: ["pdf"]),
            ]
        ) { [weak processor] urls in
            guard let processor else { return }
            MainActor.assumeIsolated {
                guard let url = urls.first else {
                    processor.activeFeatureCommand = nil
                    return
                }
                Self.route(url, engine: engine, processor: processor)
            }
        }
    }

    /// Route a chosen file to its type-specific attach flow.
    @MainActor
    static func route(_ url: URL, engine: PhrostEngine, processor: CADCommandProcessor) {
        let ext = url.pathExtension.lowercased()
        if ext == "dxf" || ext == "dwg" {
            let command = XAttachCommand()
            processor.activeFeatureCommand = command
            command.startWithPickedFile(url, engine: engine, processor: processor)
        } else if ext == "pdf" {
            let command = PdfAttachCommand()
            processor.activeFeatureCommand = command
            command.startWithPickedFile(url, engine: engine, processor: processor)
        } else if CADImageAsset.supportedExtensions.contains(ext) {
            let command = ImageAttachCommand()
            processor.activeFeatureCommand = command
            command.startWithPickedFile(url, engine: engine, processor: processor)
        } else {
            print("[Attach] Unsupported reference type: .\(ext) (drawings, images, and PDFs only)")
            processor.activeFeatureCommand = nil
        }
    }
}

// MARK: - -ATTACH (command line)

public final class MinusAttachCommand: FeatureCommand {
    public var name: String { "-ATTACH" }
    public var isSnappingEnabled: Bool { true }
    public func getDrawingSnapPoints() -> [Vector3] { [] }
    public func renderImGui(engine: PhrostEngine) {}
    public func cancel(engine: PhrostEngine, processor: CADCommandProcessor) { stage = .done }
    public func handleKeyDown(
        scancode: SDL_Scancode, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult { .continue }
    public func handleMouseClick(
        worldX: Double, worldY: Double, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult { .continue }
    public func handleMouseMotion(
        worldX: Double, worldY: Double, engine: PhrostEngine, processor: CADCommandProcessor
    ) {}
    public func renderOverlay(cam: CameraTransform, engine: PhrostEngine) {}

    private enum Stage { case awaitingPath, awaitingPage, done }
    private var stage: Stage = .awaitingPath
    private var pickedURL: URL?

    public init() {}

    public func start(engine: PhrostEngine, processor: CADCommandProcessor) {
        XrefCommandSupport.openTextPrompt("Path to file:", processor: processor)
    }

    public func handleCommandText(
        _ text: String, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch stage {
        case .awaitingPath:
            guard !input.isEmpty else { return .finished }
            let ctx = MediaCommandSupport.tabContext(engine: engine)
            let resolved = XrefPathResolver.resolve(
                savedPath: input,
                immediateHostFolder: ctx?.hostFolder,
                documentFolder: ctx?.hostFolder,
                searchPaths: ctx?.store.searchPaths ?? [])
            guard let resolved else {
                print("[Attach] File not found: \(input)")
                return .finished
            }
            let url = URL(fileURLWithPath: resolved)
            pickedURL = url
            if url.pathExtension.lowercased() == "pdf" {
                stage = .awaitingPage
                XrefCommandSupport.openTextPrompt(
                    "Page number (? lists page count) <1>:", processor: processor)
                return .continue
            }
            stage = .done
            AttachCommand.route(url, engine: engine, processor: processor)
            return .continue
        case .awaitingPage:
            guard let url = pickedURL else { return .finished }
            if input == "?" || input == "*" {
                let count = PDFPageRenderer.openPDF(at: url)?.pageCount ?? 0
                print("[Attach] \(url.lastPathComponent) has \(count) page(s)")
                XrefCommandSupport.openTextPrompt(
                    "Page number (1...\(max(1, count))) <1>:", processor: processor)
                return .continue
            }
            stage = .done
            let command = PdfAttachCommand()
            processor.activeFeatureCommand = command
            command.startWithPickedFile(
                url, page: Int(input) ?? 1, engine: engine, processor: processor)
            return .continue
        case .done:
            return .finished
        }
    }
}
