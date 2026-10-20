import Foundation

// =========================================================================
// MARK: - XrefManager
//
// Attach / detach / repath operations shared by XATTACH, -XREF, and the
// External References palette. Definitions are fanned out to every
// view document of the tab (one undo step on the active document).
// =========================================================================

public enum XrefManager {

    public enum AttachError: Error, CustomStringConvertible {
        case insertFailed(String)

        public var description: String {
            switch self {
            case .insertFailed(let message): return message
            }
        }
    }

    /// Saved-path string for an attach, per REFPATHTYPE semantics:
    /// 0 = full, 1 = relative to the host folder (full when the host is
    /// unsaved), 2 = filename only.
    public static func savedPath(
        forFileAt absolutePath: String, pathType: Int, hostFolder: String?
    ) -> String {
        // AutoCAD REFPATHTYPE: 0 = no path, 1 = relative, 2 = full.
        switch pathType {
        case 0:
            return XrefPathResolver.fileName(of: absolutePath)
        case 1:
            guard let hostFolder else { return absolutePath }
            return XrefPathResolver.relativePath(fromFolder: hostFolder, to: absolutePath)
        default:
            return absolutePath
        }
    }

    /// Attach `fileURL` as an xref in every document of the tab.
    /// Reuses the existing definition when the same file is already
    /// attached; auto-suffixes the name on collision with a different
    /// file. Kicks the load and returns the definition plus the
    /// unit-based default insertion scale for placement.
    @MainActor
    @discardableResult
    public static func attach(
        store: XrefRuntimeStore,
        documents: [CADDocument],
        activeDocument: CADDocument,
        fileURL: URL,
        isOverlay: Bool,
        pathType: Int,
        hostFolder: String?
    ) throws -> (block: CADBlock, defaultScale: Double, isNewDefinition: Bool) {
        let absolutePath = fileURL.standardizedFileURL.path
        let canonical = XrefPathResolver.canonicalPath(absolutePath)

        // Reuse an existing definition of the same file.
        for block in activeDocument.allBlocks where block.isXref {
            guard let descriptor = block.xrefDescriptor else { continue }
            let resolved = XrefPathResolver.resolve(
                savedPath: descriptor.savedPath,
                immediateHostFolder: hostFolder, documentFolder: hostFolder,
                searchPaths: store.searchPaths)
            if let resolved, XrefPathResolver.canonicalPath(resolved) == canonical {
                let imported = try? DrawingFileInsert.loadImportedFile(fromFile: absolutePath)
                let scale = CADModelSpaceBaker.unitScale(
                    from: imported?.sourceUnit, to: activeDocument.unit)
                XrefLoader.requestLoad(
                    store: store, blockHandle: block.handle,
                    documents: documents, hostFolder: hostFolder)
                return (block, scale, false)
            }
        }

        // Validate readability and seed the import cache.
        let imported: DXFImportResult
        do {
            imported = try DrawingFileInsert.loadImportedFile(fromFile: absolutePath)
        } catch let error as DrawingFileInsert.InsertError {
            throw AttachError.insertFailed("\(error)")
        }
        let stamp = XrefLoader.fileStamp(of: absolutePath)
        store.storeImport(
            canonicalPath: canonical, modifiedAt: stamp.modifiedAt,
            fileSize: stamp.size, result: imported)

        var name = DrawingFileInsert.blockName(forFilePath: absolutePath)
        let existingNames = Set(activeDocument.allBlocks.map { $0.name.uppercased() })
        if existingNames.contains(name.uppercased()) {
            var suffix = 1
            while existingNames.contains("\(name)\(suffix)".uppercased()) { suffix += 1 }
            name = "\(name)\(suffix)"
        }

        let descriptor = CADXrefDescriptor(
            savedPath: savedPath(forFileAt: absolutePath, pathType: pathType, hostFolder: hostFolder),
            isOverlay: isOverlay)
        let block = CADBlock(name: name, geometry: [], xrefDescriptor: descriptor)
        activeDocument.addBlock(block)
        for doc in documents where doc !== activeDocument {
            doc.insertBlockSilently(block)
        }
        store.ensureEntry(for: block.handle, descriptor: descriptor, blockName: name)
        XrefLoader.requestLoad(
            store: store, blockHandle: block.handle,
            documents: documents, hostFolder: hostFolder)
        let scale = CADModelSpaceBaker.unitScale(from: imported.sourceUnit, to: activeDocument.unit)
        return (block, scale, true)
    }

    /// Detach everywhere; one undo step on the active document.
    @MainActor
    @discardableResult
    public static func detach(
        store: XrefRuntimeStore,
        documents: [CADDocument],
        activeDocument: CADDocument,
        blockHandle: UUID
    ) -> (instances: Int, layersPurged: [String]) {
        var totalInstances = 0
        var purged: [String] = []
        for doc in documents {
            let result = doc.detachXref(
                blockHandle: blockHandle, pushUndoBefore: doc === activeDocument)
            totalInstances += result.instances
            purged += result.layersPurged
        }
        store.removeEntry(for: blockHandle)
        return (totalInstances, purged)
    }

    public enum BindError: Error, CustomStringConvertible {
        case notLoaded(String)
        public var description: String {
            switch self {
            case .notLoaded(let name):
                return "Xref '\(name)' must be loaded before it can be bound."
            }
        }
    }

    /// Bind a loaded xref into the host documents (one undo step on the
    /// active document). bindType 0 = Bind ($0$ names), 1 = Insert
    /// (merge, host wins on conflict). Nested content is already baked
    /// into the shadow, so it binds recursively with its own prefixes.
    @MainActor
    public static func bind(
        store: XrefRuntimeStore,
        documents: [CADDocument],
        activeDocument: CADDocument,
        blockHandle: UUID,
        bindType: Int
    ) throws {
        guard let entry = store.entry(for: blockHandle),
              let shadow = entry.shadow, entry.status.hasShadowGeometry else {
            throw BindError.notLoaded(
                store.entry(for: blockHandle)?.blockName ?? "xref")
        }
        for doc in documents {
            doc.bindXref(
                blockHandle: blockHandle, shadow: shadow,
                bindType: bindType, pushUndoBefore: doc === activeDocument)
        }
        store.removeEntry(for: blockHandle)
    }

    /// Point a definition at a different file and reload it.
    @MainActor
    public static func repath(
        store: XrefRuntimeStore,
        documents: [CADDocument],
        blockHandle: UUID,
        newFileURL: URL,
        pathType: Int,
        hostFolder: String?
    ) {
        guard let entry = store.entry(for: blockHandle) else { return }
        var descriptor = entry.descriptor
        descriptor.savedPath = savedPath(
            forFileAt: newFileURL.standardizedFileURL.path,
            pathType: pathType, hostFolder: hostFolder)
        for doc in documents {
            doc.updateXrefDescriptor(blockHandle: blockHandle, descriptor: descriptor)
        }
        store.updateEntry(for: blockHandle) {
            $0.descriptor = descriptor
            $0.status = .unloaded
            $0.shadow = nil
            $0.grid = nil
            $0.userUnloaded = false
        }
        XrefLoader.requestLoad(
            store: store, blockHandle: blockHandle,
            documents: documents, hostFolder: hostFolder)
    }
}
