import XCTest
@testable import ZephyrLisp

/// Wave-C vl-registry-* (UserDefaults) + vl-acad-defun + vl-doc-* +
/// vla undo marks.
final class LispVlRegistryTests: XCTestCase {

    private let testKey = "ZephyrLispTest/run-\(Int.random(in: 0...Int.max))"

    override func tearDown() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix("ZephyrLispRegistry.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testRegistryRoundTrip() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let written = try await evalString(
            "(vl-registry-write \"\(testKey)\" \"scale\" 2.5)", env: &env, host: host)
        XCTAssertEqual(written, .real(2.5))
        let read = try await evalString(
            "(vl-registry-read \"\(testKey)\" \"scale\")", env: &env, host: host)
        XCTAssertEqual(read, .real(2.5))
        let missing = try await evalString(
            "(vl-registry-read \"\(testKey)\" \"other\")", env: &env, host: host)
        XCTAssertEqual(missing, .nilValue)
        let deleted = try await evalString(
            "(vl-registry-delete \"\(testKey)\" \"scale\")", env: &env, host: host)
        XCTAssertEqual(deleted, .t)
        let gone = try await evalString(
            "(vl-registry-read \"\(testKey)\" \"scale\")", env: &env, host: host)
        XCTAssertEqual(gone, .nilValue)
        let deleteMissing = try await evalString(
            "(vl-registry-delete \"\(testKey)\" \"scale\")", env: &env, host: host)
        XCTAssertEqual(deleteMissing, .nilValue)
        _ = host
    }

    func testRegistryKeyLevelValue() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        _ = try await evalString(
            "(vl-registry-write \"\(testKey)\" 7)", env: &env, host: host)
        let read = try await evalString(
            "(vl-registry-read \"\(testKey)\")", env: &env, host: host)
        XCTAssertEqual(read, .int(7))
        _ = host
    }

    func testAcadDefunAndDocScope() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let defined = try await evalString(
            "(vl-acad-defun 'shared-fn 42)", env: &env, host: host)
        XCTAssertEqual(defined, .symbol("SHARED-FN"))
        XCTAssertEqual(env.globals["SHARED-FN"], .int(42))
        let exported = try await evalString(
            "(vl-doc-export 'shared-fn)", env: &env, host: host)
        XCTAssertEqual(exported, .symbol("SHARED-FN"))
        env.globals["SHARED-FN"] = nil
        let imported = try await evalString(
            "(vl-doc-import 'shared-fn)", env: &env, host: host)
        XCTAssertEqual(imported, .symbol("SHARED-FN"))
        XCTAssertEqual(env.globals["SHARED-FN"], .int(42))
        _ = host
    }

    func testUndoMarksAreNoopsOnScriptedHost() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let started = try await evalString(
            "(vla-startundomark)", env: &env, host: host)
        XCTAssertEqual(started, .nilValue)
        let ended = try await evalString("(vla-endundomark)", env: &env, host: host)
        XCTAssertEqual(ended, .nilValue)
        _ = host
    }
}
