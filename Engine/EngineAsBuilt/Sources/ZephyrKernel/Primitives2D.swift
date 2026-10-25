import Foundation

// =========================================================================
// MARK: - Primitives2D
//
// Double-precision 2D primitives for the Zephyr geometry kernel.
// Design notes (see PLAN-kernel-perf.md R4):
//   * Value types throughout; Sendable + Hashable for Swift 6 concurrency.
//   * No Codable on hot-path types — persistence/Codable lives in
//     ZephyrCore's entity layer, never in per-query math.
//   * Bulge convention shared with CADPolyline: b = tan(sweep / 4).
//     |b| <= KernelTolerance.bulgeZero (1e-12, same as CADPolyline) means
//     a straight segment.

@frozen
public struct Point2d: Hashable, Sendable {
    public var x: Double
    public var y: Double

    @inlinable
    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2d(x: 0, y: 0)

    @inlinable
    public func distance(to other: Point2d) -> Double {
        hypot(other.x - x, other.y - y)
    }

    @inlinable
    public func distanceSquared(to other: Point2d) -> Double {
        let dx = other.x - x
        let dy = other.y - y
        return dx * dx + dy * dy
    }

    @inlinable
    public func translated(by v: Vec2d) -> Point2d {
        Point2d(x: x + v.x, y: y + v.y)
    }

