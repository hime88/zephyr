import XCTest
@testable import ZephyrCore

/// Step-3 reentrancy gates: while a Lisp routine runs, `executeCommand`
/// rejects everything (single choke point covering the switch, the
/// feature-command registry, the legacy startCommand path, hotkeys, DDEDIT,
/// and spacebar repeat — all funnel through `executeCommand`).
@MainActor
final class LispReentrancyTests: XCTestCase {

    func testIdleProcessorAcceptsCommands() {
        let proc = CADCommandProcessor()
        XCTAssertEqual(proc.lispInvocationDepth, 0)
        proc.executeCommand("ERASE")
        XCTAssertEqual(proc.lastExecutedCommand, "ERASE")
    }

    func testGateRejectsWhileLispActive() {
        let proc = CADCommandProcessor()
        proc.lastExecutedCommand = "PRIOR"
        proc.lispInvocationDepth = 1
        proc.executeCommand("ERASE")
        XCTAssertEqual(
            proc.lastExecutedCommand, "PRIOR",
            "rejected command must not poison spacebar repeat")
        proc.executeCommand("BRINGTOFRONT")
        XCTAssertNil(proc.activeFeatureCommand, "registry path also gated")
    }

    func testGatePreservesInFlightInteractiveState() {
        let proc = CADCommandProcessor()
        proc.commandPrompt = "Specify base point:"
        proc.lispInvocationDepth = 1
        proc.executeCommand("LINE")
        XCTAssertEqual(
            proc.commandPrompt, "Specify base point:",
            "rejection must not clear state (no clearCommand on reject)")
    }

    func testDepthClampsAtZero() {
        let proc = CADCommandProcessor()
        proc.lispInvocationDepth = -5
        XCTAssertEqual(proc.lispInvocationDepth, 0)
        proc.executeCommand("ERASE")
        XCTAssertEqual(proc.lastExecutedCommand, "ERASE")
    }

    func testDepthRestoresAfterRoutine() {
        let proc = CADCommandProcessor()
        proc.lispInvocationDepth = 1
        proc.executeCommand("ERASE")
        XCTAssertNil(proc.lastExecutedCommand)
        proc.lispInvocationDepth = 0
        proc.executeCommand("ERASE")
        XCTAssertEqual(proc.lastExecutedCommand, "ERASE")
    }
}
