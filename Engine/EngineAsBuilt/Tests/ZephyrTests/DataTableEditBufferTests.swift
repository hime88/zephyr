import XCTest
@testable import ZephyrCore

final class DataTableEditBufferTests: XCTestCase {
    func testRoundTripPreservesText() {
        let buffer = DataTableEditor.makeCellEditBuffer(from: "hello", capacity: 4096)
        XCTAssertEqual(buffer.count, 4096)
        XCTAssertEqual(DataTableEditor.readCellEditBuffer(buffer), "hello")
    }

    func testRoundTripPreservesUnicode() {
        let buffer = DataTableEditor.makeCellEditBuffer(from: "héllo 表", capacity: 64)
        XCTAssertEqual(DataTableEditor.readCellEditBuffer(buffer), "héllo 表")
    }

    func testTruncatesToCapacityMinusOnePlusNul() {
        let buffer = DataTableEditor.makeCellEditBuffer(from: "abcdef", capacity: 4)
        XCTAssertEqual(buffer.count, 4)
        XCTAssertEqual(buffer.last, 0)
        XCTAssertEqual(DataTableEditor.readCellEditBuffer(buffer), "abc")
    }

    func testEmptyValueReadsBackEmpty() {
        let buffer = DataTableEditor.makeCellEditBuffer(from: "", capacity: 64)
        XCTAssertEqual(DataTableEditor.readCellEditBuffer(buffer), "")
    }
}
