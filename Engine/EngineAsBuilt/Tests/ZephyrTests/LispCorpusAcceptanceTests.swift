import XCTest
import ZephyrLisp
@testable import ZephyrCore

/// Step-3 seed-corpus acceptance: the three vendored scripts run headless
/// end-to-end through the real evaluator + CAD host, with broker-fed input
/// standing in for the user. These pin the corpus contract — real scripts,
/// unmodified, producing real drawing state.
@MainActor
final class LispCorpusAcceptanceTests: XCTestCase {

    private func makeHost() -> (LispCADHost, NSMutableString) {
        let doc = CADDocument()
        doc.addLayer(Layer(name: "0"))
        doc.activeLayerID = doc.findLayer(named: "0")?.handle
        let host = LispCADHost(
            document: doc,
            selection: CADSelectionManager(),
            processor: CADCommandProcessor())
        let captured = NSMutableString(capacity: 0)
        host.output = { captured.append($0) }
        return (host, captured)
    }

    private func corpusSource(_ name: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        url.appendPathComponent("Tools/lisp/corpus/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func eval(
        _ source: String, host: LispCADHost, env: inout LispEnvironment
    ) async throws -> LispValue {
        let forms = try LispReader().readAll(source)
        return try await LispEvaluator().run(forms, env: &env, host: host)
    }

    private func loadCorpus(
        _ name: String, host: LispCADHost, env: inout LispEnvironment
    ) async throws {
        _ = try await eval(try corpusSource(name), host: host, env: &env)
    }

    private func assoc(_ code: Int, _ list: LispValue) -> LispValue? {
        guard let items = list.properList else { return nil }
        for item in items {
            if case let .cons(head, tail) = item,
               case let .int(c) = head, c == code
            {
                return tail
            }
        }
        return nil
    }

    // MARK: - AddDoor: interior door, no number

    func testAddDoorIdr() async throws {
        let (host, captured) = makeHost()
        var env = LispEnvironment()
        try await loadCorpus("AddDoor.lsp", host: host, env: &env)
        // Hinge, latch, swing side (pre-queued; requests drain in order).
        host.broker.offer(.point([0, 0]))
        host.broker.offer(.point([36, 0]))
        host.broker.offer(.point([18, 10]))
        _ = try await eval("(c:IDR)", host: host, env: &env)
        XCTAssertEqual(host.document.allEntities.count, 2)
        let types = host.document.allEntities.map {
            LispEntityAdapter.dxfTypeName(entity: $0, document: host.document)
        }.sorted()
        XCTAssertEqual(types, ["ARC", "LWPOLYLINE"])
        // The door panel is a closed 4-vertex polyline.
        let panel = try XCTUnwrap(host.document.allEntities.first {
            LispEntityAdapter.dxfTypeName(entity: $0, document: host.document) == "LWPOLYLINE"
        })
        let panelData = LispEntityAdapter.entGetAssoc(entity: panel, document: host.document)
        XCTAssertEqual(assoc(90, panelData), .int(4))
        XCTAssertEqual(assoc(70, panelData), .int(1))
        // Environment restored; success message printed.
        XCTAssertTrue(
            host.document.findLayer(named: "0")?.handle == host.document.activeLayerID)
        let osmode = try await eval(#"(getvar "OSMODE")"#, host: host, env: &env)
        XCTAssertEqual(osmode, .int(0))
        let cmdecho = try await eval(#"(getvar "CMDECHO")"#, host: host, env: &env)
        XCTAssertEqual(cmdecho, .int(1))
        XCTAssertTrue(
            (captured as String).contains("Quick Door generated."),
            "output was: \(captured)")
    }

    // MARK: - AddDoor: exterior door with number (entsel + COPY + ROTATE)

    func testAddDoorIdn() async throws {
        let (host, captured) = makeHost()
        var env = LispEnvironment()
        let seed = try await eval(
            #"(entmake '((0 . "TEXT") (10 100 100 0) (40 . 2.5) (1 . "101")))"#,
            host: host, env: &env)
        guard case let .entityName(textHandle) = seed else {
            return XCTFail("seed TEXT failed: \(seed)")
        }
        try await loadCorpus("AddDoor.lsp", host: host, env: &env)
        host.broker.offer(.entity(handle: textHandle, point: [100, 100]))
        host.broker.offer(.point([0, 0]))
        host.broker.offer(.point([36, 0]))
        host.broker.offer(.point([18, -10]))
        _ = try await eval("(c:IDN)", host: host, env: &env)
        // Seed text + door panel + swing arc + copied number text.
        XCTAssertEqual(host.document.allEntities.count, 4)
        let texts = host.document.allEntities.filter {
            LispEntityAdapter.dxfTypeName(entity: $0, document: host.document) == "TEXT"
        }
        XCTAssertEqual(texts.count, 2)
        // The copy moved off the seed position and rotated.
        let moved = texts.filter {
            $0.handle.uuidString != textHandle
        }
        XCTAssertEqual(moved.count, 1)
        let copyData = LispEntityAdapter.entGetAssoc(
            entity: try XCTUnwrap(moved.first), document: host.document)
        XCTAssertNotEqual(assoc(10, copyData)?.asPoint, [100, 100, 0])
        XCTAssertNotEqual(assoc(50, copyData)?.asDouble ?? 0, 0)
        XCTAssertTrue(
            (captured as String).contains("Quick Door with Number generated."),
            "output was: \(captured)")
    }

    // MARK: - cleanup: select-by-example speckle cleaner (default path)

    func testCleanupDefaultPath() async throws {
        let (host, captured) = makeHost()
        var env = LispEnvironment()
        // Three small red speckles, one big red keeper, two small blue.
        _ = try await eval(
            #"(entmake '((0 . "LINE") (10 0 0 0) (11 1 0 0) (62 . 1)))"#,
            host: host, env: &env)
        _ = try await eval(
            #"(entmake '((0 . "LINE") (10 5 5 0) (11 6 5 0) (62 . 1)))"#,
            host: host, env: &env)
        _ = try await eval(
            #"(entmake '((0 . "LINE") (10 10 0 0) (11 11 0 0) (62 . 1)))"#,
            host: host, env: &env)
        _ = try await eval(
            #"(entmake '((0 . "LINE") (10 20 20 0) (11 70 20 0) (62 . 1)))"#,
            host: host, env: &env)
        _ = try await eval(
            #"(entmake '((0 . "LINE") (10 2 2 0) (11 3 2 0) (62 . 5)))"#,
            host: host, env: &env)
        _ = try await eval(
            #"(entmake '((0 . "LINE") (10 7 7 0) (11 8 7 0) (62 . 5)))"#,
            host: host, env: &env)
        // Pre-select two small red examples (pickfirst = grips showing).
        let smallRed = host.document.allEntities
            .filter { LispEntityAdapter.entityACI(entity: $0) == 1 }
            .filter {
                guard let box = $0.worldBoundingBox else { return false }
                return (box.max.x - box.min.x) < 5
            }
            .map(\.handle)
        XCTAssertEqual(smallRed.count, 3)
        host.selection.selectedHandles = Set(smallRed.prefix(2))
        try await loadCorpus("cleanup.lsp", host: host, env: &env)
        host.broker.offer(.point([-10, -10]))
        host.broker.offer(.point([80, 30]))
        _ = try await eval("(c:CleanSpeckles)", host: host, env: &env)
        // All three small red speckles highlighted; big red + blues spared.
        XCTAssertEqual(host.selection.selectedHandles, Set(smallRed))
        let output = captured as String
        XCTAssertTrue(output.contains("Learned:"), "output was: \(output)")
        XCTAssertTrue(output.contains("3 speckles matching"), "output was: \(output)")
    }

    // MARK: - selectByColor: learn colors, window, highlight matches

    func testSelectByColor() async throws {
        let (host, captured) = makeHost()
        var env = LispEnvironment()
        _ = try await eval(
            #"(entmake '((0 . "LINE") (10 0 0 0) (11 1 0 0) (62 . 1)))"#,
            host: host, env: &env)
        _ = try await eval(
            #"(entmake '((0 . "LINE") (10 5 5 0) (11 6 5 0) (62 . 1)))"#,
            host: host, env: &env)
        _ = try await eval(
            #"(entmake '((0 . "LINE") (10 2 2 0) (11 3 2 0) (62 . 5)))"#,
            host: host, env: &env)
        _ = try await eval(
            #"(entmake '((0 . "CIRCLE") (10 500 500 0) (40 . 10) (62 . 1)))"#,
            host: host, env: &env)
        let redInWindow = Set(host.document.allEntities
            .filter { LispEntityAdapter.entityACI(entity: $0) == 1 }
            .filter { ($0.worldBoundingBox?.min.x ?? 999) < 100 }
            .map(\.handle))
        XCTAssertEqual(redInWindow.count, 2)
        try await loadCorpus("selectByColor.lsp", host: host, env: &env)
        // Pick the two red examples, Enter, then window corners.
        for handle in redInWindow {
            host.broker.offer(.entity(handle: handle.uuidString, point: [0, 0]))
        }
        host.broker.offer(.entity(handle: nil, point: nil))
        host.broker.offer(.point([-10, -10]))
        host.broker.offer(.point([50, 50]))
        _ = try await eval("(c:SelectByColors)", host: host, env: &env)
        XCTAssertEqual(host.selection.selectedHandles, redInWindow)
        XCTAssertTrue(
            (captured as String).contains("Success: Selected 2 objects"),
            "output was: \(captured)")
    }

    // MARK: - UUID-handle symbols (cleanup cluster path relies on read/set)

    func testUuidHandleSymbolsRoundTrip() async throws {
        let (host, _) = makeHost()
        var env = LispEnvironment()
        let made = try await eval(
            #"(entmake '((0 . "LINE") (10 0 0 0) (11 1 0 0)))"#,
            host: host, env: &env)
        guard case let .entityName(handle) = made else {
            return XCTFail("entmake failed: \(made)")
        }
        // (read (strcat "SPK_H_" ah)) interns a symbol; set/boundp/eval agree.
        _ = try await eval(
            #"(setq SYM (read (strcat "SPK_H_" "\#(handle)")))"#,
            host: host, env: &env)
        _ = try await eval("(set SYM 42)", host: host, env: &env)
        let bound = try await eval("(boundp (eval 'SYM))", host: host, env: &env)
        XCTAssertEqual(bound, .t)
        let value = try await eval("(eval SYM)", host: host, env: &env)
        XCTAssertEqual(value, .int(42))
        let viaHandle = try await eval(
            #"(eval (read (strcat "SPK_H_" (cdr (assoc 5 (entget (handent "\#(handle)")))))))"#,
            host: host, env: &env)
        XCTAssertEqual(viaHandle, .int(42))
    }

    // MARK: - entget reports world coordinates after transforms

    func testEntgetWorldAfterRotate() async throws {
        let (host, _) = makeHost()
        var env = LispEnvironment()
        _ = try await eval(
            #"(setq E (entmake '((0 . "LINE") (10 0 0 0) (11 4 0 0))))"#,
            host: host, env: &env)
        _ = try await eval(
            #"(command "_.ROTATE" E "" '(0 0 0) 90.0)"#, host: host, env: &env)
        let fetched = try await eval("(entget E)", host: host, env: &env)
        let start = assoc(10, fetched)?.asPoint ?? []
        let end = assoc(11, fetched)?.asPoint ?? []
        XCTAssertEqual(start.count, 3)
        XCTAssertEqual(end.count, 3)
        XCTAssertEqual(start[0], 0, accuracy: 1e-9)
        XCTAssertEqual(start[1], 0, accuracy: 1e-9)
        XCTAssertEqual(end[0], 0, accuracy: 1e-9)
        XCTAssertEqual(end[1], 4, accuracy: 1e-9)
    }
}
