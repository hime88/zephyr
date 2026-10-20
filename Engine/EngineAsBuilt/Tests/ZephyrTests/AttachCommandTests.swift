import XCTest
import ZephyrLisp
@testable import ZephyrCore

/// ATTACH Unit 3: attach operations + scripted (command "-ATTACH").
@MainActor
final class AttachCommandTests: XCTestCase {

    private static let tinyPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR42mP8z8DwHwwKwMDA8N8ABAAFAQC8v7ZsAAAAASUVORK5CYII="

    private func makeFolder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("attach-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDoc() -> (CADDocument, MediaReferenceStore) {
        let doc = CADDocument()
        doc.addLayer(Layer(name: "0"))
        doc.activeLayerID = doc.findLayer(named: "0")?.handle
        let store = MediaReferenceStore()
        doc.mediaRuntimeStore = store
        return (doc, store)
    }

    func testAttachImageCreatesDefinitionAndReusesSameFile() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pngURL = folder.appendingPathComponent("site photo.png")
        try Data(base64Encoded: Self.tinyPNGBase64)!.write(to: pngURL)
        let (doc, store) = makeDoc()

        let def = try MediaManager.attachImage(
            store: store, documents: [doc], activeDocument: doc,
            fileURL: pngURL, pathType: 1, hostFolder: folder.path)
        XCTAssertEqual(def.name, "site photo")
        XCTAssertEqual(def.savedPath, "./site photo.png", "REFPATHTYPE=1 relative to host folder")
        XCTAssertNotNil(doc.imageDefinitions[def.name])

        let again = try MediaManager.attachImage(
            store: store, documents: [doc], activeDocument: doc,
            fileURL: pngURL, pathType: 1, hostFolder: folder.path)
        XCTAssertEqual(again.name, def.name, "same file reuses the definition")
        XCTAssertEqual(doc.imageDefinitions.count, 1)
    }

    func testAttachImageRejectsUnsupportedAndCorrupt() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let badURL = folder.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: badURL)
        let (doc, store) = makeDoc()
        XCTAssertThrowsError(try MediaManager.attachImage(
            store: store, documents: [doc], activeDocument: doc,
            fileURL: badURL, pathType: 1, hostFolder: folder.path))
        XCTAssertTrue(doc.imageDefinitions.isEmpty)
    }

    func testMakeInstanceCarriesPdfParams() {
        let entity = MediaManager.makeInstance(
            name: "Plan", kind: .pdf, naturalWidth: 612, naturalHeight: 792,
            center: Vector3(x: 10, y: 20, z: 0), scale: 2, rotationDegrees: 0,
            layerID: UUID())
        XCTAssertEqual(entity.localGeometry?.first?.imageReferenceName, "Plan")
        let params = CADPdfUnderlayMetadata.value(from: entity)
        XCTAssertEqual(params?.scaleX ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(params?.pageWidthPoints ?? 0, 612, accuracy: 1e-9)
    }

    func testCommandsRegistered() {
        for name in ["ATTACH", "IMAGEATTACH", "PDFATTACH", "-ATTACH"] {
            XCTAssertTrue(
                CommandDescriptor.allCommands.contains { $0.canonicalName == name },
                "\(name) descriptor missing")
        }
    }

    // MARK: - Scripted -ATTACH

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

    func testScriptedMinusAttachImage() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pngURL = folder.appendingPathComponent("photo.png")
        try Data(base64Encoded: Self.tinyPNGBase64)!.write(to: pngURL)

        let host = makeHost()
        var env = LispEnvironment()
        _ = try await eval(
            "(command \"-ATTACH\" \"\(pngURL.path)\" '(10 20 0) \"2\" \"0\")",
            host: host, env: &env)

        XCTAssertEqual(host.document.imageDefinitions.count, 1)
        XCTAssertEqual(host.document.imageDefinitions["photo"]?.savedPath, pngURL.path)
        let placed = host.document.allEntities.filter {
            ($0.localGeometry ?? []).contains { $0.imageReferenceName == "photo" }
        }
        XCTAssertEqual(placed.count, 1)
        // Loaded synchronously into the runtime store, not imageStore.
        XCTAssertTrue(host.document.imageStore.isEmpty)
        XCTAssertEqual(
            host.document.mediaRuntimeStore?.status(forName: "photo"), .loaded)
    }

    func testScriptedMinusAttachRejectsDrawing() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let dxfURL = folder.appendingPathComponent("x.dxf")
        try Data("0\nEOF\n".utf8).write(to: dxfURL)
        let host = makeHost()
        var env = LispEnvironment()
        do {
            _ = try await eval(
                "(command \"-ATTACH\" \"\(dxfURL.path)\" '(0 0 0))",
                host: host, env: &env)
            XCTFail("drawing attach must reject in scripted -ATTACH")
        } catch {
            // Expected hostError.
        }
    }
}

