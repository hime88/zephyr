import XCTest
import ZephyrLisp
@testable import ZephyrCore

/// Step-4d CAD bindings: osnap over real entity anchors and the
/// layerstate host surface over CADDocument layers.
@MainActor
final class LispOsnapLayerTests: XCTestCase {

    private func makeHost() -> LispCADHost {
        let doc = CADDocument()
        doc.addLayer(Layer(name: "0"))
        doc.addLayer(Layer(name: "Walls"))
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

    func testOsnapEndpointAndMidpoint() async throws {
        let host = makeHost()
        var env = LispEnvironment()
        _ = try await eval(
            #" (entmake '((0 . "LINE") (10 1 2 0) (11 3 4 0))) "#,
            host: host, env: &env)
        let end = try await eval("(osnap '(1.5 2 0) \"_end\")", host: host, env: &env)
        XCTAssertEqual(end.properList, [.real(1), .real(2), .real(0)])
        let mid = try await eval("(osnap '(2.2 3 0) \"_mid\")", host: host, env: &env)
        XCTAssertEqual(mid.properList, [.real(2), .real(3), .real(0)])
        let far = try await eval(
            "(osnap '(1000 1000 0) \"_end\")", host: host, env: &env)
        XCTAssertEqual(far, .nilValue)
    }

    func testLayerstateOverDocumentLayers() async throws {
        let host = makeHost()
        var env = LispEnvironment()
        let saved = try await eval(
            "(layerstate-save \"Day\")", host: host, env: &env)
        XCTAssertEqual(saved, .t)
        let layers = try await eval(
            "(layerstate-getlayers \"Day\")", host: host, env: &env)
        XCTAssertEqual(layers, LispValue(stringList: ["0", "Walls"]))
        let turnedOff = await host.setLayerIsOn("Walls", on: false)
        XCTAssertTrue(turnedOff)
        let isOn = await host.layerIsOn("walls")
        XCTAssertEqual(isOn, false)
        let differ = try await eval(
            "(layerstate-compare \"Day\" nil)", host: host, env: &env)
        XCTAssertEqual(differ, .nilValue)
        let restored = try await eval(
            "(layerstate-restore \"Day\")", host: host, env: &env)
        XCTAssertEqual(restored, .t)
        let backOn = await host.layerIsOn("Walls")
        XCTAssertEqual(backOn, true)
        let unknownSet = await host.setLayerIsOn("Nope", on: false)
        XCTAssertFalse(unknownSet)
        let unknownGet = await host.layerIsOn("Nope")
        XCTAssertNil(unknownGet)
    }
}
