import XCTest
@testable import ZephyrCore

/// Step-3 undo-group parity: UNDO Begin/End coalescing, Mark/Back, and
/// abnormal-path cleanup, mirroring AutoCAD's per-command + grouping model.
///
/// All tests drive the real `CADDocument` mutation path (`addEntity` pushes
/// through the group machinery), so they pin the integration, not just the
/// `UndoManager` extension in isolation.
@MainActor
final class LispUndoGroupTests: XCTestCase {

    private func makeLine(_ i: Int) -> CADEntity {
        let d = Double(i)
        return CADEntity(
            layerID: UUID(),
            localGeometry: [.line(
                start: Vector3(x: d, y: 0, z: 0),
                end: Vector3(x: d, y: 1, z: 0))])
    }

    func testPlainAddsProducePerCommandEntries() {
        let doc = CADDocument()
        doc.addEntity(makeLine(0))
        doc.addEntity(makeLine(1))
        XCTAssertEqual(doc.undoManager.undoDepth, 2)
        doc.undo()
        XCTAssertEqual(doc.snapshot().entities.count, 1)
        doc.undo()
        XCTAssertEqual(doc.snapshot().entities.count, 0)
    }

    func testBeginEndCoalescesToSingleEntry() {
        let doc = CADDocument()
        doc.undoManager.beginUndoGroup()
        doc.addEntity(makeLine(0))
        doc.addEntity(makeLine(1))
        XCTAssertEqual(doc.undoManager.undoDepth, 0, "open group commits nothing yet")
        XCTAssertEqual(doc.undoManager.undoControlFlags & 1, 1, "UNDOCTL bit 0 while group open")
        XCTAssertTrue(doc.undoManager.endUndoGroup())
        XCTAssertEqual(doc.undoManager.undoDepth, 1, "group coalesces to one entry")
        XCTAssertEqual(doc.undoManager.undoControlFlags & 1, 0)
        XCTAssertEqual(doc.snapshot().entities.count, 2)
        doc.undo()
        XCTAssertEqual(doc.snapshot().entities.count, 0, "one undo restores pre-group state")
        doc.redo()
        XCTAssertEqual(doc.snapshot().entities.count, 2)
    }

    func testNestedGroupsCommitOnce() {
        let doc = CADDocument()
        doc.undoManager.beginUndoGroup()
        doc.addEntity(makeLine(0))
        doc.undoManager.beginUndoGroup()
        doc.addEntity(makeLine(1))
        XCTAssertTrue(doc.undoManager.endUndoGroup())
        XCTAssertEqual(doc.undoManager.undoDepth, 0, "inner End commits nothing")
        XCTAssertTrue(doc.undoManager.endUndoGroup())
        XCTAssertEqual(doc.undoManager.undoDepth, 1)
        doc.undo()
        XCTAssertEqual(doc.snapshot().entities.count, 0)
    }

    func testUnmatchedEndReturnsFalse() {
        let doc = CADDocument()
        XCTAssertFalse(doc.undoManager.endUndoGroup())
        XCTAssertEqual(doc.undoManager.undoDepth, 0)
    }

    func testEmptyGroupCommitsNothing() {
        let doc = CADDocument()
        doc.undoManager.beginUndoGroup()
        XCTAssertTrue(doc.undoManager.endUndoGroup())
        XCTAssertEqual(doc.undoManager.undoDepth, 0)
    }

    func testMarkAndBack() {
        let doc = CADDocument()
        doc.addEntity(makeLine(0))
        let mark = doc.undoManager.markUndo()
        doc.addEntity(makeLine(1))
        doc.addEntity(makeLine(2))
        XCTAssertEqual(doc.snapshot().entities.count, 3)
        let current = doc.snapshot()
        guard let restored = doc.undoManager.backToUndoMark(mark, currentSnapshot: current) else {
            return XCTFail("Back should succeed")
        }
        doc.restore(from: restored)
        XCTAssertEqual(doc.snapshot().entities.count, 1, "Back restores state at mark")
        XCTAssertEqual(doc.undoManager.undoDepth, mark)
        doc.redo()
        XCTAssertEqual(doc.snapshot().entities.count, 2, "redo re-applies oldest-first")
        doc.redo()
        XCTAssertEqual(doc.snapshot().entities.count, 3)
    }

    func testBackWithOpenGroupAutoCloses() {
        let doc = CADDocument()
        doc.addEntity(makeLine(0))
        let mark = doc.undoManager.markUndo()
        doc.undoManager.beginUndoGroup()
        doc.addEntity(makeLine(1))
        let current = doc.snapshot()
        let restored = doc.undoManager.backToUndoMark(mark, currentSnapshot: current)
        XCTAssertNotNil(restored)
        XCTAssertEqual(doc.undoManager.undoGroupDepth, 0, "Back auto-closes open groups")
        XCTAssertEqual(doc.undoManager.undoDepth, mark)
    }

    func testBackRejectsOutOfRangeMark() {
        let doc = CADDocument()
        doc.addEntity(makeLine(0))
        let current = doc.snapshot()
        XCTAssertNil(doc.undoManager.backToUndoMark(-1, currentSnapshot: current))
        XCTAssertNil(doc.undoManager.backToUndoMark(99, currentSnapshot: current))
        XCTAssertEqual(doc.undoManager.undoDepth, 1, "failed Back changes nothing")
    }

    func testDiscardOpenGroupsOnAbort() {
        let doc = CADDocument()
        doc.addEntity(makeLine(0))
        doc.undoManager.beginUndoGroup()
        doc.addEntity(makeLine(1))
        doc.undoManager.discardOpenUndoGroups()
        XCTAssertEqual(doc.undoManager.undoGroupDepth, 0)
        XCTAssertEqual(doc.undoManager.undoDepth, 1, "committed entries survive abort")
        XCTAssertFalse(doc.undoManager.endUndoGroup(), "nothing left to close")
    }
}
