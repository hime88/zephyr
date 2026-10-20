import XCTest
@testable import ZephyrCore

/// ATTACH Unit 1: media reference loading — resolve, decode/rasterize,
/// runtime-asset channel keeps pixels out of imageStore/undo/saves.
@MainActor
final class MediaLoaderTests: XCTestCase {

    /// 2x2 transparent PNG.
    private static let tinyPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR42mP8z8DwHwwKwMDA8N8ABAAFAQC8v7ZsAAAAASUVORK5CYII="

    private func makeFolder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("media-loader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitForStatus(
        _ store: MediaReferenceStore, name: String, timeout: TimeInterval = 10
    ) async -> XrefStatus {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let status = store.status(forName: name)
            if status != .loading && status != .unloaded { return status }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return store.status(forName: name)
    }

    private func docWithDefs(
        image: CADImageDefinition? = nil, pdf: CADPdfDefinition? = nil
    ) -> (CADDocument, MediaReferenceStore) {
        let doc = CADDocument()
        doc.addLayer(Layer(name: "0"))
        doc.activeLayerID = doc.findLayer(named: "0")?.handle
        let store = MediaReferenceStore()
        doc.mediaRuntimeStore = store
        for def in [image].compactMap({ $0 }) {
            doc.imageDefinitions[def.name] = def
            store.ensureEntry(kind: .image, name: def.name, savedPath: def.savedPath)
        }
        for def in [pdf].compactMap({ $0 }) {
            doc.pdfDefinitions[def.name] = def
            store.ensureEntry(
                kind: .pdf, name: def.name, savedPath: def.savedPath,
                pageNumber: def.pageNumber)
        }
        return (doc, store)
    }

    func testImageLoadsIntoRuntimeStoreNotImageStore() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pngURL = folder.appendingPathComponent("photo.png")
        try Data(base64Encoded: Self.tinyPNGBase64)!.write(to: pngURL)

        let (doc, store) = docWithDefs(image: CADImageDefinition(
            name: "Photo", savedPath: "photo.png"))
        // Instance referencing the definition.
        var entity = CADEntity(
            handle: UUID(), layerID: try XCTUnwrap(doc.findLayer(named: "0")?.handle),
            blockID: nil,
            localGeometry: [.image(
                insertion: .zero, uAxis: Vector3(x: 20, y: 0, z: 0),
                vAxis: Vector3(x: 0, y: -20, z: 0), imageName: "Photo",
                clipBoundary: nil, tint: nil)],
            transform: .identity, xdata: [:], drawOrder: 0)
        entity.localBoundingBox = BoundingBox3D(min: .zero, max: Vector3(x: 20, y: 20, z: 0))
        doc.addEntities([entity])
        let editBefore = doc.editRevision

        MediaLoader.requestLoad(
            store: store, name: "Photo", documents: [doc], hostFolder: folder.path)
        let status = await waitForStatus(store, name: "Photo")
        XCTAssertEqual(status, .loaded, store.entry(forName: "Photo")?.statusDetail ?? "")

        XCTAssertEqual(store.entry(forName: "Photo")?.asset?.pixelWidth, 2)
        XCTAssertTrue(doc.imageStore.isEmpty, "runtime asset must not enter imageStore")
        XCTAssertNotNil(doc.effectiveImageStore["Photo"])
        XCTAssertEqual(doc.editRevision, editBefore, "loading must not dirty the document")
        XCTAssertTrue(doc.renderSnapshot().availableImageAssetNames.contains("Photo"))
        XCTAssertFalse(doc.snapshot().availableImageAssetNames.contains("Photo"),
                       "undo snapshots stay free of runtime assets")
        // Definition pixel size refreshed from the file.
        XCTAssertEqual(doc.imageDefinitions["Photo"]?.pixelWidth, 2)
    }

    func testImageNotFoundAndUnresolved() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let badURL = folder.appendingPathComponent("bad.png")
        try Data("not a png".utf8).write(to: badURL)

        let (doc, store) = docWithDefs(image: CADImageDefinition(
            name: "Missing", savedPath: "nope.png"))
        MediaLoader.requestLoad(
            store: store, name: "Missing", documents: [doc], hostFolder: folder.path)
        let missing = await waitForStatus(store, name: "Missing")
        XCTAssertEqual(missing, .notFound)

        store.ensureEntry(kind: .image, name: "Bad", savedPath: "bad.png")
        MediaLoader.requestLoad(
            store: store, name: "Bad", documents: [doc], hostFolder: folder.path)
        let bad = await waitForStatus(store, name: "Bad")
        XCTAssertEqual(bad, .unresolved)
    }

    func testPDFLoadRasterizesPageAndResyncsAxes() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Produce a real one-page PDF with the app's own exporter.
        let srcDoc = CADDocument()
        srcDoc.addLayer(Layer(name: "0"))
        let pdfURL = folder.appendingPathComponent("plan.pdf")
        try PDFExporter.export(document: srcDoc, to: pdfURL)
        try XCTSkipUnless(PDFPageRenderer.isAvailable, "no PDF backend")

        let (doc, store) = docWithDefs(pdf: CADPdfDefinition(
            name: "Plan", savedPath: "plan.pdf", pageNumber: 1))
        var entity = CADEntity(
            handle: UUID(), layerID: try XCTUnwrap(doc.findLayer(named: "0")?.handle),
            blockID: nil,
            localGeometry: [.image(
                insertion: .zero,
                uAxis: Vector3(x: CADPdfUnderlayParams.placeholderPageWidth, y: 0, z: 0),
                vAxis: Vector3(x: 0, y: -CADPdfUnderlayParams.placeholderPageHeight, z: 0),
                imageName: "Plan", clipBoundary: nil, tint: nil)],
            transform: .identity, xdata: [:], drawOrder: 0)
        CADPdfUnderlayMetadata.set(CADPdfUnderlayParams(), on: &entity)
        doc.addEntities([entity])

        MediaLoader.requestLoad(
            store: store, name: "Plan", documents: [doc], hostFolder: folder.path)
        let status = await waitForStatus(store, name: "Plan")
        XCTAssertEqual(status, .loaded, store.entry(forName: "Plan")?.statusDetail ?? "")

        let entry = try XCTUnwrap(store.entry(forName: "Plan"))
        XCTAssertNotNil(entry.asset)
        let pageW = try XCTUnwrap(entry.pageWidthPoints)
        XCTAssertGreaterThan(pageW, 100)
        // Instance axes resynced from placeholder to real page size.
        let stored = try XCTUnwrap(doc.allEntities.first)
        let params = try XCTUnwrap(CADPdfUnderlayMetadata.value(from: stored))
        XCTAssertEqual(params.pageWidthPoints, pageW, accuracy: 1e-6)
    }

    func testHeaderProbe() {
        let png = Data(base64Encoded: Self.tinyPNGBase64)!
        XCTAssertEqual(MediaLoader.imageDimensions(of: png)?.width, 2)
        XCTAssertEqual(MediaLoader.imageDimensions(of: png)?.height, 2)
        XCTAssertNil(MediaLoader.imageDimensions(of: Data("junk".utf8)))
    }
}
