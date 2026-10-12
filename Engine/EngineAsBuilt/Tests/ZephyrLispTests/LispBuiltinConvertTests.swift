import XCTest
@testable import ZephyrLisp

final class LispBuiltinConvertTests: XCTestCase {
    func testRtosDecimalAndScientific() async throws {
        try await assertEval("(rtos 3.14159 2 2)", .string("3.14"))
        try await assertEval("(rtos -3.14159 2 2)", .string("-3.14"))
        try await assertEval("(rtos 123.456 1 2)", .string("1.23E+02"))
        try await assertEval("(rtos 0.001 1 2)", .string("1.00E-03"))
        // Defaults come from the host (LUNITS=2, LUPREC=4).
        try await assertEval("(rtos 3.14159)", .string("3.1416"))
    }

    func testRtosImperial() async throws {
        try await assertEval("(rtos 42.5 3 2)", .string("3'-6.50\""))
        try await assertEval("(rtos 42.5 4 2)", .string("3'-6 1/2\""))
        try await assertEval("(rtos 42.5 5 1)", .string("42 1/2"))
        try await assertEval("(rtos 42.0 5 1)", .string("42"))
        try await assertEval("(rtos -42.5 5 1)", .string("-42 1/2"))
    }

    func testAngtos() async throws {
        // 45 degrees in radians.
        try await assertEval("(angtos 0.7853981633974483 0 4)", .string("45.0000"))
        try await assertEval("(angtos 0.7853981633974483 1 0)", .string("45d0'0\""))
        try await assertEval("(angtos 3.141592653589793 2 2)", .string("200.00g"))
        try await assertEval("(angtos 1.0 3 2)", .string("1.00r"))
        try await assertEval("(angtos 0.7853981633974483 4 0)", .string("N 45d0'0\" E"))
        // Defaults from the host (AUNITS=0, AUPREC=0).
        try await assertEval("(angtos 0.7853981633974483)", .string("45"))
    }

    func testAngtof() async throws {
        try await assertEval("(angtof \"45\" 0)", .real(Double.pi / 4))
        try await assertEval("(angtof \"45d30'0\\\"\" 1)", .real(45.5 * Double.pi / 180))
        try await assertEval("(angtof \"200g\" 2)", .real(Double.pi))
        try await assertEval("(angtof \"1.5r\" 3)", .real(1.5))
        try await assertEval("(angtof \"garbage\" 0)", .nilValue)
    }

    func testDistof() async throws {
        try await assertEval("(distof \"42.5\")", .real(42.5))
        try await assertEval("(distof \"3'-6 1/2\\\"\")", .real(42.5))
        try await assertEval("(distof \"42 1/2\")", .real(42.5))
        try await assertEval("(distof \"3/4\")", .real(0.75))
        try await assertEval("(distof \"nope\")", .nilValue)
    }

    func testRtosDistofRoundTrip() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let rendered = try await evalString("(rtos 42.5 4 2)", env: &env, host: host)
        XCTAssertEqual(rendered, .string("3'-6 1/2\""))
        host.lines = []
        let back = try await evalString("(distof \"3'-6 1/2\\\"\")", env: &env, host: host)
        XCTAssertEqual(back, .real(42.5))
    }
}
