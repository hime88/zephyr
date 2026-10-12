import XCTest
@testable import ZephyrLisp

/// Integrity pins for the generated 305-entry inventory. Counts mirror the
/// LispGen disposition policy; changing the policy means updating these pins
/// deliberately, never weakening them.
final class LispRegistryTests: XCTestCase {

    func testRegistryCount() {
        XCTAssertEqual(LispRegistry.expectedCount, 305)
        XCTAssertEqual(LispRegistry.all.count, 305)
    }

    func testRegistryHasNoDuplicateNames() {
        let names = LispRegistry.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testRegistryEntriesAreComplete() {
        for entry in LispRegistry.all {
            XCTAssertFalse(entry.name.isEmpty)
            XCTAssertFalse(entry.signature.isEmpty, entry.name)
            XCTAssertFalse(entry.platforms.isEmpty, entry.name)
            XCTAssertFalse(entry.summary.isEmpty, entry.name)
            XCTAssertFalse(entry.example.isEmpty, entry.name)
        }
    }

    func testDispositionCountsSumToInventory() {
        var counts: [LispDisposition: Int] = [:]
        for entry in LispRegistry.all { counts[entry.disposition, default: 0] += 1 }
        XCTAssertEqual(counts[.waveA], 104, "waveA")
        XCTAssertEqual(counts[.waveB], 89, "waveB")
        XCTAssertEqual(counts[.waveC], 95, "waveC")
        XCTAssertEqual(counts[.stub], 17, "stub")
        XCTAssertEqual(counts.values.reduce(0, +), 305)
    }

    func testPinnedDispositions() {
        let byName = Dictionary(uniqueKeysWithValues: LispRegistry.all.map { ($0.name, $0) })
        // Wave A: interactive/language core (+ corpus-promoted assoc).
        for name in ["command", "entget", "ssget", "getpoint", "defun", "grread", "assoc"] {
            XCTAssertEqual(byName[name]?.disposition, .waveA, name)
        }
        // Wave B: portable remainder.
        for name in ["open", "dictadd", "vl-string-search", "trans"] {
            XCTAssertEqual(byName[name]?.disposition, .waveB, name)
        }
        // Wave C: platform-conditional with a portable mapping.
        for name in ["vl-doc-ref", "getcfg", "startapp", "acet-ms-to-ps"] {
            XCTAssertEqual(byName[name]?.disposition, .waveC, name)
        }
        // Stubs: no portable implementation.
        for name in ["arxload", "vl-vbarun", "tablet", "menucmd", "acet-laytrans"] {
            XCTAssertEqual(byName[name]?.disposition, .stub, name)
        }
    }
}