    @inlinable
    public static func - (lhs: Point2d, rhs: Point2d) -> Vec2d {
        Vec2d(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    @inlinable
    public static func + (lhs: Point2d, rhs: Vec2d) -> Point2d {
        Point2d(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}

@frozen
public struct Vec2d: Hashable, Sendable {
    public var x: Double
    public var y: Double

    @inlinable
    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }

    @inlinable
    public var length: Double { hypot(x, y) }

    @inlinable
    public var lengthSquared: Double { x * x + y * y }

    @inlinable
    public var normalized: Vec2d {
        let len = length
        guard len > KernelTolerance.linear else { return Vec2d(x: 0, y: 0) }
        return Vec2d(x: x / len, y: y / len)
    }

    /// 90-degree counter-clockwise perpendicular (-y, x).
    @inlinable
    public var perpCCW: Vec2d { Vec2d(x: -y, y: x) }

    @inlinable
    public func dot(_ other: Vec2d) -> Double {
        x * other.x + y * other.y
    }

    /// 2D scalar cross product (z-component of the 3D cross product).
    @inlinable
    public func cross(_ other: Vec2d) -> Double {
        x * other.y - y * other.x
    }

    @inlinable
    public static func * (lhs: Vec2d, rhs: Double) -> Vec2d {
        Vec2d(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    @inlinable
    public static func + (lhs: Vec2d, rhs: Vec2d) -> Vec2d {
        Vec2d(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    @inlinable
    public static func - (lhs: Vec2d, rhs: Vec2d) -> Vec2d {
        Vec2d(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}

@frozen
public struct BoundingBox2d: Hashable, Sendable {
    public var min: Point2d
    public var max: Point2d

    @inlinable
    public init(min: Point2d, max: Point2d) {
        self.min = Point2d(x: Swift.min(min.x, max.x), y: Swift.min(min.y, max.y))
        self.max = Point2d(x: Swift.max(min.x, max.x), y: Swift.max(min.y, max.y))
    }

    @inlinable
    public init(point: Point2d) {
        self.min = point
        self.max = point
    }

    @inlinable
    public mutating func include(_ p: Point2d) {
        min.x = Swift.min(min.x, p.x); min.y = Swift.min(min.y, p.y)
        max.x = Swift.max(max.x, p.x); max.y = Swift.max(max.y, p.y)
    }

    @inlinable
    public func expanded(by amount: Double) -> BoundingBox2d {
        BoundingBox2d(
            min: Point2d(x: min.x - amount, y: min.y - amount),
            max: Point2d(x: max.x + amount, y: max.y + amount))
    }

    @inlinable
    public func intersects(_ other: BoundingBox2d, tolerance: Double = KernelTolerance.linear) -> Bool {
        !(other.min.x > max.x + tolerance ||
          other.max.x < min.x - tolerance ||
          other.min.y > max.y + tolerance ||
          other.max.y < min.y - tolerance)
    }

    @inlinable
    public func contains(_ p: Point2d, tolerance: Double = KernelTolerance.linear) -> Bool {
        p.x >= min.x - tolerance && p.x <= max.x + tolerance &&
        p.y >= min.y - tolerance && p.y <= max.y + tolerance
    }
}

@frozen
public struct LineSeg2d: Hashable, Sendable {
    public var start: Point2d
    public var end: Point2d

    @inlinable
    public init(start: Point2d, end: Point2d) {
        self.start = start
        self.end = end
    }

    @inlinable
    public var direction: Vec2d { (end - start).normalized }

    @inlinable
    public var length: Double { start.distance(to: end) }
}

@frozen
public struct Ray2d: Hashable, Sendable {
    public var origin: Point2d
    public var direction: Vec2d

    public init(origin: Point2d, direction: Vec2d) {
        self.origin = origin
        self.direction = direction.normalized
    }
}

@frozen
public struct XLine2d: Hashable, Sendable {
    public var origin: Point2d
    public var direction: Vec2d

    public init(origin: Point2d, direction: Vec2d) {
        self.origin = origin
        self.direction = direction.normalized
    }
}

/// Directed circular arc in 2D world space.
/// `sweep` is signed radians: positive = CCW, negative = CW.
@frozen
public struct Arc2d: Hashable, Sendable {
    public var center: Point2d
    public var radius: Double
    public var startAngle: Double
    public var sweep: Double

    public init(center: Point2d, radius: Double, startAngle: Double, sweep: Double) {
        self.center = center
        self.radius = radius
        self.startAngle = startAngle
        self.sweep = sweep
    }

    /// Construct from DXF arc angles (always CCW from startAngle to endAngle).
    public static func fromDXFAngles(center: Point2d, radius: Double, startAngle: Double, endAngle: Double) -> Arc2d {
        var delta = (endAngle - startAngle).truncatingRemainder(dividingBy: 2.0 * .pi)
        if delta <= 0 { delta += 2.0 * .pi }
        return Arc2d(center: center, radius: radius, startAngle: startAngle, sweep: delta)
    }

    @inlinable
    public var endAngle: Double { startAngle + sweep }

    @inlinable
    public var isCCW: Bool { sweep >= 0 }

    @inlinable
    public var startPoint: Point2d {
        Point2d(x: center.x + radius * cos(startAngle), y: center.y + radius * sin(startAngle))
    }

    @inlinable
    public var endPoint: Point2d {
        let ea = endAngle
        return Point2d(x: center.x + radius * cos(ea), y: center.y + radius * sin(ea))
    }

    /// DXF LWPOLYLINE bulge for this directed arc: b = tan(sweep / 4).
    @inlinable
    public var bulge: Double {
        tan(sweep / 4.0)
    }

    /// Exact Arc2d from two LWPOLYLINE vertices and DXF bulge b = tan(theta/4).
    /// Returns nil when |bulge| is below KernelTolerance.bulgeZero (straight line).
    /// Formulation mirrors CADPolyline.arcParameters(forSegment:) so the two agree.
    public static func fromBulge(start: Point2d, end: Point2d, bulge: Double) -> Arc2d? {
        guard abs(bulge) > KernelTolerance.bulgeZero else { return nil }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let chord = hypot(dx, dy)
        guard chord > KernelTolerance.linear else { return nil }

        // Same closed form as CADPolyline.arcParameters: center offset from
        // chord midpoint by factor*( -dy, +dx ) with factor = (1-b^2)/(4b).
        let factor = (1.0 - bulge * bulge) / (4.0 * bulge)
        let center = Point2d(
            x: (start.x + end.x) * 0.5 - dy * factor,
            y: (start.y + end.y) * 0.5 + dx * factor)
        let radius = chord * (1.0 + bulge * bulge) / (4.0 * abs(bulge))
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        return Arc2d(center: center, radius: radius, startAngle: startAngle, sweep: 4.0 * atan(bulge))
    }
}

@frozen
public struct Circle2d: Hashable, Sendable {
    public var center: Point2d
    public var radius: Double

    public init(center: Point2d, radius: Double) {
        self.center = center
        self.radius = radius
    }

    public func toArc2d() -> Arc2d {
        Arc2d(center: center, radius: radius, startAngle: 0, sweep: 2.0 * .pi)
    }
}

/// Full ellipse: center + major-axis vector + minor/major ratio.
/// Parameterization: P(t) = center + majorAxis*cos(a) + minorAxis*sin(a),
/// a in [startAngle, startAngle + sweep]; sweep = 2pi for full ellipse.
@frozen
public struct Ellipse2d: Hashable, Sendable {
    public var center: Point2d
    public var majorAxis: Vec2d
    public var minorRatio: Double
    public var startAngle: Double
    public var sweep: Double

    public init(center: Point2d, majorAxis: Vec2d, minorRatio: Double,
                startAngle: Double = 0, sweep: Double = 2.0 * .pi) {
        self.center = center
        self.majorAxis = majorAxis
        self.minorRatio = minorRatio
        self.startAngle = startAngle
        self.sweep = sweep
    }

    @inlinable
    public var minorAxis: Vec2d {
        let m = majorAxis.perpCCW.normalized
        return m * (majorAxis.length * minorRatio)
    }

    @inlinable
    public var isFull: Bool { abs(abs(sweep) - 2.0 * .pi) <= 1e-9 }
}

/// Planar NURBS spline (world-space 2D projection; z is carried by the host).
/// Same De Boor mathematics as NURBSEvaluator (ZephyrCore), operating on
/// Point2d so the kernel keeps zero dependencies.
@frozen
public struct Spline2d: Hashable, Sendable {
    public var controlPoints: [Point2d]
    public var knots: [Double]
    public var degree: Int
    public var weights: [Double]?

    public init(controlPoints: [Point2d], knots: [Double], degree: Int, weights: [Double]? = nil) {
        self.controlPoints = controlPoints
        self.knots = knots
        self.degree = degree
        self.weights = weights
    }

    @inlinable
    public var isValid: Bool {
        degree >= 1 &&
        controlPoints.count >= 2 &&
        knots.count == controlPoints.count + degree + 1
    }
}

/// One segment of a polyline: exact line or bulged arc, preserving widths
/// and segment index so trimmed/offset segments round-trip to vertices.
@frozen
public struct PolySegment2d: Hashable, Sendable {
    public enum Geometry: Hashable, Sendable {
        case line(LineSeg2d)
        case arc(Arc2d)
    }

    public var index: Int
    public var geometry: Geometry
    public var startWidth: Double
    public var endWidth: Double

    public init(
        index: Int,
        start: Point2d,
        end: Point2d,
        bulge: Double,
        startWidth: Double = 0,
        endWidth: Double = 0
    ) {
        self.index = index
        self.startWidth = startWidth
        self.endWidth = endWidth
        if let arc = Arc2d.fromBulge(start: start, end: end, bulge: bulge) {
            self.geometry = .arc(arc)
        } else {
            self.geometry = .line(LineSeg2d(start: start, end: end))
        }
    }

    public init(index: Int, geometry: Geometry, startWidth: Double = 0, endWidth: Double = 0) {
        self.index = index
        self.geometry = geometry
        self.startWidth = startWidth
        self.endWidth = endWidth
    }

    public var startPoint: Point2d {
        switch geometry {
        case .line(let l): return l.start
        case .arc(let a): return a.startPoint
        }
    }

    public var endPoint: Point2d {
        switch geometry {
        case .line(let l): return l.end
        case .arc(let a): return a.endPoint
        }
    }

    public var bulge: Double {
        switch geometry {
        case .line: return 0.0
        case .arc(let a): return a.bulge
        }
    }
}

/// Unified sum type for any single parametric 2D curve in the kernel.
@frozen
public enum Curve2d: Hashable, Sendable {
    case line(LineSeg2d)
    case ray(Ray2d)
    case xline(XLine2d)
    case arc(Arc2d)
    case circle(Circle2d)
    case ellipse(Ellipse2d)
    case spline(Spline2d)
    case polySegment(PolySegment2d)
}
