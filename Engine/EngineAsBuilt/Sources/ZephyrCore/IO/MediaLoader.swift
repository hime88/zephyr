import Foundation

// =========================================================================
// MARK: - MediaLoader
//
// Async loading for referenced images and PDF underlays, mirroring
// XrefLoader: resolve the saved path (XrefPathResolver), decode or
// rasterize off the main thread, apply on the main actor without
// touching undo or dirty state (renderRevision only).
// =========================================================================

public enum MediaLoader {

    /// Max total decoded pixels held across media references per tab.
    public static let maxTotalDecodedPixels = 512_000_000

    struct LoadOutcome: Sendable {
        var status: XrefStatus
        var detail: String?
        var foundAtPath: String?
        var modifiedAt: Date?
        var fileSize: Int?
        var asset: CADImageAsset?
        var pageWidthPoints: Double?
        var pageHeightPoints: Double?
    }

    @MainActor
    public static func loadAllPending(
        store: MediaReferenceStore, documents: [CADDocument], hostFolder: String?
    ) {
        var names: [String] = []
        for doc in documents {
            for def in doc.imageDefinitions.values {
                store.ensureEntry(kind: .image, name: def.name, savedPath: def.savedPath)
                names.append(def.name)
            }
            for def in doc.pdfDefinitions.values {
                store.ensureEntry(
                    kind: .pdf, name: def.name, savedPath: def.savedPath,
                    pageNumber: def.pageNumber)
                names.append(def.name)
            }
        }
        for name in Set(names) where store.status(forName: name) == .unloaded {
            requestLoad(store: store, name: name, documents: documents, hostFolder: hostFolder)
        }
    }

    @MainActor
    public static func requestLoad(
        store: MediaReferenceStore, name: String,
        documents: [CADDocument], hostFolder: String?,
        forceReload: Bool = false
    ) {
        guard let entry = store.entry(forName: name) else { return }
        if entry.status == .loading { return }
        if entry.status.hasShadowGeometry && !forceReload { return }
        if entry.userUnloaded && !forceReload { return }

        store.updateEntry(forName: name) {
            $0.status = .loading
            $0.statusDetail = nil
            $0.userUnloaded = false
        }
        for doc in documents { doc.markNeedsRegeneration() }

        let searchPaths = store.searchPaths
        let fallbackFolder = documents.first?.xrefSourceFolder
        let kind = entry.kind
        let savedPath = entry.savedPath
        let pageNumber = entry.pageNumber
        Task { @MainActor in
            let outcome = await Task.detached(priority: .userInitiated) {
                performLoad(
                    kind: kind, name: name, savedPath: savedPath,
                    pageNumber: pageNumber, hostFolder: hostFolder,
                    fallbackFolder: fallbackFolder, searchPaths: searchPaths)
            }.value
            apply(outcome, name: name, store: store, documents: documents)
        }
    }

    /// Nonisolated by design: touches only the lock-guarded store and
    /// plain document state, so the Lisp eval task can apply scripted
    /// attach outcomes without a MainActor hop.
    static func apply(
        _ outcome: LoadOutcome, name: String,
        store: MediaReferenceStore, documents: [CADDocument]
    ) {
        var outcome = outcome
        if outcome.status == .loaded, let asset = outcome.asset {
            let incoming = asset.pixelWidth * asset.pixelHeight
            let existing = store.entry(forName: name)?.asset
                .map { $0.pixelWidth * $0.pixelHeight } ?? 0
            if store.totalDecodedPixels() - existing + incoming > maxTotalDecodedPixels {
                outcome = LoadOutcome(
                    status: .overBudget,
                    detail: "Decoded-pixel budget reached; unload another reference first.",
                    foundAtPath: outcome.foundAtPath,
                    modifiedAt: outcome.modifiedAt, fileSize: outcome.fileSize)
            }
        }
        store.updateEntry(forName: name) { entry in
            entry.status = outcome.status
            entry.statusDetail = outcome.detail
            entry.foundAtPath = outcome.foundAtPath
            entry.fileModifiedAt = outcome.modifiedAt
            entry.fileSize = outcome.fileSize
            if outcome.status.hasShadowGeometry {
                entry.asset = outcome.asset
                entry.pageWidthPoints = outcome.pageWidthPoints
                entry.pageHeightPoints = outcome.pageHeightPoints
            } else if outcome.status != .needsReload {
                entry.asset = nil
            }
        }
        for doc in documents {
            doc.resyncMediaInstanceBounds(forName: name)
            doc.markNeedsRegeneration()
        }
    }

