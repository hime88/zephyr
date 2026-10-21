import XCTest
import ZephyrLisp
@testable import ZephyrCore

/// Examples acceptance: every script in Tools/lisp/examples runs headless
/// end-to-end through the real evaluator + CAD host. These pin the
/// documented examples — if a script stops working, the test fails.
@MainActor
final class LispExamplesTests: XCTestCase {

    private func makeHost() -> (LispCADHost, CADDocument) {
        let doc = CADDocument()
        doc.addLayer(Layer(name: "0"))
        doc.activeLayerID = doc.findLayer(named: "0")?.handle
        let host = LispCADHost(
            document: doc,
            selection: CADSelectionManager(),
            processor: CADCommandProcessor())
        host.output = { _ in }
        return (host, doc)
    }

    private func exampleSource(_ name: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        url.appendPathComponent("Tools/lisp/examples/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func eval(
        _ source: String, host: LispCADHost, env: inout LispEnvironment
    ) async throws -> LispValue {
        let forms = try LispReader().readAll(source)
        return try await LispEvaluator().run(forms, env: &env, host: host)
    }

    private func loadExample(
        _ name: String, host: LispCADHost, env: inout LispEnvironment
    ) async throws {
        _ = try await eval(try exampleSource(name), host: host, env: &env)
    }

    private func typeNames(_ doc: CADDocument) -> [String] {
        doc.allEntities.map {
            LispEntityAdapter.dxfTypeName(entity: $0, document: doc)
        }.sorted()
    }

    // MARK: - shapes.lsp

    func testShapes() async throws {
        let (host, doc) = makeHost()
        var env = LispEnvironment()
        try await loadExample("shapes.lsp", host: host, env: &env)
        _ = try await eval("(c:SHAPES)", host: host, env: &env)
        XCTAssertEqual(
            typeNames(doc),
            ["ARC", "CIRCLE", "LINE", "LWPOLYLINE", "POINT", "TEXT"])
    }

    /// Session contract the app relies on: a LOAD run defines `c:NAME` in
    /// the shared session env, and a later bare-name run calls it there.
    /// The processor looks the name up as an uppercase `C:`-prefixed key.
    func testLoadThenCallAcrossRuns() async throws {
        let (host, doc) = makeHost()
        var session = LispEnvironment()
        // Run 1 (LOAD): defines the function, draws nothing.
        try await loadExample("shapes.lsp", host: host, env: &session)
        XCTAssertTrue(doc.allEntities.isEmpty)
        XCTAssertNotNil(session.functions["C:SHAPES"])
        // Run 2 (bare SHAPES): dispatches into the same session.
        _ = try await eval("(C:SHAPES)", host: host, env: &session)
        XCTAssertEqual(doc.allEntities.count, 6)
        // Globals persist across runs too (separate EVAL-equivalent runs).
        _ = try await eval("(setq xtotal 40)", host: host, env: &session)
        let again = try await eval("(+ xtotal 2)", host: host, env: &session)
        XCTAssertEqual(again, .int(42))
    }

    // MARK: - selection.lsp

    func testSelCount() async throws {
        let (host, _) = makeHost()
        var env = LispEnvironment()
        try await loadExample("selection.lsp", host: host, env: &env)
        let result = try await eval("(c:SELCOUNT)", host: host, env: &env)
        guard let pairs = result.properList else {
            XCTFail("SELCOUNT must return a list, got \(result)")
            return
        }
        var counts: [String: Int] = [:]
        for pair in pairs {
            if case let .cons(head, tail) = pair,
               case let .string(key) = head,
               case let .int(n) = tail
            {
                counts[key] = n
            }
        }
        XCTAssertEqual(counts, ["all": 5, "circles": 2, "red": 2])
    }

    // MARK: - modify.lsp

    func testRedCircles() async throws {
        let (host, doc) = makeHost()
        var env = LispEnvironment()
        try await loadExample("modify.lsp", host: host, env: &env)
        _ = try await eval(
            "(entmake '((0 . \"CIRCLE\") (10 0 0 0) (40 . 1.0)))",
            host: host, env: &env)
        _ = try await eval(
            "(entmake '((0 . \"CIRCLE\") (10 5 0 0) (40 . 1.0) (62 . 3)))",
            host: host, env: &env)
        _ = try await eval(
            "(entmake '((0 . \"LINE\") (10 0 0 0) (11 1 0 0)))",
            host: host, env: &env)
        _ = try await eval("(c:REDCIRCLES)", host: host, env: &env)
        for entity in doc.allEntities {
            let dxf = LispEntityAdapter.entGetAssoc(
                entity: entity, document: doc)
            let color = colorGroup(dxf)
            if LispEntityAdapter.dxfTypeName(entity: entity, document: doc) == "CIRCLE" {
                XCTAssertEqual(color, 1)
            } else {
                // Untouched BYLAYER line still reports 256, like AutoCAD.
                XCTAssertEqual(color, 256)
            }
        }
    }

    /// Value of group 62 in an entget-style assoc list, if present.
    private func colorGroup(_ dxf: LispValue) -> Int? {
        guard let items = dxf.properList else { return nil }
        for item in items {
            if case let .cons(head, tail) = item,
               case let .int(code) = head, code == 62,
               case let .int(aci) = tail
            {
                return aci
            }
        }
        return nil
    }

    // MARK: - input.lsp

    func testInputDemo() async throws {
        let (host, doc) = makeHost()
        var env = LispEnvironment()
        try await loadExample("input.lsp", host: host, env: &env)
        host.broker.offer(.point([0, 0]))
        host.broker.offer(.point([10, 0]))
        host.broker.offer(.line("wall-a"))
        host.broker.offer(.line("3"))
        _ = try await eval("(c:INPUTDEMO)", host: host, env: &env)
        XCTAssertEqual(
            typeNames(doc), ["CIRCLE", "CIRCLE", "CIRCLE", "LINE", "TEXT"])
    }

    func testZephyrLogo() async throws {
        let (host, doc) = makeHost()
        var env = LispEnvironment()
        let path = "C:/Users/xingo/Downloads/gemini-code-1792561429649.lsp"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(fileURLWithPath: path)
        let source = try String(contentsOf: url, encoding: .utf8)
        _ = try await eval(source, host: host, env: &env)
        // User pressed Enter for default Dark theme (empty line)
        host.broker.offer(.line(""))
        // Insertion point at (0, 0, 0)
        host.broker.offer(.point([0, 0, 0]))
        _ = try await eval("(c:ZEPHYRLOGO)", host: host, env: &env)
        XCTAssertGreaterThan(doc.allEntities.count, 5)
    }
}
