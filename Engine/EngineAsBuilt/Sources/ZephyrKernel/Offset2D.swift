import Foundation

// =========================================================================
// MARK: - Offset2D
//
// Parallel-curve offsetting with bulge preservation. Line/arc/circle/
// polyline-segment cases are exact; polyline joints follow the host's
// OFFSETGAPTYPE policy (extend / fillet / chamfer) supplied by the caller
// as a plain enum so the kernel stays UI-agnostic. Ellipse/spline inputs
// return nil — the ZephyrCore engine keeps its sampled-spline fitting for
// those (offsets of ellipses/splines are not representable in-kind).

public enum OffsetJointPolicy: Int, Sendable {
    /// Extend/trim adjacent segments to their intersection.
    case extend = 0
    /// Fillet the joint with a tangent arc of radius = |distance|.
    case fillet = 1
    /// Bevel the joint with a straight chamfer.
    case chamfer = 2
}

public enum Offset2D: Sendable {

    /// Offset one analytical curve by `distance` toward `sidePoint`.
    /// Returns nil when the offset collapses (e.g. arc radius ≤ distance).
    public static func offsetSingleCurve(
        _ curve: Curve2d,
        distance: Double,
        sidePoint: Point2d
    ) -> Curve2d? {
        guard distance > KernelTolerance.linear else { return curve }

        switch curve {
        case .line(let seg):
            let dir = seg.direction
            let leftNormal = dir.perpCCW
            let sideSign = (sidePoint - seg.start).dot(leftNormal) >= 0 ? 1.0 : -1.0
            let shift = leftNormal * (distance * sideSign)
            return .line(LineSeg2d(start: seg.start + shift, end: seg.end + shift))

        case .ray(let r):
            let leftNormal = r.direction.perpCCW
            let sideSign = (sidePoint - r.origin).dot(leftNormal) >= 0 ? 1.0 : -1.0
            let shift = leftNormal * (distance * sideSign)
            return .ray(Ray2d(origin: r.origin + shift, direction: r.direction))

        case .xline(let x):
            let leftNormal = x.direction.perpCCW
            let sideSign = (sidePoint - x.origin).dot(leftNormal) >= 0 ? 1.0 : -1.0
            let shift = leftNormal * (distance * sideSign)
            return .xline(XLine2d(origin: x.origin + shift, direction: x.direction))

        case .arc(let arc):
            let distToCenter = sidePoint.distance(to: arc.center)
            let outward = distToCenter >= arc.radius
            let newRadius = outward ? (arc.radius + distance) : (arc.radius - distance)
            guard newRadius > KernelTolerance.linear else { return nil }
            return .arc(Arc2d(center: arc.center, radius: newRadius, startAngle: arc.startAngle, sweep: arc.sweep))

        case .circle(let circle):
            let distToCenter = sidePoint.distance(to: circle.center)
            let outward = distToCenter >= circle.radius
            let newRadius = outward ? (circle.radius + distance) : (circle.radius - distance)
            guard newRadius > KernelTolerance.linear else { return nil }
            return .circle(Circle2d(center: circle.center, radius: newRadius))

        case .polySegment(let seg):
            switch seg.geometry {
            case .line(let l):
                guard case .line(let ol)? = offsetSingleCurve(.line(l), distance: distance, sidePoint: sidePoint) else { return nil }
                return .polySegment(PolySegment2d(index: seg.index, geometry: .line(ol), startWidth: seg.startWidth, endWidth: seg.endWidth))
            case .arc(let a):
                guard case .arc(let oa)? = offsetSingleCurve(.arc(a), distance: distance, sidePoint: sidePoint) else { return nil }
                return .polySegment(PolySegment2d(index: seg.index, geometry: .arc(oa), startWidth: seg.startWidth, endWidth: seg.endWidth))
            }

        case .ellipse, .spline:
            return nil
        }
    }

