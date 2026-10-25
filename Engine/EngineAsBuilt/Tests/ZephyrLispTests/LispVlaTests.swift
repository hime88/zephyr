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

    // MARK: - Kernel-backed curve queries

    private func assoc(_ pairs: [(Int, LispValue)]) -> LispValue {
        LispValue(list: pairs.map { LispValue.cons(head: .int($0.0), tail: $0.1) })
    }

    private func pt(_ x: Double, _ y: Double, _ z: Double = 0) -> LispValue {
        LispValue(list: [.real(x), .real(y), .real(z)])
    }

    private func lineAssoc(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> LispValue {
        assoc([(0, .string("LINE")), (10, pt(ax, ay)), (11, pt(bx, by))])
    }

    private func circleAssoc(_ cx: Double, _ cy: Double, _ r: Double) -> LispValue {
        assoc([(0, .string("CIRCLE")), (10, pt(cx, cy)), (40, .real(r))])
    }

    func testVlaIntersectWithLines() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.entLists = [
            "A": lineAssoc(0, 0, 2, 2),
            "B": lineAssoc(0, 2, 2, 0),
            "C": lineAssoc(5, 5, 6, 6),
        ]
        let hit = try await LispEvaluator().applyValue(
            .symbol("VLA-INTERSECTWITH"),
            args: [.vlaObject("A"), .vlaObject("B")], env: &env, host: host, depth: 0)
        XCTAssertEqual(hit, LispValue(list: [LispValue(list: [.real(1), .real(1), .real(0)])]))
        let miss = try await LispEvaluator().applyValue(
            .symbol("VLA-INTERSECTWITH"),
            args: [.vlaObject("A"), .vlaObject("C")], env: &env, host: host, depth: 0)
        XCTAssertEqual(miss, LispValue(list: []))
    }

    func testVlaIntersectWithExtendMode() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.entLists = [
            "A": lineAssoc(0, 0, 1, 0),
            "B": lineAssoc(2, -1, 2, 1),
        ]
        // No extension: segments miss.
        let miss = try await LispEvaluator().applyValue(
            .symbol("VLA-INTERSECTWITH"),
            args: [.vlaObject("A"), .vlaObject("B")], env: &env, host: host, depth: 0)
        XCTAssertEqual(miss, LispValue(list: []))
        // Extend both: infinite lines cross at (2, 0).
        let hit = try await LispEvaluator().applyValue(
            .symbol("VLA-INTERSECTWITH"),
            args: [.vlaObject("A"), .vlaObject("B"), .int(3)], env: &env, host: host, depth: 0)
        XCTAssertEqual(hit, LispValue(list: [LispValue(list: [.real(2), .real(0), .real(0)])]))
    }

    func testVlaxCurveGetClosestPointTo() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        host.entLists = ["C": circleAssoc(0, 0, 5)]
        let near = try await LispEvaluator().applyValue(
            .symbol("VLAX-CURVE-GETCLOSESTPOINTTO"),
            args: [.vlaObject("C"), LispValue(list: [.real(10), .real(0), .real(0)])],
            env: &env, host: host, depth: 0)
        XCTAssertEqual(near, LispValue(list: [.real(5), .real(0), .real(0)]))
        // Unsupported entity types throw cleanly instead of wrong answers.
        host.entLists["T"] = assoc([(0, .string("TEXT")), (10, pt(0, 0))])
        do {
            _ = try await LispEvaluator().applyValue(
                .symbol("VLA-INTERSECTWITH"),
                args: [.vlaObject("C"), .vlaObject("T")], env: &env, host: host, depth: 0)
            XCTFail("unsupported type should throw")
        } catch is LispError {
        }
    }
}
