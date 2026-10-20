import XCTest
@testable import ZephyrCore

/// Unit 3a (xref plan): path resolution, recursive loading with
/// nesting/overlay/circular rules, dependent-symbol merging, bounds
/// resync, unload, and budget gating.
@MainActor
final class XrefLoaderTests: XCTestCase {

    // MARK: - Fixture construction

    private func lineDXF(layer: String, x1: Double, y1: Double, x2: Double, y2: Double) -> String {
        """
        0
        LINE
        8
        \(layer)
        10
        \(x1)
        20
        \(y1)
        30
        0.0
        11
        \(x2)
        21
        \(y2)
        31
        0.0
        """
    }

    private func insertDXF(block: String, x: Double, y: Double) -> String {
        """
        0
        INSERT
        8
        0
        2
        \(block)
        10
        \(x)
        20
        \(y)
        30
        0.0
        """
    }

    private func xrefBlockDXF(name: String, flags: Int, path: String) -> String {
        """
        0
        BLOCK
        8
        0
        2
        \(name)
        70
        \(flags)
        10
        0.0
        20
        0.0
        30
        0.0
        3
        \(name)
        1
        \(path)
        0
        ENDBLK
        8
        0
        """
    }

    private func drawingDXF(layers: [String], blocks: String, entities: String) -> String {
        let layerEntries = (["0"] + layers).map { name in
            """
            0
            LAYER
            2
            \(name)
            70
            0
            62
            7
            6
            Continuous
            """
        }.joined(separator: "\n")
        return """
        0
        SECTION
        2
        HEADER
        0
        ENDSEC
        0
        SECTION
        2
        TABLES
        0
        TABLE
        2
        LAYER
        \(layerEntries)
        0
        ENDTAB
        0
        ENDSEC
        0
        SECTION
        2
        BLOCKS
        \(blocks)
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        \(entities)
        0
        ENDSEC
        0
        EOF
        """
    }

    /// root/
    ///   host.dxf            (SitePlan attach -> refs/site.dxf, GridOverlay overlay -> grid.dxf)
    ///   grid.dxf            (one line)
    ///   refs/site.dxf       (Walls line 50 long; Grid attach -> grid.dxf; Notes overlay -> notes.dxf)
    ///   refs/grid.dxf       (GridLines line)
    ///   refs/notes.dxf      (must NOT appear via nested overlay)
    private func makeTree() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xref-tree-\(UUID().uuidString)")
        let refs = root.appendingPathComponent("refs")
        try FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
        func write(_ dxf: String, _ url: URL) throws {
            try dxf.write(to: url, atomically: true, encoding: .utf8)
        }
        try write(drawingDXF(
            layers: ["GridLines"], blocks: "",
            entities: lineDXF(layer: "GridLines", x1: 0, y1: 0, x2: 5, y2: 0)),
            refs.appendingPathComponent("grid.dxf"))
        try write(drawingDXF(
            layers: ["NotesLayer"], blocks: "",
            entities: lineDXF(layer: "NotesLayer", x1: 0, y1: 99, x2: 7, y2: 99)),
            refs.appendingPathComponent("notes.dxf"))
        try write(drawingDXF(
            layers: ["Walls"],
            blocks: xrefBlockDXF(name: "Grid", flags: 4, path: "grid.dxf")
                + "\n" + xrefBlockDXF(name: "Notes", flags: 12, path: "notes.dxf"),
            entities: lineDXF(layer: "Walls", x1: 0, y1: 0, x2: 50, y2: 0)
                + "\n" + insertDXF(block: "Grid", x: 100, y: 0)
                + "\n" + insertDXF(block: "Notes", x: 200, y: 0)),
            refs.appendingPathComponent("site.dxf"))
        try write(drawingDXF(
            layers: [], blocks: "",
            entities: lineDXF(layer: "0", x1: 0, y1: 0, x2: 9, y2: 0)),
            root.appendingPathComponent("grid.dxf"))
        try write(drawingDXF(
            layers: [],
            blocks: xrefBlockDXF(name: "SitePlan", flags: 4, path: #"refs\site.dxf"#)
                + "\n" + xrefBlockDXF(name: "GridOverlay", flags: 12, path: "grid.dxf"),
            entities: insertDXF(block: "SitePlan", x: 1000, y: 2000)
                + "\n" + insertDXF(block: "GridOverlay", x: 0, y: 0)
                + "\n" + lineDXF(layer: "0", x1: 0, y1: 0, x2: 1, y2: 1)),
            root.appendingPathComponent("host.dxf"))
        return root
    }

