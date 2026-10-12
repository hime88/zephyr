import XCTest
@testable import ZephyrLisp

final class LispEvalTests: XCTestCase {
    // MARK: - Atoms and lookup

    func testSelfEvaluatingAtoms() async throws {
        try await assertEval("nil", .nilValue)
        try await assertEval("42", .int(42))
        try await assertEval("2.5", .real(2.5))
        try await assertEval("\"s\"", .string("s"))
    }

    func testUnboundSymbolIsNil() async throws {
        // AutoLISP: unbound symbols evaluate to nil (the AddDoor stray-`e`
        // case loads cleanly instead of failing to parse).
        try await assertEval("neverboundanywhere", .nilValue)
    }

    func testPredefinedPiAndT() async throws {
        try await assertEval("pi", .real(Double.pi))
        try await assertEval("t", .symbol("T"))
    }

    func testProtectedSymbols() async throws {
        await assertEvalThrows("(setq t 1)", .protectedSymbol("T"))
        await assertEvalThrows("(setq nil 1)", .protectedSymbol("NIL"))
    }

    // MARK: - Special forms

    func testQuote() async throws {
        try await assertEval("'a", .symbol("A"))
        try await assertEval("'(1 2)", LispValue(list: [.int(1), .int(2)]))
        try await assertEval("(quote (1 . 2))", .cons(head: .int(1), tail: .int(2)))
    }

    func testIf() async throws {
        try await assertEval("(if t 1 2)", .int(1))
        try await assertEval("(if nil 1 2)", .int(2))
        try await assertEval("(if nil 1)", .nilValue)
        // Only nil is false: 0 and "" are true.
        try await assertEval("(if 0 1 2)", .int(1))
        try await assertEval("(if \"\" 1 2)", .int(1))
    }

    func testCond() async throws {
        try await assertEval("(cond (nil 1) (t 2))", .int(2))
        try await assertEval("(cond (nil 1))", .nilValue)
        try await assertEval("(cond ((= 1 2) 1) (t 9))", .int(9))
        // Test-only clause yields the test value.
        try await assertEval("(cond (5))", .int(5))
        try await assertEval("(cond (nil) (7))", .int(7))
    }

    func testWhile() async throws {
        try await assertEval(
            "(progn (setq i 0) (while (< i 3) (setq i (1+ i))) i)", .int(3))
        try await assertEval("(while nil 1)", .nilValue)
    }

    func testRepeat() async throws {
        try await assertEval("(progn (setq i 0) (repeat 3 (setq i (1+ i))) i)", .int(3))
        try await assertEval("(repeat 0 1)", .nilValue)
        try await assertEval("(repeat 2.9 7)", .int(7))
    }

    func testForeach() async throws {
        try await assertEval(
            "(progn (setq s 0) (foreach x '(1 2 3) (setq s (+ s x))) s)", .int(6))
        try await assertEval("(foreach x nil 1)", .nilValue)
        // Loop variable does not clobber an outer binding.
        try await assertEval(
            "(progn (setq x 9) (foreach x '(1) 0) x)", .int(9))
    }

    func testPrognSetqSet() async throws {
        try await assertEval("(progn 1 2 3)", .int(3))
        try await assertEval("(progn)", .nilValue)
        try await assertEval("(progn (setq a 1 b 2) (+ a b))", .int(3))
        try await assertEval("(progn (set 'c 4) c)", .int(4))
    }

    func testAndOrShortCircuit() async throws {
        try await assertEval("(and)", .symbol("T"))
        try await assertEval("(or)", .nilValue)
        try await assertEval("(and 1 2 3)", .int(3))
        try await assertEval("(and 1 nil 3)", .nilValue)
        try await assertEval("(or nil nil 3)", .int(3))
        // Short-circuit: the error branch never runs.
        try await assertEval("(and nil (nosuchfn))", .nilValue)
        try await assertEval("(or t (nosuchfn))", .symbol("T"))
    }

    // MARK: - Functions and dynamic scope

    func testDefunCallAndLocals() async throws {
        try await assertEval(
            "(progn (defun add2 (a / tmp) (setq tmp (+ a 2)) tmp) (add2 40))",
            .int(42))
        // defun returns the function name.
        try await assertEval("(defun f () 1)", .symbol("F"))
    }

