import XCTest
@testable import ZephyrCore

/// Unit 7 (xref plan): synthetic heavy-set measurements — a 200k-
/// primitive block for interaction latency and 20 blocks × 50k
/// (1M primitives) for full regen. Budgets are generous regression
/// fences (debug builds); the printed timings are the recorded
/// numbers the plan asks for.
@MainActor
final class XrefHeavyPerfTests: XCTestCase {

    private func makeLineBlock(count: Int, name: String) -> CADBlock {
        let geometry: [CADPrimitive] = (0..<count).map { i in
            .line(start: Vector3(x: 0, y: Double(i), z: 0),
                  end: Vector3(x: 100, y: Double(i), z: 0), color: nil)
        }
        return CADBlock(name: name, geometry: geometry)
    }

    private func elapsed(_ label: String, _ body: () -> Void) -> Double {
        let start = Date()
        body()
        let seconds = Date().timeIntervalSince(start)
        print("[XrefHeavyPerf] \(label): \(String(format: "%.3f", seconds))s")
        return seconds
    }

    func testInteractionLatencyOver200kBlock() {
        let block = makeLineBlock(count: 200_000, name: "Huge")
        let doc = CADDocument()
        let layer = Layer(name: "0", color: .white)
        let entity = CADEntity(layerID: layer.handle, blockID: block.handle, transform: .identity)
        doc.importLayersBlocksEntities(layers: [layer], blocks: [block], entities: [entity])
        doc.rebuildEntityGrid()
        XCTAssertNotNil(doc.spatialGrid(forBlock: block.handle))
        let stored = doc.allEntities.first { $0.handle == entity.handle } ?? entity

        // Hover hit-test in the middle of the block, 20 samples.
        var hit: UUID?
        let hitSeconds = elapsed("hitTest x20 over 200k") {
            for _ in 0..<20 {
                hit = CADHitTesting.hitTest(
                    worldX: 50, worldY: 100_000, document: doc,
                    threshold: 0.25, simplifyComplexBlocks: false)
            }
        }
        XCTAssertEqual(hit, entity.handle)
        XCTAssertLessThan(hitSeconds / 20, 0.05, "hover must stay under 50ms")

        // Endpoint snap inside the block, 20 samples.
        let engine = SnapEngine()
        var snapFound = false
        let snapSeconds = elapsed("snap x20 over 200k") {
            for _ in 0..<20 {
                snapFound = engine.nearestSnap(
                    worldX: 100.2, worldY: 150_000.1,
                    entities: [stored], threshold: 1.0,
                    resolveGeometry: { doc.resolvedGeometry(for: $0) },
                    spatialGrid: { doc.spatialGrid(for: $0) }) != nil
            }
        }
        XCTAssertTrue(snapFound)
        XCTAssertLessThan(snapSeconds / 20, 0.05, "snap must stay under 50ms")

        // Crossing-rect query over a small region, 20 samples.
        var intersects = false
        let rectSeconds = elapsed("rectSelect x20 over 200k") {
            for _ in 0..<20 {
                intersects = CADRectSelect.entityIntersectsRect(
                    stored,
                    rectMin: Vector3(x: 40, y: 120_000.4, z: 0),
                    rectMax: Vector3(x: 60, y: 120_000.6, z: 0), document: doc)
            }
        }
        XCTAssertFalse(intersects, "rect sits between lines 120000 and 120001")
        XCTAssertLessThan(rectSeconds / 20, 0.05, "rect-select must stay under 50ms")
    }

    func testRegenOneMillionPrimitives() async {
        let doc = CADDocument()
        let layer = Layer(name: "0", color: .white)
        var blocks: [CADBlock] = []
        var entities: [CADEntity] = []
        for index in 0..<20 {
            let block = makeLineBlock(count: 50_000, name: "Ref\(index)")
            blocks.append(block)
            entities.append(CADEntity(
                layerID: layer.handle, blockID: block.handle, transform: .identity))
        }
        doc.importLayersBlocksEntities(layers: [layer], blocks: blocks, entities: entities)
        doc.rebuildEntityGrid()

        let start = Date()
        let results = await CADRendererBridge.computeSpecs(
            fromSnapshot: doc.snapshot(), simplifyComplexBlocks: false)
        let seconds = Date().timeIntervalSince(start)
        let totalSpecs = results.reduce(0) { $0 + $1.specs.count }
        print("[XrefHeavyPerf] computeSpecs 20x50k: \(String(format: "%.3f", seconds))s, \(totalSpecs) specs")
        XCTAssertEqual(totalSpecs, 1_000_000)
        XCTAssertLessThan(seconds, 60, "1M-primitive regen regression fence (debug)")
    }
}