    /// Offset a polyline segment chain, preserving arc bulges and widths.
    /// signedDistance > 0 offsets left of travel direction.
    /// Returns nil when any arc segment collapses (caller falls back to its
    /// existing whole-offset failure semantics).
    public static func offsetPolylineSegments(
        _ segments: [PolySegment2d],
        isClosed: Bool,
        signedDistance: Double,
        joint: OffsetJointPolicy = .extend
    ) -> [PolySegment2d]? {
        guard !segments.isEmpty else { return [] }
        let absDist = abs(signedDistance)
        guard absDist > KernelTolerance.linear else { return segments }
        let sideSign = signedDistance >= 0 ? 1.0 : -1.0

        // 1. Offset each segment exactly (lines shift, arcs resize).
        var working: [PolySegment2d] = []
        working.reserveCapacity(segments.count)
        for seg in segments {
            switch seg.geometry {
            case .line(let l):
                let normal = l.direction.perpCCW * sideSign
                let shifted = LineSeg2d(start: l.start + (normal * absDist), end: l.end + (normal * absDist))
                working.append(PolySegment2d(index: seg.index, geometry: .line(shifted),
                                             startWidth: seg.startWidth, endWidth: seg.endWidth))
            case .arc(let a):
                // CCW arc (sweep > 0): left of travel is inward.
                let radiusDelta = a.isCCW ? -signedDistance : signedDistance
                let newRadius = a.radius + radiusDelta
                guard newRadius > KernelTolerance.linear else { return nil }
                let shifted = Arc2d(center: a.center, radius: newRadius, startAngle: a.startAngle, sweep: a.sweep)
                working.append(PolySegment2d(index: seg.index, geometry: .arc(shifted),
                                             startWidth: seg.startWidth, endWidth: seg.endWidth))
            }
        }

        guard working.count > 1 else { return working }

        // 2. Stitch joints. Cheap AABB precheck first (R5): only run the
        // analytical intersect when the expanded boxes overlap.
        var result: [PolySegment2d] = working
        let jointCount = isClosed ? result.count : (result.count - 1)
        var inserted = 0 // index shift from fillet/chamfer connector inserts
        for i in 0..<jointCount {
            let idxA = i + inserted
            let nextIdx = ((i + 1) % working.count) + inserted
            let segA = result[idxA]
            let segB = result[nextIdx]

            guard let boxA = CurveEval.boundingBox(.polySegment(segA)),
                  let boxB = CurveEval.boundingBox(.polySegment(segB)),
                  boxA.expanded(by: absDist + KernelTolerance.linear).intersects(boxB) else {
                continue
            }

            switch joint {
            case .extend:
                let hits = Intersector2D.intersect(
                    .polySegment(segA), .polySegment(segB),
                    extendA: true, extendB: true)
                guard let hit = hits.min(by: {
                    $0.point.distanceSquared(to: segA.endPoint) < $1.point.distanceSquared(to: segA.endPoint)
                }) else { continue }
                // Line-line joints: prefer the closed-form (avoids arc-param
                // edge cases at near-tangent joints).
                if case .polySegment(let trimmedA)? = CurveEval.splitAt(.polySegment(segA), t1: 0.0, t2: hit.paramA),
                   case .polySegment(let trimmedB)? = CurveEval.splitAt(.polySegment(segB), t1: hit.paramB, t2: 1.0) {
                    result[idxA] = trimmedA
                    result[nextIdx] = trimmedB
                }
            case .fillet, .chamfer:
                // Trim both back to the joint by absDist, then insert the
                // connector (arc for fillet, line for chamfer).
                guard let trimA = trimBackToJoint(segA, distance: absDist, fromEnd: true),
                      let trimB = trimBackToJoint(segB, distance: absDist, fromEnd: false) else { continue }
                result[idxA] = trimA
                result[nextIdx] = trimB
                // Connector insertion happens in index space: represent as an
                // extra segment appended after i (caller re-indexes).
                let pA = trimA.endPoint
                let pB = trimB.startPoint
                if joint == .fillet {
                    // Tangent arc through pA->pB with radius absDist.
                    let tA = CurveEval.tangentAt(.polySegment(trimA), t: 1.0)
                    let tB = CurveEval.tangentAt(.polySegment(trimB), t: 0.0)
                    let cross = tA.cross(tB)
                    if abs(cross) > KernelTolerance.parametric,
                       let connector = filletConnector(pA: pA, tanA: tA, pB: pB, tanB: tB, radius: absDist) {
                        result.insert(connector, at: nextIdx)
                        inserted += 1
                    }
                } else {
                    let chamfer = PolySegment2d(index: segA.index, geometry: .line(LineSeg2d(start: pA, end: pB)))
                    result.insert(chamfer, at: nextIdx)
                    inserted += 1
                }
            }
        }
        return result
    }

    // MARK: - Joint helpers

    /// Shorten a segment by `distance` measured from its end (fromEnd=true)
    /// or start, for fillet/chamfer joint trimming.
    static func trimBackToJoint(_ seg: PolySegment2d, distance: Double, fromEnd: Bool) -> PolySegment2d? {
        let total: Double = {
            switch seg.geometry {
            case .line(let l): return l.length
            case .arc(let a): return a.radius * abs(a.sweep)
            }
        }()
        guard total > distance + KernelTolerance.linear else { return nil }
        let tCut: Double = {
            switch seg.geometry {
            case .line(let l): return distance / max(l.length, KernelTolerance.linear)
            case .arc(let a): return distance / max(a.radius * abs(a.sweep), KernelTolerance.linear)
            }
        }()
        let (t1, t2) = fromEnd ? (0.0, 1.0 - tCut) : (tCut, 1.0)
        if case .polySegment(let out)? = CurveEval.splitAt(.polySegment(seg), t1: t1, t2: t2) {
            return out
        }
        return nil
    }

    /// Tangent-arc connector between trimmed joint ends for .fillet.
    static func filletConnector(pA: Point2d, tanA: Vec2d, pB: Point2d, tanB: Vec2d, radius: Double) -> PolySegment2d? {
        // Centers lie at distance `radius` left/right of each tangent line;
        // pick the pair on the inside of the corner (closest to each other).
        let nA = tanA.perpCCW
        let nB = tanB.perpCCW
        var best: Point2d? = nil
        var bestD = Double.greatestFiniteMagnitude
        for sA in [1.0, -1.0] {
            for sB in [1.0, -1.0] {
                let cA = pA + (nA * (radius * sA))
                let cB = pB + (nB * (radius * sB))
                let d = cA.distanceSquared(to: cB)
                if d < bestD {
                    bestD = d
                    best = Point2d(x: 0.5 * (cA.x + cB.x), y: 0.5 * (cA.y + cB.y))
                }
            }
        }
        guard let center = best else { return nil }
        let aA = atan2(pA.y - center.y, pA.x - center.x)
        var sweep = (atan2(pB.y - center.y, pB.x - center.x) - aA).truncatingRemainder(dividingBy: 2.0 * .pi)
        if sweep > .pi { sweep -= 2.0 * .pi }
        if sweep < -.pi { sweep += 2.0 * .pi }
        let arc = Arc2d(center: center, radius: radius, startAngle: aA, sweep: sweep)
        return PolySegment2d(index: -1, geometry: .arc(arc))
    }
}
