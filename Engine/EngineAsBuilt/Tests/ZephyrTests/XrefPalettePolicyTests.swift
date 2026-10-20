import XCTest
@testable import ZephyrCore

/// Unit 4 (xref plan): palette policy derivation and attach/detach/
/// repath manager operations.
@MainActor
final class XrefPalettePolicyTests: XCTestCase {

    private func simpleDXF(layer: String) -> String {
        """
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
        0
        LAYER
        2
        0
        70
        0
        62
        7
        6
        Continuous
        0
        LAYER
        2
        \(layer)
        70
        0
        62
        7
        6
        Continuous
        0
        ENDTAB
        0
        ENDSEC
        0
        SECTION
        2
        BLOCKS
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        8
        \(layer)
        10
        0.0
        20
        0.0
        30
        0.0
        11
        8.0
        21
        0.0
        31
        0.0
        0
        ENDSEC
        0
        EOF
        """
    }

    private func makeHost() -> (doc: CADDocument, store: XrefRuntimeStore) {
        let doc = CADDocument()
        let store = XrefRuntimeStore()
        doc.xrefRuntimeStore = store
        doc.addLayer(Layer(name: "0"))
        doc.activeLayerID = doc.findLayer(named: "0")?.handle
        return (doc, store)
    }

    private func waitForStatus(
        _ store: XrefRuntimeStore, handle: UUID, timeout: TimeInterval = 10
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

    func testSavedPathComputation() {
        XCTAssertEqual(
            XrefManager.savedPath(forFileAt: "/proj/refs/a.dwg", pathType: 0, hostFolder: "/proj"),
            "a.dwg", "REFPATHTYPE 0 = no path (AutoCAD)")
        XCTAssertEqual(
            XrefManager.savedPath(forFileAt: "/proj/refs/a.dwg", pathType: 1, hostFolder: "/proj"),
            "./refs/a.dwg")
        XCTAssertEqual(
            XrefManager.savedPath(forFileAt: "/proj/refs/a.dwg", pathType: 1, hostFolder: nil),
            "/proj/refs/a.dwg", "unsaved host stores full path")
        XCTAssertEqual(
            XrefManager.savedPath(forFileAt: "/proj/refs/a.dwg", pathType: 2, hostFolder: "/proj"),
            "/proj/refs/a.dwg", "REFPATHTYPE 2 = full path (AutoCAD)")
    }

    func testAttachDetachRepathLifecycle() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xref-mgr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let siteURL = dir.appendingPathComponent("site.dxf")
        try simpleDXF(layer: "Walls").write(to: siteURL, atomically: true, encoding: .utf8)
        let altURL = dir.appendingPathComponent("alt.dxf")
        try simpleDXF(layer: "AltLayer").write(to: altURL, atomically: true, encoding: .utf8)

        let (doc, store) = makeHost()
        let (block, _, isNew) = try XrefManager.attach(
            store: store, documents: [doc], activeDocument: doc,
            fileURL: siteURL, isOverlay: false, pathType: 1, hostFolder: dir.path)
        XCTAssertTrue(isNew)
        XCTAssertEqual(block.name, "site")
        XCTAssertEqual(block.xrefDescriptor?.savedPath, "./site.dxf")
        let loaded = await waitForStatus(store, handle: block.handle)
        XCTAssertEqual(loaded, .loaded)

        // Re-attaching the same file reuses the definition.
        let (again, _, isNewAgain) = try XrefManager.attach(
            store: store, documents: [doc], activeDocument: doc,
            fileURL: siteURL, isOverlay: false, pathType: 1, hostFolder: dir.path)
        XCTAssertEqual(again.handle, block.handle)
        XCTAssertFalse(isNewAgain)

        // Policy rows: unreferenced until an instance exists.
        var rows = XrefPalettePolicy.rows(store: store, documents: [doc])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.statusText, "Unreferenced")
        XCTAssertEqual(rows.first?.isUnreferenced, true)
        XCTAssertEqual(rows.first?.canUnload, true)
        XCTAssertEqual(rows.first?.canLoad, false)

        doc.addEntity(CADEntity(
            layerID: doc.findLayer(named: "0")!.handle,
            blockID: block.handle, transform: .identity))
        rows = XrefPalettePolicy.rows(store: store, documents: [doc])
        XCTAssertEqual(rows.first?.statusText, "Loaded")
        XCTAssertEqual(rows.first?.instanceCount, 1)
        XCTAssertNotNil(doc.findLayer(named: "site|Walls"))

        // Repath to the alt file and reload: new layer appears.
        XrefManager.repath(
            store: store, documents: [doc], blockHandle: block.handle,
            newFileURL: altURL, pathType: 1, hostFolder: dir.path)
        let repathed = await waitForStatus(store, handle: block.handle)
        XCTAssertEqual(repathed, .loaded)
        XCTAssertEqual(
            doc.block(for: block.handle)?.xrefDescriptor?.savedPath, "./alt.dxf")
        XCTAssertNotNil(doc.findLayer(named: "site|AltLayer"))

        // Detach removes definition + instances; dependent layers that
        // only this xref used are purged, still-referenced ones stay.
        let result = XrefManager.detach(
            store: store, documents: [doc], activeDocument: doc,
            blockHandle: block.handle)
        XCTAssertEqual(result.instances, 1)
        XCTAssertNil(doc.block(for: block.handle))
        XCTAssertNil(store.entry(for: block.handle))
        XCTAssertNil(doc.findLayer(named: "site|AltLayer"))
        XCTAssertTrue(doc.allEntities.allSatisfy { $0.blockID != block.handle })
    }

    func testDetachKeepsLayerReferencedByHostGeometry() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xref-mgr2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let siteURL = dir.appendingPathComponent("site.dxf")
        try simpleDXF(layer: "Walls").write(to: siteURL, atomically: true, encoding: .utf8)

        let (doc, store) = makeHost()
        let (block, _, _) = try XrefManager.attach(
            store: store, documents: [doc], activeDocument: doc,
            fileURL: siteURL, isOverlay: true, pathType: 0, hostFolder: dir.path)
        XCTAssertEqual(block.xrefDescriptor?.isOverlay, true)
        let loaded = await waitForStatus(store, handle: block.handle)
        XCTAssertEqual(loaded, .loaded)

        // Host block whose primitives style against the dependent layer.
        let hostBlock = CADBlock(
            name: "HostUsesLayer",
            geometry: [
                .line(start: Vector3(x: 0, y: 0, z: 0),
                      end: Vector3(x: 1, y: 0, z: 0), color: nil)
            ],
            primitiveStyles: [0: CADPrimitiveStyle(layerName: "site|Walls")])
        doc.addBlock(hostBlock)

        _ = XrefManager.detach(
            store: store, documents: [doc], activeDocument: doc,
            blockHandle: block.handle)
        XCTAssertNotNil(
            doc.findLayer(named: "site|Walls"),
            "layer still referenced by host block styles must survive detach")
    }

    func testDescriptorsRegistered() {
        for name in ["XATTACH", "XREF", "-XREF"] {
            XCTAssertTrue(
                CommandDescriptor.allCommands.contains { $0.canonicalName == name }, name)
        }
    }
}
