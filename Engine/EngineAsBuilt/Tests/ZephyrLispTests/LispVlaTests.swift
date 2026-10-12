import XCTest
@testable import ZephyrLisp

/// Step-3 vla-minimal underpinning: the four ActiveX functions the seed
/// corpus uses (documented extensions outside the 305 inventory).
final class LispVlaTests: XCTestCase {

    func testVlLoadComIsNoopT() async throws {
        try await assertEval("(vl-load-com)", .t)
    }

    func testVlaObjectWrapping() async throws {
        // quote cannot produce enames; drive applyValue directly.
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let made = try await LispEvaluator().applyValue(
            .symbol("VLAX-ENAME->VLA-OBJECT"),
            args: [.entityName("ABC")], env: &env, host: host, depth: 0)
        XCTAssertEqual(made, .vlaObject("ABC"))
        let idem = try await LispEvaluator().applyValue(
            .symbol("VLAX-ENAME->VLA-OBJECT"),
            args: [.vlaObject("ABC")], env: &env, host: host, depth: 0)
        XCTAssertEqual(idem, .vlaObject("ABC"))
        let kind = try await LispEvaluator().applyValue(
            .symbol("TYPE"), args: [.vlaObject("ABC")],
            env: &env, host: host, depth: 0)
        XCTAssertEqual(kind, .symbol("VLA-OBJECT"))
    }

    func testGetBoundingBoxBindsOutSymbols() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.vlaBoxes = ["ABC": (min: [0, 0, 0], max: [4, 2, 0])]
        env.globals["MINSYM"] = .nilValue
        env.globals["MAXSYM"] = .nilValue
        let result = try await LispEvaluator().applyValue(
            .symbol("VLA-GETBOUNDINGBOX"),
            args: [.vlaObject("ABC"), .symbol("MINSYM"), .symbol("MAXSYM")],
            env: &env, host: host, depth: 0)
        XCTAssertEqual(result, .t)
        XCTAssertEqual(
            env.globals["MINSYM"],
            LispValue(list: [.real(0), .real(0), .real(0)]))
        XCTAssertEqual(
            env.globals["MAXSYM"],
            LispValue(list: [.real(4), .real(2), .real(0)]))
        // Unknown entity throws (callers use vl-catch-all-apply).
        do {
            _ = try await LispEvaluator().applyValue(
                .symbol("VLA-GETBOUNDINGBOX"),
                args: [.vlaObject("ZZZ"), .symbol("MINSYM"), .symbol("MAXSYM")],
                env: &env, host: host, depth: 0)
            XCTFail("unknown entity should throw")
        } catch let error as LispError {
            XCTAssertEqual(
                error, .noActiveDrawing("vla-getboundingbox ZZZ"))
        }
    }

    func testSafearrayToListIdentity() async throws {
        try await assertEval("(vlax-safearray->list '(1 2 3))", LispValue(list: [.int(1), .int(2), .int(3)]))
        await assertEvalThrows(
            "(vlax-safearray->list 5)",
            .typeMismatch(
                name: "vlax-safearray->list",
                expected: "safearray (list)", got: .int(5)))
    }
}
