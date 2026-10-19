import XCTest
@testable import ZephyrCore

final class SHXShapeFontTests: XCTestCase {

    private func findTestFile(_ name: String) -> String {
        var dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
            dir = dir.deletingLastPathComponent()
        }
        return name
    }

    private func loadIsocp() throws -> SHXShapeFont {
        let path = findTestFile("Fonts/isocp.shx")
        let font = try SHXShapeFont(url: URL(fileURLWithPath: path))
        XCTAssertTrue(font.isUsable)
        return font
    }

    /// Renders at native scale (height == fontHeight). In that setup world X
    /// equals glyph X and world Y equals negated glyph Y (baseline at 0).
    private func lineBounds(
        _ font: SHXShapeFont, _ text: String
    ) -> (count: Int, minX: Double, maxX: Double, minY: Double, maxY: Double) {
        let primitives = font.renderText(text, origin: .zero, height: font.fontHeight)
        var count = 0
        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity
        for case .line(let start, let end, _) in primitives {
            count += 1
            minX = min(minX, start.x, end.x)
            maxX = max(maxX, start.x, end.x)
            minY = min(minY, start.y, end.y)
            maxY = max(maxY, start.y, end.y)
        }
        return (count, minX, maxX, minY, maxY)
    }

    /// isocp.shx glyphs O, G, R are built from clockwise octant arcs
    /// (opcode 10 spec bytes 0xC4/0x84, 0xE2/0xC2, 0xA4). The SHX spec byte
    /// `(-)0SC` is sign-magnitude: bit 7 is the direction, bits 6-4 the start
    /// octant, bits 2-0 the octant count. Decoding it via Int8/abs (two's
    /// complement) rotates every clockwise arc and can triple its sweep.
    /// Correct glyph-space bounds for all three caps are x 6...26, y 2...38
    /// (world Y negated), with segment counts O=38, G=23, R=22.
    func testClockwiseOctantArcGlyphs() throws {
        let font = try loadIsocp()

        let o = lineBounds(font, "O")
        XCTAssertEqual(o.count, 38)
        XCTAssertEqual(o.minX, 6.0, accuracy: 0.02)
        XCTAssertEqual(o.maxX, 26.0, accuracy: 0.02)
        XCTAssertEqual(o.minY, -38.0, accuracy: 0.02)
        XCTAssertEqual(o.maxY, -2.0, accuracy: 0.02)

        let g = lineBounds(font, "G")
        XCTAssertEqual(g.count, 23)
        XCTAssertEqual(g.minX, 6.0, accuracy: 0.02)
        XCTAssertEqual(g.maxX, 26.0, accuracy: 0.02)
        XCTAssertEqual(g.minY, -38.0, accuracy: 0.02)
        XCTAssertEqual(g.maxY, -2.0, accuracy: 0.02)

        let r = lineBounds(font, "R")
        XCTAssertEqual(r.count, 22)
        XCTAssertEqual(r.minX, 6.0, accuracy: 0.02)
        XCTAssertEqual(r.maxX, 26.0, accuracy: 0.02)
        XCTAssertEqual(r.minY, -38.0, accuracy: 0.02)
        XCTAssertEqual(r.maxY, -2.0, accuracy: 0.02)

        // Advance width is the glyph's final pen X, so a mis-decoded arc also
        // shifts the following character. Both caps advance 32 units:
        // "GO" spans x 6...58 (32 + O's maxX 26) in 61 segments.
        let go = lineBounds(font, "GO")
        XCTAssertEqual(go.count, 61)
        XCTAssertEqual(go.minX, 6.0, accuracy: 0.02)
        XCTAssertEqual(go.maxX, 58.0, accuracy: 0.02)
    }

    /// Fractional arcs (opcode 11) carry an octant *span* like opcode 10,
    /// not an absolute end octant: the arc ends in octant
    /// `start ± span ∓ 1` at endOffset/256 of an octant past that boundary,
    /// with offsets applied in the direction of travel and an end offset
    /// of 0 meaning a full offset (256). isocp "9" (spec 0x62) is the
    /// canonical case: as an absolute end octant its bowl lands at
    /// x -11.9...22.1, y 2...56 with advance 10.1; correctly decoded it
    /// sits in the same box as every other digit, advance 28.14.
    func testFractionalArcNine() throws {
        let font = try loadIsocp()

        let nine = lineBounds(font, "9")
        XCTAssertEqual(nine.count, 38)
        XCTAssertEqual(nine.minX, 6.144, accuracy: 0.05)
        XCTAssertEqual(nine.maxX, 22.144, accuracy: 0.05)
        XCTAssertEqual(nine.minY, -38.021, accuracy: 0.05)
        XCTAssertEqual(nine.maxY, -2.0, accuracy: 0.05)

        // Advance 28.144: second "9" starts there, so "99" ends at 50.289.
        let nn = lineBounds(font, "99")
        XCTAssertEqual(nn.count, 76)
        XCTAssertEqual(nn.maxX, 50.289, accuracy: 0.05)
    }

    /// "§" (167) uses fractional arcs in both directions, including isocp's
    /// only clockwise one (spec byte 0xE6). "&" (38) uses a CCW fractional
    /// arc. Both must stay inside the cap-height box and return to the
    /// baseline metrics these bounds pin down.
    func testFractionalArcSectionAndAmpersand() throws {
        let font = try loadIsocp()

        let s = lineBounds(font, "§")
        XCTAssertEqual(s.count, 88)
        XCTAssertEqual(s.minX, 5.674, accuracy: 0.05)
        XCTAssertEqual(s.maxX, 17.674, accuracy: 0.05)
        XCTAssertEqual(s.minY, -37.942, accuracy: 0.05)
        XCTAssertEqual(s.maxY, -1.963, accuracy: 0.05)

        let a = lineBounds(font, "&")
        XCTAssertEqual(a.count, 44)
        XCTAssertEqual(a.minX, 5.998, accuracy: 0.05)
        XCTAssertEqual(a.maxX, 30.0, accuracy: 0.05)
        XCTAssertEqual(a.minY, -38.051, accuracy: 0.05)
        XCTAssertEqual(a.maxY, -1.815, accuracy: 0.05)
    }

    /// "B" uses only counter-clockwise octant arcs (spec byte 0x64) and
    /// decoded correctly even before the sign-magnitude fix; it must not
    /// change. 40 segments, x 6...26, glyph y 2...38.
    func testCounterClockwiseOctantArcGlyphUnchanged() throws {
        let font = try loadIsocp()

        let b = lineBounds(font, "B")
        XCTAssertEqual(b.count, 40)
        XCTAssertEqual(b.minX, 6.0, accuracy: 0.02)
        XCTAssertEqual(b.maxX, 26.0, accuracy: 0.02)
        XCTAssertEqual(b.minY, -38.0, accuracy: 0.02)
        XCTAssertEqual(b.maxY, -2.0, accuracy: 0.02)
    }
}
