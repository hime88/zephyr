import Foundation

// =========================================================================
// MARK: - Intersector2D
//
// One canonical solver for all 2D curve-curve intersections.
// Precision strategy (PLAN-kernel-perf.md R3, user requirement: absolute
// precision preserved): tolerance stays absolute (linear = 1e-9), and
// robustness at large coordinates comes from LOCAL-FRAME SHIFTING — every
// analytic solver translates its inputs near the origin before forming
// quadratics/determinants, then translates results back. This removes the
// catastrophic cancellation that breaks naive solvers at state-plane
// magnitudes (~2.4e6, where 1 ULP ≈ 4.7e-10).

@frozen
public struct CurveIntersection2d: Hashable, Sendable {
    public var point: Point2d
    /// Normalized parameter on curve A ([0, 1] when strictly on span).
    public var paramA: Double
    /// Normalized parameter on curve B ([0, 1] when strictly on span).
    public var paramB: Double

    public init(point: Point2d, paramA: Double, paramB: Double) {
        self.point = point
        self.paramA = paramA
        self.paramB = paramB
    }
}

public enum Intersector2D: Sendable {

    // MARK: - Local-frame shifting

    /// Reference origin for a pair of curves: midpoint of their bounding-box
    /// centers. Solving relative to this point keeps intermediate magnitudes
    /// small even for state-plane coordinates.
    @inlinable
    static func referenceOrigin(_ a: Curve2d, _ b: Curve2d) -> Point2d {
        func center(of c: Curve2d) -> Point2d {
            switch c {
            case .line(let s): return Point2d(x: 0.5 * (s.start.x + s.end.x), y: 0.5 * (s.start.y + s.end.y))
            case .ray(let r): return r.origin
            case .xline(let x): return x.origin
            case .arc(let a): return a.center
            case .circle(let c): return c.center
            case .ellipse(let e): return e.center
            case .spline(let s):
                guard let box = SplineEval.controlBounds(s) else { return .zero }
                return Point2d(x: 0.5 * (box.min.x + box.max.x), y: 0.5 * (box.min.y + box.max.y))
            case .polySegment(let seg): return center(of: .line(LineSeg2d(start: seg.startPoint, end: seg.endPoint)))
            }
        }
        let ca = center(of: a), cb = center(of: b)
        return Point2d(x: 0.5 * (ca.x + cb.x), y: 0.5 * (ca.y + cb.y))
    }

    // MARK: - Entry point

