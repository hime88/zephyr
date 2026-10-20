import XCTest
@testable import ZephyrCore

final class HatchIslandAndBackgroundTests: XCTestCase {

    func testHatchRibbonSettingsIslandStyleDefaultAndCustom() {
        let defaultSettings = HatchRibbonUI.Settings(
            fillType: 0,
            patternName: "ANSI31",
            scale: 1.0,
            angle: 0.0,
            primaryColor: nil,
            backgroundColor: nil,
            secondaryColor: nil,
            selectionMode: 0,
            showModeSection: true
        )
        XCTAssertEqual(defaultSettings.islandStyle, 0)

        var outerSettings = defaultSettings
        outerSettings.islandStyle = 1
        XCTAssertEqual(outerSettings.islandStyle, 1)

        var ignoreSettings = defaultSettings
        ignoreSettings.islandStyle = 2
        XCTAssertEqual(ignoreSettings.islandStyle, 2)
    }

    func testClassifyLoopsNormalStyleAlternatesIslands() {
        // Outer loop A: 0..100
        let loopA = [
            Vector3(x: 0, y: 0, z: 0),
            Vector3(x: 100, y: 0, z: 0),
            Vector3(x: 100, y: 100, z: 0),
            Vector3(x: 0, y: 100, z: 0)
        ]
        // Island loop B: 20..80 (inside A)
        let loopB = [
            Vector3(x: 20, y: 20, z: 0),
            Vector3(x: 80, y: 20, z: 0),
            Vector3(x: 80, y: 80, z: 0),
            Vector3(x: 20, y: 80, z: 0)
        ]
        // Island loop C: 40..60 (inside B)
        let loopC = [
            Vector3(x: 40, y: 40, z: 0),
            Vector3(x: 60, y: 40, z: 0),
            Vector3(x: 60, y: 60, z: 0),
            Vector3(x: 40, y: 60, z: 0)
        ]

        let regions = CADBoundaryDetector.classifyLoops([loopA, loopB, loopC], islandStyle: 0)
        // In Normal style:
        // Region 1: Outer loop A with hole loop B
        // Region 2: Outer loop C with 0 holes (nested island hatched)
        XCTAssertEqual(regions.count, 2)

        let region1 = regions.first(where: { $0.outer.count == 4 && $0.holes.count == 1 })
        XCTAssertNotNil(region1)
        XCTAssertEqual(region1?.holes.count, 1)

        let region2 = regions.first(where: { $0.outer.count == 4 && $0.holes.isEmpty })
        XCTAssertNotNil(region2)
    }

