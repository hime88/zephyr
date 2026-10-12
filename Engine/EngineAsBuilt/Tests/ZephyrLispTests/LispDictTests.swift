import XCTest
@testable import ZephyrLisp

/// Wave-B dictionaries + appids.
final class LispDictTests: XCTestCase {

    func testDictRoundTrip() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let named = try await evalString("(namedobjdict)", env: &env, host: host)
        XCTAssertEqual(named, .entityName("NAMEDOBJDICT"))
        let kind = try await evalString("(type (namedobjdict))", env: &env, host: host)
        XCTAssertEqual(kind, .symbol("ENAME"))
        _ = try await evalString(
            "(dictadd (namedobjdict) \"MY_KEY\" \"MY_VALUE\")", env: &env, host: host)
        let found = try await evalString(
            "(dictsearch (namedobjdict) \"MY_KEY\")", env: &env, host: host)
        guard let items = found.properList, items.count == 2 else {
            return XCTFail("dictsearch shape wrong: \(found)")
        }
        // Iteration: rewind + two entries + exhaustion.
        _ = try await evalString(
            "(dictadd (namedobjdict) \"SECOND\" 42)", env: &env, host: host)
        let first = try await evalString(
            "(dictnext (namedobjdict) T)", env: &env, host: host)
        guard case let .cons(head, _) = first,
              case let .string(key) = head
        else {
            return XCTFail("dictnext shape wrong: \(first)")
        }
        XCTAssertEqual(key, "MY_KEY")
        let second = try await evalString("(dictnext (namedobjdict))", env: &env, host: host)
        guard case let .cons(head2, tail2) = second else {
            return XCTFail("dictnext shape wrong: \(second)")
        }
        XCTAssertEqual(head2, .string("SECOND"))
        XCTAssertEqual(tail2, .int(42))
        let done = try await evalString("(dictnext (namedobjdict))", env: &env, host: host)
        XCTAssertEqual(done, .nilValue)
    }

    func testDictRemoveAndRename() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        _ = try await evalString(
            "(dictadd \"MYDICT\" \"A\" 1)", env: &env, host: host)
        let renamed = try await evalString(
            "(dictrename \"MYDICT\" \"A\" \"B\")", env: &env, host: host)
        XCTAssertEqual(renamed, .int(1))
        let missing = try await evalString(
            "(dictsearch \"MYDICT\" \"A\")", env: &env, host: host)
        XCTAssertEqual(missing, .nilValue)
        let removed = try await evalString(
            "(dictremove \"MYDICT\" \"B\")", env: &env, host: host)
        XCTAssertEqual(removed, .int(1))
        let gone = try await evalString(
            "(dictremove \"MYDICT\" \"B\")", env: &env, host: host)
        XCTAssertEqual(gone, .nilValue)
    }

    func testDictsearchSetnext() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        _ = try await evalString("(dictadd \"D\" \"A\" 1)", env: &env, host: host)
        _ = try await evalString("(dictadd \"D\" \"B\" 2)", env: &env, host: host)
        _ = try await evalString("(dictsearch \"D\" \"A\" T)", env: &env, host: host)
        let next = try await evalString("(dictnext \"D\")", env: &env, host: host)
        guard case let .cons(head, _) = next else {
            return XCTFail("expected entry, got \(next)")
        }
        XCTAssertEqual(head, .string("B"))
    }

    func testRegapp() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let ok = try await evalString("(regapp \"MY_APP\")", env: &env, host: host)
        XCTAssertEqual(ok, .string("MY_APP"))
        XCTAssertTrue(env.appIDs.contains("MY_APP"))
        let bad = try await evalString("(regapp \"has space\")", env: &env, host: host)
        XCTAssertEqual(bad, .nilValue)
        let empty = try await evalString("(regapp \"\")", env: &env, host: host)
        XCTAssertEqual(empty, .nilValue)
    }
}
