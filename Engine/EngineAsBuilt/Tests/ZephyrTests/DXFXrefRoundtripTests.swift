import XCTest
@testable import ZephyrCore

/// Unit 2 (xref plan): DXF/EAB data spine — xref definitions survive
/// import → export → import with path, flags, and empty body intact,
/// and unresolved xrefs render as placeholders.
@MainActor
final class DXFXrefRoundtripTests: XCTestCase {

    /// Host DXF: one normal block, one xref attachment (flags 4, relative
    /// path), one xref overlay (flags 12, bare filename), one host LINE,
    /// and INSERTs of both xrefs.
    private func hostDXF() -> String {
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
        ENDTAB
        0
        TABLE
        2
        BLOCK_RECORD
        0
        BLOCK_RECORD
        2
        SitePlan
        70
        4
        0
        BLOCK_RECORD
        2
        GridOverlay
        70
        12
        0
        ENDTAB
        0
        ENDSEC
        0
        SECTION
        2
        BLOCKS
        0
        BLOCK
        8
        0
        2
        SitePlan
        70
        4
        10
        0.0
        20
        0.0
        30
        0.0
        3
        SitePlan
        1
        .\\refs\\site plan.dwg
        0
        ENDBLK
        8
        0
        0
        BLOCK
        8
        0
        2
        GridOverlay
        70
        12
        10
        0.0
        20
        0.0
        30
        0.0
        3
        GridOverlay
        1
        grid.dwg
        0
        ENDBLK
        8
        0
        0
        BLOCK
        8
        0
        2
        LocalBlock
        70
        0
        10
        0.0
        20
        0.0
        30
        0.0
        3
        LocalBlock
        1

        0
        LINE
        8
        0
        10
        0.0
        20
        0.0
        30
        0.0
        11
        3.0
        21
        0.0
        31
        0.0
        0
        ENDBLK
        8
        0
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        INSERT
        8
        0
        2
        SitePlan
        10
        100.0
        20
        200.0
        30
        0.0
        0
        INSERT
        8
        0
        2
        GridOverlay
        10
        5.0
        20
        5.0
        30
        0.0
        0
        LINE
        8
        0
        10
        0.0
        20
        0.0
        30
        0.0
        11
        1.0
        21
        1.0
        31
        0.0
        0
        ENDSEC
        0
        EOF
        """
    }

    private func importHostDXF() throws -> DXFImportResult {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xref-host-\(UUID().uuidString).dxf")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try hostDXF().write(to: tempURL, atomically: true, encoding: .utf8)
        return try DXFImporter.importDXFViews(filePath: tempURL.path)
    }

    func testImportCreatesDescriptorsAndPendingList() throws {
        let result = try importHostDXF()
        XCTAssertEqual(result.pendingXrefs.count, 2)

        let site = result.blocks.first { $0.name == "SitePlan" }
        XCTAssertEqual(site?.xrefDescriptor?.savedPath, #".\refs\site plan.dwg"#)
        XCTAssertEqual(site?.xrefDescriptor?.isOverlay, false)
        XCTAssertEqual(site?.xrefDescriptor?.pathKind, .relative)
        XCTAssertEqual(site?.geometry.isEmpty, true)

        let grid = result.blocks.first { $0.name == "GridOverlay" }
        XCTAssertEqual(grid?.xrefDescriptor?.savedPath, "grid.dwg")
        XCTAssertEqual(grid?.xrefDescriptor?.isOverlay, true)
        XCTAssertEqual(grid?.xrefDescriptor?.pathKind, CADXrefDescriptor.PathKind.none)

        let local = result.blocks.first { $0.name == "LocalBlock" }
        XCTAssertNil(local?.xrefDescriptor)
        XCTAssertEqual(local?.geometry.isEmpty, false)

        // INSERTs point at the descriptor blocks.
        let inserts = result.entities.filter { $0.blockID != nil }
        XCTAssertEqual(inserts.count, 2)
        XCTAssertTrue(inserts.contains { $0.blockID == site?.handle })
        XCTAssertTrue(inserts.contains { $0.blockID == grid?.handle })
        let pendingNames = Set(result.pendingXrefs.map(\.blockName))
        XCTAssertEqual(pendingNames, ["SitePlan", "GridOverlay"])
    }

    func testExportWritesGroup1FlagsAndEmptyBody() throws {
        let result = try importHostDXF()
        let doc = CADDocument()
        doc.importLayersBlocksEntities(
            layers: result.layers, blocks: result.blocks, entities: result.entities)

        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xref-host-out-\(UUID().uuidString).dxf")
        defer { try? FileManager.default.removeItem(at: outURL) }
        try DXFWriterBridge.export(document: doc, to: outURL)
        let text = try String(contentsOf: outURL, encoding: .utf8)

        XCTAssertTrue(text.contains(#".\refs\site plan.dwg"#), "saved path missing from export")
        XCTAssertTrue(text.contains("grid.dwg"), "overlay path missing from export")

        // Parse the SitePlan BLOCK section: group 70 must carry bit 4 and
        // the body must be empty (ENDBLK immediately follows the header).
        let reparsed = try DXFReader().readFile(at: outURL.path)
        let site = reparsed.blocks.first { $0.name == "SitePlan" }
        XCTAssertNotNil(site)
        XCTAssertEqual(site?.flags ?? 0 & 4, 4)
        XCTAssertEqual(site?.xrefPath, #".\refs\site plan.dwg"#)
        XCTAssertEqual(site?.entities.isEmpty, true, "xref body must stay empty")
        let grid = reparsed.blocks.first { $0.name == "GridOverlay" }
        XCTAssertEqual(grid?.flags ?? 0 & 12, 12)
        XCTAssertEqual(grid?.xrefPath, "grid.dwg")
        let record = reparsed.blockRecords.first { $0.name == "SitePlan" }
        XCTAssertEqual(record?.flags ?? 0 & 4, 4, "BLOCK_RECORD must mirror xref flags")

        // Re-import: still an xref, idempotent.
        let reimported = try DXFImporter.importDXFViews(filePath: outURL.path)
        XCTAssertEqual(reimported.pendingXrefs.count, 2)
        XCTAssertEqual(
            reimported.blocks.first { $0.name == "SitePlan" }?.xrefDescriptor?.savedPath,
            #".\refs\site plan.dwg"#)
    }

    func testExportMarksDependentSymbolsExternallyDependent() throws {
        let doc = CADDocument()
        doc.addLayer(Layer(name: "0"))
        doc.addLayer(Layer(name: "SitePlan|Walls"))
        doc.addLayer(Layer(name: "Ordinary|NotXref"))
        var block = CADBlock(name: "SitePlan", geometry: [], primitiveStyles: [:])
        block.xrefDescriptor = CADXrefDescriptor(savedPath: "site.dwg", isOverlay: false)
        doc.addBlock(block)

        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xref-depflags-\(UUID().uuidString).dxf")
        defer { try? FileManager.default.removeItem(at: outURL) }
        try DXFWriterBridge.export(document: doc, to: outURL)

        let reparsed = try DXFReader().readFile(at: outURL.path)
        let dep = reparsed.layers.first { $0.name == "SitePlan|Walls" }
        XCTAssertEqual(dep?.flags ?? 0 & 48, 48, "dependent layer needs bits 16+32")
        let plain = reparsed.layers.first { $0.name == "Ordinary|NotXref" }
        XCTAssertEqual(plain?.flags ?? -1 & 48, 0, "unrelated bar name must stay clean")
    }

    func testEABRoundTripPreservesDescriptors() throws {
        let result = try importHostDXF()
        let doc = CADDocument()
        doc.importLayersBlocksEntities(
            layers: result.layers, blocks: result.blocks, entities: result.entities)
        let siteHandle = try XCTUnwrap(result.blocks.first { $0.name == "SitePlan" }?.handle)
        doc.xrefSourceFolder = "/tmp/xref-fixture-host"
        doc.eabUnloadedXrefHandles = [siteHandle]

        let eabURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xref-host-\(UUID().uuidString).eab")
        defer { try? FileManager.default.removeItem(at: eabURL) }
        try EABWriter.write(document: doc, to: eabURL)

        let views = try EABReader.readViews(from: eabURL)
        let loaded = try XCTUnwrap(views.first?.document)
        let site = loaded.allBlocks.first { $0.name == "SitePlan" }
        XCTAssertEqual(site?.xrefDescriptor?.savedPath, #".\refs\site plan.dwg"#)
        XCTAssertEqual(site?.xrefDescriptor?.isOverlay, false)
        XCTAssertEqual(site?.geometry.isEmpty, true)
        let grid = loaded.allBlocks.first { $0.name == "GridOverlay" }
        XCTAssertEqual(grid?.xrefDescriptor?.isOverlay, true)
        XCTAssertEqual(loaded.xrefSourceFolder, "/tmp/xref-fixture-host")
        XCTAssertTrue(loaded.eabUnloadedXrefHandles.contains(siteHandle))
    }

    func testUnresolvedXrefRendersPlaceholderSpecs() async throws {
        let result = try importHostDXF()
        let doc = CADDocument()
        doc.importLayersBlocksEntities(
            layers: result.layers, blocks: result.blocks, entities: result.entities)
        let results = await CADRendererBridge.computeSpecs(
            fromSnapshot: doc.snapshot(), simplifyComplexBlocks: false)
        let siteHandle = result.blocks.first { $0.name == "SitePlan" }?.handle
        let insert = doc.allEntities.first { $0.blockID == siteHandle }
        let specs = results.first { $0.handle == insert?.handle }
        XCTAssertNotNil(specs)
        XCTAssertFalse(specs?.specs.isEmpty ?? true,
                       "unresolved xref must produce placeholder specs")
    }

    func testPathKindClassification() {
        XCTAssertEqual(CADXrefDescriptor.pathKind(of: "/abs/site.dwg"), .absolute)
        XCTAssertEqual(CADXrefDescriptor.pathKind(of: #"C:\proj\site.dwg"#), .absolute)
        XCTAssertEqual(CADXrefDescriptor.pathKind(of: #"\\server\share\site.dwg"#), .absolute)
        XCTAssertEqual(CADXrefDescriptor.pathKind(of: #"..\up.dwg"#), .relative)
        XCTAssertEqual(CADXrefDescriptor.pathKind(of: "sub/dir.dwg"), .relative)
        XCTAssertEqual(CADXrefDescriptor.pathKind(of: "bare.dwg"), .none)
        XCTAssertEqual(CADXrefDescriptor.pathKind(of: ""), .none)
    }
}