    func testClassifyLoopsOuterStyleOnlyHatchesOuterToFirstIsland() {
        let loopA = [
            Vector3(x: 0, y: 0, z: 0),
            Vector3(x: 100, y: 0, z: 0),
            Vector3(x: 100, y: 100, z: 0),
            Vector3(x: 0, y: 100, z: 0)
        ]
        let loopB = [
            Vector3(x: 20, y: 20, z: 0),
            Vector3(x: 80, y: 20, z: 0),
            Vector3(x: 80, y: 80, z: 0),
            Vector3(x: 20, y: 80, z: 0)
        ]
        let loopC = [
            Vector3(x: 40, y: 40, z: 0),
            Vector3(x: 60, y: 40, z: 0),
            Vector3(x: 60, y: 60, z: 0),
            Vector3(x: 40, y: 60, z: 0)
        ]

        let regions = CADBoundaryDetector.classifyLoops([loopA, loopB, loopC], islandStyle: 1)
        // In Outer style:
        // Only 1 region: Outer loop A with hole loop B. Inner island C is NOT hatched.
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].holes.count, 1)
    }

    func testClassifyLoopsIgnoreStyleHatchesEntireOuterIgnoringIslands() {
        let loopA = [
            Vector3(x: 0, y: 0, z: 0),
            Vector3(x: 100, y: 0, z: 0),
            Vector3(x: 100, y: 100, z: 0),
            Vector3(x: 0, y: 100, z: 0)
        ]
        let loopB = [
            Vector3(x: 20, y: 20, z: 0),
            Vector3(x: 80, y: 20, z: 0),
            Vector3(x: 80, y: 80, z: 0),
            Vector3(x: 20, y: 80, z: 0)
        ]
        let loopC = [
            Vector3(x: 40, y: 40, z: 0),
            Vector3(x: 60, y: 40, z: 0),
            Vector3(x: 60, y: 60, z: 0),
            Vector3(x: 40, y: 60, z: 0)
        ]

        let regions = CADBoundaryDetector.classifyLoops([loopA, loopB, loopC], islandStyle: 2)
        // In Ignore style:
        // 1 region: Outer loop A with 0 holes. All islands B and C are ignored.
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].holes.count, 0)
    }

    func testHatchPathBackgroundColorPreservation() {
        let outer = CADPolyline(points: [
            Vector3(x: 0, y: 0, z: 0),
            Vector3(x: 50, y: 0, z: 0),
            Vector3(x: 50, y: 50, z: 0),
            Vector3(x: 0, y: 50, z: 0)
        ], isClosed: true)

        let yellowBg = ColorRGBA(r: 255, g: 255, b: 0, a: 255)
        let hatchPrimWithBg = CADPrimitive.hatchPath(
            boundary: outer,
            holes: [],
            pattern: "ANSI31",
            scale: 1.0,
            angle: 0.0,
            color: ColorRGBA(r: 0, g: 0, b: 0, a: 255),
            backgroundColor: yellowBg
        )

        guard case .hatchPath(_, _, _, _, _, _, let bg) = hatchPrimWithBg else {
            XCTFail("Expected hatchPath primitive")
            return
        }
        XCTAssertEqual(bg, yellowBg)

        // Verify removing background color
        let hatchPrimNoBg = CADPrimitive.hatchPath(
            boundary: outer,
            holes: [],
            pattern: "ANSI31",
            scale: 1.0,
            angle: 0.0,
            color: ColorRGBA(r: 0, g: 0, b: 0, a: 255),
            backgroundColor: nil
        )

        guard case .hatchPath(_, _, _, _, _, _, let bgNone) = hatchPrimNoBg else {
            XCTFail("Expected hatchPath primitive")
            return
        }
        XCTAssertNil(bgNone)
    }

    func testHatchPrimitiveGeneratorEmitsFillSpecOnlyWhenBackgroundColorPresent() {
        let outer = CADPolyline(points: [
            Vector3(x: 0, y: 0, z: 0),
            Vector3(x: 100, y: 0, z: 0),
            Vector3(x: 100, y: 100, z: 0),
            Vector3(x: 0, y: 100, z: 0)
        ], isClosed: true)

        let yellowBg = ColorRGBA(r: 255, g: 255, b: 0, a: 255)
        let primWithBg = CADPrimitive.hatchPath(
            boundary: outer,
            holes: [],
            pattern: "ANSI31",
            scale: 1.0,
            angle: 0.0,
            color: ColorRGBA(r: 0, g: 0, b: 0, a: 255),
            backgroundColor: yellowBg
        )

        let specsWithBg = CADPrimitiveGenerator.computePrimitiveSpecs(
            from: primWithBg,
            transform: .identity,
            color: (0, 0, 0, 255),
            z: 0.0)

        // When backgroundColor is set, CADTessellator.computeMultiLoopFillSpecs generates a .fillRect spec
        let fillSpecsWithBg = specsWithBg.filter { $0.type == .fillRect }
        XCTAssertEqual(fillSpecsWithBg.count, 1, "Expected 1 background fill spec when background color is present")

        let primNoBg = CADPrimitive.hatchPath(
            boundary: outer,
            holes: [],
            pattern: "ANSI31",
            scale: 1.0,
            angle: 0.0,
            color: ColorRGBA(r: 0, g: 0, b: 0, a: 255),
            backgroundColor: nil
        )

        let specsNoBg = CADPrimitiveGenerator.computePrimitiveSpecs(
            from: primNoBg,
            transform: .identity,
            color: (0, 0, 0, 255),
            z: 0.0)

        let fillSpecsNoBg = specsNoBg.filter { $0.type == .fillRect }
        XCTAssertEqual(fillSpecsNoBg.count, 0, "Expected 0 background fill specs when background color is nil")
        XCTAssertEqual(specsNoBg.count, specsWithBg.count - 1, "Unchecking background color must reduce specs by exactly 1")
    }

    @MainActor
    func testHatchCommandInitFromEntityWithAndWithoutBackground() {
        let outer = CADPolyline(points: [
            Vector3(x: 0, y: 0, z: 0),
            Vector3(x: 50, y: 0, z: 0),
            Vector3(x: 50, y: 50, z: 0),
            Vector3(x: 0, y: 50, z: 0)
        ], isClosed: true)
        let yellowBg = ColorRGBA(r: 255, g: 255, b: 0, a: 255)
        let prim = CADPrimitive.hatchPath(
            boundary: outer,
            holes: [],
            pattern: "ANSI32",
            scale: 2.5,
            angle: 0.785,
            color: ColorRGBA(r: 10, g: 20, b: 30, a: 255),
            backgroundColor: yellowBg
        )
        var entity = CADEntity(layerID: UUID(), localGeometry: [prim])
        entity.xdata["zephyr.hatchBackgroundColor"] = .string("#FFFF00FF")
        entity.xdata["dxf.hatchStyle"] = .int(2)

        let cmd = HatchCommand()
        cmd.initFromEntity(entity)

        XCTAssertEqual(cmd.currentFillType, 0)
        XCTAssertEqual(cmd.currentPatternName, "ANSI32")
        XCTAssertEqual(cmd.currentBackgroundColor, yellowBg)
        XCTAssertEqual(cmd.currentIslandStyle, 2)

        // Now test entity where background color was unchecked / removed
        let primNoBg = CADPrimitive.hatchPath(
            boundary: outer,
            holes: [],
            pattern: "ANSI31",
            scale: 1.0,
            angle: 0.0,
            color: nil,
            backgroundColor: nil
        )
        var entityNoBg = CADEntity(layerID: UUID(), localGeometry: [primNoBg])
        entityNoBg.xdata["dxf.hatchStyle"] = .int(1)

        let cmd2 = HatchCommand()
        cmd2.initFromEntity(entityNoBg)

        XCTAssertEqual(cmd2.currentFillType, 0)
        XCTAssertEqual(cmd2.currentPatternName, "ANSI31")
        XCTAssertNil(cmd2.currentBackgroundColor)
        XCTAssertEqual(cmd2.currentIslandStyle, 1)
    }

    @MainActor
    func testHatchRibbonLastUsedBackgroundColorPreservation() {
        HatchRibbonUI.lastUsedBackgroundColor = ColorRGBA(r: 40, g: 220, b: 240, a: 255)
        XCTAssertEqual(HatchRibbonUI.lastUsedBackgroundColor, ColorRGBA(r: 40, g: 220, b: 240, a: 255))
    }
}
