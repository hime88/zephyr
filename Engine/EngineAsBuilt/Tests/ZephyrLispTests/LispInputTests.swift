import XCTest
@testable import ZephyrLisp

final class LispInputTests: XCTestCase {
    func testGetrealParsesAndRepPrompts() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.lines = ["abc", "2.5"]
        let result = try await evalString("(getreal)", env: &env, host: host)
        XCTAssertEqual(result, .real(2.5))
        XCTAssertTrue(host.output.contains("Requires a numeric value."))
    }

    func testGetrealEmptyAndInitgetBits() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.lines = [nil]
        let empty = try await evalString("(getreal)", env: &env, host: host)
        XCTAssertEqual(empty, .nilValue)

        // Bit 1 (no null): empty re-prompts; bit 4 rejects negatives.
        host.lines = [nil, "-3", "4"]
        let valued = try await evalString(
            "(progn (initget 5) (getreal))", env: &env, host: host)
        XCTAssertEqual(valued, .real(4))
        // initget is consumed by the call.
        XCTAssertTrue(env.pendingInitget.isEmpty)
    }

    func testGetintStrictness() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.lines = ["3.5", "7"]
        let result = try await evalString("(getint)", env: &env, host: host)
        XCTAssertEqual(result, .int(7))
    }

    func testGetstringSpacing() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.lines = ["a b", "a b"]
        let stopped = try await evalString("(getstring)", env: &env, host: host)
        XCTAssertEqual(stopped, .string("a"))
        let spaced = try await evalString("(getstring t)", env: &env, host: host)
        XCTAssertEqual(spaced, .string("a b"))
        host.lines = [nil]
        let empty = try await evalString("(getstring)", env: &env, host: host)
        XCTAssertEqual(empty, .string(""))
    }

    func testGetkwordMatching() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.lines = ["y"]
        let matched = try await evalString(
            "(progn (initget \"Yes No\") (getkword))", env: &env, host: host)
        XCTAssertEqual(matched, .string("Yes"))

        host.lines = ["bogus", "n"]
        let reprompted = try await evalString(
            "(progn (initget \"Yes No\") (getkword))", env: &env, host: host)
        XCTAssertEqual(reprompted, .string("No"))
        XCTAssertTrue(host.output.contains("Invalid keyword"))

        // No keywords: any text passes through as typed.
        host.lines = ["whatever"]
        let passthrough = try await evalString("(getkword)", env: &env, host: host)
        XCTAssertEqual(passthrough, .string("whatever"))
    }

    func testGetpoint() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.points = [[1.0, 2.0]]
        let point = try await evalString("(getpoint)", env: &env, host: host)
        XCTAssertEqual(point, LispValue(list: [.real(1), .real(2)]))
        host.points = [nil]
        let empty = try await evalString("(getpoint '(0 0))", env: &env, host: host)
        XCTAssertEqual(empty, .nilValue)
    }

    func testGetpointCancel() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.cancelNext = true
        do {
            _ = try await evalString("(getpoint)", env: &env, host: host)
            XCTFail("expected cancel")
        } catch let error as LispError {
            XCTAssertEqual(error, .userCancel)
        }
    }

    func testGetdistTwoPicksAndTypedNumber() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.pointNumbers = [.point([0.0, 0.0]), .point([3.0, 4.0])]
        let picked = try await evalString("(getdist)", env: &env, host: host)
        XCTAssertEqual(picked, .real(5.0))
        host.pointNumbers = [.number(2.5)]
        let typed = try await evalString("(getdist)", env: &env, host: host)
        XCTAssertEqual(typed, .real(2.5))
        host.pointNumbers = [.point([1.0, 1.0])]
        let based = try await evalString("(getdist '(1 4))", env: &env, host: host)
        XCTAssertEqual(based, .real(3.0))
    }

    func testGetangleOriented() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.pointNumbers = [.point([0.0, 0.0]), .point([0.0, 1.0])]
        let raw = try await evalString("(getangle)", env: &env, host: host)
        XCTAssertEqual(raw, .real(Double.pi / 2))
        // getorient applies ANGBASE (90-deg base turns north into zero).
        host.vars["ANGBASE"] = .real(Double.pi / 2)
        host.pointNumbers = [.point([0.0, 0.0]), .point([0.0, 1.0])]
        let oriented = try await evalString("(getorient)", env: &env, host: host)
        XCTAssertEqual(oriented, .real(0.0))
    }

    func testGetcorner() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.points = [[5.0, 6.0]]
        let corner = try await evalString("(getcorner '(0 0))", env: &env, host: host)
        XCTAssertEqual(corner, LispValue(list: [.real(5), .real(6)]))
    }

    func testEntselShape() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.entities = [("2A3F", [1.0, 2.0, 0.0])]
        let pick = try await evalString("(entsel)", env: &env, host: host)
        XCTAssertEqual(
            pick,
            LispValue(list: [
                .entityName("2A3F"),
                LispValue(list: [.real(1), .real(2), .real(0)]),
            ]))
        host.entities = [nil]
        let empty = try await evalString("(entsel)", env: &env, host: host)
        XCTAssertEqual(empty, .nilValue)
    }

    func testGrreadPassesEventsThrough() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.deviceEvents = [LispValue(list: [.int(2), .string("q")])]
        let event = try await evalString("(grread)", env: &env, host: host)
        XCTAssertEqual(event, LispValue(list: [.int(2), .string("q")]))
    }

    func testCommandForwardsToHost() async throws {
        // Step-2 hosts have no command processor: clean error, not a crash.
        await assertEvalThrows(
            "(command \"LINE\")", .hostError("(command ...) needs a command host"))
    }

    func testEntityBuiltinsNeedDrawing() async throws {
        await assertEvalThrows("(entget (handent \"1\"))", .noActiveDrawing("handent 1"))
        await assertEvalThrows("(entlast)", .noActiveDrawing("entlast"))
        await assertEvalThrows("(ssget \"_X\")", .noActiveDrawing("ssget"))
    }

    func testSsgetModeValidation() async throws {
        // A non-mode string is a PICK prompt (real AutoCAD behavior, used by
        // the seed corpus): the prompt echoes, then a pick is attempted.
        // The scripted host has no picker, so the pick reports no drawing.
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        do {
            let value = try await evalString("(ssget \"bogus\")", env: &env, host: host)
            XCTFail("expected noActiveDrawing, got \(value.prin1String)")
        } catch let error as LispError {
            XCTAssertEqual(error, .noActiveDrawing("ssget PICK"))
        }
        XCTAssertEqual(host.output, "bogus")
    }
}
