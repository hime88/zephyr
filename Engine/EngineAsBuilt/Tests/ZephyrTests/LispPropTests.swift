import XCTest
import ZephyrLisp
@testable import ZephyrCore

/// Wave-B properties + trans + textbox, headless through LispCADHost.
@MainActor
final class LispPropTests: XCTestCase {

    private func makeHost() -> (LispCADHost, NSMutableString) {
        let doc = CADDocument()
        doc.addLayer(Layer(name: "0"))
        doc.addLayer(Layer(name: "WALLS"))
        doc.activeLayerID = doc.findLayer(named: "0")?.handle
        let host = LispCADHost(
            document: doc,
            selection: CADSelectionManager(),
            processor: CADCommandProcessor())
        let captured = NSMutableString(capacity: 0)
        host.output = { captured.append($0) }
        return (host, captured)
    }

    private func eval(
        _ source: String, host: LispCADHost, env: inout LispEnvironment
    ) async throws -> LispValue {
        let forms = try LispReader().readAll(source)
        return try await LispEvaluator().run(forms, env: &env, host: host)
    }

    func testCommonProps() async throws {
        let (host, _) = makeHost()
        var env = LispEnvironment()
        _ = try await eval(
            #"(setq E (entmake '((0 . "LINE") (10 0 0 0) (11 4 0 0))))"#,
            host: host, env: &env)
        let object = try await eval("(getpropertyvalue E \"ObjectName\")", host: host, env: &env)
        XCTAssertEqual(object, .string("LINE"))
        let layer = try await eval("(getpropertyvalue E \"Layer\")", host: host, env: &env)
        XCTAssertEqual(layer, .string("0"))
        let color = try await eval("(getpropertyvalue E \"Color\")", host: host, env: &env)
        XCTAssertEqual(color, .int(256))
        // Writes round-trip.
        _ = try await eval("(setpropertyvalue E \"Layer\" \"WALLS\")", host: host, env: &env)
        let layer2 = try await eval("(getpropertyvalue E \"Layer\")", host: host, env: &env)
        XCTAssertEqual(layer2, .string("WALLS"))
        _ = try await eval("(setpropertyvalue E \"Color\" 1)", host: host, env: &env)
        let color2 = try await eval("(getpropertyvalue E \"Color\")", host: host, env: &env)
        XCTAssertEqual(color2, .int(1))
        // Read-only probes.
        let roHandle = try await eval(
            "(ispropertyreadonly E \"Handle\")", host: host, env: &env)
        XCTAssertEqual(roHandle, .t)
        let rwLayer = try await eval(
            "(ispropertyreadonly E \"Layer\")", host: host, env: &env)
        XCTAssertEqual(rwLayer, .nilValue)
        // Read-only write throws.
        do {
            _ = try await eval(
                "(setpropertyvalue E \"Handle\" \"ZZ\")", host: host, env: &env)
            XCTFail("HANDLE is read-only")
        } catch let error as LispError {
            XCTAssertTrue("\(error)".contains("read-only"), "\(error)")
        }
        _ = host
    }

    func testLineGeometryProps() async throws {
        let (host, _) = makeHost()
        var env = LispEnvironment()
        _ = try await eval(
            #"(setq E (entmake '((0 . "LINE") (10 0 0 0) (11 3 4 0))))"#,
            host: host, env: &env)
        let length = try await eval("(getpropertyvalue E \"Length\")", host: host, env: &env)
        XCTAssertEqual(length.asDouble ?? -1, 5, accuracy: 1e-9)
        let angle = try await eval("(getpropertyvalue E \"Angle\")", host: host, env: &env)
        XCTAssertEqual(angle.asDouble ?? -1, atan2(4.0, 3.0), accuracy: 1e-9)
        _ = try await eval(
            "(setpropertyvalue E \"EndPoint\" '(6 8 0))", host: host, env: &env)
        let length2 = try await eval("(getpropertyvalue E \"Length\")", host: host, env: &env)
        XCTAssertEqual(length2.asDouble ?? -1, 10, accuracy: 1e-9)
        _ = host
    }

    func testCircleArcTextProps() async throws {
        let (host, _) = makeHost()
        var env = LispEnvironment()
        _ = try await eval(
            #"(setq C (entmake '((0 . "CIRCLE") (10 0 0 0) (40 . 2))))"#,
            host: host, env: &env)
        let area = try await eval("(getpropertyvalue C \"Area\")", host: host, env: &env)
        XCTAssertEqual(area.asDouble ?? -1, Double.pi * 4, accuracy: 1e-9)
        _ = try await eval(
            #"(setq A (entmake '((0 . "ARC") (10 0 0 0) (40 . 1) (50 . 0) (51 . 90))))"#,
            host: host, env: &env)
        let total = try await eval("(getpropertyvalue A \"TotalAngle\")", host: host, env: &env)
        XCTAssertEqual(total.asDouble ?? -1, Double.pi / 2, accuracy: 1e-9)
        _ = try await eval(
            #"(setq TX (entmake '((0 . "TEXT") (10 0 0 0) (40 . 2.5) (1 . "hi"))))"#,
            host: host, env: &env)
        let string = try await eval("(getpropertyvalue TX \"TextString\")", host: host, env: &env)
        XCTAssertEqual(string, .string("hi"))
        _ = try await eval("(setpropertyvalue TX \"TextString\" \"bye\")", host: host, env: &env)
        let string2 = try await eval("(getpropertyvalue TX \"TextString\")", host: host, env: &env)
        XCTAssertEqual(string2, .string("bye"))
        let height = try await eval("(getpropertyvalue TX \"Height\")", host: host, env: &env)
        XCTAssertEqual(height.asDouble ?? -1, 2.5, accuracy: 1e-9)
        _ = host
    }

