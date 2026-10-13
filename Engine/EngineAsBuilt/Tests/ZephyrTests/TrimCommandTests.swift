import XCTest
@testable import ZephyrCore

@MainActor
final class TrimCommandTests: XCTestCase {

    // MARK: - Line Trimming Tests

    func testTrimLineSingleClickEndpoint() {
        // Horizontal line from (0, 0) to (10, 0)
        let ls = Vector3(x: 0, y: 0, z: 0)
        let le = Vector3(x: 10, y: 0, z: 0)

        // Vertical cutting edge at x = 5 from (5, -5) to (5, 5)
        let cuttingEdge = (Vector3(x: 5, y: -5, z: 0), Vector3(x: 5, y: 5, z: 0))

        // Click at (8, 0) -> should trim the right side [5..10], keeping [0..5]
        let click = Vector3(x: 8, y: 0, z: 0)
        let (res, modified, err) = TrimGeometryEngine.trimPrimitive(
            primitive: .line(start: ls, end: le, color: nil),
            transform: .identity,
            criterion: .click(point: click),
            cuttingSegments: [cuttingEdge],
            exactLines: [cuttingEdge],
            zoom: 1.0
        )

        XCTAssertNil(err)
        XCTAssertTrue(modified)
        XCTAssertEqual(res?.count, 1)

        if case .line(let start, let end, _) = res?.first {
            XCTAssertEqual(start.x, 0.0, accuracy: 1e-6)
            XCTAssertEqual(end.x, 5.0, accuracy: 1e-6)
        } else {
            XCTFail("Expected .line primitive")
        }
    }

    func testTrimLineMiddleSegmentBetweenTwoCuttingEdges() {
        // Horizontal line from (0, 0) to (10, 0)
        let ls = Vector3(x: 0, y: 0, z: 0)
        let le = Vector3(x: 10, y: 0, z: 0)

        // Two vertical cutting edges at x = 3 and x = 7
        let edge1 = (Vector3(x: 3, y: -5, z: 0), Vector3(x: 3, y: 5, z: 0))
        let edge2 = (Vector3(x: 7, y: -5, z: 0), Vector3(x: 7, y: 5, z: 0))

        // Click at (5, 0) -> trims middle [3..7], keeping [0..3] and [7..10]
        let click = Vector3(x: 5, y: 0, z: 0)
        let (res, modified, err) = TrimGeometryEngine.trimPrimitive(
            primitive: .line(start: ls, end: le, color: nil),
            transform: .identity,
            criterion: .click(point: click),
            cuttingSegments: [edge1, edge2],
            exactLines: [edge1, edge2],
            zoom: 1.0
        )

        XCTAssertNil(err)
        XCTAssertTrue(modified)
        XCTAssertEqual(res?.count, 2)

        if let line1 = res?.first, case .line(let s1, let e1, _) = line1 {
            XCTAssertEqual(s1.x, 0.0, accuracy: 1e-6)
            XCTAssertEqual(e1.x, 3.0, accuracy: 1e-6)
        } else {
            XCTFail("Expected first line")
        }

        if let line2 = res?.last, case .line(let s2, let e2, _) = line2 {
            XCTAssertEqual(s2.x, 7.0, accuracy: 1e-6)
            XCTAssertEqual(e2.x, 10.0, accuracy: 1e-6)
        } else {
            XCTFail("Expected second line")
        }
    }

    func testTrimLineCrossingBoxSelection() {
        // Horizontal line from (0, 0) to (10, 0)
        let ls = Vector3(x: 0, y: 0, z: 0)
        let le = Vector3(x: 10, y: 0, z: 0)

        // Vertical cutting edge at x = 4
        let edge = (Vector3(x: 4, y: -5, z: 0), Vector3(x: 4, y: 5, z: 0))

        // Crossing box enclosing (6, -2) to (8, 2) -> crosses the [4..10] portion
        let boxMin = Vector3(x: 6, y: -2, z: 0)
        let boxMax = Vector3(x: 8, y: 2, z: 0)

        let (res, modified, err) = TrimGeometryEngine.trimPrimitive(
            primitive: .line(start: ls, end: le, color: nil),
            transform: .identity,
            criterion: .rect(min: boxMin, max: boxMax, isCrossing: true),
            cuttingSegments: [edge],
            exactLines: [edge],
            zoom: 1.0
        )

        XCTAssertNil(err)
        XCTAssertTrue(modified)
        XCTAssertEqual(res?.count, 1)

        if case .line(let start, let end, _) = res?.first {
            XCTAssertEqual(start.x, 0.0, accuracy: 1e-6)
            XCTAssertEqual(end.x, 4.0, accuracy: 1e-6)
        } else {
            XCTFail("Expected .line primitive")
        }
    }