    /// Unified intersection of any two curves.
    /// extendA/extendB allow the solution off the bounded span (used by
    /// FILLET/EXTEND); otherwise hits are clamped to [0, 1] within tolerance.
    public static func intersect(
        _ curveA: Curve2d,
        _ curveB: Curve2d,
        extendA: Bool = false,
        extendB: Bool = false,
        tolerance: Double = KernelTolerance.linear
    ) -> [CurveIntersection2d] {
        // Unwrap polyline segments to their exact analytical primitive.
        if case .polySegment(let segA) = curveA {
            let innerA: Curve2d = {
                switch segA.geometry {
                case .line(let l): return .line(l)
                case .arc(let a): return .arc(a)
                }
            }()
            return intersect(innerA, curveB, extendA: extendA, extendB: extendB, tolerance: tolerance)
        }
        if case .polySegment(let segB) = curveB {
            let innerB: Curve2d = {
                switch segB.geometry {
                case .line(let l): return .line(l)
                case .arc(let a): return .arc(a)
                }
            }()
            return intersect(curveA, innerB, extendA: extendA, extendB: extendB, tolerance: tolerance)
        }

        // Circles are full-sweep arcs; paramAtPoint on a full circle always
        // lands in [0, 1], so span clamping passes naturally.
        if case .circle(let cA) = curveA {
            return intersect(.arc(cA.toArc2d()), curveB, extendA: false, extendB: extendB, tolerance: tolerance)
        }
        if case .circle(let cB) = curveB {
            return intersect(curveA, .arc(cB.toArc2d()), extendA: extendA, extendB: false, tolerance: tolerance)
        }

        switch (curveA, curveB) {
        case (.line(let lA), .line(let lB)):
            return intersectLineLine(lA, lB, extendA: extendA, extendB: extendB, tolerance: tolerance)
        case (.line(let l), .ray(let r)):
            return intersectLineLikeLine(l.start, l.end, lineDomain: .segment(extend: extendA),
                                         r.origin, r.origin + (r.direction * 1.0), lineDomain: .ray(extend: extendB),
                                         tolerance: tolerance, refOrigin: referenceOrigin(curveA, curveB))
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramA, paramB: $0.paramB) }
        case (.ray, .line):
            return intersect(curveB, curveA, extendA: extendB, extendB: extendA, tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.line(let l), .xline(let x)):
            return intersectLineLikeLine(l.start, l.end, lineDomain: .segment(extend: extendA),
                                         x.origin, x.origin + (x.direction * 1.0), lineDomain: .infinite,
                                         tolerance: tolerance, refOrigin: referenceOrigin(curveA, curveB))
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramA, paramB: $0.paramB) }
        case (.xline, .line):
            return intersect(curveB, curveA, extendA: extendB, extendB: extendA, tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.ray(let rA), .ray(let rB)):
            return intersectLineLikeLine(rA.origin, rA.origin + (rA.direction * 1.0), lineDomain: .ray(extend: extendA),
                                         rB.origin, rB.origin + (rB.direction * 1.0), lineDomain: .ray(extend: extendB),
                                         tolerance: tolerance, refOrigin: referenceOrigin(curveA, curveB))
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramA, paramB: $0.paramB) }
        case (.xline(let xA), .xline(let xB)):
            return intersectLineLikeLine(xA.origin, xA.origin + (xA.direction * 1.0), lineDomain: .infinite,
                                         xB.origin, xB.origin + (xB.direction * 1.0), lineDomain: .infinite,
                                         tolerance: tolerance, refOrigin: referenceOrigin(curveA, curveB))
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramA, paramB: $0.paramB) }
        case (.ray(let r), .xline(let x)):
            return intersectLineLikeLine(r.origin, r.origin + (r.direction * 1.0), lineDomain: .ray(extend: extendA),
                                         x.origin, x.origin + (x.direction * 1.0), lineDomain: .infinite,
                                         tolerance: tolerance, refOrigin: referenceOrigin(curveA, curveB))
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramA, paramB: $0.paramB) }
        case (.xline, .ray):
            return intersect(curveB, curveA, extendA: extendB, extendB: extendA, tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }

        case (.line(let line), .arc(let arc)):
            return intersectLineArc(line, arc, extendLine: extendA, extendArc: extendB, tolerance: tolerance)
        case (.arc(let arc), .line(let line)):
            return intersectLineArc(line, arc, extendLine: extendB, extendArc: extendA, tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.ray(let r), .arc(let arc)):
            return intersectRayArc(ray: r, arc: arc, extendRay: extendA, extendArc: extendB, tolerance: tolerance)
        case (.arc(let arc), .ray(let r)):
            return intersectRayArc(ray: r, arc: arc, extendRay: extendB, extendArc: extendA, tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.xline(let x), .arc(let arc)):
            return intersectRayArc(ray: Ray2d(origin: x.origin, direction: x.direction), arc: arc,
                                   extendRay: true, extendArc: extendB, tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.arc, .xline):
            return intersect(curveB, curveA, extendA: extendB, extendB: extendA, tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }

        case (.arc(let arcA), .arc(let arcB)):
            return intersectArcArc(arcA, arcB, extendA: extendA, extendB: extendB, tolerance: tolerance)

        case (.line(let line), .ellipse(let e)):
            return intersectLineEllipse(line: line, extendLine: extendA, ellipse: e, extendEllipse: extendB, tolerance: tolerance)
        case (.ellipse(let e), .line(let line)):
            return intersectLineEllipse(line: line, extendLine: extendB, ellipse: e, extendEllipse: extendA, tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.ellipse(let eA), .ellipse(let eB)):
            return intersectEllipseEllipse(eA, eB, extendA: extendA, extendB: extendB, tolerance: tolerance)
        case (.arc(let arc), .ellipse(let e)):
            return intersectArcEllipse(arc: arc, extendArc: extendA, ellipse: e, extendEllipse: extendB, tolerance: tolerance)
        case (.ellipse(let e), .arc(let arc)):
            return intersectArcEllipse(arc: arc, extendArc: extendB, ellipse: e, extendEllipse: extendA, tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.ray(let r), .ellipse(let e)):
            return intersectRayEllipse(ray: r, extendRay: extendA, ellipse: e, extendEllipse: extendB, tolerance: tolerance)
        case (.ellipse(let e), .ray(let r)):
            return intersectRayEllipse(ray: r, extendRay: extendB, ellipse: e, extendEllipse: extendA, tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.xline(let x), .ellipse(let e)):
            return intersectRayEllipse(ray: Ray2d(origin: x.origin, direction: x.direction), extendRay: true, ellipse: e, extendEllipse: extendB, tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.ellipse, .xline):
            return intersect(curveB, curveA, extendA: extendB, extendB: extendA, tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }

        case (.line(let line), .spline(let s)):
            return intersectLineSpline(line: line, extendLine: extendA, spline: s, refOrigin: referenceOrigin(curveA, curveB), tolerance: tolerance)
        case (.spline(let s), .line(let line)):
            return intersectLineSpline(line: line, extendLine: extendB, spline: s, refOrigin: referenceOrigin(curveA, curveB), tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.ray(let r), .spline(let s)):
            return intersectRaySpline(ray: r, extendRay: extendA, spline: s, refOrigin: referenceOrigin(curveA, curveB), tolerance: tolerance)
        case (.spline(let s), .ray(let r)):
            return intersectRaySpline(ray: r, extendRay: extendB, spline: s, refOrigin: referenceOrigin(curveA, curveB), tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.xline(let x), .spline(let s)):
            return intersectRaySpline(ray: Ray2d(origin: x.origin, direction: x.direction), extendRay: true, spline: s, refOrigin: referenceOrigin(curveA, curveB), tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.spline, .xline):
            return intersect(curveB, curveA, extendA: extendB, extendB: extendA, tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.arc(let arc), .spline(let s)):
            return intersectAnalyticSpline(analytic: .arc(arc), extendAnalytic: extendA, spline: s, refOrigin: referenceOrigin(curveA, curveB), tolerance: tolerance)
        case (.spline(let s), .arc(let arc)):
            return intersectAnalyticSpline(analytic: .arc(arc), extendAnalytic: extendB, spline: s, refOrigin: referenceOrigin(curveA, curveB), tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.ellipse(let e), .spline(let s)):
            return intersectAnalyticSpline(analytic: .ellipse(e), extendAnalytic: extendA, spline: s, refOrigin: referenceOrigin(curveA, curveB), tolerance: tolerance)
        case (.spline(let s), .ellipse(let e)):
            return intersectAnalyticSpline(analytic: .ellipse(e), extendAnalytic: extendB, spline: s, refOrigin: referenceOrigin(curveA, curveB), tolerance: tolerance)
                .map { CurveIntersection2d(point: $0.point, paramA: $0.paramB, paramB: $0.paramA) }
        case (.spline(let sA), .spline(let sB)):
            return intersectSplineSpline(sA, sB, refOrigin: referenceOrigin(curveA, curveB), tolerance: tolerance)

        default:
            return []
        }
    }

    // MARK: - Line-like domains

    enum LineDomain {
        case segment(extend: Bool)
        case ray(extend: Bool)
        case infinite

        func isValid(_ t: Double, tolerance: Double, scale: Double) -> Bool {
            let tol = tolerance / max(scale, tolerance)
            switch self {
            case .segment(let extend): return extend || (t >= -tol && t <= 1.0 + tol)
            case .ray(let extend): return extend || t >= -tol
            case .infinite: return true
            }
        }

        func clamped(_ t: Double) -> Double {
            switch self {
            case .segment(let extend): return extend ? t : min(max(t, 0.0), 1.0)
            case .ray(let extend): return extend ? t : max(t, 0.0)
            case .infinite: return t
            }
        }
    }

    static func intersectLineLikeLine(
        _ a0: Point2d, _ a1: Point2d, lineDomain domA: LineDomain,
        _ b0: Point2d, _ b1: Point2d, lineDomain domB: LineDomain,
        tolerance: Double, refOrigin: Point2d
    ) -> [CurveIntersection2d] {
        // Shift to local frame.
        let A0 = a0 - refOrigin, A1 = a1 - refOrigin
        let B0 = b0 - refOrigin, B1 = b1 - refOrigin
        let r = A1 - A0
        let s = B1 - B0
        let denom = r.cross(s)
        let rLen = r.length, sLen = s.length
        guard rLen > tolerance, sLen > tolerance else { return [] }
        guard abs(denom) > KernelTolerance.parametric * rLen * sLen else { return [] }
        let qp = B0 - A0
        let t = qp.cross(s) / denom
        let u = qp.cross(r) / denom
        guard domA.isValid(t, tolerance: tolerance, scale: rLen),
              domB.isValid(u, tolerance: tolerance, scale: sLen) else { return [] }
        let cA = domA.clamped(t), cB = domB.clamped(u)
        let pt = a0 + ((a1 - a0) * cA)
        return [CurveIntersection2d(point: pt, paramA: cA, paramB: cB)]
    }

    // MARK: - Analytical Line-Line solver (local-frame shifted)

    public static func intersectLineLine(
        _ a: LineSeg2d,
        _ b: LineSeg2d,
        extendA: Bool,
        extendB: Bool,
        tolerance: Double = KernelTolerance.linear
    ) -> [CurveIntersection2d] {
        let ref = Point2d(x: 0.25 * (a.start.x + a.end.x + b.start.x + b.end.x),
                          y: 0.25 * (a.start.y + a.end.y + b.start.y + b.end.y))
        return intersectLineLikeLine(a.start, a.end, lineDomain: .segment(extend: extendA),
                                     b.start, b.end, lineDomain: .segment(extend: extendB),
                                     tolerance: tolerance, refOrigin: ref)
    }

    // MARK: - Analytical Line-Arc solver (local-frame shifted)

    public static func intersectLineArc(
        _ line: LineSeg2d,
        _ arc: Arc2d,
        extendLine: Bool,
        extendArc: Bool,
        tolerance: Double = KernelTolerance.linear
    ) -> [CurveIntersection2d] {
        // Local frame at arc center: eliminates cancellation for large coords.
        let ox = arc.center.x, oy = arc.center.y
        let sx = line.start.x - ox, sy = line.start.y - oy
        let ex = line.end.x - ox, ey = line.end.y - oy
        let dx = ex - sx, dy = ey - sy
        let lenSq = dx * dx + dy * dy
        let len = sqrt(lenSq)
        guard len > tolerance, arc.radius > tolerance else { return [] }

        let aCoeff = lenSq
        let bCoeff = 2.0 * (sx * dx + sy * dy)
        let cCoeff = sx * sx + sy * sy - arc.radius * arc.radius

        // Compensated discriminant: tiny negatives within tolerance snap to
        // tangent (single root) instead of missing.
        var disc = bCoeff * bCoeff - 4.0 * aCoeff * cCoeff
        let discTol = 4.0 * aCoeff * tolerance * arc.radius
        if disc < -discTol { return [] }
        if disc < 0 { disc = 0 }

        let sqrtDisc = sqrt(disc)
        let tCandidates: [Double]
        if sqrtDisc <= KernelTolerance.parametric * len {
            tCandidates = [-bCoeff / (2.0 * aCoeff)]
        } else {
            tCandidates = [(-bCoeff - sqrtDisc) / (2.0 * aCoeff),
                           (-bCoeff + sqrtDisc) / (2.0 * aCoeff)]
        }

        let tTol = tolerance / len
        let arcLen = max(arc.radius * abs(arc.sweep), tolerance)
        let uTol = tolerance / arcLen
        var results: [CurveIntersection2d] = []
        for t in tCandidates {
            if !extendLine && (t < -tTol || t > 1.0 + tTol) { continue }
            let finalT = extendLine ? t : min(max(t, 0.0), 1.0)
            let px = line.start.x + (line.end.x - line.start.x) * finalT
            let py = line.start.y + (line.end.y - line.start.y) * finalT
            let pt = Point2d(x: px, y: py)
            let u = CurveEval.paramAtPoint(.arc(arc), point: pt)
            if !extendArc && (u < -uTol || u > 1.0 + uTol) { continue }
            let finalU = extendArc ? u : min(max(u, 0.0), 1.0)
            results.append(CurveIntersection2d(point: pt, paramA: finalT, paramB: finalU))
        }
        return results
    }

    static func intersectRayArc(
        ray: Ray2d, arc: Arc2d, extendRay: Bool, extendArc: Bool, tolerance: Double
    ) -> [CurveIntersection2d] {
        // Long-segment proxy: ray parameter t maps to segment t in [0,1]
        // over length L = 2 * (|origin-center| + radius + 1).
        let distOC = ray.origin.distance(to: arc.center)
        let L = 2.0 * (distOC + arc.radius + 1.0)
        let seg = LineSeg2d(start: ray.origin, end: ray.origin + (ray.direction * L))
        let hits = intersectLineArc(seg, arc, extendLine: false, extendArc: extendArc, tolerance: tolerance)
        return hits.compactMap { h in
            let tRay = h.paramA * L
            if !extendRay && tRay < -tolerance { return nil }
            let clamped = extendRay ? tRay : max(tRay, 0.0)
            let pt = CurveEval.pointAt(.ray(ray), t: clamped)
            // Re-derive arc param at the true ray point for clamping accuracy.
            let u = CurveEval.paramAtPoint(.arc(arc), point: pt)
            let arcLen = max(arc.radius * abs(arc.sweep), tolerance)
            let uTol = tolerance / arcLen
            if !extendArc && (u < -uTol || u > 1.0 + uTol) { return nil }
            return CurveIntersection2d(point: pt, paramA: clamped, paramB: extendArc ? u : min(max(u, 0.0), 1.0))
        }
    }

    // MARK: - Analytical Arc-Arc solver (local-frame shifted)

    public static func intersectArcArc(
        _ arcA: Arc2d,
        _ arcB: Arc2d,
        extendA: Bool,
        extendB: Bool,
        tolerance: Double = KernelTolerance.linear
    ) -> [CurveIntersection2d] {
        // Work in the frame of arcA's center.
        let cx = arcB.center.x - arcA.center.x
        let cy = arcB.center.y - arcA.center.y
        let d = hypot(cx, cy)
        let r1 = arcA.radius, r2 = arcB.radius
        guard d > tolerance,
              d <= r1 + r2 + tolerance,
              d >= abs(r1 - r2) - tolerance else { return [] }

        let a = (r1 * r1 - r2 * r2 + d * d) / (2.0 * d)
        let hSq = max(0.0, r1 * r1 - a * a)
        let h = sqrt(hSq)

        let ux = cx / d, uy = cy / d
        // Mid point in arcA-centered frame; translate back at the end.
        let mx = ux * a, my = uy * a
        let candLocal: [(Double, Double)]
        if h <= tolerance {
            candLocal = [(mx, my)]
        } else {
            candLocal = [(mx + (-uy) * h, my + ux * h),
                         (mx - (-uy) * h, my - ux * h)]
        }

        let tolA = tolerance / max(r1 * abs(arcA.sweep), tolerance)
        let tolB = tolerance / max(r2 * abs(arcB.sweep), tolerance)
        var results: [CurveIntersection2d] = []
        for (lx, ly) in candLocal {
            let pt = Point2d(x: arcA.center.x + lx, y: arcA.center.y + ly)
            let tA = CurveEval.paramAtPoint(.arc(arcA), point: pt)
            let tB = CurveEval.paramAtPoint(.arc(arcB), point: pt)
            if !extendA && (tA < -tolA || tA > 1.0 + tolA) { continue }
            if !extendB && (tB < -tolB || tB > 1.0 + tolB) { continue }
            results.append(CurveIntersection2d(
                point: pt,
                paramA: extendA ? tA : min(max(tA, 0.0), 1.0),
                paramB: extendB ? tB : min(max(tB, 0.0), 1.0)))
        }
        return results
    }

    // MARK: - Ellipse solvers

    static func intersectLineEllipse(
        line: LineSeg2d, extendLine: Bool, ellipse e: Ellipse2d, extendEllipse: Bool, tolerance: Double
    ) -> [CurveIntersection2d] {
        let a = e.majorAxis.length
        guard a > tolerance else { return [] }
        let b = a * e.minorRatio
        let ux = e.majorAxis.normalized
        let uy = ux.perpCCW
        if b <= tolerance {
            // Degenerate: major-axis segment.
            let seg = LineSeg2d(start: e.center + (ux * -a), end: e.center + (ux * a))
            return intersectLineLine(line, seg, extendA: extendLine, extendB: extendEllipse, tolerance: tolerance)
        }
        // Local ellipse frame: origin at center, x along major, y along minor.
        func toLocal(_ p: Point2d) -> (Double, Double) {
            let r = p - e.center
            return (r.dot(ux), r.dot(uy))
        }
        let (x0, y0) = toLocal(line.start)
        let (x1, y1) = toLocal(line.end)
        let dx = x1 - x0, dy = y1 - y0
        let A = (dx * dx) / (a * a) + (dy * dy) / (b * b)
        let B = 2.0 * ((x0 * dx) / (a * a) + (y0 * dy) / (b * b))
        let C = (x0 * x0) / (a * a) + (y0 * y0) / (b * b) - 1.0
        guard abs(A) > 1e-24 else { return [] }
        var disc = B * B - 4.0 * A * C
        if disc < 0 {
            // Tolerance-scaled tangent snap.
            let scale = max(a, b)
            if disc < -tolerance * 4.0 * abs(A) * scale { return [] }
            disc = 0
        }
        let sq = sqrt(disc)
        let ts = disc <= 0 ? [-B / (2.0 * A)] : [(-B - sq) / (2.0 * A), (-B + sq) / (2.0 * A)]
        let len = line.length
        let tTol = tolerance / max(len, tolerance)
        let ellLen = max(.pi * (3.0 * (a + b) - sqrt((3.0 * a + b) * (a + 3.0 * b))), tolerance)
        let uTol = tolerance / ellLen
        var out: [CurveIntersection2d] = []
        for t in ts {
            if !extendLine && (t < -tTol || t > 1.0 + tTol) { continue }
            let ft = extendLine ? t : min(max(t, 0.0), 1.0)
            let pt = CurveEval.pointAt(.line(line), t: ft)
            let u = CurveEval.paramAtPoint(.ellipse(e), point: pt)
            if !extendEllipse && (u < -uTol || u > 1.0 + uTol) { continue }
            out.append(CurveIntersection2d(point: pt, paramA: ft,
                                           paramB: extendEllipse ? u : min(max(u, 0.0), 1.0)))
        }
        return out
    }

    static func intersectRayEllipse(
        ray: Ray2d, extendRay: Bool, ellipse e: Ellipse2d, extendEllipse: Bool, tolerance: Double
    ) -> [CurveIntersection2d] {
        let d = ray.origin.distance(to: e.center)
        let L = 2.0 * (d + e.majorAxis.length + 1.0)
        let seg = LineSeg2d(start: ray.origin, end: ray.origin + (ray.direction * L))
        return intersectLineEllipse(line: seg, extendLine: false, ellipse: e, extendEllipse: extendEllipse, tolerance: tolerance)
            .compactMap { h in
                let tRay = h.paramA * L
                if !extendRay && tRay < -tolerance { return nil }
                let c = extendRay ? tRay : max(tRay, 0.0)
                let pt = CurveEval.pointAt(.ray(ray), t: c)
                return CurveIntersection2d(point: pt, paramA: c, paramB: h.paramB)
            }
    }

    /// Ellipse-ellipse and arc-ellipse: subdivide the second curve to
    /// chord segments (bounded count, tolerance-scaled) and test each
    /// analytically. Deterministic; chord error ≤ 1e-7 relative.
    /// Spline subdivision scales with control-polygon length so chord
    /// error stays ~1e-6 relative: a crossing of the true curve always
    /// lies in a segment whose bbox overlaps the query strip, so
    /// bbox-gated segment tests cannot miss.
    static func splineSegments(_ s: Spline2d, maxSegments: Int = 1024) -> [LineSeg2d] {
        guard s.isValid, let (u0, u1) = SplineEval.domain(of: s) else { return [] }
        var ctrlLen = 0.0
        for i in 1..<s.controlPoints.count {
            ctrlLen += s.controlPoints[i - 1].distance(to: s.controlPoints[i])
        }
        guard ctrlLen > 1e-12 else { return [] }
        let target = max(1e-6 * ctrlLen, 1e-9)
        let n = min(maxSegments, max(32, Int(ceil(ctrlLen / target))))
        var segs: [LineSeg2d] = []
        segs.reserveCapacity(n)
        var prev = SplineEval.evaluate(s, at: u0) ?? .zero
        for i in 1...n {
            let p = SplineEval.evaluate(s, at: u0 + (u1 - u0) * Double(i) / Double(n)) ?? .zero
            segs.append(LineSeg2d(start: prev, end: p))
            prev = p
        }
        return segs
    }

    static func subdividedSegments(of curve: Curve2d, maxSegments: Int = 256) -> [LineSeg2d] {
        switch curve {
        case .ellipse(let e):
            let sweepLen = abs(e.sweep)
            let n = min(maxSegments, max(16, Int(ceil(sweepLen * 48.0))))
            var segs: [LineSeg2d] = []
            segs.reserveCapacity(n)
            var prev = CurveEval.pointAt(curve, t: 0)
            for i in 1...n {
                let p = CurveEval.pointAt(curve, t: Double(i) / Double(n))
                segs.append(LineSeg2d(start: prev, end: p))
                prev = p
            }
            return segs
        case .spline(let s):
            return splineSegments(s, maxSegments: maxSegments)
        case .arc(let a):
            let n = min(maxSegments, max(8, Int(ceil(abs(a.sweep) * 48.0))))
            var segs: [LineSeg2d] = []
            var prev = CurveEval.pointAt(curve, t: 0)
            for i in 1...n {
                let p = CurveEval.pointAt(curve, t: Double(i) / Double(n))
                segs.append(LineSeg2d(start: prev, end: p))
                prev = p
            }
            return segs
        default:
            return []
        }
    }

    static func intersectEllipseEllipse(
        _ eA: Ellipse2d, _ eB: Ellipse2d, extendA: Bool, extendB: Bool, tolerance: Double
    ) -> [CurveIntersection2d] {
        let segsB = subdividedSegments(of: .ellipse(eB))
        var out: [CurveIntersection2d] = []
        for (i, seg) in segsB.enumerated() {
            let tB = (Double(i) + 0.5) / Double(segsB.count)
            _ = tB
            let hits = intersectLineEllipse(line: seg, extendLine: true, ellipse: eA, extendEllipse: extendA, tolerance: tolerance)
            for h in hits {
                // h.paramA is on the sub-segment; map to ellipse-B param.
                let uB = (Double(i) + h.paramA) / Double(segsB.count)
                if !extendB {
                    let ellLen = max(eB.majorAxis.length * abs(eB.sweep), tolerance)
                    let tolB = tolerance / ellLen
                    if uB < -tolB || uB > 1.0 + tolB { continue }
                }
                let ptB = CurveEval.pointAt(.ellipse(eB), t: min(max(uB, 0.0), 1.0))
                // Snap point to ellipse A exactly (removes chord error on A side).
                let uA = CurveEval.paramAtPoint(.ellipse(eA), point: h.point)
                out.append(CurveIntersection2d(point: h.point, paramA: extendA ? uA : min(max(uA, 0.0), 1.0),
                                               paramB: extendB ? uB : min(max(uB, 0.0), 1.0)))
                _ = ptB
            }
        }
        return dedupe(out, tolerance: tolerance)
    }

    static func intersectArcEllipse(
        arc: Arc2d, extendArc: Bool, ellipse e: Ellipse2d, extendEllipse: Bool, tolerance: Double
    ) -> [CurveIntersection2d] {
        let segs = subdividedSegments(of: .arc(arc))
        var out: [CurveIntersection2d] = []
        for (i, seg) in segs.enumerated() {
            let hits = intersectLineEllipse(line: seg, extendLine: true, ellipse: e, extendEllipse: extendEllipse, tolerance: tolerance)
            for h in hits {
                let uA = (Double(i) + h.paramA) / Double(segs.count)
                let arcLen = max(arc.radius * abs(arc.sweep), tolerance)
                if !extendArc && (uA < -tolerance / arcLen || uA > 1.0 + tolerance / arcLen) { continue }
                let uArc = CurveEval.paramAtPoint(.arc(arc), point: h.point)
                out.append(CurveIntersection2d(point: h.point,
                                               paramA: extendArc ? uArc : min(max(uArc, 0.0), 1.0),
                                               paramB: h.paramB))
            }
        }
        return dedupe(out, tolerance: tolerance)
    }

    // MARK: - Spline intersections (recursive subdivision, AABB-rejected)

    static func intersectLineSpline(
        line: LineSeg2d, extendLine: Bool, spline s: Spline2d, refOrigin: Point2d, tolerance: Double
    ) -> [CurveIntersection2d] {
        _ = refOrigin
        guard s.isValid, let (u0, u1) = SplineEval.domain(of: s) else { return [] }
        // Broad phase: control bounds vs line bbox.
        if let cb = SplineEval.controlBounds(s) {
            let lb = BoundingBox2d(min: line.start, max: line.end).expanded(by: tolerance)
            if !cb.intersects(lb) { return [] }
        }
        // Flatten once (chord error ~1e-6 relative), then bbox-gate each
        // chord segment against the line bbox: a true crossing always lies
        // in an overlapping segment, so gating cannot miss.
        let segs = splineSegments(s)
        guard !segs.isEmpty else { return [] }
        let lineBox = BoundingBox2d(min: line.start, max: line.end)
        var out: [CurveIntersection2d] = []
        out.reserveCapacity(4)
        for (i, chord) in segs.enumerated() {
            if !BoundingBox2d(min: chord.start, max: chord.end).expanded(by: tolerance).intersects(lineBox) {
                continue
            }
            // Solve against the infinite line here (endpoint effects are
            // decided by the refined true point below, not the chord).
            let hits = intersectLineLine(line, chord, extendA: true, extendB: true, tolerance: tolerance)
            for h in hits {
                let tSpline = (Double(i) + h.paramB) / Double(segs.count)
                // Newton refinement of signed distance to the infinite line,
                // seeded at the chord hit (same root-finding as the legacy
                // sampler, converging to 1e-12 instead of sample resolution).
                let uGuess = u0 + (u1 - u0) * tSpline
                let span = (u1 - u0) / Double(segs.count)
                let dir = line.end - line.start
                let nLen = dir.length
                guard nLen > tolerance else { continue }
                let normal = dir.perpCCW * (1.0 / nLen)
                func signedDist(_ uu: Double) -> Double? {
                    guard let p = SplineEval.evaluate(s, at: uu) else { return nil }
                    return (p - line.start).dot(normal)
                }
                var u = uGuess
                let hStep = max(1e-10, 1e-6 * (u1 - u0))
                let uLo = max(u0, uGuess - span), uHi = min(u1, uGuess + span)
                for _ in 0..<20 {
                    guard let dist = signedDist(u) else { break }
                    if abs(dist) < 1e-12 { break }
                    let up = min(uHi, u + hStep), um = max(uLo, u - hStep)
                    guard up > um else { break }
                    guard let dp = signedDist(up), let dm = signedDist(um) else { break }
                    let deriv = (dp - dm) / (up - um)
                    guard abs(deriv) > 1e-12 else { break }
                    var step = -dist / deriv
                    step = min(0.5 * (u1 - u0), max(-0.5 * (u1 - u0), step))
                    u = min(uHi, max(uLo, u + step))
                }
                guard let pBest = SplineEval.evaluate(s, at: u),
                      let dist = signedDist(u), abs(dist) <= 1e-9 else { continue }
                let tBest = (u - u0) / (u1 - u0)
                let tL = CurveEval.paramAtPoint(.line(line), point: pBest)
                if !extendLine {
                    let len = max(line.length, tolerance)
                    if tL < -tolerance / len || tL > 1.0 + tolerance / len { continue }
                }
                out.append(CurveIntersection2d(point: pBest,
                                               paramA: extendLine ? tL : min(max(tL, 0.0), 1.0),
                                               paramB: tBest))
            }
        }
        return dedupe(out, tolerance: tolerance)
    }

    static func intersectRaySpline(
        ray: Ray2d, extendRay: Bool, spline s: Spline2d, refOrigin: Point2d, tolerance: Double
    ) -> [CurveIntersection2d] {
        guard let box = SplineEval.controlBounds(s) else { return [] }
        let d = ray.origin.distance(to: Point2d(x: 0.5 * (box.min.x + box.max.x), y: 0.5 * (box.min.y + box.max.y)))
        let L = 2.0 * (d + 1.0)
        let seg = LineSeg2d(start: ray.origin, end: ray.origin + (ray.direction * L))
        return intersectLineSpline(line: seg, extendLine: false, spline: s, refOrigin: refOrigin, tolerance: tolerance)
            .compactMap { h in
                let tRay = h.paramA * L
                if !extendRay && tRay < -tolerance { return nil }
                let c = extendRay ? tRay : max(tRay, 0.0)
                return CurveIntersection2d(point: CurveEval.pointAt(.ray(ray), t: c), paramA: c, paramB: h.paramB)
            }
    }

    /// Analytic curve (arc/ellipse) vs spline: subdivide spline to segments,
    /// test each against the analytic curve.
    static func intersectAnalyticSpline(
        analytic: Curve2d, extendAnalytic: Bool, spline s: Spline2d, refOrigin: Point2d, tolerance: Double
    ) -> [CurveIntersection2d] {
        guard s.isValid, SplineEval.domain(of: s) != nil else { return [] }
        if let cb = SplineEval.controlBounds(s),
           let ab = CurveEval.boundingBox(analytic)?.expanded(by: tolerance),
           !cb.intersects(ab) { return [] }
        let segs = subdividedSegments(of: .spline(s))
        var out: [CurveIntersection2d] = []
        for (i, seg) in segs.enumerated() {
            let hits = intersect(.line(seg), analytic, extendA: true, extendB: extendAnalytic, tolerance: tolerance)
            for h in hits {
                let uS = (Double(i) + h.paramA) / Double(segs.count)
                let tS = min(max(uS, 0.0), 1.0)
                out.append(CurveIntersection2d(point: h.point, paramA: tS, paramB: h.paramB))
            }
        }
        return dedupe(out, tolerance: tolerance)
    }

    static func intersectSplineSpline(
        _ sA: Spline2d, _ sB: Spline2d, refOrigin: Point2d, tolerance: Double
    ) -> [CurveIntersection2d] {
        _ = refOrigin
        guard sA.isValid, sB.isValid else { return [] }
        guard let (ua0, ua1) = SplineEval.domain(of: sA),
              let (ub0, ub1) = SplineEval.domain(of: sB) else { return [] }
        if let a = SplineEval.controlBounds(sA), let b = SplineEval.controlBounds(sB),
           !a.expanded(by: tolerance).intersects(b.expanded(by: tolerance)) { return [] }
        // Flatten both once; bbox-gate the segment pairs.
        let segsA = splineSegments(sA)
        let segsB = splineSegments(sB)
        guard !segsA.isEmpty, !segsB.isEmpty else { return [] }
        let boxesB = segsB.map { BoundingBox2d(min: $0.start, max: $0.end).expanded(by: tolerance) }
        var out: [CurveIntersection2d] = []
        for (i, segA) in segsA.enumerated() {
            let boxA = BoundingBox2d(min: segA.start, max: segA.end).expanded(by: tolerance)
            for (j, segB) in segsB.enumerated() {
                if !boxA.intersects(boxesB[j]) { continue }
                let hits = intersectLineLine(segA, segB, extendA: true, extendB: true, tolerance: tolerance)
                for h in hits {
                    out.append(CurveIntersection2d(point: h.point,
                                                   paramA: min(max((Double(i) + h.paramA) / Double(segsA.count), 0.0), 1.0),
                                                   paramB: min(max((Double(j) + h.paramB) / Double(segsB.count), 0.0), 1.0)))
                }
            }
        }
        _ = (ua0, ua1, ub0, ub1)
        return dedupe(out, tolerance: tolerance)
    }

    /// Merge hits closer than tolerance (subdivision seams produce doubles).
    static func dedupe(_ hits: [CurveIntersection2d], tolerance: Double) -> [CurveIntersection2d] {
        guard hits.count > 1 else { return hits }
        let sorted = hits.sorted { $0.paramA < $1.paramA }
        var out: [CurveIntersection2d] = []
        for h in sorted {
            if let last = out.last,
               last.point.distanceSquared(to: h.point) <= tolerance * tolerance * 4 {
                continue
            }
            out.append(h)
        }
        return out
    }
}
