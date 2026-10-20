import XCTest
@testable import ZephyrCore

/// Unit 3b (xref plan): per-block spatial grid correctness (parity with
/// linear scan), grid-backed snapping, SIMPLIFY exemption for xrefs,
/// and a generous interaction-latency budget over a large block.
@MainActor
final class XrefInteractionPerfTests: XCTestCase {

    /// Block of `count` horizontal lines, line i from (0,i) to (10,i).
    private func makeLineBlock(count: Int, name: String = "BigBlock") -> CADBlock {
        let geometry: [CADPrimitive] = (0..<count).map { i in
            .line(start: Vector3(x: 0, y: Double(i), z: 0),
                  end: Vector3(x: 10, y: Double(i), z: 0), color: nil)
        }
        return CADBlock(name: name, geometry: geometry)
    }

    private func makeDoc(block: CADBlock) -> (CADDocument, CADEntity) {
        let doc = CADDocument()
        let layer = Layer(name: "0", color: .white)
        let entity = CADEntity(layerID: layer.handle, blockID: block.handle, transform: .identity)
        doc.importLayersBlocksEntities(layers: [layer], blocks: [block], entities: [entity])
        doc.rebuildEntityGrid()
        return (doc, entity)
    }

    func testGridCandidatesAreSupersetOfRectHits() {
        let block = makeLineBlock(count: 400)
        let grid = CADBlockSpatialGrid(primitives: block.geometry)
        // Rect covering y in [99.5, 102.5]: lines 100, 101, 102 must appear.
        let candidates = Set(grid.candidateIndices(minX: -1, minY: 99.5, maxX: 11, maxY: 102.5))
        XCTAssertTrue(candidates.isSuperset(of: [100, 101, 102]))
        XCTAssertLessThan(candidates.count, 200, "grid must actually cull")
    }

    func testHitTestParityAndSnapInsideBigBlock() {
        let block = makeLineBlock(count: 400)
        let (doc, entity) = makeDoc(block: block)
        XCTAssertNotNil(doc.spatialGrid(forBlock: block.handle))

        // On line 250 → hit; in the gap between lines → miss.
        XCTAssertEqual(
            CADHitTesting.hitTest(
                worldX: 5, worldY: 250, document: doc,
                threshold: 0.25, simplifyComplexBlocks: false),
            entity.handle)
        XCTAssertNil(
            CADHitTesting.hitTest(
                worldX: 5, worldY: 250.5, document: doc,
                threshold: 0.25, simplifyComplexBlocks: false))

        // Rectangle-crossing parity.
        XCTAssertTrue(CADRectSelect.entityIntersectsRect(
            entity,
            rectMin: Vector3(x: 4, y: 249.5, z: 0),
            rectMax: Vector3(x: 6, y: 250.5, z: 0), document: doc))
        XCTAssertFalse(CADRectSelect.entityIntersectsRect(
            entity,
            rectMin: Vector3(x: 20, y: 249.5, z: 0),
            rectMax: Vector3(x: 22, y: 250.5, z: 0), document: doc))

        // Endpoint snap inside a >100-primitive block: impossible via the
        // anchor cache (bbox-only above 100), must come from the grid.
        // (Use the stored entity: it carries prepared bounds/anchors.)
        let stored = doc.allEntities.first { $0.handle == entity.handle } ?? entity
        let engine = SnapEngine()
        let snap = engine.nearestSnap(
            worldX: 10.2, worldY: 250.1,
            entities: [stored], threshold: 1.0,
            resolveGeometry: { doc.resolvedGeometry(for: $0) },
            spatialGrid: { doc.spatialGrid(for: $0) })
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.worldPos.x ?? -1, 10, accuracy: 1e-9)
        XCTAssertEqual(snap?.worldPos.y ?? -1, 250, accuracy: 1e-9)
    }

    func testSimplifyExemptsXrefBlocks() async {
        let plain = makeLineBlock(count: 60, name: "Plain60")
        var xrefBlock = makeLineBlock(count: 60, name: "Ref60")
        xrefBlock.xrefDescriptor = CADXrefDescriptor(savedPath: "ref.dxf")

        func specCount(for block: CADBlock) async -> Int {
            let (doc, entity) = makeDoc(block: block)
            let results = await CADRendererBridge.computeSpecs(
                fromSnapshot: doc.snapshot(), simplifyComplexBlocks: true)
            return results.first { $0.handle == entity.handle }?.specs.count ?? 0
        }
        let plainCount = await specCount(for: plain)
        let xrefCount = await specCount(for: xrefBlock)
        XCTAssertGreaterThan(xrefCount, plainCount,
                             "xref must render real geometry under SIMPLIFY")
        XCTAssertGreaterThanOrEqual(xrefCount, 60)
    }

    func testLargeBlockHitTestLatencyBudget() {
        let block = makeLineBlock(count: 50_000)
        let (doc, entity) = makeDoc(block: block)
        XCTAssertNotNil(doc.spatialGrid(forBlock: block.handle))
        let start = Date()
        var hits = 0
        for i in 0..<50 {
            // Alternate hit (on a line) and miss (open space right of lines).
            let y = Double((i * 997) % 50_000)
            if CADHitTesting.hitTest(
                worldX: i.isMultiple(of: 2) ? 5 : 500, worldY: y,
                document: doc, threshold: 0.25, simplifyComplexBlocks: false
            ) == entity.handle { hits += 1 }
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(hits, 25)
        XCTAssertLessThan(elapsed, 2.0, "50 hover hit-tests over 50k prims took \(elapsed)s")
    }
}
