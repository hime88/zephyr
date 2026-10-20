import XCTest
import ZephyrLisp
@testable import ZephyrCore

/// Unit 6 (xref plan): SPATIAL_FILTER clip persistence (read/write),
/// PDF clip emission, xref Lisp system variables, tblsearch group 1,
/// and VISRETAIN=0 symbol reset.
@MainActor
final class XrefClipSysvarTests: XCTestCase {

    // MARK: - Helpers

    private func lineBlock(name: String) -> CADBlock {
        CADBlock(
            name: name,
            geometry: [.line(start: Vector3(x: 0, y: 0, z: 0),
                             end: Vector3(x: 20, y: 20, z: 0), color: nil)],
            primitiveStyles: [:])
    }

    private func clipDoc() throws -> CADDocument {
        let doc = CADDocument()
        doc.addLayer(Layer(name: "0"))
        doc.activeLayerID = doc.findLayer(named: "0")?.handle
        let block = lineBlock(name: "ClipBlock")
        doc.addBlock(block)
        let transform = Transform3D.translated(by: Vector3(x: 5, y: 5, z: 0))
            .multiplying(by: .rotated(by: .pi / 6))
            .multiplying(by: .scaled(by: Vector3(x: 2, y: 2, z: 1)))
        var entity = CADEntity(
            handle: UUID(),
            layerID: try XCTUnwrap(doc.findLayer(named: "0")?.handle),
            blockID: block.handle,
            localGeometry: nil,
            transform: transform,
            xdata: [:],
            drawOrder: 0,
            localBoundingBox: block.localBoundingBox)
        let boundary = [
            Vector3(x: 0, y: 0, z: 0), Vector3(x: 10, y: 0, z: 0),
            Vector3(x: 10, y: -8, z: 0), Vector3(x: 0, y: -8, z: 0),
        ]
        CADClipMetadata.set(
            CADClipData(boundary: boundary, isEnabled: true, frontDepth: 3),
            on: &entity)
        doc.addEntities([entity])
        return doc
    }

    // MARK: - DXF SPATIAL_FILTER round trip

    func testDXFClipRoundTripThroughSpatialFilter() throws {
        let doc = try clipDoc()
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xref-clip-\(UUID().uuidString).dxf")
        defer { try? FileManager.default.removeItem(at: outURL) }
        try DXFWriterBridge.export(document: doc, to: outURL)
        let text = try String(contentsOf: outURL, encoding: .utf8)
        XCTAssertTrue(text.contains("SPATIAL_FILTER"), "standard clip object missing")
        XCTAssertTrue(text.contains("{ACAD_XDICTIONARY"), "extension dictionary link missing")

        let reimported = try DXFImporter.importDXFViews(filePath: outURL.path)
        let refs = reimported.entities.filter { $0.blockID != nil }
        XCTAssertEqual(refs.count, 1)
        let clip = try XCTUnwrap(refs.first.flatMap { CADClipMetadata.value(from: $0) },
                                 "clip lost in round trip")
        XCTAssertTrue(clip.isEnabled)
        XCTAssertFalse(clip.isInverted)
        XCTAssertEqual(clip.frontDepth ?? -1, 3, accuracy: 1e-9)
        XCTAssertEqual(clip.boundary.count, 4)
        let expected = [
            Vector3(x: 0, y: 0, z: 0), Vector3(x: 10, y: 0, z: 0),
            Vector3(x: 10, y: -8, z: 0), Vector3(x: 0, y: -8, z: 0),
        ]
        for (actual, want) in zip(clip.boundary, expected) {
            XCTAssertEqual(actual.x, want.x, accuracy: 1e-6)
            XCTAssertEqual(actual.y, want.y, accuracy: 1e-6)
        }
    }