extension AttachCommandTests {

    // MARK: - Palette policy + management (Unit 4)

    private func loadedPhotoDoc() async throws -> (CADDocument, MediaReferenceStore, URL) {
        let folder = try makeFolder()
        let pngURL = folder.appendingPathComponent("photo.png")
        try Data(base64Encoded: Self.tinyPNGBase64)!.write(to: pngURL)
        let (doc, store) = makeDoc()
        let def = try MediaManager.attachImage(
            store: store, documents: [doc], activeDocument: doc,
            fileURL: pngURL, pathType: 0, hostFolder: folder.path)
        let entity = MediaManager.makeInstance(
            name: def.name, kind: .image,
            naturalWidth: Double(def.pixelWidth), naturalHeight: Double(def.pixelHeight),
            center: .zero, scale: 1, rotationDegrees: 0,
            layerID: doc.findLayer(named: "0")!.handle)
        doc.addEntity(entity)
        // Wait for the async load kicked by attach.
        let deadline = Date().addingTimeInterval(10)
        while store.status(forName: def.name) != .loaded, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return (doc, store, folder)
    }

    func testMediaRowsAndWarning() async throws {
        let (doc, store, folder) = try await loadedPhotoDoc()
        defer { try? FileManager.default.removeItem(at: folder) }

        let rows = XrefPalettePolicy.mediaRows(store: store, documents: [doc])
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.name, "photo")
        XCTAssertEqual(row.kind, .image)
        XCTAssertEqual(row.status, .loaded)
        XCTAssertEqual(row.instanceCount, 1)
        XCTAssertTrue(row.canEmbed)
        XCTAssertTrue(row.canUnload)
        XCTAssertFalse(XrefPalettePolicy.hasMediaWarning(store: store))

        store.updateEntry(forName: "photo") { $0.status = .needsReload }
        XCTAssertTrue(XrefPalettePolicy.hasMediaWarning(store: store))
    }

    func testEmbedMakesInstanceSelfContained() async throws {
        let (doc, store, folder) = try await loadedPhotoDoc()
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertTrue(MediaManager.embed(
            store: store, documents: [doc], activeDocument: doc, name: "photo"))
        XCTAssertNil(doc.imageDefinitions["photo"])
        XCTAssertNil(store.entry(forName: "photo"))
        let names = doc.allEntities.flatMap {
            ($0.localGeometry ?? []).compactMap(\.imageReferenceName)
        }
        XCTAssertEqual(names.count, 1)
        let assetName = try XCTUnwrap(names.first)
        XCTAssertNotNil(doc.imageStore[assetName], "embedded asset must live in imageStore")
    }

    func testDetachRemovesDefinitionAndInstances() async throws {
        let (doc, store, folder) = try await loadedPhotoDoc()
        defer { try? FileManager.default.removeItem(at: folder) }

        MediaManager.detach(
            store: store, documents: [doc], activeDocument: doc, name: "photo")
        XCTAssertNil(doc.imageDefinitions["photo"])
        XCTAssertNil(store.entry(forName: "photo"))
        XCTAssertTrue(doc.allEntities.isEmpty)
    }
}