    func testPolylineCoordinatesIndexed() async throws {
        let (host, _) = makeHost()
        var env = LispEnvironment()
        _ = try await eval(
            "(setq P (entmake '((0 . \"LWPOLYLINE\") (90 . 3) (70 . 1) (10 0 0 0) (10 4 0 0) (10 4 3 0))))",
            host: host, env: &env)
        let area = try await eval("(getpropertyvalue P \"Area\")", host: host, env: &env)
        XCTAssertEqual(area.asDouble ?? -1, 6, accuracy: 1e-9)
        let second = try await eval(
            "(getpropertyvalue P \"Coordinates\" 1)", host: host, env: &env)
        XCTAssertEqual(second.asPoint, [4, 0, 0])
        let closed = try await eval("(getpropertyvalue P \"Closed\")", host: host, env: &env)
        XCTAssertEqual(closed, .t)
        _ = try await eval("(setpropertyvalue P \"Closed\" nil)", host: host, env: &env)
        let open = try await eval("(getpropertyvalue P \"Closed\")", host: host, env: &env)
        XCTAssertEqual(open, .nilValue)
        _ = host
    }

    func testDumpallproperties() async throws {
        let (host, captured) = makeHost()
        var env = LispEnvironment()
        _ = try await eval(
            #"(setq E (entmake '((0 . "LINE") (10 0 0 0) (11 1 0 0))))"#,
            host: host, env: &env)
        let result = try await eval("(dumpallproperties E)", host: host, env: &env)
        XCTAssertEqual(result, .t)
        let output = captured as String
        XCTAssertTrue(output.contains("LAYER: "), output)
        XCTAssertTrue(output.contains("LENGTH: "), output)
    }

    func testUnknownPropThrows() async throws {
        let (host, _) = makeHost()
        var env = LispEnvironment()
        _ = try await eval(
            #"(setq E (entmake '((0 . "LINE") (10 0 0 0) (11 1 0 0))))"#,
            host: host, env: &env)
        do {
            _ = try await eval("(getpropertyvalue E \"Nope\")", host: host, env: &env)
            XCTFail("unknown property should throw")
        } catch let error as LispError {
            XCTAssertTrue("\(error)".contains("Nope"), "\(error)")
        }
        _ = host
    }

    func testTransIdentityAndEntity() async throws {
        let (host, _) = makeHost()
        var env = LispEnvironment()
        // WCS<->UCS is identity (single coordinate system).
        let ident = try await eval("(trans '(1 2 0) 1 0)", host: host, env: &env)
        XCTAssertEqual(ident.asPoint, [1, 2, 0])
        // Entity frame round-trip through a moved block insert... use a
        // moved LINE: world (10,0,0) with entity moved by (10,0,0).
        _ = try await eval(
            #"(setq E (entmake '((0 . "LINE") (10 0 0 0) (11 1 0 0))))"#,
            host: host, env: &env)
        _ = try await eval("(command \"_.MOVE\" E \"\" '(0 0 0) '(10 0 0))", host: host, env: &env)
        let local = try await eval("(trans '(10 0 0) 0 E)", host: host, env: &env)
        XCTAssertEqual(local.asPoint?[0] ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(local.asPoint?[1] ?? -1, 0, accuracy: 1e-9)
        let world = try await eval("(trans '(0 0 0) E 0)", host: host, env: &env)
        XCTAssertEqual(world.asPoint?[0] ?? -1, 10, accuracy: 1e-9)
        _ = host
    }

    func testXdroom() async throws {
        let (host, _) = makeHost()
        var env = LispEnvironment()
        _ = try await eval(
            #"(setq E (entmake '((0 . "LINE") (10 0 0 0) (11 1 0 0))))"#,
            host: host, env: &env)
        // No xdata written: full budget remains.
        let room = try await eval("(xdroom E)", host: host, env: &env)
        XCTAssertEqual(room, .int(16368))
        _ = host
    }

    func testTextbox() async throws {
        let (host, _) = makeHost()
        var env = LispEnvironment()
        _ = try await eval(
            #"(setq E (entmake '((0 . "TEXT") (10 5 5 0) (40 . 2) (1 . "abcd"))))"#,
            host: host, env: &env)
        let box = try await eval("(textbox (entget E))", host: host, env: &env)
        guard let corners = box.properList, corners.count == 2,
              let min = corners[0].asPoint, let max = corners[1].asPoint
        else {
            return XCTFail("textbox shape is ((min)(max)), got \(box)")
        }
        XCTAssertLessThan(min[0], max[0])
        XCTAssertLessThan(min[1], max[1])
        XCTAssertGreaterThanOrEqual(min[0], 5, "box starts at insertion x")
        // Bare assoc without -1 also works.
        let bare = try await eval(
            "(textbox '((0 . \"TEXT\") (10 0 0 0) (40 . 1) (1 . \"z\")))",
            host: host, env: &env)
        XCTAssertNotNil(bare.properList)
        // Non-text yields nil.
        let none = try await eval(
            "(textbox '((0 . \"LINE\") (10 0 0 0) (11 1 0 0)))",
            host: host, env: &env)
        XCTAssertEqual(none, .nilValue)
        _ = host
    }
}