    @MainActor
    public static func unload(
        store: MediaReferenceStore, name: String, documents: [CADDocument]
    ) {
        store.updateEntry(forName: name) {
            $0.status = .unloaded
            $0.statusDetail = nil
            $0.asset = nil
            $0.userUnloaded = true
        }
        for doc in documents { doc.markNeedsRegeneration() }
    }

    /// Off-thread mtime/size poll → Needs Reloading (mirrors XrefLoader).
    @MainActor
    public static func checkForChanges(
        store: MediaReferenceStore, documents: [CADDocument]
    ) {
        let loaded = store.allEntries().filter { $0.status.hasShadowGeometry }
        guard !loaded.isEmpty else { return }
        let stamps: [(String, String, Date?, Int?)] = loaded.compactMap { entry in
            guard let path = entry.foundAtPath else { return nil }
            return (entry.name, path, entry.fileModifiedAt, entry.fileSize)
        }
        Task { @MainActor in
            let changed: [String] = await Task.detached {
                stamps.compactMap { name, path, mtime, size in
                    let now = fileStamp(of: path)
                    return (now.modifiedAt != mtime || now.size != size) ? name : nil
                }
            }.value
            guard !changed.isEmpty else { return }
            for name in changed {
                store.updateEntry(forName: name) {
                    if $0.status == .loaded { $0.status = .needsReload }
                }
            }
            for doc in documents { doc.markNeedsRegeneration() }
        }
    }

