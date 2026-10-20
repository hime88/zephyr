import Foundation

// =========================================================================
// MARK: - MediaManager
//
// Attach / detach / repath for referenced images and PDF underlays,
// shared by ATTACH, IMAGEATTACH, PDFATTACH, -ATTACH, and the External
// References palette. Mirrors XrefManager: definitions fan out to
// every view document, one undo step on the active document.
// =========================================================================

public enum MediaManager {

    public enum AttachError: Error, CustomStringConvertible {
        case failed(String)
        public var description: String {
            switch self { case .failed(let message): return message }
        }
    }

    /// Definition name for a file: stem, uniquified against existing
    /// media definitions in the document.
    public static func definitionName(forFileAt path: String, in document: CADDocument) -> String {
        let stem = (XrefPathResolver.fileName(of: path) as NSString).deletingPathExtension
        let base = stem.isEmpty ? "Reference" : stem
        var used = Set(document.imageDefinitions.keys.map { $0.uppercased() })
        used.formUnion(document.pdfDefinitions.keys.map { $0.uppercased() })
        var candidate = base
        var suffix = 1
        while used.contains(candidate.uppercased()) {
            suffix += 1
            candidate = "\(base)_\(suffix)"
        }
        return candidate
    }

    @MainActor
    @discardableResult
    public static func attachImage(
        store: MediaReferenceStore,
        documents: [CADDocument],
        activeDocument: CADDocument,
        fileURL: URL,
        pathType: Int,
        hostFolder: String?
    ) throws -> CADImageDefinition {
        let absolutePath = fileURL.standardizedFileURL.path
        let canonical = XrefPathResolver.canonicalPath(absolutePath)

        // Reuse an existing definition of the same file.
        for def in activeDocument.imageDefinitions.values {
            if let resolved = XrefPathResolver.resolve(
                savedPath: def.savedPath, immediateHostFolder: hostFolder,
                documentFolder: hostFolder, searchPaths: store.searchPaths),
               XrefPathResolver.canonicalPath(resolved) == canonical {
                store.ensureEntry(kind: .image, name: def.name, savedPath: def.savedPath)
                MediaLoader.requestLoad(
                    store: store, name: def.name, documents: documents, hostFolder: hostFolder)
                return def
            }
        }

        // Validate: supported type + decodable header + size caps.
        let ext = fileURL.pathExtension.lowercased()
        guard CADImageAsset.supportedExtensions.contains(ext) else {
            throw AttachError.failed("Unsupported image type: .\(ext)")
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            throw AttachError.failed("Could not read \(fileURL.lastPathComponent)")
        }
        guard data.count <= CADImageAsset.maxFileBytes else {
            throw AttachError.failed("Image file too large")
        }
        guard let dims = MediaLoader.imageDimensions(of: data) else {
            throw AttachError.failed("Could not decode image header")
        }
        guard dims.width * dims.height <= CADImageAsset.maxDecodedPixels else {
            throw AttachError.failed("Image too large: \(dims.width)×\(dims.height)")
        }

        let def = CADImageDefinition(
            name: definitionName(forFileAt: absolutePath, in: activeDocument),
            savedPath: XrefManager.savedPath(
                forFileAt: absolutePath, pathType: pathType, hostFolder: hostFolder),
            pixelWidth: dims.width, pixelHeight: dims.height)
        activeDocument.pushUndo()
        activeDocument.imageDefinitions[def.name] = def
        activeDocument.markEdited(regenerate: true)
        for doc in documents where doc !== activeDocument {
            doc.imageDefinitions[def.name] = def
        }
        store.ensureEntry(kind: .image, name: def.name, savedPath: def.savedPath)
        MediaLoader.requestLoad(
            store: store, name: def.name, documents: documents, hostFolder: hostFolder)
        return def
    }

    @MainActor
    @discardableResult
    public static func attachPDF(
        store: MediaReferenceStore,
        documents: [CADDocument],
        activeDocument: CADDocument,
        fileURL: URL,
        pageNumber: Int,
        pathType: Int,
        hostFolder: String?
    ) throws -> CADPdfDefinition {
        let absolutePath = fileURL.standardizedFileURL.path
        let canonical = XrefPathResolver.canonicalPath(absolutePath)

        guard let info = PDFPageRenderer.openPDF(at: fileURL) else {
            throw AttachError.failed("Could not open PDF file")
        }
        let page = min(max(1, pageNumber), info.pageCount)

        for def in activeDocument.pdfDefinitions.values where def.pageNumber == page {
            if let resolved = XrefPathResolver.resolve(
                savedPath: def.savedPath, immediateHostFolder: hostFolder,
                documentFolder: hostFolder, searchPaths: store.searchPaths),
               XrefPathResolver.canonicalPath(resolved) == canonical {
                store.ensureEntry(
                    kind: .pdf, name: def.name, savedPath: def.savedPath, pageNumber: page)
                MediaLoader.requestLoad(
                    store: store, name: def.name, documents: documents, hostFolder: hostFolder)
                return def
            }
        }

        let def = CADPdfDefinition(
            name: definitionName(forFileAt: absolutePath, in: activeDocument),
            savedPath: XrefManager.savedPath(
                forFileAt: absolutePath, pathType: pathType, hostFolder: hostFolder),
            pageNumber: page)
        activeDocument.pushUndo()
        activeDocument.pdfDefinitions[def.name] = def
        activeDocument.markEdited(regenerate: true)
        for doc in documents where doc !== activeDocument {
            doc.pdfDefinitions[def.name] = def
        }
        store.ensureEntry(
            kind: .pdf, name: def.name, savedPath: def.savedPath, pageNumber: page)
        MediaLoader.requestLoad(
            store: store, name: def.name, documents: documents, hostFolder: hostFolder)
        return def
    }

