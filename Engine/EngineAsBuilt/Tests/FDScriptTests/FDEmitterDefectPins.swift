import XCTest
@testable import FieldDraftScriptCore
@testable import FieldDraftScriptBackends

/// Characterization pins for five known FDScript emitter defects.
///
/// Each `KnownDefect` test asserts the CURRENT (buggy) output so the suite
/// stays green while documenting the exact defect. When the transpiled path
/// is built (plan step 5), fix the defect and flip the assertion to the
/// CORRECT behavior noted in each comment. Do not "fix" these tests by
/// weakening them: a flip must come with the product fix.
final class FDEmitterDefectPins: XCTestCase {

    private func parse(_ source: String) throws -> FDProgram {
        try FieldDraftScriptParser(source).parseProgram()
    }

    private func commandBody(_ program: FDProgram) throws -> [FDStmt] {
        guard case let .command(cmd) = program.declarations.first else {
            throw XCTSkip("expected a command declaration")
        }
        return cmd.body
    }

    // MARK: - Defect 1: raw("...") emits invalid (raw "...") form

    func testRawCallEmitsBareRawForm_KnownDefect() throws {
        let program = try parse("command T {\n raw(\"(+ 1 2)\")\n}")
        let body = try commandBody(program)
        XCTAssertEqual(body.count, 1)
        guard case .expr(.call("raw", _)) = body[0] else {
            return XCTFail("expected raw() to parse as a call expression")
        }
        let output = try AutoLISPBackend().emit(program)
        // CORRECT: the string should be emitted verbatim as `(+ 1 2)`.
        // `(raw ...)` is not valid AutoLISP.
        XCTAssertTrue(output.contains("(raw \"(+ 1 2)\")"), output)
    }

    // MARK: - Defect 2a: yield keeps only the last caller statement

    func testYieldKeepsOnlyLastStatement_KnownDefect() throws {
        let program = try parse("""
        macro withSetup {
          setup
          yield
          restore
        }
        command T {
          withSetup {
            setq x = 1
            setq y = 2
          }
        }
        """)
        let body = try commandBody(program)
        // CORRECT: the macro call should splice [setup, setq x, setq y, restore].
        // Observed: parseMacroCall returns only the last expanded statement.
        XCTAssertEqual(body.count, 1)
        guard case .restore = body[0] else {
            return XCTFail("expected only the trailing restore to survive, got: \(body)")
        }
    }

    // MARK: - Defect 2b: macro call keeps only the last expansion statement

    func testMacroCallKeepsOnlyLastStatement_KnownDefect() throws {
        let program = try parse("""
        macro pair {
          setq a = 1
          setq b = 2
        }
        command T {
          pair
        }
        """)
        let body = try commandBody(program)
        // CORRECT: both setq statements should survive expansion.
        XCTAssertEqual(body.count, 1)
        guard case let .setq(pairs) = body[0], pairs.count == 1, pairs[0].0 == "b" else {
            return XCTFail("expected only `setq b` to survive, got: \(body)")
        }
    }

    // MARK: - Defect 2c: doorPoints et al discard their bodies (EDR door-math loss)

    func testDoorPointsDiscardsBody_KnownDefect() throws {
        let program = try parse("command T {\n doorPoints {\n setq dWidth = 1\n }\n}")
        let body = try commandBody(program)
        // CORRECT: the block content should lower to door-math statements.
        // Observed: a silent empty placeholder; the math never reaches the AST.
        XCTAssertEqual(body.count, 1)
        guard case let .raw(code) = body[0], code.isEmpty else {
            return XCTFail("expected a silent empty placeholder, got: \(body)")
        }
    }

    // MARK: - Defect 3: branch locals missing from / declarations

    func testBranchLocalsMissingFromDefun_KnownDefect() throws {
        let program = FDProgram(declarations: [
            .command(FDCommandDecl(name: "T", body: [
                .ifStmt(
                    condition: .bool(true),
                    then: [.setq([("branchVar", .number(1))])],
                    elseBody: nil
                )
            ]))
        ])
        let output = try AutoLISPBackend().emit(program)
        // CORRECT: `(defun c:T ( / branchVar )`. Observed: no locals, so
        // branch-assigned variables leak to globals at runtime.
        XCTAssertTrue(output.contains("(defun c:T (  )"), output)
        XCTAssertFalse(output.contains("/ branchVar"), output)
    }

    // MARK: - Defect 4: vl-*/file function names pass through unmapped

    func testVlAndFileNamesUnmapped_KnownDefect() throws {
        let program = FDProgram(declarations: [
            .function(FDFunctionDecl(name: "f", params: [], body: [
                .expr(.call("vlStringToList", [.string("a")])),
                .expr(.call("fileOpen", [.string("f"), .string("r")])),
                .expr(.call("readLine", [.symbol("fh")])),
            ]))
        ])
        let output = try AutoLISPBackend().emit(program)
        // CORRECT mappings: vl-string->list, open, read-line.
        XCTAssertTrue(output.contains("(vlStringToList "), output)
        XCTAssertTrue(output.contains("(fileOpen "), output)
        XCTAssertTrue(output.contains("(readLine "), output)
    }

    // MARK: - Defect 5: symbol lists emit the evaluating (list ...) form

    func testSymbolListEmitsEvaluatingForm_KnownDefect() throws {
        let program = FDProgram(declarations: [
            .function(FDFunctionDecl(name: "f", params: [], body: [
                .expr(.list([.symbol("POINT")])),
            ]))
        ])
        let output = try AutoLISPBackend().emit(program)
        // CORRECT: quoted data `'(POINT)`. Observed `(list POINT)` evaluates
        // the symbol as a variable instead of producing data.
        XCTAssertTrue(output.contains("(list POINT)"), output)
    }

    // MARK: - Smoke: basic command shape still holds

    func testBasicCommandEmitsDefunShape() throws {
        let program = try parse("command T {\n setq x = 1\n}")
        let output = try AutoLISPBackend().emit(program)
        XCTAssertTrue(output.contains("(defun c:T ( / x )"), output)
        XCTAssertTrue(output.contains("(vl-load-com)"), output)
        XCTAssertTrue(output.hasSuffix("(princ)\n)"), output)
    }
}
