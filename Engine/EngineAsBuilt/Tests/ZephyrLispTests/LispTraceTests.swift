import XCTest
@testable import ZephyrLisp

/// Wave-C trace/untrace + vlexit.
final class LispTraceTests: XCTestCase {

    func testTracePrintsEntryAndResult() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        _ = try await evalString(
            "(defun dbl (x) (* x 2))", env: &env, host: host)
        let traced = try await evalString("(trace 'dbl)", env: &env, host: host)
        XCTAssertEqual(traced, .symbol("DBL"))
        let result = try await evalString("(dbl 21)", env: &env, host: host)
        XCTAssertEqual(result, .int(42))
        XCTAssertTrue(host.output.contains("Entering DBL 21"), host.output)
        XCTAssertTrue(host.output.contains("Result of DBL: 42"), host.output)
        let untraced = try await evalString("(untrace 'dbl)", env: &env, host: host)
        XCTAssertEqual(untraced, .symbol("DBL"))
        host.output = ""
        _ = try await evalString("(dbl 1)", env: &env, host: host)
        XCTAssertEqual(host.output, "")
        _ = host
    }

    func testErrorModeStack() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let pushed = try await evalString(
            "(*push-error-using-stack*)", env: &env, host: host)
        XCTAssertEqual(pushed, .nilValue)
        _ = try await evalString(
            "(*push-error-using-command*)", env: &env, host: host)
        XCTAssertEqual(env.errorModeStack, ["STACK", "COMMAND"])
        let popped = try await evalString("(*pop-error-mode*)", env: &env, host: host)
        XCTAssertEqual(popped, .nilValue)
        XCTAssertEqual(env.errorModeStack, ["STACK"])
        _ = host
    }

    func testVlexitThrowsQuit() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        do {
            _ = try await evalString("(vlexit)", env: &env, host: host)
            XCTFail("vlexit should throw quitRequested")
        } catch let error as LispError {
            XCTAssertTrue(error.isFatalToCatchAll)
        }
        _ = host
    }
}
