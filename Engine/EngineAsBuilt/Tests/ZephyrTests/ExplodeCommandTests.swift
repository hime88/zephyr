import XCTest
@testable import ZephyrCore

@MainActor
final class ExplodeCommandTests: XCTestCase {

    func testExplodeRectangleGeneratesFourSeparateLines() {
        let doc = CADDocument()
        let layer = Layer(name: "0", color: .white)
        doc.importLayersBlocksEntities(layers: [layer], blocks: [], entities: [])

        let origin = Vector3(x: 10, y: 20, z: 0)
        let size = Vector3(x: 100, y: 50, z: 0)
        let rectEntity = CADEntity(
            layerID: layer.handle,
            localGeometry: [.rect(origin: origin, size: size, color: nil)]
        )
        doc.addEntity(rectEntity)

        XCTAssertNotNil(doc.entity(for: rectEntity.handle))
        XCTAssertEqual(doc.allEntities.count, 1)

        let newHandles = doc.explodeEntities(handles: [rectEntity.handle])
        XCTAssertEqual(newHandles.count, 4)

        // Original rect must be removed
        XCTAssertNil(doc.entity(for: rectEntity.handle))
        XCTAssertEqual(doc.allEntities.count, 4)

        // All 4 new entities must be independent lines
        var lineSegments: [(Vector3, Vector3)] = []
        for handle in newHandles {
            guard let ent = doc.entity(for: handle) else {
                XCTFail("New entity handle not found in document")
                continue
            }
            guard let geom = ent.localGeometry, geom.count == 1 else {
                XCTFail("Expected single primitive in exploded entity")
                continue
            }
            guard case let .line(start, end, _) = geom[0] else {
                XCTFail("Expected .line primitive in exploded entity")
                continue
            }
            lineSegments.append((start, end))
        }

        XCTAssertEqual(lineSegments.count, 4)

        let expectedEdges = [
            (Vector3(x: 10, y: 20, z: 0), Vector3(x: 110, y: 20, z: 0)),
            (Vector3(x: 110, y: 20, z: 0), Vector3(x: 110, y: 70, z: 0)),
            (Vector3(x: 110, y: 70, z: 0), Vector3(x: 10, y: 70, z: 0)),
            (Vector3(x: 10, y: 70, z: 0), Vector3(x: 10, y: 20, z: 0))
        ]

        for (expStart, expEnd) in expectedEdges {
            let found = lineSegments.contains { seg in
                (seg.0.distance(to: expStart) < 1e-6 && seg.1.distance(to: expEnd) < 1e-6) ||
                (seg.0.distance(to: expEnd) < 1e-6 && seg.1.distance(to: expStart) < 1e-6)
            }
            XCTAssertTrue(found, "Expected edge between \(expStart) and \(expEnd)")
        }

        // Test Undo
        doc.undo()
        XCTAssertNotNil(doc.entity(for: rectEntity.handle))
        XCTAssertEqual(doc.allEntities.count, 1)
        for handle in newHandles {
            XCTAssertNil(doc.entity(for: handle))
        }

        // Test Redo
        doc.redo()
        XCTAssertNil(doc.entity(for: rectEntity.handle))
        XCTAssertEqual(doc.allEntities.count, 4)
        for handle in newHandles {
            XCTAssertNotNil(doc.entity(for: handle))
        }
    }

    func testExplodeTransformedRectangle() {
        let doc = CADDocument()
        let layer = Layer(name: "0", color: .white)
        doc.importLayersBlocksEntities(layers: [layer], blocks: [], entities: [])

        let origin = Vector3(x: 0, y: 0, z: 0)
        let size = Vector3(x: 10, y: 5, z: 0)
        let transform = Transform3D.translated(by: Vector3(x: 100, y: 200, z: 0))
        let rectEntity = CADEntity(
            layerID: layer.handle,
            localGeometry: [.rect(origin: origin, size: size, color: nil)],
            transform: transform
        )
        doc.addEntity(rectEntity)

        let newHandles = doc.explodeEntities(handles: [rectEntity.handle])
        XCTAssertEqual(newHandles.count, 4)

        // In world coordinates, origin is at (100, 200) and max corner is at (110, 205)
        var starts: [Vector3] = []
        var ends: [Vector3] = []
        for handle in newHandles {
            guard let ent = doc.entity(for: handle),
                  let geom = ent.localGeometry,
                  case let .line(s, e, _) = geom[0] else {
                XCTFail("Expected line")
                continue
            }
            starts.append(s)
            ends.append(e)
        }

        let allPoints = starts + ends
        XCTAssertTrue(allPoints.contains { $0.distance(to: Vector3(x: 100, y: 200, z: 0)) < 1e-6 })
        XCTAssertTrue(allPoints.contains { $0.distance(to: Vector3(x: 110, y: 200, z: 0)) < 1e-6 })
        XCTAssertTrue(allPoints.contains { $0.distance(to: Vector3(x: 110, y: 205, z: 0)) < 1e-6 })
        XCTAssertTrue(allPoints.contains { $0.distance(to: Vector3(x: 100, y: 205, z: 0)) < 1e-6 })
    }

