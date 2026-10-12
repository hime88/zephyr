import XCTest
@testable import ZephyrLisp

/// Wave-B/C/stub surface coverage (step 4): every Wave-B and Wave-C
/// inventory entry must dispatch, and every stub entry must dispatch to a
/// clean-error stub. Mirrors LispWaveACoverageTests.
final class LispWaveBCCoverageTests: XCTestCase {

    func testEveryWaveBEntryDispatches() {
        let waveB = LispRegistry.all.filter { $0.disposition == .waveB }
        XCTAssertEqual(waveB.count, 89)
        var missing: [String] = []
        for entry in waveB {
            if !LispEvaluator.knows(entry.name.uppercased()) {
                missing.append(entry.name)
            }
        }
        XCTAssertTrue(
            missing.isEmpty,
            "Wave-B entries without an implementation: \(missing.sorted())")
    }

    func testEveryWaveCEntryDispatches() {
        let waveC = LispRegistry.all.filter { $0.disposition == .waveC }
        XCTAssertEqual(waveC.count, 95)
        var missing: [String] = []
        for entry in waveC {
            if !LispEvaluator.knows(entry.name.uppercased()) {
                missing.append(entry.name)
            }
        }
        XCTAssertTrue(
            missing.isEmpty,
            "Wave-C entries without an implementation: \(missing.sorted())")
    }

    func testEveryStubEntryDispatches() {
        let stubs = LispRegistry.all.filter { $0.disposition == .stub }
        XCTAssertEqual(stubs.count, 17)
        var missing: [String] = []
        for entry in stubs {
            if !LispEvaluator.knows(entry.name.uppercased()) {
                missing.append(entry.name)
            }
        }
        XCTAssertTrue(
            missing.isEmpty,
            "Stub entries without an implementation: \(missing.sorted())")
    }

    func testFullInventoryCount() {
        XCTAssertEqual(LispRegistry.all.count, LispRegistry.expectedCount)
        XCTAssertEqual(LispRegistry.expectedCount, 305)
    }
}
