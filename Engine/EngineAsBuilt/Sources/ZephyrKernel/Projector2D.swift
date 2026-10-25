import Foundation

// =========================================================================
// MARK: - Projector2D
//
// Closest-point projection, tangent-point solving, and the analytical
// fillet solver. Consolidates the math behind CADSnapEngine nearest /
// perpendicular / tangent, CADHitTesting aperture checks, and
// FilletChamferCommands — with ellipse and spline coverage the proposal
// snippets lacked (full-kernel scope).

@frozen
public struct CurveProjection2d: Hashable, Sendable {
    public var point: Point2d
    public var param: Double
    public var distance: Double

    public init(point: Point2d, param: Double, distance: Double) {
        self.point = point
        self.param = param
        self.distance = distance
    }
}

@frozen
public struct FilletSolution2d: Hashable, Sendable {
    public var trimmedA: Curve2d
    public var trimmedB: Curve2d
    public var filletArc: Arc2d?

    public init(trimmedA: Curve2d, trimmedB: Curve2d, filletArc: Arc2d?) {
        self.trimmedA = trimmedA
        self.trimmedB = trimmedB
        self.filletArc = filletArc
    }
}

public enum Projector2D: Sendable {

    /// Closest point on a curve to queryPoint. clamped=false allows the
    /// solution off the bounded span (used for fillet tangent points).
    public static func closestPointOnCurve(
        _ curve: Curve2d,
        to queryPoint: Point2d,
        clamped: Bool = true
    ) -> CurveProjection2d {
        switch curve {
        case .line(let seg):
            let tRaw = CurveEval.paramAtPoint(.line(seg), point: queryPoint)
            let t = clamped ? min(max(tRaw, 0.0), 1.0) : tRaw
            let pt = CurveEval.pointAt(.line(seg), t: t)
            return CurveProjection2d(point: pt, param: t, distance: pt.distance(to: queryPoint))

        case .ray(let r):
            let tRaw = CurveEval.paramAtPoint(.ray(r), point: queryPoint)
            let t = clamped ? max(tRaw, 0.0) : tRaw
            let pt = CurveEval.pointAt(.ray(r), t: t)
            return CurveProjection2d(point: pt, param: t, distance: pt.distance(to: queryPoint))

        case .xline(let xl):
            let t = CurveEval.paramAtPoint(.xline(xl), point: queryPoint)
            let pt = CurveEval.pointAt(.xline(xl), t: t)
            return CurveProjection2d(point: pt, param: t, distance: pt.distance(to: queryPoint))

        case .arc(let arc):
            let radial = queryPoint - arc.center
            let rLen = radial.length
            guard rLen > KernelTolerance.linear else {
                let pt = arc.startPoint
                return CurveProjection2d(point: pt, param: 0.0, distance: arc.radius)
            }
            let unconstrained = arc.center + (radial * (arc.radius / rLen))
            let tRaw = CurveEval.paramAtPoint(.arc(arc), point: unconstrained)
            if !clamped || (tRaw >= 0.0 && tRaw <= 1.0) {
                let t = clamped ? min(max(tRaw, 0.0), 1.0) : tRaw
                let pt = CurveEval.pointAt(.arc(arc), t: t)
                return CurveProjection2d(point: pt, param: t, distance: pt.distance(to: queryPoint))
            }
            let pStart = arc.startPoint
            let pEnd = arc.endPoint
            let dStart = pStart.distance(to: queryPoint)
            let dEnd = pEnd.distance(to: queryPoint)
            if dStart <= dEnd {
                return CurveProjection2d(point: pStart, param: 0.0, distance: dStart)
            } else {
                return CurveProjection2d(point: pEnd, param: 1.0, distance: dEnd)
            }

        case .circle(let circle):
            return closestPointOnCurve(.arc(circle.toArc2d()), to: queryPoint, clamped: false)

        case .ellipse(let e):
            // Newton-refined parametric angle from circular seed (shared with
            // CurveEval.paramAtPoint.ellipse), then endpoint clamp.
            let tRaw = CurveEval.paramAtPoint(.ellipse(e), point: queryPoint)
            if !clamped || (tRaw >= 0.0 && tRaw <= 1.0) {
                let t = clamped ? min(max(tRaw, 0.0), 1.0) : tRaw
                let pt = CurveEval.pointAt(.ellipse(e), t: t)
                return CurveProjection2d(point: pt, param: t, distance: pt.distance(to: queryPoint))
            }
            let pStart = CurveEval.pointAt(.ellipse(e), t: 0)
            let pEnd = CurveEval.pointAt(.ellipse(e), t: 1)
            let dS = pStart.distance(to: queryPoint)
            let dE = pEnd.distance(to: queryPoint)
            if dS <= dE {
                return CurveProjection2d(point: pStart, param: 0.0, distance: dS)
            } else {
                return CurveProjection2d(point: pEnd, param: 1.0, distance: dE)
            }

        case .spline(let spline):
            let tRaw = CurveEval.paramAtPoint(.spline(spline), point: queryPoint)
            let t = clamped ? min(max(tRaw, 0.0), 1.0) : tRaw
            let pt = CurveEval.pointAt(.spline(spline), t: t)
            return CurveProjection2d(point: pt, param: t, distance: pt.distance(to: queryPoint))

        case .polySegment(let seg):
            switch seg.geometry {
            case .line(let l): return closestPointOnCurve(.line(l), to: queryPoint, clamped: clamped)
            case .arc(let a): return closestPointOnCurve(.arc(a), to: queryPoint, clamped: clamped)
            }
        }
    }

