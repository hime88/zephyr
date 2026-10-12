import XCTest
@testable import ZephyrLisp

/// Wave-C layerstate-* family against the scripted layer store.
final class LispLayerStateTests: XCTestCase {

    private func hostWithLayers() -> ScriptedLispHost {
        let host = ScriptedLispHost()
        host.layers = ["0": true, "Walls": true, "Hidden": false]
        return host
    }

    func testSaveRestoreRoundTrip() async throws {
        var env = LispEnvironment()
        let host = hostWithLayers()
        let saved = try await evalString(
            "(layerstate-save \"Day\")", env: &env, host: host)
        XCTAssertEqual(saved, .t)
        let hasDay = try await evalString(
            "(layerstate-has \"Day\")", env: &env, host: host)
        XCTAssertEqual(hasDay, .t)
        let hasNope = try await evalString(
            "(layerstate-has \"Nope\")", env: &env, host: host)
        XCTAssertEqual(hasNope, .nilValue)
        host.layers["Walls"] = false
        let differ = try await evalString(
            "(layerstate-compare \"Day\" nil)", env: &env, host: host)
        XCTAssertEqual(differ, .nilValue)
        let restored = try await evalString(
            "(layerstate-restore \"Day\")", env: &env, host: host)
        XCTAssertEqual(restored, .t)
        XCTAssertEqual(host.layers["Walls"], true)
        let same = try await evalString(
            "(layerstate-compare \"Day\" nil)", env: &env, host: host)
        XCTAssertEqual(same, .t)
        let last = try await evalString(
            "(layerstate-getlastrestored)", env: &env, host: host)
        XCTAssertEqual(last, .string("Day"))
        let unknown = try await evalString(
            "(layerstate-restore \"Nope\")", env: &env, host: host)
        XCTAssertEqual(unknown, .nilValue)
        _ = host
    }

    func testNamesLayersAddRemove() async throws {
        var env = LispEnvironment()
        let host = hostWithLayers()
        _ = try await evalString("(layerstate-save \"A\")", env: &env, host: host)
        _ = try await evalString("(layerstate-save \"B\")", env: &env, host: host)
        let names = try await evalString(
            "(layerstate-getnames)", env: &env, host: host)
        XCTAssertEqual(names, LispValue(stringList: ["A", "B"]))
        let layersA = try await evalString(
            "(layerstate-getlayers \"A\")", env: &env, host: host)
        XCTAssertEqual(layersA, LispValue(stringList: ["0", "Hidden", "Walls"]))
        _ = try await evalString(
            "(layerstate-removelayers \"A\" '(\"Walls\"))", env: &env, host: host)
        let removed = try await evalString(
            "(layerstate-getlayers \"A\")", env: &env, host: host)
        XCTAssertEqual(removed, LispValue(stringList: ["0", "Hidden"]))
        _ = try await evalString(
            "(layerstate-addlayers \"A\" '(\"Walls\"))", env: &env, host: host)
        let added = try await evalString(
            "(layerstate-getlayers \"A\")", env: &env, host: host)
        XCTAssertEqual(added, LispValue(stringList: ["0", "Hidden", "Walls"]))
        let renamed = try await evalString(
            "(layerstate-rename \"B\" \"C\")", env: &env, host: host)
        XCTAssertEqual(renamed, .t)
        let hasC = try await evalString(
            "(layerstate-has \"C\")", env: &env, host: host)
        XCTAssertEqual(hasC, .t)
        let deleted = try await evalString(
            "(layerstate-delete \"A\")", env: &env, host: host)
        XCTAssertEqual(deleted, .t)
        let deletedAgain = try await evalString(
            "(layerstate-delete \"A\")", env: &env, host: host)
        XCTAssertEqual(deletedAgain, .nilValue)
        _ = host
    }

    func testRestoreOffMissingFlag() async throws {
        var env = LispEnvironment()
        let host = hostWithLayers()
        _ = try await evalString("(layerstate-save \"Day\")", env: &env, host: host)
        _ = try await evalString(
            "(layerstate-removelayers \"Day\" '(\"Walls\"))", env: &env, host: host)
        host.layers["Extra"] = true
        let restored = try await evalString(
            "(layerstate-restore \"Day\" nil 1)", env: &env, host: host)
        XCTAssertEqual(restored, .t)
        XCTAssertEqual(host.layers["Extra"], false)
        XCTAssertEqual(host.layers["0"], true)
        _ = host
    }

    func testExportImportRoundTrip() async throws {
        var env = LispEnvironment()
        let host = hostWithLayers()
        _ = try await evalString("(layerstate-save \"Day\")", env: &env, host: host)
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("day-\(Int.random(in: 0...Int.max)).las").path
        let exported = try await evalString(
            "(layerstate-export \"Day\" \"\(path)\")", env: &env, host: host)
        XCTAssertEqual(exported, .t)
        let exportMissing = try await evalString(
            "(layerstate-export \"Nope\" \"\(path)\")", env: &env, host: host)
        XCTAssertEqual(exportMissing, .nilValue)
        var fresh = LispEnvironment()
        let imported = try await evalString(
            "(layerstate-import \"\(path)\")", env: &fresh, host: host)
        XCTAssertEqual(imported, .t)
        let layers = try await evalString(
            "(layerstate-getlayers \"Day\")", env: &fresh, host: host)
        XCTAssertEqual(layers, LispValue(stringList: ["0", "Hidden", "Walls"]))
        let importMissing = try await evalString(
            "(layerstate-import \"/no/such/file.las\")", env: &fresh, host: host)
        XCTAssertEqual(importMissing, .nilValue)
        _ = host
    }

    func testImportfromdbReturnsNil() async throws {
        var env = LispEnvironment()
        let host = hostWithLayers()
        let result = try await evalString(
            "(layerstate-importfromdb \"Day\" nil)", env: &env, host: host)
        XCTAssertEqual(result, .nilValue)
        _ = host
    }
}