    func testExplodePolygonGeneratesLineSegments() {
        let doc = CADDocument()
        let layer = Layer(name: "0", color: .white)
        doc.importLayersBlocksEntities(layers: [layer], blocks: [], entities: [])

        let pts = [
            Vector3(x: 0, y: 0, z: 0),
            Vector3(x: 30, y: 0, z: 0),
            Vector3(x: 15, y: 20, z: 0)
        ]
        let polygonEntity = CADEntity(
            layerID: layer.handle,
            localGeometry: [.polygon(points: pts, color: nil)]
        )
        doc.addEntity(polygonEntity)

        let newHandles = doc.explodeEntities(handles: [polygonEntity.handle])
        XCTAssertEqual(newHandles.count, 3)
        XCTAssertNil(doc.entity(for: polygonEntity.handle))
    }

    func testExplodePolylineGeneratesSegments() {
        let doc = CADDocument()
        let layer = Layer(name: "0", color: .white)
        doc.importLayersBlocksEntities(layers: [layer], blocks: [], entities: [])

        let polyline = CADPolyline(points: [
            Vector3(x: 0, y: 0, z: 0),
            Vector3(x: 10, y: 0, z: 0),
            Vector3(x: 10, y: 10, z: 0)
        ], isClosed: false)

        let entity = CADEntity(
            layerID: layer.handle,
            localGeometry: [.polyline(path: polyline, color: nil)]
        )
        doc.addEntity(entity)

        let newHandles = doc.explodeEntities(handles: [entity.handle])
        XCTAssertEqual(newHandles.count, 2)
        XCTAssertNil(doc.entity(for: entity.handle))
    }

    func testExplodeBlockReferenceGeneratesLooseEntities() {
        let doc = CADDocument()
        let layer = Layer(name: "0", color: .white)
        let block = CADBlock(
            name: "TestBlock",
            geometry: [
                .line(start: Vector3(x: 0, y: 0, z: 0), end: Vector3(x: 5, y: 0, z: 0), color: nil),
                .circle(center: Vector3(x: 10, y: 10, z: 0), radius: 2.0, color: nil)
            ]
        )
        doc.importLayersBlocksEntities(layers: [layer], blocks: [block], entities: [])

        let instance = CADEntity(
            layerID: layer.handle,
            blockID: block.handle,
            transform: .translated(by: Vector3(x: 50, y: 50, z: 0))
        )
        doc.addEntity(instance)

        let newHandles = doc.explodeEntities(handles: [instance.handle])
        XCTAssertEqual(newHandles.count, 2)
        XCTAssertNil(doc.entity(for: instance.handle))

        var foundLine = false
        var foundCircle = false
        for handle in newHandles {
            guard let ent = doc.entity(for: handle), let geom = ent.localGeometry?.first else { continue }
            switch geom {
            case .line(let s, let e, _):
                foundLine = true
                XCTAssertEqual(s.x, 50, accuracy: 1e-6)
                XCTAssertEqual(s.y, 50, accuracy: 1e-6)
                XCTAssertEqual(e.x, 55, accuracy: 1e-6)
                XCTAssertEqual(e.y, 50, accuracy: 1e-6)
            case .polygon:
                // Note: CADGeometryMath.transformPrimitives converts circle to polygon approximation
                foundCircle = true
            default:
                break
            }
        }
        XCTAssertTrue(foundLine)
        XCTAssertTrue(foundCircle)
    }

    func testExplodeSingleLineDoesNothing() {
        let doc = CADDocument()
        let layer = Layer(name: "0", color: .white)
        doc.importLayersBlocksEntities(layers: [layer], blocks: [], entities: [])

        let lineEntity = CADEntity(
            layerID: layer.handle,
            localGeometry: [.line(start: Vector3(x: 0, y: 0, z: 0), end: Vector3(x: 10, y: 0, z: 0), color: nil)]
        )
        doc.addEntity(lineEntity)

        let newHandles = doc.explodeEntities(handles: [lineEntity.handle])
        XCTAssertTrue(newHandles.isEmpty)
        XCTAssertNotNil(doc.entity(for: lineEntity.handle))
    }
}
