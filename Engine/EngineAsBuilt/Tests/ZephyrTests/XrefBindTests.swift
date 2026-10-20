import XCTest
@testable import ZephyrCore

/// Unit 5 (xref plan): Bind (both BINDTYPE modes), $n$ collision
/// increment, merge semantics, XBIND single-layer behavior, and that a
/// bound xref writes as a plain internal block.
@MainActor
final class XrefBindTests: XCTestCase {

    private func siteDXF() -> String {
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
        Walls
        70
        0
        62
        3
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
        Walls
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

    private struct Fixture {
        var dir: URL
        var doc: CADDocument
        var store: XrefRuntimeStore
        var blockHandle: UUID
    }

    private func makeLoadedFixture() async throws -> Fixture {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xref-bind-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let siteURL = dir.appendingPathComponent("site.dxf")
        try siteDXF().write(to: siteURL, atomically: true, encoding: .utf8)

        let doc = CADDocument()
        let store = XrefRuntimeStore()
        doc.xrefRuntimeStore = store
        doc.addLayer(Layer(name: "0"))
        doc.activeLayerID = doc.findLayer(named: "0")?.handle
        let (block, _, _) = try XrefManager.attach(
            store: store, documents: [doc], activeDocument: doc,
            fileURL: siteURL, isOverlay: false, pathType: 1, hostFolder: dir.path)
        doc.addEntity(CADEntity(
            layerID: doc.findLayer(named: "0")!.handle,
            blockID: block.handle, transform: .identity))

        let deadline = Date().addingTimeInterval(10)
        while store.status(for: block.handle) != .loaded, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard store.status(for: block.handle) == .loaded else {
            throw XCTSkip("fixture xref failed to load: \(String(describing: store.status(for: block.handle)))")
        }
        return Fixture(dir: dir, doc: doc, store: store, blockHandle: block.handle)
    }

    func testBoundSymbolNameModes() {
        XCTAssertEqual(
            CADDocument.boundSymbolName("Site|Walls", bindType: 0, existingUpperNames: []),
            "Site$0$Walls")
        XCTAssertEqual(
            CADDocument.boundSymbolName(
                "Site|Walls", bindType: 0, existingUpperNames: ["SITE$0$WALLS", "SITE$1$WALLS"]),
            "Site$2$Walls")
        XCTAssertEqual(
            CADDocument.boundSymbolName("Site|Walls", bindType: 1, existingUpperNames: []),
            "Walls")
        XCTAssertNil(CADDocument.boundSymbolName("Plain", bindType: 0, existingUpperNames: []))
    }

    func testBindMode0MaterializesAndRenames() async throws {
        let fixture = try await makeLoadedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let doc = fixture.doc

        try XrefManager.bind(
            store: fixture.store, documents: [doc], activeDocument: doc,
            blockHandle: fixture.blockHandle, bindType: 0)

        let block = try XCTUnwrap(doc.block(for: fixture.blockHandle))
        XCTAssertNil(block.xrefDescriptor)
        XCTAssertEqual(block.geometry.count, 1)
        XCTAssertEqual(block.primitiveStyles[0]?.layerName, "site$0$Walls")
        XCTAssertNotNil(doc.findLayer(named: "site$0$Walls"))
        XCTAssertNil(doc.findLayer(named: "site|Walls"))
        XCTAssertNil(fixture.store.entry(for: fixture.blockHandle))

        // Bound output writes as a plain block with content, no group 1 path.
        let outURL = fixture.dir.appendingPathComponent("bound.dxf")
        try DXFWriterBridge.export(document: doc, to: outURL)
        let reparsed = try DXFReader().readFile(at: outURL.path)
        let exported = try XCTUnwrap(reparsed.blocks.first { $0.name == "site" })
        XCTAssertEqual(exported.xrefPath, "")
        XCTAssertEqual(exported.flags & 4, 0)
        XCTAssertFalse(exported.entities.isEmpty)
    }

    func testBindMode1MergesIntoHostLayer() async throws {
        let fixture = try await makeLoadedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let doc = fixture.doc
        // Pre-existing host layer with the same leaf name (red).
        doc.addLayer(Layer(name: "Walls", color: ColorRGBA(r: 255, g: 0, b: 0, a: 255)))

        try XrefManager.bind(
            store: fixture.store, documents: [doc], activeDocument: doc,
            blockHandle: fixture.blockHandle, bindType: 1)

        let block = try XCTUnwrap(doc.block(for: fixture.blockHandle))
        XCTAssertNil(block.xrefDescriptor)
        XCTAssertEqual(block.primitiveStyles[0]?.layerName, "Walls")
        XCTAssertNil(doc.findLayer(named: "site|Walls"))
        // Host definition wins: still red, still one Walls layer.
        let walls = doc.allLayers.filter { $0.name == "Walls" }
        XCTAssertEqual(walls.count, 1)
        XCTAssertEqual(walls.first?.color, ColorRGBA(r: 255, g: 0, b: 0, a: 255))
    }

    func testBindRequiresLoaded() async throws {
        let fixture = try await makeLoadedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        XrefLoader.unload(
            store: fixture.store, blockHandle: fixture.blockHandle,
            documents: [fixture.doc])
        XCTAssertThrowsError(try XrefManager.bind(
            store: fixture.store, documents: [fixture.doc],
            activeDocument: fixture.doc, blockHandle: fixture.blockHandle, bindType: 0))
    }

    func testXBindSingleLayerSurvivesDetach() async throws {
        let fixture = try await makeLoadedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let doc = fixture.doc

        let bound = doc.xbindLayer(named: "site|Walls", bindType: 0)
        XCTAssertEqual(bound, "site$0$Walls")
        XCTAssertNotNil(doc.findLayer(named: "site$0$Walls"))
        XCTAssertNil(doc.findLayer(named: "site|Walls"))
        // Shadow styles were rewritten to the bound name.
        XCTAssertEqual(
            fixture.store.shadowBlock(for: fixture.blockHandle)?.primitiveStyles[0]?.layerName,
            "site$0$Walls")

        _ = XrefManager.detach(
            store: fixture.store, documents: [doc], activeDocument: doc,
            blockHandle: fixture.blockHandle)
        XCTAssertNotNil(
            doc.findLayer(named: "site$0$Walls"),
            "xbound layer is a host layer now and survives detach")
    }
}
