import XCTest
@testable import ZephyrLisp

/// Wave-C defun-q lists + dbmod + doc ref/set + undefun + vl-exits +
/// registry descendents.
final class LispVlSessionTests: XCTestCase {

    private let testKey = "ZephyrLispSession/run-\(Int.random(in: 0...Int.max))"

    override func tearDown() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix("ZephyrLispRegistry.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testDefunQListRoundTrip() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        _ = try await evalString("(defun-q qadd (a b) (+ a b))", env: &env, host: host)
        let ref = try await evalString("(defun-q-list-ref 'qadd)", env: &env, host: host)
        guard let parts = ref.properList, parts.count == 2 else {
            return XCTFail("ref shape wrong: \(ref)")
        }
        XCTAssertEqual(parts[0].properList, [.symbol("A"), .symbol("B")])
        let defined = try await evalString(
            "(defun-q-list-set 'qcopy (defun-q-list-ref 'qadd))", env: &env, host: host)
        XCTAssertEqual(defined, .symbol("QCOPY"))
        let result = try await evalString("(qcopy 3 4)", env: &env, host: host)
        XCTAssertEqual(result, .int(7))
        _ = try await evalString("(defun plain (x) x)", env: &env, host: host)
        let plainRef = try await evalString(
            "(defun-q-list-ref 'plain)", env: &env, host: host)
        XCTAssertEqual(plainRef, .nilValue)
        _ = host
    }

    func testDbmodPushPop() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        env.dbmod = 5
        let pushed = try await evalString("(acad-push-dbmod)", env: &env, host: host)
        XCTAssertEqual(pushed, .t)
        XCTAssertEqual(env.dbmod, 0)
        let popped = try await evalString("(acad-pop-dbmod)", env: &env, host: host)
        XCTAssertEqual(popped, .t)
        XCTAssertEqual(env.dbmod, 5)
        let empty = try await evalString("(acad-pop-dbmod)", env: &env, host: host)
        XCTAssertEqual(empty, .nilValue)
        _ = host
    }

    func testDocRefSetAndUndefun() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let unset = try await evalString("(vl-doc-ref 'mode)", env: &env, host: host)
        XCTAssertEqual(unset, .nilValue)
        let set = try await evalString("(vl-doc-set 'mode 2)", env: &env, host: host)
        XCTAssertEqual(set, .int(2))
        let ref = try await evalString("(vl-doc-ref 'mode)", env: &env, host: host)
        XCTAssertEqual(ref, .int(2))
        _ = try await evalString("(defun tempfn (x) x)", env: &env, host: host)
        let removed = try await evalString(
            "(vl-acad-undefun 'tempfn)", env: &env, host: host)
        XCTAssertEqual(removed, .t)
        let again = try await evalString(
            "(vl-acad-undefun 'tempfn)", env: &env, host: host)
        XCTAssertEqual(again, .nilValue)
        _ = host
    }

    func testExitWithValueReturnsFromRun() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let result = try await evalString(
            "(progn (vl-exit-with-value 99) 1)", env: &env, host: host)
        XCTAssertEqual(result, .int(99))
        _ = host
    }

    func testExitWithErrorThrows() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        do {
            _ = try await evalString(
                "(vl-exit-with-error \"boom\")", env: &env, host: host)
            XCTFail("should throw")
        } catch let error as LispError {
            XCTAssertEqual(error.description, "boom")
        }
        _ = host
    }

    func testRegistryDescendents() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        _ = try await evalString(
            "(vl-registry-write \"\(testKey)\" \"top\" 1)", env: &env, host: host)
        _ = try await evalString(
            "(vl-registry-write \"\(testKey).child\" \"leaf\" 2)", env: &env, host: host)
        let subs = try await evalString(
            "(vl-registry-descendents \"\(testKey)\")", env: &env, host: host)
        XCTAssertEqual(subs.properList, [.string("child")])
        let values = try await evalString(
            "(vl-registry-descendents \"\(testKey)\" T)", env: &env, host: host)
        XCTAssertEqual(values.properList, [.string("top")])
        let none = try await evalString(
            "(vl-registry-descendents \"\(testKey).missing\")", env: &env, host: host)
        XCTAssertEqual(none, .nilValue)
        _ = host
    }
}
