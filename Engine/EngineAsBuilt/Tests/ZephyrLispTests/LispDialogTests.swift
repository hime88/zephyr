import XCTest
@testable import ZephyrLisp

/// Wave-C file + color dialogs.
final class LispDialogTests: XCTestCase {

    func testGetfiledCancelAndPick() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let cancelled = try await evalString(
            "(getfiled \"Open\" \"/tmp\" \"lsp\" 8)", env: &env, host: host)
        XCTAssertEqual(cancelled, .nilValue)
        host.cannedFile = "/tmp/picked.lsp"
        let picked = try await evalString(
            "(getfiled \"Open\" \"/tmp\" \"lsp\" 8)", env: &env, host: host)
        XCTAssertEqual(picked, .string("/tmp/picked.lsp"))
        _ = host
    }

    func testColdlg() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let cancelled = try await evalString(
            "(acad_colordlg 1 nil)", env: &env, host: host)
        XCTAssertEqual(cancelled, .nilValue)
        host.cannedColor = 3
        let picked = try await evalString(
            "(acad_colordlg 1 T)", env: &env, host: host)
        XCTAssertEqual(picked, .int(3))
        _ = host
    }

    func testTruecolordlg() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let cancelled = try await evalString(
            "(acad_truecolordlg '(62 . 1))", env: &env, host: host)
        XCTAssertEqual(cancelled, .nilValue)
        host.cannedTrueColor = LispValue(list: [
            LispValue.cons(head: .int(420), tail: .int(255)),
        ])
        let picked = try await evalString(
            "(acad_truecolordlg '((62 . 1)))", env: &env, host: host)
        XCTAssertEqual(picked, host.cannedTrueColor)
        // Group codes written `62.` arrive as real 62.0; flat two-lists work.
        let realCoded = try await evalString(
            "(acad_truecolordlg '(62. 1))", env: &env, host: host)
        XCTAssertEqual(realCoded, host.cannedTrueColor)
        _ = host
    }

    func testTruecolorcliParsesAciAndRgb() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.lines = ["5"]
        let aci = try await evalString(
            "(acad_truecolorcli '((62 . 1)))", env: &env, host: host)
        XCTAssertEqual(
            aci.properList,
            [LispValue.cons(head: .int(62), tail: .int(5))])
        host.lines = ["255,0,0"]
        let rgb = try await evalString(
            "(acad_truecolorcli '((62 . 1)))", env: &env, host: host)
        XCTAssertEqual(
            rgb.properList,
            [LispValue.cons(head: .int(420), tail: .int(16711680))])
        host.lines = [nil]
        let kept = try await evalString(
            "(acad_truecolorcli '((62 . 4)))", env: &env, host: host)
        XCTAssertEqual(
            kept.properList,
            [LispValue.cons(head: .int(62), tail: .int(4))])
        host.lines = ["bogus", "9"]
        let retried = try await evalString(
            "(acad_truecolorcli '((62 . 1)))", env: &env, host: host)
        XCTAssertEqual(
            retried.properList,
            [LispValue.cons(head: .int(62), tail: .int(9))])
        XCTAssertTrue(host.output.contains("Invalid color"), host.output)
        _ = host
    }
}
