import XCTest
@testable import ZephyrCore

/// ATTACH Unit 5: media load timings (printed; generous fences).
@MainActor
final class MediaHeavyPerfTests: XCTestCase {

    private static let tinyPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR42mP8z8DwHwwKwMDA8N8ABAAFAQC8v7ZsAAAAASUVORK5CYII="

    func testLoadTwentyImagesAndOnePDF() async throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("media-perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let png = Data(base64Encoded: Self.tinyPNGBase64)!
        let doc = CADDocument()
        doc.addLayer(Layer(name: "0"))
        let store = MediaReferenceStore()
        doc.mediaRuntimeStore = store
        for i in 0..<20 {
            let url = folder.appendingPathComponent("img\(i).png")
            try png.write(to: url)
            let def = CADImageDefinition(name: "img\(i)", savedPath: "img\(i).png")
            doc.imageDefinitions[def.name] = def
            store.ensureEntry(kind: .image, name: def.name, savedPath: def.savedPath)
        }
        // One real PDF via the app's exporter.
        let srcDoc = CADDocument()
        srcDoc.addLayer(Layer(name: "0"))
        let pdfURL = folder.appendingPathComponent("plan.pdf")
        try PDFExporter.export(document: srcDoc, to: pdfURL)
        let pdfDef = CADPdfDefinition(name: "plan", savedPath: "plan.pdf", pageNumber: 1)
        doc.pdfDefinitions[pdfDef.name] = pdfDef
        store.ensureEntry(kind: .pdf, name: pdfDef.name, savedPath: pdfDef.savedPath, pageNumber: 1)

        let start = Date()
        MediaLoader.loadAllPending(store: store, documents: [doc], hostFolder: folder.path)
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let pending = store.allEntries().contains {
                $0.status == .loading || $0.status == .unloaded
            }
            if !pending { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let seconds = Date().timeIntervalSince(start)
        let loaded = store.allEntries().filter { $0.status == .loaded }.count
        print("[MediaHeavyPerf] 20 images + 1 PDF load: \(String(format: "%.3f", seconds))s, \(loaded) loaded, \(store.totalDecodedPixels()) decoded px")
        XCTAssertEqual(loaded, 21)
        XCTAssertLessThan(seconds, 30, "media batch load regression fence (debug)")
    }
}
