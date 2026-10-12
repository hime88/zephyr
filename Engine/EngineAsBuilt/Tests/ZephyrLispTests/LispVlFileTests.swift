import XCTest
@testable import ZephyrLisp

/// Wave-C vl-file-* + mkdir + directory-files + blackboard.
final class LispVlFileTests: XCTestCase {

    private func sandbox() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lispvlfile_\(Int.random(in: 0...Int.max))").path
        try! FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    func testFileCopyDeleteRenameSize() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let dir = sandbox()
        let src = (dir as NSString).appendingPathComponent("a.txt")
        try "hello".write(toFile: src, atomically: true, encoding: .utf8)
        let dst = (dir as NSString).appendingPathComponent("b.txt")
        let copied = try await evalString(
            "(vl-file-copy \"\(src)\" \"\(dst)\")", env: &env, host: host)
        XCTAssertEqual(copied, .int(5))
        let size = try await evalString("(vl-file-size \"\(dst)\")", env: &env, host: host)
        XCTAssertEqual(size, .int(5))
        let renamed = (dir as NSString).appendingPathComponent("c.txt")
        let renameResult = try await evalString(
            "(vl-file-rename \"\(dst)\" \"\(renamed)\")", env: &env, host: host)
        XCTAssertEqual(renameResult, .t)
        let deleted = try await evalString(
            "(vl-file-delete \"\(renamed)\")", env: &env, host: host)
        XCTAssertEqual(deleted, .t)
        let missing = try await evalString(
            "(vl-file-delete \"\(renamed)\")", env: &env, host: host)
        XCTAssertEqual(missing, .nilValue)
        let noSize = try await evalString(
            "(vl-file-size \"\(renamed)\")", env: &env, host: host)
        XCTAssertEqual(noSize, .nilValue)
        _ = host
    }

    func testFileCopyAppend() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let dir = sandbox()
        let src = (dir as NSString).appendingPathComponent("a.txt")
        try "ab".write(toFile: src, atomically: true, encoding: .utf8)
        let dst = (dir as NSString).appendingPathComponent("b.txt")
        try "XY".write(toFile: dst, atomically: true, encoding: .utf8)
        _ = try await evalString(
            "(vl-file-copy \"\(src)\" \"\(dst)\" T)", env: &env, host: host)
        let back = try String(contentsOfFile: dst, encoding: .utf8)
        XCTAssertEqual(back, "XYab")
        _ = host
    }

    func testDirectoryPAndMkdir() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let dir = sandbox()
        let isDir = try await evalString(
            "(vl-file-directory-p \"\(dir)\")", env: &env, host: host)
        XCTAssertEqual(isDir, .t)
        let file = (dir as NSString).appendingPathComponent("f.txt")
        try "x".write(toFile: file, atomically: true, encoding: .utf8)
        let notDir = try await evalString(
            "(vl-file-directory-p \"\(file)\")", env: &env, host: host)
        XCTAssertEqual(notDir, .nilValue)
        let sub = (dir as NSString).appendingPathComponent("sub/deep")
        let made = try await evalString("(vl-mkdir \"\(sub)\")", env: &env, host: host)
        XCTAssertEqual(made, .t)
        var isDir2: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: sub, isDirectory: &isDir2))
        _ = host
    }

    func testDirectoryFilesPattern() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let dir = sandbox()
        try "x".write(
            toFile: (dir as NSString).appendingPathComponent("a.lsp"),
            atomically: true, encoding: .utf8)
        try "x".write(
            toFile: (dir as NSString).appendingPathComponent("b.txt"),
            atomically: true, encoding: .utf8)
        let listed = try await evalString(
            "(vl-directory-files \"\(dir)\" \"*.lsp\")", env: &env, host: host)
        XCTAssertEqual(listed.properList, [.string("a.lsp")])
        let none = try await evalString(
            "(vl-directory-files \"\(dir)\" \"*.zzz\")", env: &env, host: host)
        XCTAssertEqual(none, .nilValue)
        _ = host
    }

    func testFileSystimeShape() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let dir = sandbox()
        let file = (dir as NSString).appendingPathComponent("t.txt")
        try "x".write(toFile: file, atomically: true, encoding: .utf8)
        let stamp = try await evalString("(vl-file-systime \"\(file)\")", env: &env, host: host)
        guard let items = stamp.properList, items.count == 8 else {
            return XCTFail("systime shape wrong: \(stamp)")
        }
        if case let .int(year) = items[0] {
            XCTAssertGreaterThan(year, 2020)
        } else {
            XCTFail("year is an int: \(stamp)")
        }
        let missing = try await evalString(
            "(vl-file-systime \"\(dir)/nope.txt\")", env: &env, host: host)
        XCTAssertEqual(missing, .nilValue)
        _ = host
    }

    func testBlackboard() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let unset = try await evalString("(vl-bb-ref 'factor)", env: &env, host: host)
        XCTAssertEqual(unset, .nilValue)
        let set = try await evalString("(vl-bb-set 'factor 1.5)", env: &env, host: host)
        XCTAssertEqual(set, .real(1.5))
        let ref = try await evalString("(vl-bb-ref 'factor)", env: &env, host: host)
        XCTAssertEqual(ref, .real(1.5))
        _ = host
    }
}