    func testTrimLineFenceSelection() {
        // Horizontal line from (0, 0) to (10, 0)
        let ls = Vector3(x: 0, y: 0, z: 0)
        let le = Vector3(x: 10, y: 0, z: 0)

        // Vertical cutting edge at x = 5
        let edge = (Vector3(x: 5, y: -5, z: 0), Vector3(x: 5, y: 5, z: 0))

        // Fence segment from (7, -3) to (7, 3) crosses the [5..10] portion
        let fenceP1 = Vector3(x: 7, y: -3, z: 0)
        let fenceP2 = Vector3(x: 7, y: 3, z: 0)

        let (res, modified, err) = TrimGeometryEngine.trimPrimitive(
            primitive: .line(start: ls, end: le, color: nil),
            transform: .identity,
            criterion: .fence(p1: fenceP1, p2: fenceP2),
            cuttingSegments: [edge],
            exactLines: [edge],
            zoom: 1.0
        )

        XCTAssertNil(err)
        XCTAssertTrue(modified)
        XCTAssertEqual(res?.count, 1)

        if case .line(let start, let end, _) = res?.first {
            XCTAssertEqual(start.x, 0.0, accuracy: 1e-6)
            XCTAssertEqual(end.x, 5.0, accuracy: 1e-6)
        } else {
            XCTFail("Expected .line primitive")
        }
    }

    // MARK: - Circle Trimming Tests

    func testTrimCircleWithTwoCuttingEdgesBecomesArc() {
        // Circle at origin with radius 5
        let center = Vector3(x: 0, y: 0, z: 0)
        let radius = 5.0

        // Horizontal cutting edge along x-axis (intersects at angles 0 and pi)
        let edge = (Vector3(x: -10, y: 0, z: 0), Vector3(x: 10, y: 0, z: 0))

        // Click top half at (0, 5) -> removes top half [0..pi], keeping bottom half [pi..2pi]
        let click = Vector3(x: 0, y: 5, z: 0)
        let (res, modified, err) = TrimGeometryEngine.trimPrimitive(
            primitive: .circle(center: center, radius: radius, color: nil),
            transform: .identity,
            criterion: .click(point: click),
            cuttingSegments: [edge],
            exactLines: [edge],
            zoom: 1.0
        )

        XCTAssertNil(err)
        XCTAssertTrue(modified)
        XCTAssertEqual(res?.count, 1)

        if case .arc(let c, let r, let sa, let ea, _) = res?.first {
            XCTAssertEqual(c.x, 0.0, accuracy: 1e-6)
            XCTAssertEqual(r, 5.0, accuracy: 1e-6)
            // Kept arc starts at pi and ends at 2pi (or 0)
            XCTAssertEqual(sa, .pi, accuracy: 1e-4)
            XCTAssertEqual(TrimGeometryEngine.normAngle(ea), 0.0, accuracy: 1e-4)
        } else {
            XCTFail("Expected .arc primitive after circle trim")
        }
    }

    // MARK: - Command Options & Metadata Tests

    func testTrimCommandTextOptions() {
        let cmd = TrimCommand()
        // Target selection options should include Fence, Crossing, Cutting edges, Mode, eRase, Undo
        let options = cmd.commandTextOptions(for: "")
        // Initial state is selectCuttingEdges
        XCTAssertTrue(options.contains { $0.value == "ALL" })
        XCTAssertTrue(options.contains { $0.value == "M" })
    }

    func testTrimModeDefaultIsStandard() {
        XCTAssertEqual(TrimCommand.preferredMode, .standard)
    }
}
