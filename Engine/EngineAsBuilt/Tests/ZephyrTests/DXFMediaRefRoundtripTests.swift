import XCTest
@testable import ZephyrCore

/// ATTACH Unit 0: media definition spine — IMAGEDEF/PDFDEFINITION
/// import into document definitions, instance retargeting, EAB
/// round trip, and silent (geometry-free) output for unresolved references.
@MainActor
final class DXFMediaRefRoundtripTests: XCTestCase {

    /// Hand-written DXF: one IMAGE (clipped) + one PDFUNDERLAY page 2,
    /// definitions in the OBJECTS section dictionaries.
    private func mediaDXF() -> String {
        let lines: [String] = [
            "0", "SECTION", "2", "HEADER", "0", "ENDSEC",
            "0", "SECTION", "2", "TABLES",
            "0", "TABLE", "2", "LAYER", "5", "10",
            "0", "LAYER", "5", "11", "2", "0", "70", "0", "62", "7", "6", "Continuous",
            "0", "ENDTAB", "0", "ENDSEC",
            "0", "SECTION", "2", "ENTITIES",
            // IMAGE: 100x50 px at origin, 1 unit/px, clipped to inner rect.
            "0", "IMAGE", "5", "30", "100", "AcDbEntity", "8", "0",
            "100", "AcDbRasterImage",
            "10", "0.0", "20", "0.0", "30", "0.0",
            "11", "1.0", "21", "0.0", "31", "0.0",
            "12", "0.0", "22", "1.0", "32", "0.0",
            "13", "100.0", "23", "50.0",
            "340", "100",
            "70", "3", "280", "1", "281", "50", "282", "50", "283", "0",
            "71", "1", "91", "2",
            "14", "10.0", "24", "5.0",
            "14", "90.0", "24", "45.0",
            // PDFUNDERLAY page 2 at (200,0), scale 2, boundary rect.
            "0", "PDFUNDERLAY", "5", "31", "100", "AcDbEntity", "8", "0",
            "100", "AcDbPdfUnderlay",
            "340", "110",
            "10", "200.0", "20", "0.0", "30", "0.0",
            "41", "2.0", "42", "2.0", "43", "1.0",
            "50", "0.0",
            "280", "3", "281", "90", "282", "10",
            "11", "0.0", "21", "0.0",
            "11", "300.0", "21", "400.0",
            "0", "ENDSEC",
            "0", "SECTION", "2", "OBJECTS",
            "0", "DICTIONARY", "5", "C", "330", "0", "100", "AcDbDictionary", "281", "1",
            "3", "ACAD_IMAGE_DICT", "350", "F0",
            "3", "ACAD_PDFDEFINITIONS", "350", "F1",
            "0", "DICTIONARY", "5", "F0", "330", "C", "100", "AcDbDictionary", "281", "1",
            "3", "SitePhoto", "350", "100",
            "0", "IMAGEDEF", "5", "100", "330", "F0", "100", "AcDbRasterImageDef",
            "90", "0", "1", #".\media\site photo.jpg"#,
            "10", "100.0", "20", "50.0", "11", "1.0", "21", "1.0",
            "280", "1", "281", "0",
            "0", "DICTIONARY", "5", "F1", "330", "C", "100", "AcDbDictionary", "281", "1",
            "3", "PlanSet", "350", "110",
            "0", "PDFDEFINITION", "5", "110", "330", "F1", "100", "AcDbPdfDefinition",
            "1", #"..\docs\plan set.pdf"#, "2", "2",
            "0", "ENDSEC",
            "0", "EOF",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    private func importFixture() throws -> DXFImportResult {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("media-fixture-\(UUID().uuidString).dxf")
        defer { try? FileManager.default.removeItem(at: url) }
        try mediaDXF().write(to: url, atomically: true, encoding: .utf8)
        return try DXFImporter.importDXFViews(filePath: url.path)
    }

    func testImportCreatesMediaDefinitionsAndRetargetsInstances() throws {
        let result = try importFixture()

        XCTAssertEqual(result.imageDefinitions.count, 1)
        let photo = try XCTUnwrap(result.imageDefinitions.first)
        XCTAssertEqual(photo.name, "SitePhoto")
        XCTAssertEqual(photo.savedPath, #".\media\site photo.jpg"#)
        XCTAssertEqual(photo.pixelWidth, 100)
        XCTAssertEqual(photo.pixelHeight, 50)

        XCTAssertEqual(result.pdfDefinitions.count, 1)
        let plan = try XCTUnwrap(result.pdfDefinitions.first)
        XCTAssertEqual(plan.name, "PlanSet")
        XCTAssertEqual(plan.savedPath, #"..\docs\plan set.pdf"#)
        XCTAssertEqual(plan.pageNumber, 2)

        // Instances name definitions, not file paths.
        let imageNames = result.entities.flatMap { entity in
            (entity.localGeometry ?? []).compactMap(\.imageReferenceName)
        }
        XCTAssertEqual(Set(imageNames), ["SitePhoto", "PlanSet"])

        // PDF instance carries underlay params.
        let pdfEntity = try XCTUnwrap(result.entities.first {
            CADPdfUnderlayMetadata.value(from: $0) != nil
        })
        let params = try XCTUnwrap(CADPdfUnderlayMetadata.value(from: pdfEntity))
        XCTAssertEqual(params.scaleX, 2, accuracy: 1e-9)
        XCTAssertEqual(params.contrast, 90)
        XCTAssertEqual(params.fade, 10)
        XCTAssertTrue(params.isOn)

        // Image instance carries a mapped clip boundary (pixel → local).
        let clipped = result.entities.flatMap { $0.localGeometry ?? [] }.compactMap { prim -> [Vector3]? in
            if case .image(_, _, _, let name, let clip, _) = prim, name == "SitePhoto" {
                return clip
            }
            return nil
        }.first
        let boundary = try XCTUnwrap(clipped ?? nil)
        XCTAssertEqual(boundary.count, 4)
        XCTAssertEqual(boundary.map(\.x).max() ?? -1, 90, accuracy: 1e-9)
    }

    func testEABRoundTripPreservesDefinitionsWithoutPixels() throws {
        let result = try importFixture()
        let doc = CADDocument()
        doc.importLayersBlocksEntities(
            layers: result.layers, blocks: result.blocks, entities: result.entities)
        doc.importMediaDefinitions(
            image: result.imageDefinitions, pdf: result.pdfDefinitions)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("media-\(UUID().uuidString).eab")
        defer { try? FileManager.default.removeItem(at: url) }
        try EABWriter.write(document: doc, to: url)

        let views = try EABReader.readViews(from: url)
        let restored = try XCTUnwrap(views.first?.document)
        XCTAssertEqual(restored.imageDefinitions["SitePhoto"]?.savedPath,
                       #".\media\site photo.jpg"#)
        XCTAssertEqual(restored.pdfDefinitions["PlanSet"]?.pageNumber, 2)
        XCTAssertTrue(restored.imageStore.isEmpty,
                      "referenced media pixels must never enter the archive")
    }

    func testDXFExportWritesStandardDefinitionsAndReimports() throws {
        let result = try importFixture()
        let doc = CADDocument()
        doc.importLayersBlocksEntities(
            layers: result.layers, blocks: result.blocks, entities: result.entities)
        doc.importMediaDefinitions(
            image: result.imageDefinitions, pdf: result.pdfDefinitions)

        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("media-out-\(UUID().uuidString).dxf")
        defer { try? FileManager.default.removeItem(at: outURL) }
        try DXFWriterBridge.export(document: doc, to: outURL)
        let text = try String(contentsOf: outURL, encoding: .utf8)

        XCTAssertTrue(text.contains("IMAGEDEF"))
        XCTAssertTrue(text.contains("PDFDEFINITION"))
        XCTAssertTrue(text.contains("PDFUNDERLAY"))
        XCTAssertTrue(text.contains("ACAD_PDFDEFINITIONS"))
        XCTAssertTrue(text.contains(#".\media\site photo.jpg"#))
        XCTAssertTrue(text.contains(#"..\docs\plan set.pdf"#))
        XCTAssertTrue(text.contains("SitePhoto"), "definition name must be the dictionary key")
        XCTAssertTrue(text.contains("PlanSet"))

        let reimported = try DXFImporter.importDXFViews(filePath: outURL.path)
        XCTAssertEqual(reimported.imageDefinitions.count, 1)
        XCTAssertEqual(reimported.imageDefinitions.first?.name, "SitePhoto")
        XCTAssertEqual(reimported.imageDefinitions.first?.savedPath, #".\media\site photo.jpg"#)
        XCTAssertEqual(reimported.imageDefinitions.first?.pixelWidth, 100)
        XCTAssertEqual(reimported.pdfDefinitions.count, 1)
        XCTAssertEqual(reimported.pdfDefinitions.first?.name, "PlanSet")
        XCTAssertEqual(reimported.pdfDefinitions.first?.pageNumber, 2)

        let names = reimported.entities.flatMap {
            ($0.localGeometry ?? []).compactMap(\.imageReferenceName)
        }
        XCTAssertEqual(Set(names), ["SitePhoto", "PlanSet"])
        let params = reimported.entities.compactMap {
            CADPdfUnderlayMetadata.value(from: $0)
        }.first
        XCTAssertEqual(params?.scaleX ?? 0, 2, accuracy: 1e-6)
        XCTAssertEqual(params?.contrast, 90)
    }

    func testUnresolvedMediaRendersNothing() async throws {
        let result = try importFixture()
        let doc = CADDocument()
        doc.importLayersBlocksEntities(
            layers: result.layers, blocks: result.blocks, entities: result.entities)
        doc.importMediaDefinitions(
            image: result.imageDefinitions, pdf: result.pdfDefinitions)

        let results = await CADRendererBridge.computeSpecs(
            fromSnapshot: doc.snapshot(), simplifyComplexBlocks: false)
        let withImage = results.filter { !$0.imageSpecs.isEmpty }
        XCTAssertEqual(withImage.count, 2)
        for entry in withImage {
            XCTAssertTrue(entry.specs.isEmpty,
                          "unresolved media must render nothing; the reference stays listed in the xref palette")
        }
    }
}