    private func importHost(at root: URL) throws -> (doc: CADDocument, store: XrefRuntimeStore) {
        let result = try DXFImporter.importDXFViews(
            filePath: root.appendingPathComponent("host.dxf").path)
        let doc = CADDocument()
        let store = XrefRuntimeStore()
        doc.xrefRuntimeStore = store
        doc.importLayersBlocksEntities(
            layers: result.layers, blocks: result.blocks, entities: result.entities)
        return (doc, store)
    }

    private func waitForStatus(
        _ store: XrefRuntimeStore, handle: UUID,
        timeout: TimeInterval = 10
    ) async -> XrefStatus? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let status = store.status(for: handle), status != .loading, status != .unloaded {
                return status
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return store.status(for: handle)
    }

    // MARK: - Resolver

    func testPathResolverTable() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let rootPath = root.path
        XCTAssertEqual(
            XrefPathResolver.resolve(
                savedPath: #"refs\site.dxf"#, immediateHostFolder: rootPath,
                documentFolder: rootPath),
            (rootPath as NSString).appendingPathComponent("refs/site.dxf"))
        XCTAssertEqual(
            XrefPathResolver.resolve(
                savedPath: "grid.dxf", immediateHostFolder: rootPath + "/refs",
                documentFolder: rootPath),
            (rootPath as NSString).appendingPathComponent("refs/grid.dxf"),
            "immediate host folder wins over document folder")
        XCTAssertEqual(
            XrefPathResolver.resolve(
                savedPath: #"C:\cad\lib\site.dxf"#, immediateHostFolder: rootPath + "/refs",
                documentFolder: rootPath),
            (rootPath as NSString).appendingPathComponent("refs/site.dxf"),
            "drive path degrades to filename search")
        XCTAssertNil(XrefPathResolver.resolve(
            savedPath: "missing-xyz.dxf", immediateHostFolder: rootPath,
            documentFolder: rootPath))
    }

    func testRelativePathComputation() {
        XCTAssertEqual(
            XrefPathResolver.relativePath(fromFolder: "/a/b", to: "/a/b/c.dxf"), "./c.dxf")
        XCTAssertEqual(
            XrefPathResolver.relativePath(fromFolder: "/a/b/c", to: "/a/x.dxf"), "../../x.dxf")
    }

    // MARK: - End-to-end load

    func testLoadNestedTreeEndToEnd() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let (doc, store) = try importHost(at: root)
        let siteHandle = try XCTUnwrap(doc.allBlocks.first { $0.name == "SitePlan" }?.handle)
        let editRevisionBefore = doc.editRevision
        let renderRevisionBefore = doc.renderRevision

        XrefLoader.loadAllPending(store: store, documents: [doc], hostFolder: root.path)
        let status = await waitForStatus(store, handle: siteHandle)
        XCTAssertEqual(status, .loaded, store.entry(for: siteHandle)?.statusDetail ?? "")

        let entry = try XCTUnwrap(store.entry(for: siteHandle))
        let shadow = try XCTUnwrap(entry.shadow)
        // Own Walls line + nested Grid line; Notes overlay excluded.
        XCTAssertEqual(shadow.geometry.count, 2)
        XCTAssertEqual(entry.children.count, 2)
        XCTAssertEqual(entry.children.first { $0.blockName == "Grid" }?.status, .loaded)
        XCTAssertEqual(entry.children.first { $0.blockName == "Notes" }?.status, .orphaned)

        // Dependent layers merged, "0" never prefixed.
        XCTAssertNotNil(doc.findLayer(named: "SitePlan|Walls"))
        XCTAssertNotNil(doc.findLayer(named: "Grid|GridLines"))
        XCTAssertNil(doc.findLayer(named: "SitePlan|0"))
        XCTAssertNil(doc.findLayer(named: "Notes|NotesLayer"))
        XCTAssertEqual(shadow.primitiveStyles[0]?.layerName, "SitePlan|Walls")

        // Instance bounds resynced from shadow (50-long wall line).
        let instance = try XCTUnwrap(doc.allEntities.first { $0.blockID == siteHandle })
        XCTAssertEqual(instance.localBoundingBox?.max.x ?? 0, 105, accuracy: 1e-9,
                       "wall 0..50 plus grid at x=100..105")

        // Host-level overlay loads as a root.
        let overlayHandle = try XCTUnwrap(doc.allBlocks.first { $0.name == "GridOverlay" }?.handle)
        let overlayStatus = await waitForStatus(store, handle: overlayHandle)
        XCTAssertEqual(overlayStatus, .loaded)

        // Loading never dirties or enters undo.
        XCTAssertEqual(doc.editRevision, editRevisionBefore)
        XCTAssertGreaterThan(doc.renderRevision, renderRevisionBefore)

        // VISRETAIN: hide a dependent layer, force reload, override kept.
        let wallsHandle = try XCTUnwrap(doc.findLayer(named: "SitePlan|Walls")?.handle)
        doc.setLayerVisible(wallsHandle, visible: false)
        XrefLoader.requestLoad(
            store: store, blockHandle: siteHandle, documents: [doc],
            hostFolder: root.path, forceReload: true)
        let reloadStatus = await waitForStatus(store, handle: siteHandle)
        XCTAssertEqual(reloadStatus, .loaded)
        XCTAssertEqual(doc.layer(for: wallsHandle)?.isVisible, false)

        // Unload: shadow gone, bounds revert to placeholder.
        XrefLoader.unload(store: store, blockHandle: siteHandle, documents: [doc])
        XCTAssertEqual(store.status(for: siteHandle), .unloaded)
        XCTAssertNil(store.shadowBlock(for: siteHandle))
        let afterUnload = try XCTUnwrap(doc.allEntities.first { $0.blockID == siteHandle })
        XCTAssertEqual(afterUnload.localBoundingBox?.max.x ?? 0, 10, accuracy: 1e-9)
    }

    func testMovedTreeStillResolves() async throws {
        let root = try makeTree()
        let moved = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xref-moved-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: moved)
        }
        try FileManager.default.moveItem(at: root, to: moved)
        let (doc, store) = try importHost(at: moved)
        let siteHandle = try XCTUnwrap(doc.allBlocks.first { $0.name == "SitePlan" }?.handle)
        XrefLoader.loadAllPending(store: store, documents: [doc], hostFolder: moved.path)
        let movedStatus = await waitForStatus(store, handle: siteHandle)
        XCTAssertEqual(movedStatus, .loaded)
    }

    func testNotFoundAndCircular() async throws {
        // Circular pair: a.dxf <-> b.dxf, host references A.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xref-circ-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ dxf: String, _ name: String) throws {
            try dxf.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try write(drawingDXF(
            layers: [],
            blocks: xrefBlockDXF(name: "Bref", flags: 4, path: "b.dxf"),
            entities: lineDXF(layer: "0", x1: 0, y1: 0, x2: 3, y2: 0)
                + "\n" + insertDXF(block: "Bref", x: 10, y: 0)), "a.dxf")
        try write(drawingDXF(
            layers: [],
            blocks: xrefBlockDXF(name: "Aref", flags: 4, path: "a.dxf"),
            entities: lineDXF(layer: "0", x1: 0, y1: 0, x2: 4, y2: 0)
                + "\n" + insertDXF(block: "Aref", x: 20, y: 0)), "b.dxf")
        try write(drawingDXF(
            layers: [],
            blocks: xrefBlockDXF(name: "A", flags: 4, path: "a.dxf")
                + "\n" + xrefBlockDXF(name: "Gone", flags: 4, path: "gone-xyz.dxf"),
            entities: insertDXF(block: "A", x: 0, y: 0)
                + "\n" + insertDXF(block: "Gone", x: 50, y: 50)), "host.dxf")

        let result = try DXFImporter.importDXFViews(
            filePath: root.appendingPathComponent("host.dxf").path)
        let doc = CADDocument()
        let store = XrefRuntimeStore()
        doc.xrefRuntimeStore = store
        doc.importLayersBlocksEntities(
            layers: result.layers, blocks: result.blocks, entities: result.entities)
        let aHandle = try XCTUnwrap(doc.allBlocks.first { $0.name == "A" }?.handle)
        let goneHandle = try XCTUnwrap(doc.allBlocks.first { $0.name == "Gone" }?.handle)

        XrefLoader.loadAllPending(store: store, documents: [doc], hostFolder: root.path)
        let aStatus = await waitForStatus(store, handle: aHandle)
        XCTAssertEqual(aStatus, .loaded)
        let goneStatus = await waitForStatus(store, handle: goneHandle)
        XCTAssertEqual(goneStatus, .notFound)
        let aEntry = try XCTUnwrap(store.entry(for: aHandle))
        // A's own line + B's line; B's insert of A is circular-cut.
        XCTAssertEqual(aEntry.shadow?.geometry.count, 2)
        XCTAssertEqual(
            aEntry.children.first?.children.first?.status, .circular)
    }

    func testOverBudgetStaysUnloaded() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let (doc, store) = try importHost(at: root)
        store.limits.maxTotalPrimitives = 1
        let siteHandle = try XCTUnwrap(doc.allBlocks.first { $0.name == "SitePlan" }?.handle)
        XrefLoader.requestLoad(
            store: store, blockHandle: siteHandle, documents: [doc], hostFolder: root.path)
        let budgetStatus = await waitForStatus(store, handle: siteHandle)
        XCTAssertEqual(budgetStatus, .overBudget)
        XCTAssertNil(store.shadowBlock(for: siteHandle))
    }
}
