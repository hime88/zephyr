import XCTest
@testable import ZephyrLisp

/// Wave-B environment + filename + misc builtins.
final class LispEnvTests: XCTestCase {

    func testAllocExpandGc() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let old = try await evalString("(alloc 20000)", env: &env, host: host)
        XCTAssertEqual(old, .int(10_000))
        let again = try await evalString("(alloc 5)", env: &env, host: host)
        XCTAssertEqual(again, .int(20_000))
        let segments = try await evalString("(expand 3)", env: &env, host: host)
        XCTAssertEqual(segments, .int(1))
        try await assertEval("(gc)", .nilValue)
        _ = host
    }

    func testGetenvSetenvRoundTrip() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        _ = try await evalString(
            "(setenv \"ZEPHYR_LISP_TEST_VAR\" \"hello\")", env: &env, host: host)
        let back = try await evalString(
            "(getenv \"ZEPHYR_LISP_TEST_VAR\")", env: &env, host: host)
        XCTAssertEqual(back, .string("hello"))
        let missing = try await evalString(
            "(getenv \"ZEPHYR_LISP_NO_SUCH_VAR\")", env: &env, host: host)
        XCTAssertEqual(missing, .nilValue)
        _ = host
    }

    func testFindfile() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("lispfind_test.txt").path
        try "x".write(toFile: path, atomically: true, encoding: .utf8)
        let found = try await evalString("(findfile \"\(path)\")", env: &env, host: host)
        XCTAssertEqual(found, .string(path))
        let missing = try await evalString(
            "(findfile \"no-such-file-xyz-123.txt\")", env: &env, host: host)
        XCTAssertEqual(missing, .nilValue)
        let trusted = try await evalString(
            "(findtrustedfile \"\(path)\")", env: &env, host: host)
        XCTAssertEqual(trusted, .string(path))
        _ = host
    }

    func testVlFilenameSplitting() async throws {
        try await assertEval(
            "(vl-filename-base \"C:/temp/draw.lsp\")", .string("draw"))
        try await assertEval(
            "(vl-filename-directory \"C:/temp/draw.lsp\")", .string("C:/temp"))
        try await assertEval(
            "(vl-filename-extension \"draw.lsp\")", .string(".lsp"))
        try await assertEval("(vl-filename-extension \"noext\")", .string(""))
        try await assertEval("(vl-filename-base \"D:\\\\a\\\\b\")", .string("b"))
    }

    func testVlFilenameMktemp() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let made = try await evalString(
            "(vl-filename-mktemp \"test\" nil \".txt\")", env: &env, host: host)
        guard case let .string(path) = made else {
            return XCTFail("mktemp should return a string, got \(made)")
        }
        XCTAssertTrue(path.hasSuffix(".txt"), path)
        XCTAssertTrue(path.contains("test"), path)
        _ = host
    }

    func testVlPropagateAndVports() async throws {
        try await assertEval("(vl-propagate 'scale_factor)", .nilValue)
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let viewports = try await evalString("(vports)", env: &env, host: host)
        guard let outer = viewports.properList, outer.count == 1,
              let corners = outer[0].properList, corners.count == 2
        else {
            return XCTFail("vports shape wrong: \(viewports)")
        }
        XCTAssertEqual(corners[0].asPoint, [0, 0])
        XCTAssertEqual(corners[1].asPoint, [1, 1])
        _ = host
    }

    func testXdsize() async throws {
        // Two pairs: 1001/MY_APP + 1000/DATA.
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let size = try await evalString(
            "(xdsize '((1001 . \"MY_APP\") (1000 . \"DATA\")))",
            env: &env, host: host)
        // (8 + 6+1) + (8 + 4+1) = 28.
        XCTAssertEqual(size, .int(28))
        _ = host
    }
}
