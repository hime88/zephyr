import XCTest
@testable import ZephyrLisp

/// Wave-B file IO: open/close/read-char/read-line/write-char/write-line.
final class LispFileTests: XCTestCase {

    private func tempPath(_ name: String) -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lispfile_\(name)").path
    }

    func testWriteThenReadRoundTrip() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let path = tempPath("roundtrip.txt")
        try? FileManager.default.removeItem(atPath: path)
        let opened = try await evalString(
            "(setq F (open \"\(path)\" \"w\"))", env: &env, host: host)
        guard case .int = opened else {
            return XCTFail("open should return a descriptor, got \(opened)")
        }
        _ = try await evalString("(write-line \"hello\" F)", env: &env, host: host)
        _ = try await evalString("(write-line \"world\" F)", env: &env, host: host)
        let closed = try await evalString("(close F)", env: &env, host: host)
        XCTAssertEqual(closed, .nilValue)
        _ = try await evalString("(setq G (open \"\(path)\" \"r\"))", env: &env, host: host)
        let line1 = try await evalString("(read-line G)", env: &env, host: host)
        XCTAssertEqual(line1, .string("hello"))
        let line2 = try await evalString("(read-line G)", env: &env, host: host)
        XCTAssertEqual(line2, .string("world"))
        let eof = try await evalString("(read-line G)", env: &env, host: host)
        XCTAssertEqual(eof, .nilValue)
        _ = try await evalString("(close G)", env: &env, host: host)
    }

    func testReadCharCodes() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let path = tempPath("chars.txt")
        try "AB".write(toFile: path, atomically: true, encoding: .utf8)
        _ = try await evalString("(setq F (open \"\(path)\" \"r\"))", env: &env, host: host)
        let a = try await evalString("(read-char F)", env: &env, host: host)
        XCTAssertEqual(a, .int(65))
        let b = try await evalString("(read-char F)", env: &env, host: host)
        XCTAssertEqual(b, .int(66))
        let eof = try await evalString("(read-char F)", env: &env, host: host)
        XCTAssertEqual(eof, .nilValue)
    }

    func testWriteCharEchoesCode() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let path = tempPath("chars2.txt")
        try? FileManager.default.removeItem(atPath: path)
        _ = try await evalString("(setq F (open \"\(path)\" \"w\"))", env: &env, host: host)
        let echoed = try await evalString("(write-char 65 F)", env: &env, host: host)
        XCTAssertEqual(echoed, .int(65))
        _ = try await evalString("(close F)", env: &env, host: host)
        let back = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertEqual(back, "A")
    }

    func testOpenFailuresReturnNil() async throws {
        try await assertEval(
            "(open \"/nonexistent-dir-xyz/file.txt\" \"r\")", .nilValue)
        try await assertEval(
            "(open \"/tmp/x\" \"bogus-mode\")", .nilValue)
    }

    func testCloseIsLenient() async throws {
        // Closing nil / unknown ids returns nil rather than throwing.
        try await assertEval("(close nil)", .nilValue)
        try await assertEval("(close 999)", .nilValue)
    }

    func testBadDescriptorThrows() async throws {
        await assertEvalThrows(
            "(read-line 999)",
            .hostError("read-line: invalid file descriptor"))
        await assertEvalThrows(
            "(write-line \"x\" 999)",
            .hostError("write-line: invalid file descriptor"))
    }

    func testModeMismatchThrows() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let path = tempPath("mode.txt")
        try "data".write(toFile: path, atomically: true, encoding: .utf8)
        _ = try await evalString("(setq F (open \"\(path)\" \"r\"))", env: &env, host: host)
        do {
            _ = try await evalString("(write-line \"x\" F)", env: &env, host: host)
            XCTFail("writing a read-mode file should throw")
        } catch let error as LispError {
            XCTAssertEqual(
                error, .hostError("write-line: file is not open for writing"))
        }
    }

    func testConsoleReadsUseHostLines() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.lines = ["typed", ""]
        let line = try await evalString("(read-line)", env: &env, host: host)
        XCTAssertEqual(line, .string("typed"))
        let char = try await evalString("(read-char)", env: &env, host: host)
        // Empty line: read-char yields nil.
        _ = char
        XCTAssertEqual(char, .nilValue)
    }

    func testConsoleWritesEcho() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let echoed = try await evalString("(write-line \"hi\")", env: &env, host: host)
        XCTAssertEqual(echoed, .string("hi"))
        XCTAssertEqual(host.output, "hi\n")
        let code = try await evalString("(write-char 33)", env: &env, host: host)
        XCTAssertEqual(code, .int(33))
        XCTAssertEqual(host.output, "hi\n!")
    }
}
