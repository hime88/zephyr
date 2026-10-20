import XCTest
import SwiftSDL
@testable import ZephyrCore

/// Unit 0 (xref plan): clipper fast paths (AABB reject, hoisted
/// triangulation) must preserve clipping coverage.
final class CADRenderClipperTests: XCTestCase {

    private func pt(_ x: Float, _ y: Float) -> SDL_FPoint { SDL_FPoint(x: x, y: y) }

    private func lineSpec(_ a: SDL_FPoint, _ b: SDL_FPoint) -> PrimitiveSpec {
        PrimitiveSpec(type: .line, points: [a, b], rects: [], corners: [],
                      z: 0, color: (255, 255, 255, 255))
    }

    private var square: [SDL_FPoint] { [pt(0, 0), pt(10, 0), pt(10, 10), pt(0, 10)] }

    func testSegmentFullyOutsideRejectedAndKeptWhenInverted() {
        let spec = lineSpec(pt(20, 20), pt(30, 20))
        XCTAssertTrue(CADRenderClipper.clip(specs: [spec], polygon: square, inverted: false).isEmpty)
        let kept = CADRenderClipper.clip(specs: [spec], polygon: square, inverted: true)
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.points.first?.x, 20)
    }

    func testSegmentInsideKeptWhole() {
        let spec = lineSpec(pt(2, 5), pt(8, 5))
        let out = CADRenderClipper.clip(specs: [spec], polygon: square, inverted: false)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.points.count, 2)
        XCTAssertEqual(out.first?.points.first?.x, 2)
        XCTAssertEqual(out.first?.points.last?.x, 8)
    }

    func testCrossingSegmentClippedToBoundary() {
        let spec = lineSpec(pt(-5, 5), pt(15, 5))
        let out = CADRenderClipper.clip(specs: [spec], polygon: square, inverted: false)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.points.first?.x ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(out.first?.points.last?.x ?? -1, 10, accuracy: 0.001)
    }

    func testFillTriangleOutsideRejectedOverlapKeepsHalfArea() {
        // Triangle fully outside.
        let outside = PrimitiveSpec(
            type: .fillRect, points: [], rects: [],
            corners: [pt(20, 0), pt(30, 0), pt(20, 10)],
            z: 0, color: (255, 255, 255, 255))
        XCTAssertTrue(CADRenderClipper.clip(specs: [outside], polygon: square, inverted: false).isEmpty)

        // Right triangle covering the square's left half diagonally:
        // (0,0)-(10,0)-(0,10) has area 50, entirely inside the square.
        let half = PrimitiveSpec(
            type: .fillRect, points: [], rects: [],
            corners: [pt(0, 0), pt(10, 0), pt(0, 10)],
            z: 0, color: (255, 255, 255, 255))
        let out = CADRenderClipper.clip(specs: [half], polygon: square, inverted: false)
        var area: Float = 0
        for spec in out {
            let c = spec.corners
            for i in stride(from: 0, to: c.count - 2, by: 3) {
                area += abs((c[i + 1].x - c[i].x) * (c[i + 2].y - c[i].y)
                            - (c[i + 1].y - c[i].y) * (c[i + 2].x - c[i].x)) / 2
            }
        }
        XCTAssertEqual(area, 50, accuracy: 0.01)
    }
}