    /// Hand-written AutoCAD-style fixture: 2-point rectangular filter
    /// linked through nested dictionaries, identity insert.
    private func spatialFilterFixture(inverted: Bool) -> String {
        var objects = """
        0
        DICTIONARY
        5
        100
        330
        30
        100
        AcDbDictionary
        281
        1
        3
        ACAD_FILTER
        350
        101
        0
        DICTIONARY
        5
        101
        330
        100
        100
        AcDbDictionary
        281
        1
        3
        SPATIAL
        350
        102
        0
        SPATIAL_FILTER
        5
        102
        330
        101
        """
        objects += "\n"
        if inverted {
            objects += """
            102
            {ACAD_XDICTIONARY
            360
            103
            102
            }
            """
            objects += "\n"
        }
        objects += """
        100
        AcDbFilter
        100
        AcDbSpatialFilter
        70
        2
        10
        0.0
        20
        0.0
        10
        10.0
        20
        10.0
        210
        0.0
        220
        0.0
        230
        1.0
        11
        0.0
        21
        0.0
        31
        0.0
        71
        1
        72
        0
        73
        0
        """
        objects += "\n"
        // 24x group 40: inverse = identity, transform = identity.
        for value in ["1.0", "0.0", "0.0", "0.0", "1.0", "0.0",
                      "0.0", "0.0", "1.0", "0.0", "0.0", "0.0",
                      "1.0", "0.0", "0.0", "0.0", "1.0", "0.0",
                      "0.0", "0.0", "1.0", "0.0", "0.0", "0.0"] {
            objects += "40\n\(value)\n"
        }
        objects += """
        100
        AcDbSpatialFilter
        71
        1
        """
        objects += "\n"
        if inverted {
            objects += """
            0
            DICTIONARY
            5
            103
            330
            102
            100
            AcDbDictionary
            281
            1
            3
            ACAD_XREC_ROUNDTRIP
            350
            104
            0
            XRECORD
            5
            104
            330
            103
            100
            AcDbXrecord
            280
            1
            10
            2.0
            20
            2.0
            10
            4.0
            20
            2.0
            10
            4.0
            20
            4.0
            10
            2.0
            20
            4.0
            """
        }
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
        5
        10
        0
        LAYER
        5
        11
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
        ENDSEC
        0
        SECTION
        2
        BLOCKS
        0
        BLOCK
        5
        20
        8
        0
        2
        ClipBlock
        70
        0
        10
        0.0
        20
        0.0
        30
        0.0
        0
        LINE
        5
        21
        8
        0
        10
        0.0
        20
        0.0
        11
        20.0
        21
        20.0
        0
        ENDBLK
        5
        22
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        INSERT
        5
        30
        102
        {ACAD_XDICTIONARY
        360
        100
        102
        }
        100
        AcDbEntity
        8
        0
        100
        AcDbBlockReference
        2
        ClipBlock
        10
        0.0
        20
        0.0
        30
        0.0
        0
        ENDSEC
        0
        SECTION
        2
        OBJECTS
        \(objects)0
        ENDSEC
        0
        EOF
        """
    }

    private func importFixture(_ dxf: String) throws -> DXFImportResult {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sf-fixture-\(UUID().uuidString).dxf")
        defer { try? FileManager.default.removeItem(at: url) }
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        return try DXFImporter.importDXFViews(filePath: url.path)
    }

    func testHandFixtureSpatialFilterImportsAsClip() throws {
        let result = try importFixture(spatialFilterFixture(inverted: false))
        let refs = result.entities.filter { $0.blockID != nil }
        XCTAssertEqual(refs.count, 1)
        let clip = try XCTUnwrap(refs.first.flatMap { CADClipMetadata.value(from: $0) })
        XCTAssertTrue(clip.isEnabled)
        XCTAssertFalse(clip.isInverted)
        XCTAssertEqual(clip.boundary.count, 4)
        // 2-point rect (0,0)-(10,10) expanded, Y negated into internal space.
        let xs = clip.boundary.map(\.x)
        let ys = clip.boundary.map(\.y)
        XCTAssertEqual(xs.max() ?? -1, 10, accuracy: 1e-9)
        XCTAssertEqual(ys.min() ?? 1, -10, accuracy: 1e-9)
    }

    func testHandFixtureInvertedClipReadsRoundtripXRecord() throws {
        let result = try importFixture(spatialFilterFixture(inverted: true))
        let refs = result.entities.filter { $0.blockID != nil }
        let clip = try XCTUnwrap(refs.first.flatMap { CADClipMetadata.value(from: $0) })
        XCTAssertTrue(clip.isInverted)
        XCTAssertEqual(clip.boundary.count, 4)
        XCTAssertEqual(clip.boundary.map(\.x).max() ?? -1, 4, accuracy: 1e-9)
        XCTAssertEqual(clip.boundary.map(\.y).min() ?? 1, -4, accuracy: 1e-9)
    }


    // MARK: - PDF clip

    func testPDFExportEmitsClipPath() throws {
        let doc = try clipDoc()
        let entity = try XCTUnwrap(doc.allEntities.first { $0.blockID != nil })
        let builder = PDFContentBuilder()
        PDFPrimitives.writeEntity(
            entity, in: doc, entityColor: .white,
            lineWeightMM: 0.25, pageScale: 1, to: builder)
        let text = String(decoding: builder.build(), as: UTF8.self)
        XCTAssertTrue(text.contains("W n"),
                      "PDF content must carry the clip path operator, got: \(text)")
    }

    // MARK: - Lisp sysvars + tblsearch

    private func makeHost() -> LispCADHost {
        let doc = CADDocument()
        doc.addLayer(Layer(name: "0"))
        doc.activeLayerID = doc.findLayer(named: "0")?.handle
        let host = LispCADHost(
            document: doc,
            selection: CADSelectionManager(),
            processor: CADCommandProcessor())
        host.output = { _ in }
        return host
    }

    private func eval(
        _ source: String, host: LispCADHost, env: inout LispEnvironment
    ) async throws -> LispValue {
        let forms = try LispReader().readAll(source)
        return try await LispEvaluator().run(forms, env: &env, host: host)
    }

    func testXrefSysvarsRoundTripAndValidate() async throws {
        let host = makeHost()
        var env = LispEnvironment()
        let savedFade = XrefSysvars.fadePercent
        let savedPath = XrefSysvars.refPathType
        let savedBind = XrefSysvars.bindType
        defer {
            XrefSysvars.fadePercent = savedFade
            XrefSysvars.refPathType = savedPath
            XrefSysvars.bindType = savedBind
            // UserDefaults-backed vars reset to documented defaults so
            // no test pollution leaks into later suites or runs.
            XrefSysvars.visRetain = 1
            XrefSysvars.xrefNotify = 1
            XrefSysvars.xloadCtl = 2
        }

        for (name, value) in [("REFPATHTYPE", 2), ("VISRETAIN", 0),
                              ("BINDTYPE", 1), ("XREFNOTIFY", 0),
                              ("XDWGFADECTL", 70), ("XLOADCTL", 0)] {
            let set = try await eval("(setvar \"\(name)\" \(value))", host: host, env: &env)
            XCTAssertEqual(set, .int(value), "setvar \(name)")
            let got = try await eval("(getvar \"\(name)\")", host: host, env: &env)
            XCTAssertEqual(got, .int(value), "getvar \(name)")
        }
        // Out-of-range values are rejected: stored values stay put.
        _ = try await eval(#"(setvar "XDWGFADECTL" 95)"#, host: host, env: &env)
        let stillFade = try await eval(#"(getvar "XDWGFADECTL")"#, host: host, env: &env)
        XCTAssertEqual(stillFade, .int(70))
        _ = try await eval(#"(setvar "VISRETAIN" 7)"#, host: host, env: &env)
        let still = try await eval(#"(getvar "VISRETAIN")"#, host: host, env: &env)
        XCTAssertEqual(still, .int(0))
    }

    func testTblsearchBlockReturnsXrefGroups() async throws {
        let host = makeHost()
        var env = LispEnvironment()
        var block = CADBlock(name: "SitePlan", geometry: [], primitiveStyles: [:])
        block.xrefDescriptor = CADXrefDescriptor(
            savedPath: #".\refs\site plan.dwg"#, isOverlay: true)
        host.document.addBlock(block)

        let result = try await eval(#"(tblsearch "BLOCK" "SitePlan")"#, host: host, env: &env)
        guard let items = result.properList else {
            return XCTFail("tblsearch should return a DXF list, got \(result)")
        }
        var byCode: [Int: LispValue] = [:]
        for item in items {
            if case let .cons(head, tail) = item, case let .int(code) = head {
                byCode[code] = tail
            }
        }
        XCTAssertEqual(byCode[1], .string(#".\refs\site plan.dwg"#))
        guard case let .int(flags)? = byCode[70] else {
            return XCTFail("group 70 flags missing")
        }
        XCTAssertEqual(flags & 4, 4, "xref bit")
        XCTAssertEqual(flags & 8, 8, "overlay bit")
    }

    // MARK: - VISRETAIN=0 reset

    func testVisretainZeroResetsDependentLayers() {
        let doc = CADDocument()
        doc.addLayer(Layer(name: "0"))
        var stale = Layer(name: "Site|Walls")
        stale.isVisible = false
        doc.addLayer(stale)

        var fresh = Layer(name: "Site|Walls")
        fresh.isVisible = true
        doc.mergeXrefDependentSymbols(
            layers: [fresh], textStyles: [:], dimensionStyles: [:],
            leaderStyles: [:], linetypePatterns: [:], resetExisting: false)
        XCTAssertEqual(doc.findLayer(named: "Site|Walls")?.isVisible, false,
                       "VISRETAIN=1 keeps host overrides")

        doc.mergeXrefDependentSymbols(
            layers: [fresh], textStyles: [:], dimensionStyles: [:],
            leaderStyles: [:], linetypePatterns: [:], resetExisting: true)
        XCTAssertEqual(doc.findLayer(named: "Site|Walls")?.isVisible, true,
                       "VISRETAIN=0 resets to source state")
    }
}
