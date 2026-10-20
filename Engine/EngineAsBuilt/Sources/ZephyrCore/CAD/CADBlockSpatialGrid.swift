import Foundation

// =========================================================================
// MARK: - CADBlockSpatialGrid
//
// Local-space uniform grid over a block's primitives, built once for
// large blocks (loaded xrefs especially: one entity can hold 500k+
// primitives spanning the whole viewport, so entity-level broad-phase
// never rejects it). Hit-testing, snapping, and rectangle selection
// query only the cells near the cursor instead of scanning everything.
// =========================================================================

public struct CADBlockSpatialGrid: Sendable {
    /// Blocks at or below this many primitives scan linearly.
    public static let buildThreshold = 200

    public let bounds: BoundingBox3D
    public let primitiveCount: Int
    private let originX: Double
    private let originY: Double
    private let cellWidth: Double
    private let cellHeight: Double
    private let columns: Int
    private let rows: Int
    private let cells: [[Int]]

    public init(primitives: [CADPrimitive]) {
        self.primitiveCount = primitives.count
        var boxes: [BoundingBox3D] = []
        boxes.reserveCapacity(primitives.count)
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for prim in primitives {
            let box = CADBlock.computeBoundingBox(from: [prim])
            boxes.append(box)
            minX = min(minX, box.min.x); minY = min(minY, box.min.y)
            maxX = max(maxX, box.max.x); maxY = max(maxY, box.max.y)
        }
        if !minX.isFinite {
            minX = 0; minY = 0; maxX = 0; maxY = 0
        }
        self.bounds = BoundingBox3D(
            min: Vector3(x: minX, y: minY, z: 0),
            max: Vector3(x: maxX, y: maxY, z: 0))
        self.originX = minX
        self.originY = minY
        // Aim for roughly 8 primitives per cell, capped at 128×128.
        let side = max(1, min(128, Int(ceil(sqrt(Double(max(primitives.count, 1)) / 8.0)))))
        self.columns = side
        self.rows = side
        let extentX = max(maxX - minX, 0)
        let extentY = max(maxY - minY, 0)
        self.cellWidth = extentX > 0 ? extentX / Double(side) : 1
        self.cellHeight = extentY > 0 ? extentY / Double(side) : 1

        var cells = [[Int]](repeating: [], count: side * side)
        for (index, box) in boxes.enumerated() {
            let colRange = Self.cellRange(
                min: box.min.x, max: box.max.x, origin: minX,
                cell: cellWidth, count: side)
            let rowRange = Self.cellRange(
                min: box.min.y, max: box.max.y, origin: minY,
                cell: cellHeight, count: side)
            for row in rowRange {
                for col in colRange {
                    cells[row * side + col].append(index)
                }
            }
        }
        self.cells = cells
    }

    private static func cellRange(
        min minV: Double, max maxV: Double, origin: Double, cell: Double, count: Int
    ) -> ClosedRange<Int> {
        guard cell > 0, minV.isFinite, maxV.isFinite else { return 0...0 }
        let lo = Int(floor((minV - origin) / cell))
        let hi = Int(floor((maxV - origin) / cell))
        return max(0, min(count - 1, lo))...max(0, min(count - 1, hi))
    }

    /// Primitive indices whose cells intersect the local-space rect
    /// (superset of true intersections; callers still test precisely).
    public func candidateIndices(minX: Double, minY: Double, maxX: Double, maxY: Double) -> [Int] {
        let colRange = Self.cellRange(
            min: minX, max: maxX, origin: originX, cell: cellWidth, count: columns)
        let rowRange = Self.cellRange(
            min: minY, max: maxY, origin: originY, cell: cellHeight, count: rows)
        var seen = Set<Int>()
        var out: [Int] = []
        for row in rowRange {
            for col in colRange {
                for index in cells[row * columns + col] where seen.insert(index).inserted {
                    out.append(index)
                }
            }
        }
        return out
    }

    public func candidateIndices(near point: Vector3, radius: Double) -> [Int] {
        candidateIndices(
            minX: point.x - radius, minY: point.y - radius,
            maxX: point.x + radius, maxY: point.y + radius)
    }
}