    func testDefunLocalsDoNotLeak() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        _ = try await evalString("(defun f (/ tmp) (setq tmp 1))", env: &env, host: host)
        _ = try await evalString("(f)", env: &env, host: host)
        XCTAssertNil(env.globals["TMP"])
    }

    func testDynamicScope() async throws {
        // Inner function sees the caller's locals (dynamic, not lexical).
        try await assertEval(
            """
            (progn
              (defun inner () x)
              (defun outer (/ x) (setq x 7) (inner))
              (outer))
            """, .int(7))
    }

    func testLambdaAsDataAndApplication() async throws {
        // A lambda form evaluates to itself.
        try await assertEval(
            "(car '((lambda (x) x)))",
            LispValue(list: [.symbol("LAMBDA"), LispValue(list: [.symbol("X")]), .symbol("X")]))
        // Direct application in operator position.
        try await assertEval("((lambda (x) (+ x 1)) 41)", .int(42))
    }

    func testApplyMapcarEval() async throws {
        try await assertEval("(apply '+ '(1 2 3))", .int(6))
        try await assertEval("(apply 'strcat \"a\" '(\"b\" \"c\"))", .string("abc"))
        try await assertEval(
            "(mapcar '1+ '(1 2 3))", LispValue(list: [.int(2), .int(3), .int(4)]))
        try await assertEval(
            "(mapcar '(lambda (x) (* x 2)) '(1 2))",
            LispValue(list: [.int(2), .int(4)]))
        try await assertEval(
            "(mapcar 'cons '(1 2) '(3 4))",
            LispValue(list: [
                .cons(head: .int(1), tail: .int(3)),
                .cons(head: .int(2), tail: .int(4)),
            ]))
        try await assertEval("(eval '(+ 1 2))", .int(3))
    }

    func testDefunArgMismatch() async throws {
        await assertEvalThrows(
            "(progn (defun f (a b) a) (f 1))",
            .arity(name: "function", expected: "2", got: 1))
    }

    func testUnboundFunctionCall() async throws {
        await assertEvalThrows("(nosuchfn 1)", .unboundFunction("NOSUCHFN"))
    }

    func testStackOverflowGuard() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        _ = try await evalString("(defun loop (n) (loop (1+ n)))", env: &env, host: host)
        do {
            _ = try await LispEvaluator(maxDepth: 64).run(
                try LispReader().readAll("(loop 0)"), env: &env, host: host)
            XCTFail("expected stack overflow")
        } catch let error as LispError {
            XCTAssertEqual(error, .stackOverflow)
        }
    }

    // MARK: - Errors, *error*, vl-catch-all

    func testErrorWithoutHandlerPropagates() async throws {
        await assertEvalThrows("(/ 1 0)", .divisionByZero)
    }

    func testErrorHandlerRunsAndSwallows() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let result = try await evalString(
            "(progn (defun *error* (msg) (setq seen msg)) (/ 1 0))",
            env: &env, host: host)
        XCTAssertEqual(result, .nilValue)
        XCTAssertEqual(env.globals["SEEN"], .string("divide by zero"))
    }

    func testCancelRunsHandlerThenRethrows() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.cancelNext = true
        do {
            _ = try await evalString(
                "(progn (defun *error* (msg) (setq seen msg)) (getint))",
                env: &env, host: host)
            XCTFail("expected cancel to propagate")
        } catch let error as LispError {
            XCTAssertEqual(error, .userCancel)
        }
        XCTAssertEqual(env.globals["SEEN"], .string("quit / exit abort"))
    }

    func testQuitSkipsHandler() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        do {
            _ = try await evalString(
                "(progn (defun *error* (msg) (setq seen msg)) (quit))",
                env: &env, host: host)
            XCTFail("expected quit to propagate")
        } catch let error as LispError {
            XCTAssertEqual(error, .quitRequested)
        }
        XCTAssertNil(env.globals["SEEN"])
    }

    func testCatchAllCatchesWithoutHandler() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let result = try await evalString(
            """
            (progn
              (defun *error* (msg) (setq seen msg))
              (setq r (vl-catch-all-apply '/ '(1 0)))
              (list (vl-catch-all-error-p r) (vl-catch-all-error-message r)))
            """,
            env: &env, host: host)
        XCTAssertEqual(
            result,
            LispValue(list: [.symbol("T"), .string("divide by zero")]))
        // *error* must NOT fire for caught errors.
        XCTAssertNil(env.globals["SEEN"])
    }

    func testCatchAllPassesValuesThrough() async throws {
        try await assertEval("(vl-catch-all-apply '+ '(1 2))", .int(3))
    }

    func testCatchAllDoesNotCatchQuit() async throws {
        await assertEvalThrows(
            "(vl-catch-all-apply 'quit nil)", .quitRequested)
    }

    // MARK: - load / autoload

    func testLoadEvaluatesFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("lib.lsp").path
        try "(defun libfn (x) (* x 2))".write(toFile: path, atomically: true, encoding: .utf8)
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let loaded = try await evalString("(load \"\(path)\")", env: &env, host: host)
        XCTAssertEqual(loaded, .string(path))
        let result = try await evalString("(libfn 21)", env: &env, host: host)
        XCTAssertEqual(result, .int(42))
    }

    func testLoadMissingFileWithFallback() async throws {
        try await assertEval("(load \"/nonexistent-zephyr-xyz\" 'fallback)", .symbol("FALLBACK"))
    }

    func testAutoloadDefinesOnFirstCall() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("auto.lsp").path
        try "(defun c:lazy () 7)".write(toFile: path, atomically: true, encoding: .utf8)
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        _ = try await evalString(
            "(autoload \"\(path)\" '(\"C:LAZY\"))", env: &env, host: host)
        let result = try await evalString("(c:lazy)", env: &env, host: host)
        XCTAssertEqual(result, .int(7))
    }
}