    /// Tangent points on an arc/circle from an external point.
    /// Powers OSNAP tangent.
    public static func tangentPoints(on curve: Curve2d, from externalPoint: Point2d) -> [CurveProjection2d] {
        let arc: Arc2d
        let isFullCircle: Bool
        switch curve {
        case .circle(let c):
            arc = c.toArc2d()
            isFullCircle = true
        case .arc(let a):
            arc = a
            isFullCircle = false
        case .polySegment(let seg):
            if case .arc(let a) = seg.geometry {
                arc = a
                isFullCircle = false
            } else {
                return []
            }
        default:
            return []
        }

        let v = externalPoint - arc.center
        let d = v.length
        guard d >= arc.radius - KernelTolerance.linear, d > KernelTolerance.linear else { return [] }

        let baseAngle = atan2(v.y, v.x)
        let cosAlpha = min(1.0, max(-1.0, arc.radius / d))
        let alpha = acos(cosAlpha)
        let angles = alpha <= KernelTolerance.parametric ? [baseAngle] : [baseAngle + alpha, baseAngle - alpha]
        var results: [CurveProjection2d] = []
        for ang in angles {
            let pt = Point2d(x: arc.center.x + arc.radius * cos(ang), y: arc.center.y + arc.radius * sin(ang))
            let t = CurveEval.paramAtPoint(.arc(arc), point: pt)
            if isFullCircle || (t >= -KernelTolerance.parametric && t <= 1.0 + KernelTolerance.parametric) {
                let clampedT = min(max(t, 0.0), 1.0)
                results.append(CurveProjection2d(point: pt, param: clampedT, distance: pt.distance(to: externalPoint)))
            }
        }
        return results
    }

    /// Analytical fillet for two curves picked near pickA/pickB.
    /// Offsets both curves toward the other pick by `radius`, intersects the
    /// offsets (extended) for the fillet center, projects back for tangent
    /// points, and splits both curves at them. Radius 0 = sharp corner.
    /// Works for line/arc/circle/polySegment; ellipse/spline inputs return
    /// nil so callers keep their existing paths (no silent wrong answers).
    public static func filletCurves(
        _ curveA: Curve2d,
        pickA: Point2d,
        _ curveB: Curve2d,
        pickB: Point2d,
        radius: Double
    ) -> FilletSolution2d? {
        guard supportsFillet(curveA) && supportsFillet(curveB) else { return nil }
        let projA = closestPointOnCurve(curveA, to: pickA)
        let projB = closestPointOnCurve(curveB, to: pickB)

        if radius <= KernelTolerance.linear {
            guard let hit = Intersector2D.intersect(curveA, curveB, extendA: true, extendB: true).first else {
                return nil
            }
            let keepStartA = projA.param <= hit.paramA
            let keepStartB = projB.param <= hit.paramB
            guard let trimA = CurveEval.splitAt(curveA, t1: keepStartA ? 0.0 : hit.paramA, t2: keepStartA ? hit.paramA : 1.0),
                  let trimB = CurveEval.splitAt(curveB, t1: keepStartB ? 0.0 : hit.paramB, t2: keepStartB ? hit.paramB : 1.0) else {
                return nil
            }
            return FilletSolution2d(trimmedA: trimA, trimmedB: trimB, filletArc: nil)
        }

        guard let offsetA = Offset2D.offsetSingleCurve(curveA, distance: radius, sidePoint: projB.point),
              let offsetB = Offset2D.offsetSingleCurve(curveB, distance: radius, sidePoint: projA.point) else {
            return nil
        }

        let centers = Intersector2D.intersect(offsetA, offsetB, extendA: true, extendB: true)
        guard let bestCenter = centers.min(by: {
            ($0.point.distance(to: projA.point) + $0.point.distance(to: projB.point)) <
            ($1.point.distance(to: projA.point) + $1.point.distance(to: projB.point))
        })?.point else {
            return nil
        }

        let tanA = closestPointOnCurve(curveA, to: bestCenter, clamped: false)
        let tanB = closestPointOnCurve(curveB, to: bestCenter, clamped: false)

        let keepStartA = projA.param <= tanA.param
        let keepStartB = projB.param <= tanB.param
        guard let trimA = CurveEval.splitAt(curveA, t1: keepStartA ? 0.0 : tanA.param, t2: keepStartA ? tanA.param : 1.0),
              let trimB = CurveEval.splitAt(curveB, t1: keepStartB ? 0.0 : tanB.param, t2: keepStartB ? tanB.param : 1.0) else {
            return nil
        }

        let angleA = atan2(tanA.point.y - bestCenter.y, tanA.point.x - bestCenter.x)
        let angleB = atan2(tanB.point.y - bestCenter.y, tanB.point.x - bestCenter.x)
        var sweep = (angleB - angleA).truncatingRemainder(dividingBy: 2.0 * .pi)
        if sweep > .pi { sweep -= 2.0 * .pi }
        if sweep < -.pi { sweep += 2.0 * .pi }

        let filletArc = Arc2d(center: bestCenter, radius: radius, startAngle: angleA, sweep: sweep)
        return FilletSolution2d(trimmedA: trimA, trimmedB: trimB, filletArc: filletArc)
    }

    static func supportsFillet(_ curve: Curve2d) -> Bool {
        switch curve {
        case .line, .arc, .circle: return true
        case .polySegment: return true
        case .ray, .xline, .ellipse, .spline: return false
        }
    }
}