    static func fileStamp(of path: String) -> (modifiedAt: Date?, size: Int?) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.modificationDate] as? Date, (attrs?[.size] as? NSNumber)?.intValue)
    }

    // MARK: - Off-thread work

    static func performLoad(
        kind: MediaReferenceKind, name: String, savedPath: String,
        pageNumber: Int, hostFolder: String?, fallbackFolder: String?,
        searchPaths: [String]
    ) -> LoadOutcome {
        guard let found = XrefPathResolver.resolve(
            savedPath: savedPath,
            immediateHostFolder: hostFolder,
            documentFolder: hostFolder,
            searchPaths: searchPaths,
            fallbackFolder: fallbackFolder
        ) else {
            return LoadOutcome(
                status: .notFound,
                detail: "File not found: \(savedPath)")
        }
        let stamp = fileStamp(of: found)
        switch kind {
        case .image:
            return loadImage(name: name, path: found, stamp: stamp)
        case .pdf:
            return loadPDF(name: name, path: found, pageNumber: pageNumber, stamp: stamp)
        }
    }

    private static func loadImage(
        name: String, path: String, stamp: (modifiedAt: Date?, size: Int?)
    ) -> LoadOutcome {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        guard CADImageAsset.supportedExtensions.contains(ext) else {
            return LoadOutcome(
                status: .unresolved, detail: "Unsupported image type: .\(ext)",
                foundAtPath: path, modifiedAt: stamp.modifiedAt, fileSize: stamp.size)
        }
        if let size = stamp.size, size > CADImageAsset.maxFileBytes {
            return LoadOutcome(
                status: .unresolved, detail: "Image file too large",
                foundAtPath: path, modifiedAt: stamp.modifiedAt, fileSize: stamp.size)
        }
        guard let data = try? Data(contentsOf: url) else {
            return LoadOutcome(
                status: .unresolved, detail: "Could not read image file",
                foundAtPath: path, modifiedAt: stamp.modifiedAt, fileSize: stamp.size)
        }
        guard let dims = imageDimensions(of: data) else {
            return LoadOutcome(
                status: .unresolved, detail: "Could not decode image header",
                foundAtPath: path, modifiedAt: stamp.modifiedAt, fileSize: stamp.size)
        }
        if dims.width * dims.height > CADImageAsset.maxDecodedPixels {
            return LoadOutcome(
                status: .unresolved,
                detail: "Image too large: \(dims.width)×\(dims.height)",
                foundAtPath: path, modifiedAt: stamp.modifiedAt, fileSize: stamp.size)
        }
        let asset = CADImageAsset(
            name: name,
            originalFilename: url.lastPathComponent,
            mimeType: CADImageAsset.mimeType(forExtension: ext),
            pixelWidth: dims.width, pixelHeight: dims.height,
            sha256: CADImageAsset.sha256Hex(data),
            data: data)
        return LoadOutcome(
            status: .loaded, foundAtPath: path,
            modifiedAt: stamp.modifiedAt, fileSize: stamp.size, asset: asset)
    }

    private static func loadPDF(
        name: String, path: String, pageNumber: Int,
        stamp: (modifiedAt: Date?, size: Int?)
    ) -> LoadOutcome {
        let url = URL(fileURLWithPath: path)
        guard PDFPageRenderer.isAvailable else {
            return LoadOutcome(
                status: .unresolved, detail: "No PDF rendering backend available",
                foundAtPath: path, modifiedAt: stamp.modifiedAt, fileSize: stamp.size)
        }
        guard let info = PDFPageRenderer.openPDF(at: url) else {
            return LoadOutcome(
                status: .unresolved, detail: "Could not open PDF file",
                foundAtPath: path, modifiedAt: stamp.modifiedAt, fileSize: stamp.size)
        }
        let pageIndex = min(max(0, pageNumber - 1), info.pageCount - 1)
        let dpi = PDFPageRenderer.defaultDPI
        guard let rendered = PDFPageRenderer.renderPage(
            at: url, pageIndex: pageIndex, dpi: dpi) else {
            return LoadOutcome(
                status: .unresolved, detail: "Could not render PDF page \(pageIndex + 1)",
                foundAtPath: path, modifiedAt: stamp.modifiedAt, fileSize: stamp.size)
        }
        let asset = CADImageAsset(
            name: name,
            originalFilename: url.lastPathComponent,
            mimeType: "image/png",
            pixelWidth: rendered.pixelWidth, pixelHeight: rendered.pixelHeight,
            sha256: CADImageAsset.sha256Hex(rendered.pngData),
            data: rendered.pngData)
        return LoadOutcome(
            status: .loaded, foundAtPath: path,
            modifiedAt: stamp.modifiedAt, fileSize: stamp.size, asset: asset,
            pageWidthPoints: Double(rendered.pixelWidth) * 72.0 / Double(dpi),
            pageHeightPoints: Double(rendered.pixelHeight) * 72.0 / Double(dpi))
    }

    // MARK: - Image header probe (PNG/JPEG/GIF/BMP)

    public static func imageDimensions(of data: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data.prefix(64 * 1024))
        func u32be(_ i: Int) -> Int? {
            guard i + 3 < bytes.count else { return nil }
            return Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16
                | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
        }
        func u16be(_ i: Int) -> Int? {
            guard i + 1 < bytes.count else { return nil }
            return Int(bytes[i]) << 8 | Int(bytes[i + 1])
        }
        func u16le(_ i: Int) -> Int? {
            guard i + 1 < bytes.count else { return nil }
            return Int(bytes[i]) | Int(bytes[i + 1]) << 8
        }
        // PNG: 8-byte signature, IHDR width/height at 16/20.
        if bytes.count >= 24, bytes[0] == 0x89, bytes[1] == 0x50,
           let w = u32be(16), let h = u32be(20), w > 0, h > 0 {
            return (w, h)
        }
        // GIF: logical screen size at 6/8 little-endian.
        if bytes.count >= 10, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46,
           let w = u16le(6), let h = u16le(8), w > 0, h > 0 {
            return (w, h)
        }
        // BMP: DIB width/height at 18/22 little-endian (signed).
        if bytes.count >= 26, bytes[0] == 0x42, bytes[1] == 0x4D,
           let w = u16le(18), let w2 = u16le(20), let h = u16le(22), let h2 = u16le(24) {
            let width = w | w2 << 16
            let height = abs(h | h2 << 16)
            if width > 0, height > 0 { return (width, height) }
        }
        // JPEG: scan markers for SOF0/SOF1/SOF2.
        if bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 {
            var i = 2
            while i + 9 < bytes.count {
                guard bytes[i] == 0xFF else { break }
                let marker = bytes[i + 1]
                if marker == 0xC0 || marker == 0xC1 || marker == 0xC2 {
                    if let h = u16be(i + 5), let w = u16be(i + 7), w > 0, h > 0 {
                        return (w, h)
                    }
                    return nil
                }
                guard let segmentLength = u16be(i + 2) else { return nil }
                i += 2 + segmentLength
            }
        }
        return nil
    }
}
