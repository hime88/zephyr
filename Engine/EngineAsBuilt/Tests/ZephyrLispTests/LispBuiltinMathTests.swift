import XCTest
@testable import ZephyrLisp

final class LispBuiltinMathTests: XCTestCase {
    func testArithmeticIntDomain() async throws {
        try await assertEval("(+ 1 2 3)", .int(6))
        try await assertEval("(+)", .int(0))
        try await assertEval("(- 10 3 2)", .int(5))
        try await assertEval("(- 5)", .int(-5))
        try await assertEval("(* 2 3 4)", .int(24))
        try await assertEval("(*)", .int(1))
        // Integer division truncates.
        try await assertEval("(/ 5 2)", .int(2))
        try await assertEval("(/ -5 2)", .int(-2))
        try await assertEval("(/ 2)", .int(0))
        // 32-bit wrap.
        try await assertEval("(+ 2147483647 1)", .int(Int(Int32.min)))
    }

    func testArithmeticRealPromotion() async throws {
        try await assertEval("(+ 1 2.5)", .real(3.5))
        try await assertEval("(/ 5.0 2)", .real(2.5))
        try await assertEval("(/ 2.0)", .real(0.5))
        try await assertEval("(- 1.5)", .real(-1.5))
    }

    func testDivisionByZero() async throws {
        await assertEvalThrows("(/ 1 0)", .divisionByZero)
        await assertEvalThrows("(/ 1.0 0.0)", .divisionByZero)
        await assertEvalThrows("(rem 1 0)", .divisionByZero)
    }

    func testComparisons() async throws {
        try await assertEval("(= 1 1 1)", .symbol("T"))
        try await assertEval("(= 1 2)", .nilValue)
        try await assertEval("(= 1 1.0)", .symbol("T"))
        try await assertEval("(= \"a\" \"a\")", .symbol("T"))
        try await assertEval("(/= 1 2)", .symbol("T"))
        try await assertEval("(< 1 2 3)", .symbol("T"))
        try await assertEval("(<= 2 2)", .symbol("T"))
        try await assertEval("(> 3 2)", .symbol("T"))
        try await assertEval("(>= 2 3)", .nilValue)
        // All six orderings compare strings lexicographically (step 4e oracle).
        try await assertEval("(> \"c\" \"b\")", .symbol("T"))
        try await assertEval("(< \"a\" \"b\" \"c\")", .symbol("T"))
        try await assertEval("(<= \"a\" \"a\")", .symbol("T"))
        try await assertEval("(>= \"b\" \"c\")", .nilValue)
    }

    func testOnePlusMinusBitNot() async throws {
        try await assertEval("(1+ 10)", .int(11))
        try await assertEval("(1- 10.5)", .real(9.5))
        try await assertEval("(~ 0)", .int(-1))
        try await assertEval("(~ -1)", .int(0))
    }

    func testInventoryExamples() async throws {
        // Oracles straight from the inventory example fields.
        try await assertEval("(abs -10)", .int(10))
        try await assertEval("(1+ 10)", .int(11))
        try await assertEval("(1- 10)", .int(9))
        try await assertEval("(1- 10.5)", .real(9.5))
    }

    func testTranscendentals() async throws {
        try await assertEval("(cos 0)", .real(1.0))
        try await assertEval("(sin 0)", .real(0.0))
        try await assertEval("(expt 2 3)", .int(8))
        try await assertEval("(sqrt 16)", .real(4.0))
        try await assertEval("(atan 0)", .real(0.0))
        try await assertEval("(gcd 12 8)", .int(4))
        try await assertEval("(rem 5 3)", .int(2))
        try await assertEval("(max 1 9 3)", .int(9))
        try await assertEval("(min 1.5 9)", .real(1.5))
        try await assertEval("(fix 1.9)", .int(1))
        try await assertEval("(fix -1.9)", .int(-1))
        try await assertEval("(float 2)", .real(2.0))
        try await assertEval("(exp 0)", .real(1.0))
        try await assertEval("(log 1)", .real(0.0))
    }

    func testNumericPredicates() async throws {
        try await assertEval("(minusp -1)", .symbol("T"))
        try await assertEval("(minusp 0)", .nilValue)
        try await assertEval("(zerop 0)", .symbol("T"))
        try await assertEval("(zerop 0.0)", .symbol("T"))
        try await assertEval("(numberp 3)", .symbol("T"))
        try await assertEval("(numberp \"3\")", .nilValue)
    }

    func testBitwise() async throws {
        try await assertEval("(logand 6 3)", .int(2))
        try await assertEval("(logior 6 3)", .int(7))
        try await assertEval("(lsh 8 -1)", .int(4))
        try await assertEval("(lsh 1 3)", .int(8))
        // boole op 1 = AND, 6 = XOR, 7 = IOR over the CL truth table.
        try await assertEval("(boole 1 6 3)", .int(2))
        try await assertEval("(boole 6 6 3)", .int(5))
        try await assertEval("(boole 7 6 3)", .int(7))
    }

    func testPointGeometry() async throws {
        try await assertEval("(distance '(0 0) '(3 4))", .real(5.0))
        try await assertEval("(angle '(0 0) '(1 0))", .real(0.0))
        try await assertEval("(angle '(0 0) '(-1 0))", .real(Double.pi))
        // Negative atan2 normalizes into 0..2pi.
        let negative = try await evalToDouble("(angle '(0 0) '(0 -1))")
        XCTAssertEqual(negative, 3 * Double.pi / 2, accuracy: 1e-12)
        try await assertEval(
            "(polar '(0 0) 0 10)", LispValue(list: [.real(10), .real(0)]))
        // AutoCAD inters returns a 3D point (step 4e oracle).
        try await assertEval(
            "(inters '(0 0) '(2 2) '(0 2) '(2 0))",
            LispValue(list: [.real(1), .real(1), .real(0)]))
        try await assertEval("(inters '(0 0) '(1 0) '(0 1) '(1 1))", .nilValue)
    }

    func testCvunit() async throws {
        try await assertEval("(cvunit 1 \"inch\" \"mm\")", .real(25.4))
        try await assertEval("(cvunit 1000 \"mm\" \"m\")", .real(1.0))
    }

    private func evalToDouble(_ source: String) async throws -> Double {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let value = try await evalString(source, env: &env, host: host)
        guard case let .real(v) = value else {
            throw XCTSkip("expected real, got \(value.prin1String)")
        }
        return v
    }
}
