import XCTest
@testable import ZephyrCore

@MainActor
final class VerbNounModifyCommandTests: XCTestCase {

    func testStartCommandWithSelectingObjects() {
        let processor = CADCommandProcessor()
        processor.startCommand("MOVE", prompt: "Select objects to move, then press Enter", selectingObjects: true)

        XCTAssertEqual(processor.activeCommand, "MOVE")
        XCTAssertTrue(processor.isSelectingObjects)
        XCTAssertEqual(processor.commandPrompt, "Select objects to move, then press Enter")
        XCTAssertNil(processor.commandRefPoint)
    }

    func testClearCommandResetsSelectingObjects() {
        let processor = CADCommandProcessor()
        processor.startCommand("MOVE", prompt: "Select objects to move, then press Enter", selectingObjects: true)
        XCTAssertTrue(processor.isSelectingObjects)

        processor.clearCommand()
        XCTAssertNil(processor.activeCommand)
        XCTAssertFalse(processor.isSelectingObjects)
        XCTAssertNil(processor.commandPrompt)
    }

    func testUpdateObjectSelectionPromptWithoutSelection() {
        let processor = CADCommandProcessor()
        processor.startCommand("MOVE", prompt: "Select objects to move, then press Enter", selectingObjects: true)

        processor.updateObjectSelectionPrompt()
        XCTAssertEqual(processor.commandPrompt, "Select objects to move, then press Enter")
    }

    func testConfirmObjectSelectionWithNoEngineOrSelectionClearsCommand() {
        let processor = CADCommandProcessor()
        processor.startCommand("MOVE", prompt: "Select objects to move, then press Enter", selectingObjects: true)

        // Without selection or engine, confirm should clear command
        processor.confirmObjectSelection()
        XCTAssertNil(processor.activeCommand)
        XCTAssertFalse(processor.isSelectingObjects)
    }

    func testVerbNounPromptsForDifferentCommands() {
        let processor = CADCommandProcessor()

        processor.startCommand("ROTATE", prompt: "", selectingObjects: true)
        processor.updateObjectSelectionPrompt()
        XCTAssertEqual(processor.commandPrompt, "Select objects to rotate, then press Enter")

        processor.startCommand("SCALE", prompt: "", selectingObjects: true)
        processor.updateObjectSelectionPrompt()
        XCTAssertEqual(processor.commandPrompt, "Select objects to scale, then press Enter")

        processor.startCommand("COPY", prompt: "", selectingObjects: true)
        processor.updateObjectSelectionPrompt()
        XCTAssertEqual(processor.commandPrompt, "Select objects to copy, then press Enter")

        processor.startCommand("ERASE", prompt: "", selectingObjects: true)
        processor.updateObjectSelectionPrompt()
        XCTAssertEqual(processor.commandPrompt, "Select objects to erase, then press Enter")
    }
}
