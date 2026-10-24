import XCTest
import Foundation
@testable import ZephyrCore

/// Regression tests for PDF page scale/size selection.
///
/// A sub-letter drawing at true unit scale used to land as a speck in the
/// corner of the enforced 612x792 minimum page (e.g. the SS-5 Model view:
/// 8.5x11 mm at 2.83 pt/mm is 24x31 pt of ink). Small drawings must scale up
/// to fill the minimum page; oversized drawings must still cap at the viewer
/// limit; sheet-size drawings keep exact true scale.
@MainActor
final class PDFExportPageFitTests: XCTestCase {

    private var mm: Double { CADUnit.millimeter.pointsPerUnit }

    // SS-5 case: 8.5x11 mm drawing must fill the minimum page.
    func testSmallDrawingScalesUpToFillMinPage() {
        let r = PDFExporter.pageScaleAndSize(worldW: 8.5, worldH: 11.0, pointsPerUnit: mm)
        XCTAssertGreaterThan(r.scale, mm, "small drawing must scale up from true unit scale")
        XCTAssertEqual(r.scale, 63.53, accuracy: 0.05)
        XCTAssertEqual(r.pageW, 612.0, accuracy: 0.5)
        XCTAssertEqual(r.pageH, 792.0, accuracy: 0.5)
    }

    // Oversized drawings still cap at the viewer limit (14,400 pt).
    func testLargeDrawingScalesDownToCap() {
        let ft = CADUnit.foot.pointsPerUnit
        let r = PDFExporter.pageScaleAndSize(worldW: 1700, worldH: 2338, pointsPerUnit: ft)
        XCTAssertLessThan(r.scale, ft, "oversized drawing must scale down")
        XCTAssertEqual(r.pageH, 14_400.0, accuracy: 2.0)
        XCTAssertLessThanOrEqual(max(r.pageW, r.pageH), 14_400.0 + 72.0)
    }

    // A true letter sheet in mm keeps exact unit scale (no-op either way).
    func testSheetSizeDrawingKeepsTrueScale() {
        let r = PDFExporter.pageScaleAndSize(worldW: 215.9, worldH: 279.4, pointsPerUnit: mm)
        XCTAssertEqual(r.scale, mm, accuracy: 1e-12)
        XCTAssertEqual(r.pageW, 215.9 * mm + 72.0, accuracy: 0.5)
        XCTAssertEqual(r.pageH, 279.4 * mm + 72.0, accuracy: 0.5)
    }

    // Wide-but-short content fits the limiting dimension, preserving aspect.
    func testWideShortDrawingFitsWidth() {
        let r = PDFExporter.pageScaleAndSize(worldW: 500, worldH: 10, pointsPerUnit: 1.0)
        XCTAssertEqual(r.scale, 1.08, accuracy: 1e-9)
        XCTAssertEqual(r.pageW, 612.0, accuracy: 1e-6)
        XCTAssertEqual(r.pageH, 792.0)
    }

    // Degenerate extents must not explode: finite scale, minimum page.
    func testDegenerateExtentStaysFinite() {
        let r = PDFExporter.pageScaleAndSize(worldW: 0, worldH: 0, pointsPerUnit: mm)
        XCTAssertTrue(r.scale.isFinite)
        XCTAssertEqual(r.pageW, 612.0, accuracy: 1e-6)
        XCTAssertEqual(r.pageH, 792.0)
    }

    // Paperspace layout already near sheet size: aspect-preserving fill.
    func testLayoutExtentFillsPageHeight() {
        let r = PDFExporter.pageScaleAndSize(
            worldW: 7.844934061473321, worldH: 17.55728879184793, pointsPerUnit: mm)
        XCTAssertGreaterThan(r.scale, mm)
        XCTAssertEqual(r.pageW, 612.0, accuracy: 1.0)
        XCTAssertEqual(r.pageH, 792.0, accuracy: 1.0)
    }
}