    /// Instance entity for a media definition (centered at `point`,
    /// natural size × scale: pixels for images, points for PDF).
    /// Pure construction — nonisolated for the Lisp eval task.
    public static func makeInstance(
        name: String, kind: MediaReferenceKind,
        naturalWidth: Double, naturalHeight: Double,
        center: Vector3, scale: Double, rotationDegrees: Double,
        layerID: UUID
    ) -> CADEntity {
        let prim = CADPrimitive.image(
            center: center,
            width: naturalWidth * scale, height: naturalHeight * scale,
            rotation: rotationDegrees * .pi / 180,
            imageName: name)
        var entity = CADEntity(
            layerID: layerID, localGeometry: [prim], transform: .identity)
        if kind == .pdf {
            var params = CADPdfUnderlayParams()
            params.scaleX = scale
            params.scaleY = scale
            params.rotation = rotationDegrees * .pi / 180
            params.pageWidthPoints = naturalWidth
            params.pageHeightPoints = naturalHeight
            CADPdfUnderlayMetadata.set(params, on: &entity)
            entity.xdata[CADClipMetadata.underlayTypeKey] = .string("PDF")
        }
        return entity
    }

    /// Remove a definition and all its instances everywhere.
    @MainActor
    public static func detach(
        store: MediaReferenceStore,
        documents: [CADDocument],
        activeDocument: CADDocument,
        name: String
    ) {
        for doc in documents {
            let doomed = doc.allEntities.filter { entity in
                (entity.localGeometry ?? []).contains { $0.imageReferenceName == name }
            }.map(\.handle)
            if !doomed.isEmpty { doc.removeEntities(handles: Set(doomed)) }
            doc.imageDefinitions.removeValue(forKey: name)
            doc.pdfDefinitions.removeValue(forKey: name)
            doc.markNeedsRegeneration()
        }
        store.removeEntry(forName: name)
    }

    /// Point a definition at a different file (same kind), then reload.
    @MainActor
    public static func repath(
        store: MediaReferenceStore,
        documents: [CADDocument],
        activeDocument: CADDocument,
        name: String, newURL: URL,
        pathType: Int, hostFolder: String?
    ) {
        let saved = XrefManager.savedPath(
            forFileAt: newURL.standardizedFileURL.path,
            pathType: pathType, hostFolder: hostFolder)
        activeDocument.pushUndo()
        defer { activeDocument.markEdited(regenerate: true) }
        for doc in documents {
            if var def = doc.imageDefinitions[name] {
                def.savedPath = saved
                doc.imageDefinitions[name] = def
            }
            if var def = doc.pdfDefinitions[name] {
                def.savedPath = saved
                doc.pdfDefinitions[name] = def
            }
        }
        store.updateEntry(forName: name) {
            $0.savedPath = saved
            $0.status = .unloaded
            $0.asset = nil
            $0.userUnloaded = false
        }
        MediaLoader.requestLoad(
            store: store, name: name, documents: documents,
            hostFolder: hostFolder, forceReload: true)
    }

    /// Convert a loaded reference into an embedded image (media Bind):
    /// copy pixels into the document asset store, retarget instances
    /// to the asset hash name, drop the definition. Returns false
    /// when nothing is loaded to embed.
    @MainActor
    @discardableResult
    public static func embed(
        store: MediaReferenceStore,
        documents: [CADDocument],
        activeDocument: CADDocument,
        name: String
    ) -> Bool {
        guard let entry = store.entry(forName: name), let runtime = entry.asset else {
            return false
        }
        let asset = CADImageAsset(
            name: runtime.sha256,
            originalFilename: runtime.originalFilename,
            mimeType: runtime.mimeType,
            pixelWidth: runtime.pixelWidth, pixelHeight: runtime.pixelHeight,
            sha256: runtime.sha256, data: runtime.data)
        for doc in documents {
            doc.imageStore[asset.name] = asset
            for entity in doc.allEntities {
                guard var geometry = entity.localGeometry,
                      geometry.contains(where: { $0.imageReferenceName == name })
                else { continue }
                for index in geometry.indices {
                    if case .image(let ins, let u, let v, let n, let clip, let tint) = geometry[index],
                       n == name {
                        geometry[index] = .image(
                            insertion: ins, uAxis: u, vAxis: v,
                            imageName: asset.name, clipBoundary: clip, tint: tint)
                    }
                }
                var copy = entity
                copy.localGeometry = geometry
                if entry.kind == .pdf {
                    CADPdfUnderlayMetadata.set(nil, on: &copy)
                }
                doc.replaceEntity(copy)
            }
            doc.imageDefinitions.removeValue(forKey: name)
            doc.pdfDefinitions.removeValue(forKey: name)
            doc.markNeedsRegeneration()
        }
        store.removeEntry(forName: name)
        return true
    }
}
