import XCTest
@testable import ZephyrLisp

/// Wave-A surface coverage: every Wave-A inventory entry must dispatch
/// (builtin table) or be a special form. Wave B/C/stub entries pin as
/// undispatched until their wave lands; flipping a pin means implementing
/// the builtin, never editing the expectation alone.
final class LispWaveACoverageTests: XCTestCase {
    private static let specialForms: Set<String> = [
        "QUOTE", "IF", "COND", "WHILE", "REPEAT", "FOREACH", "PROGN",
        "SETQ", "SET", "DEFUN", "DEFUN-Q", "LAMBDA", "AND", "OR",
    ]

    /// Wave-A inventory entries that are user-defined or predefined state,
    /// not dispatchable builtins: *error* comes from defun. (The three
    /// *push/pop-error* entries graduated to real builtins in step 4e
    /// when the example oracle proved they are callable; their global
    /// preloads stay pinned bound below.)
    private static let stateEntries: Set<String> = [
        "*ERROR*",
    ]

    func testEveryWaveAEntryDispatches() {
        let waveA = LispRegistry.all.filter { $0.disposition == .waveA }
        XCTAssertEqual(waveA.count, 104)
        var missing: [String] = []
        for entry in waveA {
            let upper = entry.name.uppercased()
            if !LispEvaluator.knows(upper), !Self.specialForms.contains(upper),
                !Self.stateEntries.contains(upper)
            {
                missing.append(entry.name)
            }
        }
        XCTAssertTrue(
            missing.isEmpty,
            "Wave-A entries without an implementation: \(missing.sorted())")
    }

    func testErrorModeFlagsPredefined() {
        let env = LispEnvironment()
        XCTAssertEqual(env.globals["*POP-ERROR-MODE*"], .nilValue)
        XCTAssertEqual(env.globals["*PUSH-ERROR-USING-COMMAND*"], .symbol("T"))
        XCTAssertEqual(env.globals["*PUSH-ERROR-USING-STACK*"], .symbol("T"))
    }

    // testLaterWavesStayUndispatched retired in step 4e: every pin
    // graduated — STARTAPP/GRDRAW to real builtins, ARXLOAD/VL-VBARUN/
    // TABLET to clean-error stubs — and LispWaveBCCoverageTests plus
    // LispExampleOracleTests now pin the full 305 surface.
}
